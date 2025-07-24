#!/bin/bash

set -euo pipefail

# Redirect all non-JSON output to stderr
exec 3>&1
exec 1>&2

# Validate number of arguments
if [ $# -ne 4 ]; then
  echo "{\"final_key_name\": \"\", \"exists_in_s3\": \"false\", \"exists_in_aws\": \"false\", \"error\": \"Usage: $0 <key_name> <aws_region> <usermail> <local_key_dir>\"}" >&3
  exit 1
fi

KEY_NAME="$1"
AWS_REGION="$2"
USERMAIL="$3"
LOCAL_KEY_DIR="$4"
BUCKET="splunk-deployment-test"

CLEAN_KEY_NAME=$(echo "$KEY_NAME" | tr '[:space:]' '-' | tr -cd '[:alnum:]-')

# Function to output JSON
output_json() {
  jq -n \
    --arg final_key_name "$FINAL_KEY_NAME" \
    --arg exists_in_s3 "$1" \
    --arg exists_in_aws "$2" \
    --arg error "$3" \
    '{final_key_name: $final_key_name, exists_in_s3: $exists_in_s3, exists_in_aws: $exists_in_aws, error: $error}' >&3
}

# Input validation
if [[ -z "$KEY_NAME" || -z "$AWS_REGION" || -z "$USERMAIL" || -z "$LOCAL_KEY_DIR" ]]; then
  output_json "false" "false" "Missing required arguments"
  exit 1
fi

# Check AWS CLI
if ! command -v aws &> /dev/null; then
  output_json "false" "false" "AWS CLI is not installed"
  exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
  output_json "false" "false" "AWS credentials are not valid"
  exit 1
fi

# === Attempt to use original name FIRST ===
FINAL_KEY_NAME="$CLEAN_KEY_NAME"
S3_KEY_PATH="clients/${USERMAIL}/keys/${FINAL_KEY_NAME}.pem"

S3_KEY_EXISTS="false"
AWS_KEY_EXISTS="false"

# Check if it exists in S3
if aws s3api head-object --bucket "$BUCKET" --key "$S3_KEY_PATH" --region "$AWS_REGION" >/dev/null 2>&1; then
  S3_KEY_EXISTS="true"
fi

# Check if it exists in AWS
if aws ec2 describe-key-pairs --key-names "$FINAL_KEY_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  AWS_KEY_EXISTS="true"
fi

# === If conflict in either S3 or AWS, then suffix ===
if [ "$S3_KEY_EXISTS" = "true" ] || [ "$AWS_KEY_EXISTS" = "true" ]; then
  SUFFIX=1
  MAX_ATTEMPTS=99
  while [ "$SUFFIX" -le "$MAX_ATTEMPTS" ]; do
    TEST_NAME="${CLEAN_KEY_NAME}-${SUFFIX}"
    S3_TEST_PATH="clients/${USERMAIL}/keys/${TEST_NAME}.pem"

    S3_CONFLICT=false
    AWS_CONFLICT=false

    if aws s3api head-object --bucket "$BUCKET" --key "$S3_TEST_PATH" --region "$AWS_REGION" >/dev/null 2>&1; then
      S3_CONFLICT=true
    fi
    if aws ec2 describe-key-pairs --key-names "$TEST_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
      AWS_CONFLICT=true
    fi

    if [ "$S3_CONFLICT" = "false" ] && [ "$AWS_CONFLICT" = "false" ]; then
      FINAL_KEY_NAME="$TEST_NAME"
      S3_KEY_PATH="$S3_TEST_PATH"
      break
    fi

    SUFFIX=$((SUFFIX + 1))
  done

  if [ "$SUFFIX" -gt "$MAX_ATTEMPTS" ]; then
    output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Too many existing key pairs with similar names"
    exit 1
  fi
fi

# Recalculate S3 existence for the FINAL_KEY_NAME
if aws s3api head-object --bucket "$BUCKET" --key "$S3_KEY_PATH" --region "$AWS_REGION" >/dev/null 2>&1; then
  S3_KEY_EXISTS="true"

  mkdir -p "$LOCAL_KEY_DIR" || {
    output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Failed to create local dir"
    exit 1
  }

  if ! aws s3 cp "s3://${BUCKET}/${S3_KEY_PATH}" "${LOCAL_KEY_DIR}/${FINAL_KEY_NAME}.pem" --region "$AWS_REGION" >/dev/null 2>&1; then
    output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Failed to download key from S3"
    exit 1
  fi

  chmod 0400 "${LOCAL_KEY_DIR}/${FINAL_KEY_NAME}.pem" || {
    output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Failed to set key permissions"
    exit 1
  }

  if [ "$AWS_KEY_EXISTS" = "false" ]; then
    if ! aws ec2 import-key-pair \
      --key-name "$FINAL_KEY_NAME" \
      --public-key-material "fileb://${LOCAL_KEY_DIR}/${FINAL_KEY_NAME}.pem" \
      --region "$AWS_REGION" >/dev/null 2>&1; then
      output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Failed to import key to AWS"
      exit 1
    fi
    AWS_KEY_EXISTS="true"
  fi
fi

output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" ""
exit 0
