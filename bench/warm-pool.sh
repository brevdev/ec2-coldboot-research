#!/bin/bash
# Benchmark: Warm pool - running instance, inject new SSH key
# Simulates grabbing a pre-running instance and provisioning access
#
# This measures the theoretical minimum: instance already running,
# just need to inject credentials and connect.
#
# Usage: ./bench/warm-pool.sh <existing_key_file> [instance_id]

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

EXISTING_KEY="${1:-$HOME/.ssh/instant-env-admin.pem}"
INSTANCE_ID="${2:-}"

if [[ ! -f "$EXISTING_KEY" ]]; then
  echo "Usage: $0 <existing_private_key> [instance_id]"
  exit 1
fi

echo "=== Warm Pool Benchmark ==="
echo "Technique: Running instance + SSH key injection"
echo ""

# Generate a fresh keypair for this "user session"
TEMP_DIR=$(mktemp -d)
NEW_KEY="$TEMP_DIR/session-key"
NEW_KEY_PUB="$TEMP_DIR/session-key.pub"

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

  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI" \
    --instance-type m7i.large \
    --key-name instant-env-admin \
    --security-group-ids "$SG" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=warm-pool}]' \
    --query 'Instances[0].InstanceId' \
    --output text)
  CREATED_INSTANCE="$INSTANCE_ID"

  echo "Created instance: $INSTANCE_ID"
  echo "Waiting for running + SSH ready..."
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

  # Wait for SSH with existing key
  wait_for_ssh "$IP" "$EXISTING_KEY" >/dev/null
  echo "Instance ready: $IP"
  echo ""
fi

# Get instance IP
IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)

echo "Instance: $INSTANCE_ID"
echo "IP: $IP"
echo ""

# === BENCHMARK STARTS HERE ===
# This is what we're measuring: from "give me an instance" to "I can SSH in"

echo "=== Starting warm pool benchmark ==="
echo "Simulating: User requests instance from pool"
echo ""

T_START=$(now_ms)

# Step 1: Generate new keypair (simulates user's fresh session key)
echo "Generating session keypair..."
ssh-keygen -t ed25519 -f "$NEW_KEY" -N "" -q
T_KEYGEN=$(now_ms)
echo "  Keypair generated: $((T_KEYGEN - T_START))ms"

# Step 2: Inject public key via existing SSH access
# (In production, could use EC2 Instance Connect API, SSM, or pre-baked agent)
echo "Injecting public key..."
NEW_PUB=$(cat "$NEW_KEY_PUB")
ssh -i "$EXISTING_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes \
  ec2-user@"$IP" "echo '$NEW_PUB' >> ~/.ssh/authorized_keys"
T_INJECT=$(now_ms)
echo "  Key injected: $((T_INJECT - T_START))ms (+$((T_INJECT - T_KEYGEN))ms)"

# Step 3: Connect with new key
echo "Connecting with new session key..."
ssh -i "$NEW_KEY" -o StrictHostKeyChecking=no -o BatchMode=yes \
  ec2-user@"$IP" "echo 'Session established'"
T_CONNECT=$(now_ms)
echo "  Connected: $((T_CONNECT - T_START))ms (+$((T_CONNECT - T_INJECT))ms)"

# Results
echo ""
echo "=== WARM POOL RESULTS ==="
echo "Keygen:       $((T_KEYGEN - T_START))ms"
echo "Key inject:   $((T_INJECT - T_KEYGEN))ms"
echo "SSH connect:  $((T_CONNECT - T_INJECT))ms"
echo "---"
echo "TOTAL:        $((T_CONNECT - T_START))ms"
echo ""

# Comparison
TOTAL_MS=$((T_CONNECT - T_START))
echo "=== Comparison ==="
echo "  Cold launch:       25800ms"
echo "  Start-stopped:     21200ms"
echo "  Warm pool:         ${TOTAL_MS}ms"
echo ""
SAVED_PCT=$(echo "scale=0; (25800 - $TOTAL_MS) * 100 / 25800" | bc)
echo "  Speedup vs cold:   ${SAVED_PCT}%"
echo ""
echo "This is the theoretical floor with pre-running instances."
