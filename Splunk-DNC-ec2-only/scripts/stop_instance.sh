#!/bin/bash

INSTANCE_ID="$1"

if [ -z "$INSTANCE_ID" ]; then
  echo "❌ No instance ID provided!"
  exit 1
fi

echo "🛑 Stopping EC2 Instance ID: $INSTANCE_ID"
aws ec2 stop-instances --instance-ids "$INSTANCE_ID"
