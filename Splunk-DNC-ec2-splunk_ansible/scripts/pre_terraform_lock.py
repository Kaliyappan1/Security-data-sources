import boto3
import time
import json
import botocore
import os

s3 = boto3.client('s3')

bucket = "splunk-deployment-test"
usermail = os.getenv("TF_VAR_usermail")
key_name = os.getenv("TF_VAR_key_name").replace(" ", "-")
region = os.getenv("TF_VAR_aws_region")

lock_key = f"clients/{usermail}/key-lock.json"
pem_key = f"clients/{usermail}/keys/{key_name}.pem"

# Wait for lock to clear if present
for attempt in range(10):
    try:
        s3.head_object(Bucket=bucket, Key=lock_key)
        print(f"🔒 Lock exists. Waiting... attempt {attempt+1}")
        time.sleep(10)
    except botocore.exceptions.ClientError:
        break  # Lock not found

# Check if PEM already in S3
try:
    s3.head_object(Bucket=bucket, Key=pem_key)
    print("✅ Key already exists in S3. No lock needed.")
    exit(0)
except botocore.exceptions.ClientError:
    print("🔑 Key not found. Creating lock...")

# Create lock
s3.put_object(Bucket=bucket, Key=lock_key, Body=json.dumps({"status": "generating"}))
