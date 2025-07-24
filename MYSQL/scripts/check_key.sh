#!/bin/bash

set -euo pipefail

KEY_NAME="$1"
AWS_REGION="$2"
USERMAIL="$3"
BUCKET="splunk-deployment-test"
LOCAL_KEY_DIR="keys"  # Relative to where Terraform is run

# Validate inputs
if [[ -z "$KEY_NAME" || -z "$AWS_REGION" || -z "$USERMAIL" ]]; then
  echo "Missing arguments. Usage: $0 <key_name> <aws_region> <usermail>" >&2
  exit 1
fi

# S3 key path
OBJECT_KEY="clients/${USERMAIL}/keys/${KEY_NAME}.pem"

# Check if the key exists in S3
if aws s3api head-object \
    --bucket "$BUCKET" \
    --key "$OBJECT_KEY" \
    --region "$AWS_REGION" > /dev/null 2>&1; then
  EXISTS="true"
  
  # Create local keys directory if it doesn't exist
  mkdir -p "$LOCAL_KEY_DIR"
  
  # Download the key
  aws s3 cp \
    "s3://${BUCKET}/${OBJECT_KEY}" \
    "${LOCAL_KEY_DIR}/${KEY_NAME}.pem" \
    --region "$AWS_REGION"
    
  # Set proper permissions
  chmod 0400 "${LOCAL_KEY_DIR}/${KEY_NAME}.pem"
else
  EXISTS="false"
fi

# Output expected JSON format for Terraform external data
echo "{\"final_key_name\": \"${KEY_NAME}\", \"exists\": \"${EXISTS}\"}"