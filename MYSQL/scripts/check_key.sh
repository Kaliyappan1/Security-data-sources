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

# Function to find highest existing suffix for a key
find_highest_suffix() {
  local base_name=$1
  local max_suffix=0
  
  # Check AWS for existing keys with suffixes
  aws ec2 describe-key-pairs --region "$AWS_REGION" --query "KeyPairs[?starts_with(KeyName, '${base_name}-')].KeyName" --output text | \
  while read -r key; do
    suffix=$(echo "$key" | sed "s/^${base_name}-//")
    if [[ "$suffix" =~ ^[0-9]+$ ]] && [ "$suffix" -gt "$max_suffix" ]; then
      max_suffix=$suffix
    fi
  done
  
  # Check S3 for existing keys with suffixes
  aws s3api list-objects --bucket "$BUCKET" --prefix "clients/${USERMAIL}/keys/${base_name}-" --region "$AWS_REGION" --query "Contents[].Key" --output text | \
  while read -r key; do
    suffix=$(basename "$key" .pem | sed "s/^${base_name}-//")
    if [[ "$suffix" =~ ^[0-9]+$ ]] && [ "$suffix" -gt "$max_suffix" ]; then
      max_suffix=$suffix
    fi
  done
  
  echo $max_suffix
}

# Check if original key exists
ORIGINAL_EXISTS_AWS=$(check_aws_key_exists "$CLEAN_KEY_NAME" && echo "true" || echo "false")
ORIGINAL_EXISTS_S3=$(check_s3_key_exists "$CLEAN_KEY_NAME" && echo "true" || echo "false")

if [[ "$ORIGINAL_EXISTS_AWS" == "false" && "$ORIGINAL_EXISTS_S3" == "false" ]]; then
  # No existing key - use original name
  FINAL_KEY_NAME="$CLEAN_KEY_NAME"
else
  # Find the highest existing suffix
  HIGHEST_SUFFIX=$(find_highest_suffix "$CLEAN_KEY_NAME")
  
  if [ "$HIGHEST_SUFFIX" -gt 0 ]; then
    # Reuse the highest suffix
    FINAL_KEY_NAME="${CLEAN_KEY_NAME}-${HIGHEST_SUFFIX}"
    EXISTS_AWS=$(check_aws_key_exists "$FINAL_KEY_NAME" && echo "true" || echo "false")
    EXISTS_S3=$(check_s3_key_exists "$FINAL_KEY_NAME" && echo "true" || echo "false")
  else
    # No existing suffixes - start with 1
    FINAL_KEY_NAME="${CLEAN_KEY_NAME}-1"
    EXISTS_AWS="false"
    EXISTS_S3="false"
  fi
  
  # Try to download from S3 if it exists
  if [[ "$EXISTS_S3" == "true" ]]; then
    mkdir -p "$LOCAL_KEY_DIR" || {
      output_json "$EXISTS_S3" "$EXISTS_AWS" "Failed to create local directory"
      exit 1
    }
    
    S3_KEY_PATH="clients/${USERMAIL}/keys/${FINAL_KEY_NAME}.pem"
    if ! aws s3 cp "s3://${BUCKET}/${S3_KEY_PATH}" "${LOCAL_KEY_DIR}/${FINAL_KEY_NAME}.pem" --region "$AWS_REGION" >/dev/null 2>&1; then
      output_json "$EXISTS_S3" "$EXISTS_AWS" "Failed to download key from S3"
      exit 1
    fi
    
    chmod 0400 "${LOCAL_KEY_DIR}/${FINAL_KEY_NAME}.pem" || {
      output_json "$EXISTS_S3" "$EXISTS_AWS" "Failed to set key permissions"
      exit 1
    }
  fi
fi

output_json "$ORIGINAL_EXISTS_S3" "$ORIGINAL_EXISTS_AWS" ""
exit 0