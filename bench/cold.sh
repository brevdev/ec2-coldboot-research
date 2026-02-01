#!/bin/bash
# Benchmark: Cold launch with cloud-init
# This is the baseline - full RunInstances with default Amazon Linux 2023

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

KEY_FILE="${1:-$HOME/.ssh/instant-env-admin.pem}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Usage: $0 <private_key_file>"
  echo "Run scripts/setup-keypair.sh first"
  exit 1
fi

echo "=== Cold Launch Benchmark ==="
echo "Instance: m7i.large"
echo "Technique: cloud-init (baseline)"
echo ""

# Get AMI and security group
AMI=$(get_al2023_ami)
SG=$(get_security_group)
echo "AMI: $AMI"
echo "Security Group: $SG"

# Start timing
T_START=$(now_ms)

# Launch instance
echo ""
echo "Launching instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI" \
  --instance-type m7i.large \
  --key-name instant-env-admin \
  --security-group-ids "$SG" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=cold}]' \
  --query 'Instances[0].InstanceId' \
  --output text)

T_API=$(now_ms)
echo "Instance ID: $INSTANCE_ID (API took $((T_API - T_START))ms)"

# Wait for running
echo "Waiting for running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
T_RUNNING=$(now_ms)
echo "Running after $((T_RUNNING - T_START))ms"

# Get public IP
IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)
echo "Public IP: $IP"

# Wait for SSH
T_SSH=$(wait_for_ssh "$IP" "$KEY_FILE")

# Print results
print_timing "COLD LAUNCH" "$T_START" "$T_API" "$T_RUNNING" "$T_SSH"

# Cleanup
read -p "Terminate instance? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  cleanup_instance "$INSTANCE_ID"
fi
