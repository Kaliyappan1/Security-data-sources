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

# Clean up key name (replace spaces and special characters with hyphens)
CLEAN_KEY_NAME=$(echo "$KEY_NAME" | tr '[:space:]' '-' | tr -cd '[:alnum:]-')
FINAL_KEY_NAME="$CLEAN_KEY_NAME"

# Output JSON function
output_json() {
  jq -n \
    --arg final_key_name "$FINAL_KEY_NAME" \
    --arg exists_in_s3 "$1" \
    --arg exists_in_aws "$2" \
    --arg error "$3" \
    '{final_key_name: $final_key_name, exists_in_s3: $exists_in_s3, exists_in_aws: $exists_in_aws, error: $error}' >&3
}

# Validate inputs
if [[ -z "$KEY_NAME" || -z "$AWS_REGION" || -z "$USERMAIL" || -z "$LOCAL_KEY_DIR" ]]; then
  output_json "false" "false" "Missing required arguments"
  exit 1
fi

# Check if AWS CLI is available
if ! command -v aws &> /dev/null; then
  output_json "false" "false" "AWS CLI is not installed"
  exit 1
fi

# Check AWS credentials
if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
  output_json "false" "false" "AWS credentials are not valid"
  exit 1
fi

# Check if key exists in AWS and find a unique name if needed
AWS_KEY_EXISTS="false"
SUFFIX=0
MAX_ATTEMPTS=99

while [ "$SUFFIX" -le "$MAX_ATTEMPTS" ]; do
  if [ "$SUFFIX" -eq 0 ]; then
    TEST_NAME="$CLEAN_KEY_NAME"
  else
    TEST_NAME="${CLEAN_KEY_NAME}-$(printf "%02d" $SUFFIX)"
  fi
  
  if aws ec2 describe-key-pairs --key-names "$TEST_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
    SUFFIX=$((SUFFIX + 1))
  else
    if [ "$SUFFIX" -ne 0 ]; then
      FINAL_KEY_NAME="${CLEAN_KEY_NAME}-$(printf "%02d" $SUFFIX)"
    fi
    break
  fi
done

# If we've exhausted all attempts
if [ "$SUFFIX" -gt "$MAX_ATTEMPTS" ]; then
  output_json "false" "true" "Too many existing key pairs with similar names (tried up to ${CLEAN_KEY_NAME}-${MAX_ATTEMPTS})"
  exit 1
fi

# S3 key path (using the original clean name for S3, not the potentially suffixed one)
S3_KEY_PATH="clients/${USERMAIL}/keys/${CLEAN_KEY_NAME}.pem"

# Check if key exists in S3
S3_KEY_EXISTS="false"
if aws s3api head-object --bucket "$BUCKET" --key "$S3_KEY_PATH" --region "$AWS_REGION" >/dev/null 2>&1; then
  S3_KEY_EXISTS="true"
  
  # Create local directory if it doesn't exist
  mkdir -p "$LOCAL_KEY_DIR" || {
    output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Failed to create local directory $LOCAL_KEY_DIR"
    exit 1
  }
  
  # Download from S3
  if ! aws s3 cp "s3://${BUCKET}/${S3_KEY_PATH}" "${LOCAL_KEY_DIR}/${FINAL_KEY_NAME}.pem" --region "$AWS_REGION" >/dev/null 2>&1; then
    output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Failed to download key from S3"
    exit 1
  fi
  
  # Set proper permissions
  if ! chmod 0400 "${LOCAL_KEY_DIR}/${FINAL_KEY_NAME}.pem"; then
    output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Failed to set key permissions"
    exit 1
  fi
  
  # Import the key to AWS if it doesn't exist
  if [ "$AWS_KEY_EXISTS" = "false" ]; then
    if ! aws ec2 import-key-pair --key-name "$FINAL_KEY_NAME" \
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