#!/bin/bash
# Create security group for instant-env SSH access
# Idempotent: skips if group already exists

set -euo pipefail

SG_NAME="instant-env-ssh"
DESCRIPTION="SSH access for instant-env benchmarking"

echo "Creating security group: $SG_NAME"

# Check if exists
EXISTING=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=$SG_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "None")

if [ "$EXISTING" != "None" ] && [ "$EXISTING" != "" ]; then
    echo "Security group already exists: $EXISTING"
    exit 0
fi

# Get default VPC
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [ "$VPC_ID" == "None" ] || [ -z "$VPC_ID" ]; then
    echo "Error: No default VPC found. Create one or modify this script."
    exit 1
fi

echo "Using VPC: $VPC_ID"

# Create security group
SG_ID=$(aws ec2 create-security-group \
    --group-name "$SG_NAME" \
    --description "$DESCRIPTION" \
    --vpc-id "$VPC_ID" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Project,Value=instant-env},{Key=Purpose,Value=benchmark},{Key=ManagedBy,Value=cli}]" \
    --query 'GroupId' \
    --output text)

echo "Created security group: $SG_ID"

# Add SSH ingress rule
aws ec2 authorize-security-group-ingress \
    --group-id "$SG_ID" \
    --protocol tcp \
    --port 22 \
    --cidr 0.0.0.0/0

echo "Added SSH ingress rule (0.0.0.0/0:22)"
echo "Done. Security group ID: $SG_ID"
