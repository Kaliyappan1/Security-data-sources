#!/bin/bash

set -euo pipefail

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

# Acquire lock function
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

# Release lock function
release_lock() {
  aws dynamodb delete-item \
    --table-name "$LOCK_TABLE" \
    --key '{"KeyName": {"S": "'"$CLEAN_KEY_NAME"'"}}' \
    --region "$AWS_REGION" >/dev/null 2>&1 || true
}

# Main execution
trap 'release_lock' EXIT

if ! acquire_lock; then
  echo "{\"error\":\"Failed to acquire lock for key creation\"}"
  exit 1
fi

# Check if key exists now (another process might have created it)
if aws ec2 describe-key-pairs --key-names "$CLEAN_KEY_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  exit 0
fi

# Create key in AWS
if ! aws ec2 import-key-pair \
  --key-name "$CLEAN_KEY_NAME" \
  --public-key-material "fileb://${LOCAL_KEY_DIR}/${CLEAN_KEY_NAME}.pub" \
  --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "{\"error\":\"Failed to create key pair in AWS\"}"
  exit 1
fi

exit 0