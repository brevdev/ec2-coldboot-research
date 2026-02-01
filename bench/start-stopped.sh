#!/bin/bash
# Benchmark: Start a stopped instance (pre-warmed disk/ENI)
# Simulates warm pool behavior - EBS and ENI already attached
#
# Usage: ./bench/start-stopped.sh <private_key_file> [instance_id]
#
# If no instance_id provided, creates one and stops it first.

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

KEY_FILE="${1:-$HOME/.ssh/instant-env-admin.pem}"
INSTANCE_ID="${2:-}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Usage: $0 <private_key_file> [instance_id]"
  echo "Run scripts/setup-keypair.sh first"
  exit 1
fi

echo "=== Start-from-Stopped Benchmark ==="
echo "Instance: m7i.large"
echo "Technique: pre-warmed (EBS/ENI already attached)"
echo ""

# If no instance provided, create and stop one
if [[ -z "$INSTANCE_ID" ]]; then
  echo "No instance provided, creating a stopped instance first..."
  echo ""

  AMI=$(get_al2023_ami)
  SG=$(get_security_group)

  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI" \
    --instance-type m7i.large \
    --key-name instant-env-admin \
    --security-group-ids "$SG" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=start-stopped}]' \
    --query 'Instances[0].InstanceId' \
    --output text)

  echo "Created instance: $INSTANCE_ID"
  echo "Waiting for running state..."
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  # Get IP and wait for SSH to ensure it's fully booted
  IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)
  echo "Waiting for initial SSH (to ensure full boot)..."
  wait_for_ssh "$IP" "$KEY_FILE" >/dev/null

  echo "Stopping instance..."
  aws ec2 stop-instances --instance-ids "$INSTANCE_ID" >/dev/null
  aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
  echo "Instance stopped. Ready for benchmark."
  echo ""
fi

# Verify instance is stopped
STATE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)

if [[ "$STATE" != "stopped" ]]; then
  echo "ERROR: Instance $INSTANCE_ID is not stopped (state: $STATE)"
  echo "Stop it first or let this script create a new one"
  exit 1
fi

echo "Instance ID: $INSTANCE_ID"
echo "State: stopped"
echo ""

# Start timing
echo "Starting instance..."
T_START=$(now_ms)

aws ec2 start-instances --instance-ids "$INSTANCE_ID" >/dev/null
T_API=$(now_ms)
echo "API returned: $((T_API - T_START))ms"

# Wait for running
echo "Waiting for running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
T_RUNNING=$(now_ms)
echo "Running after $((T_RUNNING - T_START))ms"

# Get public IP (may have changed)
IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)
echo "Public IP: $IP"

# Wait for SSH
T_SSH=$(wait_for_ssh "$IP" "$KEY_FILE")

# Print results
print_timing "START-FROM-STOPPED" "$T_START" "$T_API" "$T_RUNNING" "$T_SSH"

# Compare to baseline
echo ""
echo "=== Comparison to Cold Launch (25.8s baseline) ==="
TOTAL_MS=$((T_SSH - T_START))
TOTAL_S=$(echo "scale=1; $TOTAL_MS / 1000" | bc)
SAVED_MS=$((25800 - TOTAL_MS))
SAVED_S=$(echo "scale=1; $SAVED_MS / 1000" | bc)
SAVED_PCT=$(echo "scale=0; $SAVED_MS * 100 / 25800" | bc)

echo "  Cold launch:       25.8s"
echo "  Start-from-stopped: ${TOTAL_S}s"
echo "  Saved:             ${SAVED_S}s (${SAVED_PCT}%)"
echo ""
echo "This represents the theoretical floor with pre-warmed infrastructure."

# Offer to run again or cleanup
echo ""
echo "Options:"
echo "  1) Run again (instance stays stopped)"
echo "  2) Terminate instance"
echo "  3) Keep instance stopped for later"
read -p "Choice [1/2/3]: " -n 1 -r
echo

case $REPLY in
  1)
    echo "Stopping instance for another run..."
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID" >/dev/null
    aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
    echo "Run again with: $0 $KEY_FILE $INSTANCE_ID"
    ;;
  2)
    cleanup_instance "$INSTANCE_ID"
    ;;
  3)
    echo "Stopping instance..."
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID" >/dev/null
    echo "Instance $INSTANCE_ID will be stopped. Re-run with:"
    echo "  $0 $KEY_FILE $INSTANCE_ID"
    ;;
esac
