#!/bin/bash

set -euo pipefail

# Redirect all non-JSON output to stderr
exec 3>&1
exec 1>&2

KEY_NAME="$1"
AWS_REGION="$2"
USERMAIL="$3"
LOCAL_KEY_DIR="$4"
BUCKET="splunk-deployment-test"

# Clean up key name (replace spaces with hyphens)
CLEAN_KEY_NAME=$(echo "$KEY_NAME" | tr ' ' '-')

# Output JSON function
output_json() {
  echo "{\"final_key_name\": \"$CLEAN_KEY_NAME\", \"exists\": \"$1\", \"error\": \"$2\"}" >&3
}

# Validate inputs
if [[ -z "$KEY_NAME" || -z "$AWS_REGION" || -z "$USERMAIL" || -z "$LOCAL_KEY_DIR" ]]; then
  output_json "false" "Missing required arguments"
  exit 1
fi

# S3 key path
S3_KEY_PATH="clients/${USERMAIL}/keys/${CLEAN_KEY_NAME}.pem"

# Check if key exists in S3
if aws s3api head-object --bucket "$BUCKET" --key "$S3_KEY_PATH" --region "$AWS_REGION" >/dev/null 2>&1; then
  # Key exists in S3 - download it
  mkdir -p "$LOCAL_KEY_DIR" || {
    output_json "false" "Failed to create local directory"
    exit 1
  }
  
  if aws s3 cp "s3://${BUCKET}/${S3_KEY_PATH}" "${LOCAL_KEY_DIR}/${CLEAN_KEY_NAME}.pem" --region "$AWS_REGION" >/dev/null 2>&1; then
    chmod 0400 "${LOCAL_KEY_DIR}/${CLEAN_KEY_NAME}.pem" || {
      output_json "false" "Failed to set key permissions"
      exit 1
    }
    output_json "true" ""
    exit 0
  else
    output_json "false" "Failed to download key from S3"
    exit 1
  fi
else
  # Key doesn't exist in S3
  output_json "false" ""
  exit 0
fi