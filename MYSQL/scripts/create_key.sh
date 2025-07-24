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

# Acquire lock function (same as in check_key.sh)
acquire_lock() {
  # ... same implementation as above ...
}

# Release lock function (same as in check_key.sh)
release_lock() {
  # ... same implementation as above ...
}

# Main execution
if ! acquire_lock; then
  echo "Failed to acquire lock for key creation"
  exit 1
fi

# Check if key exists now (another process might have created it)
if aws ec2 describe-key-pairs --key-names "$CLEAN_KEY_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  release_lock
  exit 0
fi

# Create key in AWS
if ! aws ec2 import-key-pair \
  --key-name "$CLEAN_KEY_NAME" \
  --public-key-material "fileb://${LOCAL_KEY_DIR}/${CLEAN_KEY_NAME}.pub" \
  --region "$AWS_REGION" >/dev/null 2>&1; then
  release_lock
  echo "Failed to create key pair in AWS"
  exit 1
fi

release_lock
exit 0