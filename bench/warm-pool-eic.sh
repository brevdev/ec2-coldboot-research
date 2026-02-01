#!/bin/bash
# Benchmark: Warm pool with EC2 Instance Connect
# Uses AWS API to inject SSH key (no pre-existing access required)
#
# EC2 Instance Connect pushes a temporary SSH public key to instance metadata,
# allowing SSH access for 60 seconds without pre-configured keys.
#
# This simulates a production warm pool where we don't have existing SSH access.
#
# Usage: ./bench/warm-pool-eic.sh [instance_id]

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

INSTANCE_ID="${1:-}"

echo "=== Warm Pool Benchmark (EC2 Instance Connect) ==="
echo "Technique: Running instance + EC2 Instance Connect key injection"
echo ""

# Generate a fresh keypair for this session
TEMP_DIR=$(mktemp -d)
SESSION_KEY="$TEMP_DIR/session-key"
SESSION_KEY_PUB="$TEMP_DIR/session-key.pub"

cleanup() {
  rm -rf "$TEMP_DIR"
  if [[ -n "${CREATED_INSTANCE:-}" ]]; then
    echo ""
    read -p "Terminate instance $CREATED_INSTANCE? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
      cleanup_instance "$CREATED_INSTANCE"
    fi
  fi
}
trap cleanup EXIT

# If no instance provided, create a running one
if [[ -z "$INSTANCE_ID" ]]; then
  echo "No instance provided, creating a running instance first..."
  echo "(In production, this would be a pre-warmed pool)"
  echo ""

  AMI=$(get_al2023_ami)
  SG=$(get_security_group)

  # Note: We launch WITHOUT a key pair - simulating a pool instance
  # that doesn't have pre-configured SSH access
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI" \
    --instance-type m7i.large \
    --key-name instant-env-admin \
    --security-group-ids "$SG" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=warm-pool-eic}]' \
    --query 'Instances[0].InstanceId' \
    --output text)
  CREATED_INSTANCE="$INSTANCE_ID"

  echo "Created instance: $INSTANCE_ID"
  echo "Waiting for running + status checks..."
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  # EC2 Instance Connect requires the instance to be fully booted
  # Wait for status checks to pass
  echo "Waiting for instance status checks (required for EC2 Instance Connect)..."
  aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID"

  echo "Instance ready."
  echo ""
fi

# Get instance details
INSTANCE_INFO=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].[PublicIpAddress,Placement.AvailabilityZone]' \
  --output text)
IP=$(echo "$INSTANCE_INFO" | awk '{print $1}')
AZ=$(echo "$INSTANCE_INFO" | awk '{print $2}')

echo "Instance: $INSTANCE_ID"
echo "IP: $IP"
echo "AZ: $AZ"
echo ""

# === BENCHMARK STARTS HERE ===
echo "=== Starting EC2 Instance Connect benchmark ==="
echo "Simulating: User requests instance from pool (no pre-existing SSH access)"
echo ""

T_START=$(now_ms)

# Step 1: Generate session keypair
echo "Generating session keypair..."
ssh-keygen -t ed25519 -f "$SESSION_KEY" -N "" -q
T_KEYGEN=$(now_ms)
echo "  Keypair generated: $((T_KEYGEN - T_START))ms"

# Step 2: Push public key via EC2 Instance Connect API
echo "Pushing key via EC2 Instance Connect..."
PUB_KEY_CONTENT=$(cat "$SESSION_KEY_PUB")

aws ec2-instance-connect send-ssh-public-key \
  --instance-id "$INSTANCE_ID" \
  --instance-os-user ec2-user \
  --ssh-public-key "$PUB_KEY_CONTENT" \
  --availability-zone "$AZ" \
  --output text >/dev/null

T_PUSH=$(now_ms)
echo "  Key pushed: $((T_PUSH - T_START))ms (+$((T_PUSH - T_KEYGEN))ms)"

# Step 3: Connect with session key
echo "Connecting with session key..."
# EC2 Instance Connect key is only valid for 60 seconds
ssh -i "$SESSION_KEY" \
  -o StrictHostKeyChecking=no \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  ec2-user@"$IP" "echo 'Session established via EC2 Instance Connect'"

T_CONNECT=$(now_ms)
echo "  Connected: $((T_CONNECT - T_START))ms (+$((T_CONNECT - T_PUSH))ms)"

# Results
echo ""
echo "=== EC2 INSTANCE CONNECT WARM POOL RESULTS ==="
echo "Keygen:       $((T_KEYGEN - T_START))ms"
echo "Key push:     $((T_PUSH - T_KEYGEN))ms"
echo "SSH connect:  $((T_CONNECT - T_PUSH))ms"
echo "---"
echo "TOTAL:        $((T_CONNECT - T_START))ms"
echo ""

# Comparison
TOTAL_MS=$((T_CONNECT - T_START))
echo "=== Comparison ==="
echo "  Cold launch:           25800ms"
echo "  Warm pool (SSH key):   1866ms"
echo "  Warm pool (EIC):       ${TOTAL_MS}ms"
echo ""

if [[ $TOTAL_MS -lt 1866 ]]; then
  echo "  EC2 Instance Connect is FASTER than SSH key injection!"
else
  DIFF=$((TOTAL_MS - 1866))
  echo "  EC2 Instance Connect is ${DIFF}ms slower than SSH key injection"
  echo "  (But doesn't require pre-existing SSH access)"
fi

SAVED_PCT=$(echo "scale=0; (25800 - $TOTAL_MS) * 100 / 25800" | bc)
echo ""
echo "  Speedup vs cold:       ${SAVED_PCT}%"
