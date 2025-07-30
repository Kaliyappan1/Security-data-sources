#!/bin/bash

set -euo pipefail
exec 3>&1
exec 1>&2

KEY_NAME="$1"
AWS_REGION="$2"
USERMAIL="$3"
LOCAL_KEY_DIR="$4"
BUCKET="splunk-deployment-test"

CLEAN_KEY_NAME=$(echo "$KEY_NAME" | tr ' ' '-')

output_json() {
  echo "{\"final_key_name\": \"$FINAL_KEY_NAME\", \"exists_in_s3\": \"$1\", \"exists_in_aws\": \"$2\", \"error\": \"$3\"}" >&3
}

check_aws_key_exists() {
  aws ec2 describe-key-pairs --key-names "$1" --region "$AWS_REGION" >/dev/null 2>&1
}

check_s3_key_exists() {
  local s3_key="clients/${USERMAIL}/keys/${1}.pem"
  aws s3api head-object --bucket "$BUCKET" --key "$s3_key" --region "$AWS_REGION" >/dev/null 2>&1
}

# 🔁 Find key suffix for current user
find_user_suffix() {
  for i in {0..20}; do
    local name="$CLEAN_KEY_NAME"
    [[ $i -ne 0 ]] && name="${CLEAN_KEY_NAME}-${i}"

    if check_s3_key_exists "$name"; then
      echo "$name"
      return 0
    fi
  done
  return 1
}

# 🔍 Find max suffix in global (AWS + S3) space
find_max_suffix() {
  local max=-1
  for i in {0..20}; do
    local name="$CLEAN_KEY_NAME"
    [[ $i -ne 0 ]] && name="${CLEAN_KEY_NAME}-${i}"

    if check_aws_key_exists "$name" || aws s3api head-object --bucket "$BUCKET" --key "clients/" --query "Contents[?contains(Key, '$name.pem')]" --region "$AWS_REGION" >/dev/null 2>&1; then
      max=$i
    fi
  done
  echo "$((max + 1))"
}

# 1️⃣ Try to reuse key for this user
FINAL_KEY_NAME="$(find_user_suffix || true)"

if [[ -n "$FINAL_KEY_NAME" ]]; then
  AWS_KEY_EXISTS=$(check_aws_key_exists "$FINAL_KEY_NAME" && echo "true" || echo "false")
  S3_KEY_EXISTS="true"

  mkdir -p "$LOCAL_KEY_DIR"
  aws s3 cp "s3://${BUCKET}/clients/${USERMAIL}/keys/${FINAL_KEY_NAME}.pem" "${LOCAL_KEY_DIR}/${FINAL_KEY_NAME}.pem" --region "$AWS_REGION"
  chmod 0400 "${LOCAL_KEY_DIR}/${FINAL_KEY_NAME}.pem"

else
  # 2️⃣ Else, calculate new suffix
  NEW_SUFFIX=$(find_max_suffix)
  FINAL_KEY_NAME="${CLEAN_KEY_NAME}-${NEW_SUFFIX}"
  AWS_KEY_EXISTS="false"
  S3_KEY_EXISTS="false"
fi

output_json "$S3_KEY_EXISTS" "$AWS_KEY_EXISTS" ""
exit 0