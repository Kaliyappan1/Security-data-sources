#!/bin/bash

KEY_NAME="$1"
AWS_REGION="$2"
USERMAIL="$3"
BUCKET="splunk-deployment-test"

# S3 path format
OBJECT_KEY="clients/${USERMAIL}/keys/${KEY_NAME}.pem"

# Check S3 for PEM key existence
if aws s3api head-object --bucket "$BUCKET" --key "$OBJECT_KEY" --region "$AWS_REGION" 2>/dev/null; then
  echo "{\"final_key_name\": \"${KEY_NAME}\", \"exists\": \"true\"}"
else
  echo "{\"final_key_name\": \"${KEY_NAME}\", \"exists\": \"false\"}"
fi