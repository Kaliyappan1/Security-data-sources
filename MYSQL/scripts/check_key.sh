#!/bin/bash

set -euo pipefail

exec 3>&1
exec 1>&2

# Configuration
KEY_NAME="$1"
AWS_REGION="$2"
USERMAIL="$3"
LOCAL_KEY_DIR="$4"
BUCKET="splunk-deployment-test"
LOCK_TABLE="KeyPairCreationLock"
LOCK_TIMEOUT=60  # seconds

# Clean key name
CLEAN_KEY_NAME=$(echo "$KEY_NAME" | tr ' ' '-')

# JSON output function
output_json() {
  echo "{\"final_key_name\":\"$CLEAN_KEY_NAME\",\"exists_in_s3\":\"$1\",\"exists_in_aws\":\"$2\",\"error\":\"$3\"}" >&3
}

# Error handler
handle_error() {
  output_json "false" "false" "$1"
  exit 1
}

# Check if key exists in AWS
check_aws_key() {
  aws ec2 describe-key-pairs --key-names "$CLEAN_KEY_NAME" --region "$AWS_REGION" >/dev/null 2>&1
  echo $?
}

# Check if key exists in S3
check_s3_key() {
  aws s3api head-object --bucket "$BUCKET" --key "clients/${USERMAIL}/keys/${CLEAN_KEY_NAME}.pem" --region "$AWS_REGION" >/dev/null 2>&1
  echo $?
}

# Acquire lock
acquire_lock() {
  local lock_acquired=false
  local end_time=$(( $(date +%s) + LOCK_TIMEOUT ))
  
  while [ $(date +%s) -lt $end_time ]; do
    if aws dynamodb put-item \
      --table-name "$LOCK_TABLE" \
      --item '{"KeyName": {"S": "'"$CLEAN_KEY_NAME"'"}}' \
      --condition-expression "attribute_not_exists(KeyName)" \
      --region "$AWS_REGION" >/dev/null 2>&1; then
      lock_acquired=true
      break
    fi
    sleep 1
  done
  
  [ "$lock_acquired" = true ]
}

# Release lock
release_lock() {
  aws dynamodb delete-item \
    --table-name "$LOCK_TABLE" \
    --key '{"KeyName": {"S": "'"$CLEAN_KEY_NAME"'"}}' \
    --region "$AWS_REGION" >/dev/null 2>&1 || true
}

# Main execution
trap 'release_lock' EXIT

if ! acquire_lock; then
  handle_error "Failed to acquire lock for key creation"
fi

# Check AWS key existence
AWS_EXISTS=$(check_aws_key)
S3_EXISTS=$(check_s3_key)

# If key exists in AWS but not in S3 (inconsistent state)
if [ $AWS_EXISTS -eq 0 ] && [ $S3_EXISTS -ne 0 ]; then
  handle_error "Key exists in AWS but not in S3"
fi

# If key exists in both places
if [ $AWS_EXISTS -eq 0 ] && [ $S3_EXISTS -eq 0 ]; then
  # Download from S3
  mkdir -p "$LOCAL_KEY_DIR" || {
    handle_error "Failed to create local directory"
  }
  
  if ! aws s3 cp "s3://${BUCKET}/clients/${USERMAIL}/keys/${CLEAN_KEY_NAME}.pem" "${LOCAL_KEY_DIR}/${CLEAN_KEY_NAME}.pem" --region "$AWS_REGION" >/dev/null 2>&1; then
    handle_error "Failed to download key from S3"
  fi
  
  chmod 0400 "${LOCAL_KEY_DIR}/${CLEAN_KEY_NAME}.pem" || {
    handle_error "Failed to set key permissions"
  }
  
  output_json "true" "true" ""
  exit 0
fi

# If we get here, key needs to be created
output_json "false" "false" ""
exit 0