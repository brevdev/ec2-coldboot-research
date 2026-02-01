#!/bin/bash
# Benchmark: Realistic warm pool with EC2 Instance Connect
# Simulates full production flow including pool management API calls:
#
# 1. Query for available instances in warm pool (describe-instances)
# 2. Claim instance by updating tags (create-tags)
# 3. Generate session keypair
# 4. Push key via EC2 Instance Connect
# 5. SSH connect
#
# This measures the realistic end-to-end time from "user requests instance"
# to "user has SSH access"
#
# Usage: ./bench/warm-pool-realistic.sh [instance_id]

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

INSTANCE_ID="${1:-}"

echo "=== Realistic Warm Pool Benchmark ==="
echo "Simulates: Query pool → Claim instance → EIC key push → SSH"
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
    else
      # Reset pool status so it can be reused
      echo "Resetting WarmPoolStatus to 'available'..."
      aws ec2 create-tags \
        --resources "$CREATED_INSTANCE" \
        --tags Key=WarmPoolStatus,Value=available
    fi
  fi
}
trap cleanup EXIT

# If no instance provided, create a running one with warm pool tags
if [[ -z "$INSTANCE_ID" ]]; then
  echo "No instance provided, creating a warm pool instance first..."
  echo "(In production, this would already exist in the pool)"
  echo ""

  AMI=$(get_al2023_ami)
  SG=$(get_security_group)

  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI" \
    --instance-type m7i.large \
    --key-name instant-env-admin \
    --security-group-ids "$SG" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=warm-pool-realistic},{Key=WarmPoolStatus,Value=available}]' \
    --query 'Instances[0].InstanceId' \
    --output text)
  CREATED_INSTANCE="$INSTANCE_ID"

  echo "Created instance: $INSTANCE_ID"
  echo "Waiting for running + status checks..."
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  echo "Waiting for instance status checks (required for EC2 Instance Connect)..."
  aws ec2 wait instance-status-ok --instance-ids "$INSTANCE_ID"

  echo "Instance ready in warm pool."
  echo ""
fi

echo "=== Starting realistic warm pool benchmark ==="
echo "Simulating: User requests an instance from the warm pool"
echo ""

# === BENCHMARK STARTS HERE ===
T_START=$(now_ms)

# Step 1: Query for available instances in warm pool
echo "1. Querying warm pool for available instances..."
AVAILABLE_INSTANCE=$(aws ec2 describe-instances \
  --filters \
    "Name=tag:Project,Values=instant-env" \
    "Name=tag:WarmPoolStatus,Values=available" \
    "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].[InstanceId,PublicIpAddress,Placement.AvailabilityZone]' \
  --output text)

T_QUERY=$(now_ms)

if [[ -z "$AVAILABLE_INSTANCE" ]] || [[ "$AVAILABLE_INSTANCE" == "None"* ]]; then
  echo "   ERROR: No available instances in warm pool"
  exit 1
fi

INSTANCE_ID=$(echo "$AVAILABLE_INSTANCE" | awk '{print $1}')
IP=$(echo "$AVAILABLE_INSTANCE" | awk '{print $2}')
AZ=$(echo "$AVAILABLE_INSTANCE" | awk '{print $3}')

echo "   Found: $INSTANCE_ID ($IP in $AZ)"
echo "   Query time: $((T_QUERY - T_START))ms"

# Step 2: Claim instance by updating tags
echo "2. Claiming instance (updating WarmPoolStatus tag)..."
aws ec2 create-tags \
  --resources "$INSTANCE_ID" \
  --tags Key=WarmPoolStatus,Value=claimed Key=ClaimedAt,Value="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

T_CLAIM=$(now_ms)
echo "   Claimed: +$((T_CLAIM - T_QUERY))ms"

# Step 3: Generate session keypair
echo "3. Generating session keypair..."
ssh-keygen -t ed25519 -f "$SESSION_KEY" -N "" -q
T_KEYGEN=$(now_ms)
echo "   Keypair generated: +$((T_KEYGEN - T_CLAIM))ms"

# Step 4: Push public key via EC2 Instance Connect API
echo "4. Pushing key via EC2 Instance Connect..."
PUB_KEY_CONTENT=$(cat "$SESSION_KEY_PUB")

aws ec2-instance-connect send-ssh-public-key \
  --instance-id "$INSTANCE_ID" \
  --instance-os-user ec2-user \
  --ssh-public-key "$PUB_KEY_CONTENT" \
  --availability-zone "$AZ" \
  --output text >/dev/null

T_PUSH=$(now_ms)
echo "   Key pushed: +$((T_PUSH - T_KEYGEN))ms"

# Step 5: Connect with session key
echo "5. Connecting with session key..."
ssh -i "$SESSION_KEY" \
  -o StrictHostKeyChecking=no \
  -o BatchMode=yes \
  -o ConnectTimeout=10 \
  ec2-user@"$IP" "echo 'Session established'"

T_CONNECT=$(now_ms)
echo "   Connected: +$((T_CONNECT - T_PUSH))ms"

# Results
echo ""
echo "=== REALISTIC WARM POOL RESULTS ==="
echo ""
echo "Phase breakdown:"
echo "  1. Query pool:      $((T_QUERY - T_START))ms"
echo "  2. Claim instance:  $((T_CLAIM - T_QUERY))ms"
echo "  3. Keygen:          $((T_KEYGEN - T_CLAIM))ms"
echo "  4. EIC key push:    $((T_PUSH - T_KEYGEN))ms"
echo "  5. SSH connect:     $((T_CONNECT - T_PUSH))ms"
echo "  ---"
echo "  TOTAL:              $((T_CONNECT - T_START))ms"
echo ""

# Grouped breakdown
POOL_MGMT=$((T_CLAIM - T_START))
KEY_INJECT=$((T_PUSH - T_CLAIM))
SSH_TIME=$((T_CONNECT - T_PUSH))
TOTAL_MS=$((T_CONNECT - T_START))

echo "Grouped breakdown:"
echo "  Pool management (query + claim):  ${POOL_MGMT}ms"
echo "  Key injection (keygen + push):    ${KEY_INJECT}ms"
echo "  SSH connect:                      ${SSH_TIME}ms"
echo "  ---"
echo "  TOTAL:                            ${TOTAL_MS}ms"
echo ""

# Comparison
echo "=== Comparison ==="
echo "  Cold launch:              25800ms"
echo "  Warm pool (simple EIC):   3949ms"
echo "  Warm pool (realistic):    ${TOTAL_MS}ms"
echo ""

OVERHEAD=$((TOTAL_MS - 3949))
echo "  Pool management overhead: ~${OVERHEAD}ms"

SAVED_PCT=$(echo "scale=0; (25800 - $TOTAL_MS) * 100 / 25800" | bc)
echo "  Speedup vs cold:          ${SAVED_PCT}%"
