#!/bin/bash
# Create a pre-allocated ENI for instant-env benchmarking
# Idempotent: reuses existing ENI if found
#
# The hypothesis is that pre-creating the ENI saves time during
# instance launch since AWS doesn't need to create+attach it.

set -euo pipefail

ENI_NAME="instant-env-pre-eni"

echo "=== Pre-allocated ENI Setup ==="

# Get security group
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=instant-env-ssh" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "None")

if [[ "$SG_ID" == "None" ]] || [[ -z "$SG_ID" ]]; then
    echo "Error: Security group 'instant-env-ssh' not found."
    echo "Run scripts/setup-security-group.sh first"
    exit 1
fi

echo "Security Group: $SG_ID"

# Check if ENI already exists
EXISTING_ENI=$(aws ec2 describe-network-interfaces \
    --filters "Name=tag:Name,Values=$ENI_NAME" \
              "Name=status,Values=available" \
    --query 'NetworkInterfaces[0].NetworkInterfaceId' \
    --output text 2>/dev/null || echo "None")

if [[ "$EXISTING_ENI" != "None" ]] && [[ -n "$EXISTING_ENI" ]]; then
    echo "ENI already exists and is available: $EXISTING_ENI"
    echo ""
    echo "To use in benchmark:"
    echo "  PRE_ENI_ID=$EXISTING_ENI ./bench/pre-eni.sh ~/.ssh/instant-env-admin.pem"
    exit 0
fi

# Get default VPC
VPC_ID=$(aws ec2 describe-vpcs \
    --filters "Name=is-default,Values=true" \
    --query 'Vpcs[0].VpcId' \
    --output text)

if [[ "$VPC_ID" == "None" ]] || [[ -z "$VPC_ID" ]]; then
    echo "Error: No default VPC found."
    exit 1
fi

echo "VPC: $VPC_ID"

# Get a subnet from the default VPC
SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
              "Name=default-for-az,Values=true" \
    --query 'Subnets[0].SubnetId' \
    --output text)

if [[ "$SUBNET_ID" == "None" ]] || [[ -z "$SUBNET_ID" ]]; then
    echo "Error: No default subnet found in VPC $VPC_ID"
    exit 1
fi

echo "Subnet: $SUBNET_ID"

# Create the ENI
echo ""
echo "Creating ENI..."
ENI_ID=$(aws ec2 create-network-interface \
    --subnet-id "$SUBNET_ID" \
    --groups "$SG_ID" \
    --description "Pre-allocated ENI for instant-env benchmark" \
    --tag-specifications "ResourceType=network-interface,Tags=[{Key=Name,Value=$ENI_NAME},{Key=Project,Value=instant-env},{Key=Purpose,Value=pre-eni-benchmark}]" \
    --query 'NetworkInterface.NetworkInterfaceId' \
    --output text)

echo "Created ENI: $ENI_ID"

# Get the subnet's AZ for reference
AZ=$(aws ec2 describe-subnets \
    --subnet-ids "$SUBNET_ID" \
    --query 'Subnets[0].AvailabilityZone' \
    --output text)

echo "Availability Zone: $AZ"

echo ""
echo "=== SUCCESS ==="
echo "ENI ID: $ENI_ID"
echo "Subnet: $SUBNET_ID"
echo "AZ: $AZ"
echo ""
echo "To use in benchmark:"
echo "  PRE_ENI_ID=$ENI_ID ./bench/pre-eni.sh ~/.ssh/instant-env-admin.pem"
echo ""
echo "NOTE: The instance must launch in the same AZ as the ENI ($AZ)"
