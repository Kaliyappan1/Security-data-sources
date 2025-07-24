#!/bin/bash

set -euo pipefail

# Redirect all non-JSON output to stderr
exec 3>&1  # Save original stdout
exec 1>&2  # Redirect stdout to stderr

KEY_NAME="$1"
AWS_REGION="$2"
USERMAIL="$3"
BUCKET="splunk-deployment-test"
LOCAL_KEY_DIR="${4:-keys}"  # Default directory or can be passed as 4th arg

# Validate inputs
if [[ -z "$KEY_NAME" || -z "$AWS_REGION" || -z "$USERMAIL" ]]; then
  echo "{\"error\": \"Missing arguments. Usage: $0 <key_name> <aws_region> <usermail> [key_dir]\"}" >&3
  exit 1
fi

# Clean up key name to ensure consistent format
CLEAN_KEY_NAME=$(echo "$KEY_NAME" | tr ' ' '-')

# S3 key path
OBJECT_KEY="clients/${USERMAIL}/keys/${CLEAN_KEY_NAME}.pem"

# Initialize result variables
EXISTS="false"
ERROR=""

# Check if the key exists in S3
if aws s3api head-object \
    --bucket "$BUCKET" \
    --key "$OBJECT_KEY" \
    --region "$AWS_REGION" > /dev/null 2>&1; then
  EXISTS="true"
  
  # Create local keys directory if it doesn't exist
  mkdir -p "$LOCAL_KEY_DIR" || {
    ERROR="Failed to create local key directory"
    echo "{\"error\": \"$ERROR\", \"exists\": \"false\"}" >&3
    exit 1
  }
  
  # Download the key
  if ! aws s3 cp \
    "s3://${BUCKET}/${OBJECT_KEY}" \
    "${LOCAL_KEY_DIR}/${CLEAN_KEY_NAME}.pem" \
    --region "$AWS_REGION" > /dev/null 2>&1; then
    ERROR="Failed to download key from S3"
    echo "{\"error\": \"$ERROR\", \"exists\": \"false\"}" >&3
    exit 1
  fi
  
  # Set proper permissions
  chmod 0400 "${LOCAL_KEY_DIR}/${CLEAN_KEY_NAME}.pem" || {
    ERROR="Failed to set key permissions"
    echo "{\"error\": \"$ERROR\", \"exists\": \"false\"}" >&3
    exit 1
  }
fi

# Output final JSON to original stdout (fd 3)
echo "{\"final_key_name\": \"${CLEAN_KEY_NAME}\", \"exists\": \"${EXISTS}\", \"error\": \"${ERROR}\"}" >&3