#!/bin/bash

# Ensure we fail immediately if any command fails
set -euo pipefail

# Redirect all output to stderr except the final JSON output
exec 3>&1
exec 1>&2

# Configuration
KEY_NAME="$1"
AWS_REGION="$2"
USERMAIL="$3"
LOCAL_KEY_DIR="$4"
BUCKET="splunk-deployment-test"
LOCK_TABLE="KeyPairCreationLock"
LOCK_TIMEOUT=60

# Clean key name
CLEAN_KEY_NAME=$(echo "$KEY_NAME" | tr '[:upper:]' '[:lower:]' | tr ' ' '-' | tr -cd '[:alnum:]-')

# Simple JSON output function
json_output() {
  echo "{\"final_key_name\":\"$CLEAN_KEY_NAME\",\"exists_in_s3\":\"$1\",\"exists_in_aws\":\"$2\",\"error\":\"$3\"}" >&3
}

# Error handler
error_exit() {
  json_output "false" "false" "${1//\"/\\\"}"  # Escape quotes for JSON
  exit 1
}

# Check AWS CLI availability
check_aws() {
  if ! command -v aws &>/dev/null; then
    error_exit "AWS CLI not found"
  fi
}

# Main execution
main() {
  check_aws

  # Initialize default values
  local exists_in_aws="false"
  local exists_in_s3="false"
  local error_msg=""

  # Check AWS key
  if aws ec2 describe-key-pairs --key-names "$CLEAN_KEY_NAME" --region "$AWS_REGION" &>/dev/null; then
    exists_in_aws="true"
  fi

  # Check S3 key
  if aws s3api head-object --bucket "$BUCKET" --key "clients/${USERMAIL}/keys/${CLEAN_KEY_NAME}.pem" --region "$AWS_REGION" &>/dev/null; then
    exists_in_s3="true"
  fi

  # Handle inconsistent state
  if [ "$exists_in_aws" = "true" ] && [ "$exists_in_s3" = "false" ]; then
    error_exit "Key exists in AWS but not in S3"
  fi

  # If both exist, download the key
  if [ "$exists_in_aws" = "true" ] && [ "$exists_in_s3" = "true" ]; then
    mkdir -p "$LOCAL_KEY_DIR" || error_exit "Failed to create local directory"
    if ! aws s3 cp "s3://${BUCKET}/clients/${USERMAIL}/keys/${CLEAN_KEY_NAME}.pem" \
         "${LOCAL_KEY_DIR}/${CLEAN_KEY_NAME}.pem" --region "$AWS_REGION" &>/dev/null; then
      error_exit "Failed to download key from S3"
    fi
    chmod 0400 "${LOCAL_KEY_DIR}/${CLEAN_KEY_NAME}.pem" || true
  fi

  json_output "$exists_in_s3" "$exists_in_aws" "$error_msg"
}

main