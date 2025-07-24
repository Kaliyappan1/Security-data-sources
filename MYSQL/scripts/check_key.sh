#!/bin/bash

set -euo pipefail

KEY_NAME="$1"
AWS_REGION="$2"
USERMAIL="$3"
BUCKET="splunk-deployment-test"

# Validate inputs
if [[ -z "$KEY_NAME" || -z "$AWS_REGION" || -z "$USERMAIL" ]]; then
  echo "Missing arguments. Usage: $0 <key_name> <aws_region> <usermail>" >&2
  exit 1
fi

# S3 key path
OBJECT_KEY="clients/${USERMAIL}/keys/${KEY_NAME}.pem"

# Check if the key exists in S3 (suppress all output)
if aws s3api head-object \
    --bucket "$BUCKET" \
    --key "$OBJECT_KEY" \
    --region "$AWS_REGION" > /dev/null 2>&1; then
  EXISTS="true"
else
  EXISTS="false"
fi

# Output expected JSON format for Terraform external data
echo "{\"final_key_name\": \"${KEY_NAME}\", \"exists\": \"${EXISTS}\"}"
