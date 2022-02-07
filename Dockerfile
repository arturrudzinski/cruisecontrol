# -------------------------------------------------------------------------------------------------
# BUILDER IMAGE
# -------------------------------------------------------------------------------------------------
#FROM openjdk:8-jdk-alpine as builder
FROM debian:latest as builder
ARG VERSION="2.5.22"


###
### Dependencies
###

# RUN apk update && apk upgrade

# RUN apk add --no-cache \
# 	curl \
# 	git \
# 	ca-certificates

RUN apt-get update &&  \
    apt-get install -y ca-certificates curl git default-jdk && \
    rm -rf /var/lib/apt/lists/*

###
### Download
###

#RUN curl -sSL "https://github.com/linkedin/cruise-control/archive/${VERSION}.tar.gz" > /tmp/cc.tar.gz

RUN set -eux \
	&& if [ "${VERSION}" = "latest" ]; then \
			DATA="$( \
				curl -sS https://github.com/linkedin/cruise-control/releases \
				| tac \
				| tac \
				| grep -Eo 'href=".+[.0-9]+\.tar.gz"' \
				| awk -F'\"' '{print $2}' \
				| sort -u \
				| tail -1 \
			)"; \
			echo "${DATA}"; \
			VERSION="$( echo "${DATA}" | grep -Eo '[.0-9]+[0-9]' )"; \
		fi \
	&& echo "${VERSION}" \
	&& echo "${VERSION}" > /VERSION \
	&& curl -sSL "https://github.com/linkedin/cruise-control/archive/${VERSION}.tar.gz" > /tmp/cc.tar.gz


RUN curl -O https://s3.amazonaws.com/amazoncloudwatch-agent/debian/amd64/latest/amazon-cloudwatch-agent.deb && \
    dpkg -i -E amazon-cloudwatch-agent.deb && \
    rm -rf /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-config-wizard && \
    rm -rf /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl && \
    rm -rf /opt/aws/amazon-cloudwatch-agent/bin/config-downloader

###
### Extract
###
RUN set -eux \
	&& cd /tmp \
	&& tar xzvf /tmp/cc.tar.gz \
	&& mv /tmp/cruise-control-* /tmp/cruise-control

###
### Setup git user and init repo
###
RUN set -eux \
	&& cd /tmp/cruise-control \
	&& git config --global user.email root@localhost \
	&& git config --global user.name root \
	&& git init \
	&& git add . \
	&& git commit -m "Init local repo." \
	&& git tag -a ${VERSION} -m "Init local version."
###
### Install dependencies
###
RUN set -eux \
	&& cd /tmp/cruise-control \
	#&& ./gradlew jar \
	&& ./gradlew jar copyDependantLibs
###
### Download UI
###
RUN set -eux \
	&& UI="$( \
		curl -sSL https://github.com/linkedin/cruise-control-ui/releases/latest \
			| grep -Eo '".+cruise-control-ui-[.0-9]+.tar.gz"'\
			| sed 's/\"//g' \
		)" \
	#&& curl -sL "https://github.com${UI}" > /tmp/cc-ui.tar.gz \
	&& cd /tmp \
	&& curl -sL "https://github.com${UI}" > /tmp/cc-ui.tar.gz \
	&& tar xvfz cc-ui.tar.gz

###
### Setup dist
###
RUN set -eux \
	&& mkdir -p /cc/cruise-control/build \
	&& mkdir -p /cc/cruise-control-core/build \
    && mkdir -p /cc/logs \
	&& cp -a /tmp/cruise-control/cruise-control/build/dependant-libs /cc/cruise-control/build/ \
	&& cp -a /tmp/cruise-control/cruise-control/build/libs /cc/cruise-control/build/ \
	&& cp -a /tmp/cruise-control/cruise-control-core/build/libs /cc/cruise-control-core/build/ \
	&& cp -a /tmp/cruise-control/config /cc/ \
	&& cp -a /tmp/cruise-control/kafka-cruise-control-start.sh /cc/ \
    && cp -a /tmp/cruise-control/kafka-cruise-control-stop.sh /cc/ \
	&& cp -a /tmp/cruise-control-ui /cc 

# -------------------------------------------------------------------------------------------------
# PRODUCTION IMAGE
# -------------------------------------------------------------------------------------------------
#FROM openjdk:8-jdk-alpine as production
FROM debian:latest as production

ENV RUN_IN_CONTAINER="True"

###
### Install requirements
###
#RUN set -eux && apk add --no-cache bash
RUN apt-get update && apt-get install -y bash default-jdk iputils-ping

###
### Copy files
###
COPY --from=builder /cc /cc
COPY --from=builder /VERSION /VERSION
#COPY run.sh /run.sh

# 
COPY --from=builder /tmp /tmp
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /opt/aws/amazon-cloudwatch-agent /opt/aws/amazon-cloudwatch-agent

COPY cwatch-agent.json /etc/cwagentconfig/
COPY credentials /root/.aws/
COPY start.sh /cc/

###
### Expose
###
EXPOSE 9091

###
### Startup
###

WORKDIR /cc
CMD ["./kafka-cruise-control-start.sh","config/cruisecontrol.properties","9091"]
#CMD ["sleep","3600"]
#ENTRYPOINT ["/cc/start.sh"]