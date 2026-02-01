#!/bin/bash
# Benchmark: Launch with minimal AMI (no cloud-init)
# Compares to cold baseline to measure cloud-init overhead
#
# Prerequisites:
#   1. Run scripts/bake-minimal-ami.sh first to create the AMI
#   2. Set MINIMAL_AMI_ID env var or pass as second argument

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

KEY_FILE="${1:-$HOME/.ssh/instant-env-admin.pem}"
AMI_ID="${2:-${MINIMAL_AMI_ID:-}}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Usage: $0 <private_key_file> [ami_id]"
  echo "Run scripts/setup-keypair.sh first"
  exit 1
fi

if [[ -z "$AMI_ID" ]]; then
  echo "Usage: $0 <private_key_file> <ami_id>"
  echo "  Or set MINIMAL_AMI_ID environment variable"
  echo ""
  echo "Run scripts/bake-minimal-ami.sh first to create the minimal AMI"
  exit 1
fi

echo "=== Minimal AMI Benchmark ==="
echo "Instance: m7i.large"
echo "Technique: minimal AMI (no cloud-init)"
echo ""

# Verify AMI exists
AMI_STATE=$(aws ec2 describe-images \
  --image-ids "$AMI_ID" \
  --query 'Images[0].State' \
  --output text 2>/dev/null || echo "not-found")

if [[ "$AMI_STATE" != "available" ]]; then
  echo "ERROR: AMI $AMI_ID not found or not available (state: $AMI_STATE)"
  exit 1
fi

SG=$(get_security_group)
echo "AMI: $AMI_ID"
echo "Security Group: $SG"

# Start timing
T_START=$(now_ms)

# Launch instance
echo ""
echo "Launching instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type m7i.large \
  --key-name instant-env-admin \
  --security-group-ids "$SG" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=minimal-ami}]' \
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
print_timing "MINIMAL AMI LAUNCH" "$T_START" "$T_API" "$T_RUNNING" "$T_SSH"

# Compare to baseline
echo ""
echo "Compare to cold baseline (25.8s avg):"
TOTAL_MS=$((T_SSH - T_START))
TOTAL_S=$(echo "scale=1; $TOTAL_MS / 1000" | bc)
SAVED_MS=$((25800 - TOTAL_MS))
echo "  This run: ${TOTAL_S}s"
echo "  Difference: ${SAVED_MS}ms"

# Cleanup
read -p "Terminate instance? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  cleanup_instance "$INSTANCE_ID"
fi
