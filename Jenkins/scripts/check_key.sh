#!/bin/bash

KEY_NAME=$1
AWS_REGION=$2

# Get all existing key names starting with the given prefix
EXISTING_KEYS=$(aws ec2 describe-key-pairs \
    --region "$AWS_REGION" \
    --query "KeyPairs[?starts_with(KeyName, \`$KEY_NAME\`)].KeyName" \
    --output text)

# If no existing keys, return the original key name
if [ -z "$EXISTING_KEYS" ]; then
    echo "{\"final_key_name\":\"$KEY_NAME\"}"
    exit 0
fi

# Initialize max_suffix
max_suffix=0

for key in $EXISTING_KEYS; do
    if [[ "$key" == "$KEY_NAME" ]]; then
        # base key exists without suffix
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

# Suggest next key name
next_suffix=$((max_suffix + 1))
next_key_name="${KEY_NAME}-${next_suffix}"

echo "{\"final_key_name\":\"$next_key_name\"}"
