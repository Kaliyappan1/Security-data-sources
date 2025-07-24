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

CLEAN_KEY_NAME=$(echo "$KEY_NAME" | tr ' ' '-')

# Output JSON
output_json() {
  echo "{\"final_key_name\": \"$FINAL_KEY_NAME\", \"exists_in_s3\": \"$1\", \"exists_in_aws\": \"$2\", \"error\": \"$3\"}" >&3
}

if [[ -z "$KEY_NAME" || -z "$AWS_REGION" || -z "$USERMAIL" || -z "$LOCAL_KEY_DIR" ]]; then
  output_json "false" "false" "Missing required arguments"
  exit 1
fi

check_aws_key_exists() {
  aws ec2 describe-key-pairs --key-names "$1" --region "$AWS_REGION" >/dev/null 2>&1
}

check_s3_key_exists() {
  local s3_key="clients/${USERMAIL}/keys/${1}.pem"
  aws s3api head-object --bucket "$BUCKET" --key "$s3_key" --region "$AWS_REGION" >/dev/null 2>&1
}

# 🔍 Find highest suffix of existing keys
find_highest_suffix() {
  local base_name="$1"
  local max_suffix=-1

  for i in {0..20}; do
    if [[ $i -eq 0 ]]; then
      candidate="$base_name"
    else
      candidate="${base_name}-${i}"
    fi

    check_aws_key_exists "$candidate" || check_s3_key_exists "$candidate" || continue
    max_suffix=$i
  done

  echo "$max_suffix"
}

# Start suffix detection
HIGHEST_SUFFIX=$(find_highest_suffix "$CLEAN_KEY_NAME")
AWS_KEY_EXISTS="false"
S3_KEY_EXISTS="false"

if [[ "$HIGHEST_SUFFIX" -ge 0 ]]; then
  if [[ "$HIGHEST_SUFFIX" -eq 0 ]]; then
    FINAL_KEY_NAME="$CLEAN_KEY_NAME"
  else
    FINAL_KEY_NAME="${CLEAN_KEY_NAME}-${HIGHEST_SUFFIX}"
  fi

  # Check existence flags
  check_aws_key_exists "$FINAL_KEY_NAME" && AWS_KEY_EXISTS="true"
  check_s3_key_exists "$FINAL_KEY_NAME" && S3_KEY_EXISTS="true"

  if [[ "$S3_KEY_EXISTS" == "true" ]]; then
    mkdir -p "$LOCAL_KEY_DIR" || {
      output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Failed to create local directory"
      exit 1
    }

    S3_KEY_PATH="clients/${USERMAIL}/keys/${FINAL_KEY_NAME}.pem"
    if ! aws s3 cp "s3://${BUCKET}/${S3_KEY_PATH}" "${LOCAL_KEY_DIR}/${FINAL_KEY_NAME}.pem" --region "$AWS_REGION" >/dev/null 2>&1; then
      output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Failed to download key from S3"
      exit 1
    fi

    chmod 0400 "${LOCAL_KEY_DIR}/${FINAL_KEY_NAME}.pem" || {
      output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Failed to set key permissions"
      exit 1
    }
  fi

else
  # No key exists, use base name (unsuffixed) as new name
  FINAL_KEY_NAME="$CLEAN_KEY_NAME"
fi

output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" ""
exit 0
