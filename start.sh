#!/usr/bin/env bash
/opt/aws/amazon-cloudwatch-agent/bin/start-amazon-cloudwatch-agent &
/cc/kafka-cruise-control-start.sh config/cruisecontrol.properties 9091