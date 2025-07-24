#!/bin/bash

set -euo pipefail

# Redirect stderr to stdout for Terraform to capture
exec 2>&1

# Configuration
KEY_NAME="$1"
AWS_REGION="$2"
USERMAIL="$3"
LOCAL_KEY_DIR="$4"
BUCKET="splunk-deployment-test"
LOCK_TABLE="KeyPairCreationLock"
LOCK_TIMEOUT=60

# Clean key name
CLEAN_KEY_NAME=$(echo "$KEY_NAME" | tr ' ' '-')

# Initialize default JSON output
output_json() {
  echo "{\"final_key_name\":\"$CLEAN_KEY_NAME\",\"exists_in_s3\":\"$1\",\"exists_in_aws\":\"$2\",\"error\":\"$3\"}"
}

# Error handler
error_exit() {
  output_json "false" "false" "$1"
  exit 1
}

# Check AWS CLI availability
check_aws_cli() {
  if ! command -v aws &> /dev/null; then
    error_exit "AWS CLI not found"
  fi
}

# Check if key exists in AWS
check_aws_key() {
  if aws ec2 describe-key-pairs --key-names "$CLEAN_KEY_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "true"
  else
    echo "false"
  fi
}

# Check if key exists in S3
check_s3_key() {
  if aws s3api head-object --bucket "$BUCKET" --key "clients/${USERMAIL}/keys/${CLEAN_KEY_NAME}.pem" --region "$AWS_REGION" >/dev/null 2>&1; then
    echo "true"
  else
    echo "false"
  fi
}

# Acquire lock
acquire_lock() {
  local end_time=$(( $(date +%s) + LOCK_TIMEOUT ))
  
  while [ $(date +%s) -lt $end_time ]; do
    if aws dynamodb put-item \
      --table-name "$LOCK_TABLE" \
      --item '{"KeyName": {"S": "'"$CLEAN_KEY_NAME"'"}}' \
      --condition-expression "attribute_not_exists(KeyName)" \
      --region "$AWS_REGION" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# Release lock
release_lock() {
  aws dynamodb delete-item \
    --table-name "$LOCK_TABLE" \
    --key '{"KeyName": {"S": "'"$CLEAN_KEY_NAME"'"}}' \
    --region "$AWS_REGION" >/dev/null 2>&1 || true
}

# Main execution
main() {
  check_aws_cli

  if ! acquire_lock; then
    error_exit "Failed to acquire lock for key creation"
  fi
  trap release_lock EXIT

  local aws_exists
  local s3_exists
  aws_exists=$(check_aws_key)
  s3_exists=$(check_s3_key)

  # Check for inconsistent state
  if [ "$aws_exists" = "true" ] && [ "$s3_exists" = "false" ]; then
    error_exit "Key exists in AWS but not in S3"
  fi

  # If key exists in both places
  if [ "$aws_exists" = "true" ] && [ "$s3_exists" = "true" ]; then
    # Ensure local directory exists
    mkdir -p "$LOCAL_KEY_DIR" || error_exit "Failed to create local directory"
    
    # Download key from S3
    if ! aws s3 cp "s3://${BUCKET}/clients/${USERMAIL}/keys/${CLEAN_KEY_NAME}.pem" \
         "${LOCAL_KEY_DIR}/${CLEAN_KEY_NAME}.pem" --region "$AWS_REGION" >/dev/null 2>&1; then
      error_exit "Failed to download key from S3"
    fi
    
    # Set proper permissions
    chmod 0400 "${LOCAL_KEY_DIR}/${CLEAN_KEY_NAME}.pem" || \
      error_exit "Failed to set key permissions"
    
    output_json "true" "true" ""
    exit 0
  fi

  # If we get here, key needs to be created
  output_json "false" "false" ""
}

main