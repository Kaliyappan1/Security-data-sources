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
  echo "{\"final_key_name\": \"$FINAL_KEY_NAME\", \"exists_in_s3\": \"$1\", \"exists_in_aws\": \"$2\", \"error\": \"$3\"}" >&3
}

# Validate inputs
if [[ -z "$KEY_NAME" || -z "$AWS_REGION" || -z "$USERMAIL" || -z "$LOCAL_KEY_DIR" ]]; then
  output_json "false" "false" "Missing required arguments"
  exit 1
fi

# Function to check if key exists in AWS
check_aws_key_exists() {
  local key_name=$1
  if aws ec2 describe-key-pairs --key-names "$key_name" --region "$AWS_REGION" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Function to check if key exists in S3
check_s3_key_exists() {
  local key_name=$1
  local s3_path="clients/${USERMAIL}/keys/${key_name}.pem"
  if aws s3api head-object --bucket "$BUCKET" --key "$s3_path" --region "$AWS_REGION" >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Find a unique key name by adding integer suffix if needed
FINAL_KEY_NAME="$CLEAN_KEY_NAME"
counter=1
while check_aws_key_exists "$FINAL_KEY_NAME" || check_s3_key_exists "$FINAL_KEY_NAME"; do
  FINAL_KEY_NAME="${CLEAN_KEY_NAME}-${counter}"
  ((counter++))
done

# Check if the final key name is different from the original (meaning it exists)
AWS_KEY_EXISTS="false"
S3_KEY_EXISTS="false"

if [[ "$FINAL_KEY_NAME" != "$CLEAN_KEY_NAME" ]]; then
  # Check if original exists in AWS
  if check_aws_key_exists "$CLEAN_KEY_NAME"; then
    AWS_KEY_EXISTS="true"
  fi
  
  # Check if original exists in S3
  if check_s3_key_exists "$CLEAN_KEY_NAME"; then
    S3_KEY_EXISTS="true"
    
    # Download from S3 if it exists
    mkdir -p "$LOCAL_KEY_DIR" || {
      output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Failed to create local directory"
      exit 1
    }
    
    S3_KEY_PATH="clients/${USERMAIL}/keys/${CLEAN_KEY_NAME}.pem"
    if ! aws s3 cp "s3://${BUCKET}/${S3_KEY_PATH}" "${LOCAL_KEY_DIR}/${FINAL_KEY_NAME}.pem" --region "$AWS_REGION" >/dev/null 2>&1; then
      output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Failed to download key from S3"
      exit 1
    fi
    
    chmod 0400 "${LOCAL_KEY_DIR}/${FINAL_KEY_NAME}.pem" || {
      output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" "Failed to set key permissions"
      exit 1
    }
  fi
fi

output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" ""
exit 0