#!/bin/bash
# Create EC2 key pair for admin access during AMI baking
# Idempotent: skips if key already exists

set -euo pipefail

KEY_NAME="instant-env-admin"
KEY_FILE="$HOME/.ssh/${KEY_NAME}.pem"

echo "Creating key pair: $KEY_NAME"

# Check if exists in AWS
EXISTING=$(aws ec2 describe-key-pairs \
    --key-names "$KEY_NAME" \
    --query 'KeyPairs[0].KeyName' \
    --output text 2>/dev/null || echo "None")

if [ "$EXISTING" != "None" ] && [ "$EXISTING" != "" ]; then
    echo "Key pair already exists in AWS: $KEY_NAME"
    if [ -f "$KEY_FILE" ]; then
        echo "Private key exists at: $KEY_FILE"
    else
        echo "WARNING: Private key not found at $KEY_FILE"
        echo "You may need to delete the key pair and recreate it."
    fi
    exit 0
fi

# Create key pair
aws ec2 create-key-pair \
    --key-name "$KEY_NAME" \
    --key-type ed25519 \
    --tag-specifications "ResourceType=key-pair,Tags=[{Key=Project,Value=instant-env},{Key=Purpose,Value=benchmark},{Key=ManagedBy,Value=cli}]" \
    --query 'KeyMaterial' \
    --output text > "$KEY_FILE"

chmod 600 "$KEY_FILE"

echo "Created key pair: $KEY_NAME"
echo "Private key saved to: $KEY_FILE"
