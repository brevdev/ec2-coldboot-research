#!/bin/bash
# Benchmark: Launch with pre-allocated ENI
# Tests whether pre-creating the ENI reduces Pending→Running time
#
# Hypothesis: ENI creation/attachment is part of the ~18s pending phase.
# Pre-allocating it should reduce that time.
#
# Prerequisites:
#   1. Run scripts/setup-eni.sh first to create the ENI
#   2. Set PRE_ENI_ID env var or pass as second argument

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

KEY_FILE="${1:-$HOME/.ssh/instant-env-admin.pem}"
ENI_ID="${2:-${PRE_ENI_ID:-}}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Usage: $0 <private_key_file> [eni_id]"
  echo "Run scripts/setup-keypair.sh first"
  exit 1
fi

if [[ -z "$ENI_ID" ]]; then
  echo "Usage: $0 <private_key_file> <eni_id>"
  echo "  Or set PRE_ENI_ID environment variable"
  echo ""
  echo "Run scripts/setup-eni.sh first to create a pre-allocated ENI"
  exit 1
fi

echo "=== Pre-allocated ENI Benchmark ==="
echo "Instance: m7i.large"
echo "Technique: pre-allocated ENI"
echo ""

# Verify ENI exists and get its subnet/AZ
ENI_INFO=$(aws ec2 describe-network-interfaces \
  --network-interface-ids "$ENI_ID" \
  --query 'NetworkInterfaces[0].{Status:Status,SubnetId:SubnetId,AZ:AvailabilityZone}' \
  --output json 2>/dev/null || echo '{"Status":"not-found"}')

ENI_STATUS=$(echo "$ENI_INFO" | grep -o '"Status":"[^"]*"' | cut -d'"' -f4)
SUBNET_ID=$(echo "$ENI_INFO" | grep -o '"SubnetId":"[^"]*"' | cut -d'"' -f4)
AZ=$(echo "$ENI_INFO" | grep -o '"AZ":"[^"]*"' | cut -d'"' -f4)

if [[ "$ENI_STATUS" != "available" ]]; then
  echo "ERROR: ENI $ENI_ID not available (status: $ENI_STATUS)"
  echo "Make sure the ENI exists and is not attached to another instance"
  exit 1
fi

# Get AMI
AMI=$(get_al2023_ami)
echo "ENI: $ENI_ID"
echo "Subnet: $SUBNET_ID"
echo "AZ: $AZ"
echo "AMI: $AMI"

# Start timing
T_START=$(now_ms)

# Launch instance with pre-allocated ENI
# Note: We use --network-interfaces which replaces --security-group-ids
echo ""
echo "Launching instance with pre-allocated ENI..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI" \
  --instance-type m7i.large \
  --key-name instant-env-admin \
  --network-interfaces "NetworkInterfaceId=$ENI_ID,DeviceIndex=0" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=pre-eni}]' \
  --query 'Instances[0].InstanceId' \
  --output text)

T_API=$(now_ms)
echo "Instance ID: $INSTANCE_ID (API took $((T_API - T_START))ms)"

# Wait for running
echo "Waiting for running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
T_RUNNING=$(now_ms)
echo "Running after $((T_RUNNING - T_START))ms"

# Get public IP (from the ENI now attached to the instance)
IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

if [[ "$IP" == "None" ]] || [[ -z "$IP" ]]; then
  echo "WARNING: No public IP assigned. ENI may not have auto-assign public IP."
  echo "Checking ENI for public IP..."
  IP=$(aws ec2 describe-network-interfaces \
    --network-interface-ids "$ENI_ID" \
    --query 'NetworkInterfaces[0].Association.PublicIp' \
    --output text 2>/dev/null || echo "None")
fi

if [[ "$IP" == "None" ]] || [[ -z "$IP" ]]; then
  echo "ERROR: No public IP. Need to allocate/associate an EIP to the ENI."
  echo "Terminating instance..."
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null
  exit 1
fi

echo "Public IP: $IP"

# Wait for SSH
T_SSH=$(wait_for_ssh "$IP" "$KEY_FILE")

# Print results
print_timing "PRE-ENI LAUNCH" "$T_START" "$T_API" "$T_RUNNING" "$T_SSH"

# Compare to baseline
echo ""
echo "Compare to cold baseline (25.8s avg, 17.8s pending):"
TOTAL_MS=$((T_SSH - T_START))
PENDING_MS=$((T_RUNNING - T_API))
TOTAL_S=$(echo "scale=1; $TOTAL_MS / 1000" | bc)
PENDING_S=$(echo "scale=1; $PENDING_MS / 1000" | bc)
echo "  This run: ${TOTAL_S}s total, ${PENDING_S}s pending"
echo "  Pending saved: $((17800 - PENDING_MS))ms"

# Cleanup - but detach ENI first so it can be reused
echo ""
read -p "Terminate instance? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  echo "Terminating instance (ENI will be detached automatically)..."
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null

  # Wait for ENI to become available again
  echo "Waiting for ENI to become available for reuse..."
  for i in {1..30}; do
    STATUS=$(aws ec2 describe-network-interfaces \
      --network-interface-ids "$ENI_ID" \
      --query 'NetworkInterfaces[0].Status' \
      --output text 2>/dev/null || echo "unknown")
    if [[ "$STATUS" == "available" ]]; then
      echo "ENI $ENI_ID is available for reuse"
      break
    fi
    sleep 2
  done
fi
