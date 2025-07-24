#!/bin/bash

KEY_NAME=$1
AWS_REGION=$2
S3_BUCKET="splunk-deployment-test"

# Step 1: Get all existing EC2 key names that match the base
EXISTING_KEYS=$(aws ec2 describe-key-pairs \
    --region "$AWS_REGION" \
    --query "KeyPairs[?starts_with(KeyName, \`$KEY_NAME\`)].KeyName" \
    --output text)

# Step 2: Find max suffix
max_suffix=0

for key in $EXISTING_KEYS; do
    if [[ "$key" == "$KEY_NAME" ]]; then
        if [ "$max_suffix" -eq 0 ]; then
            max_suffix=0
        fi
    elif [[ "$key" =~ ^$KEY_NAME-([0-9]+)$ ]]; then
        suffix="${BASH_REMATCH[1]}"
        if [ "$suffix" -gt "$max_suffix" ]; then
            max_suffix=$suffix
        fi
    fi
done

# Step 3: Suggest new key name if needed
next_suffix=$((max_suffix + 1))
final_key_name=$KEY_NAME
if [ "$max_suffix" -gt 0 ]; then
    final_key_name="${KEY_NAME}-${next_suffix}"
fi

# Step 4: Check if PEM exists in S3
S3_KEY="clients/${KEY_NAME}/keys/${KEY_NAME}.pem"
aws s3api head-object --bucket "$S3_BUCKET" --key "$S3_KEY" --region "$AWS_REGION" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "{\"final_key_name\":\"$KEY_NAME\", \"exists\": true}"
else
    echo "{\"final_key_name\":\"$final_key_name\", \"exists\": false}"
fi
