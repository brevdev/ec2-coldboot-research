#!/bin/bash
# Benchmark: Resume from hibernation
# Instance state is preserved in RAM image on EBS - skips kernel boot entirely
#
# Requirements:
# - Instance type must support hibernation
# - Root volume must be encrypted (EBS encryption)
# - Sufficient EBS space for RAM
#
# Usage: ./bench/hibernate.sh <private_key_file> [instance_id]

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

KEY_FILE="${1:-$HOME/.ssh/instant-env-admin.pem}"
INSTANCE_ID="${2:-}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Usage: $0 <private_key_file> [instance_id]"
  exit 1
fi

echo "=== Hibernate Resume Benchmark ==="
echo "Instance: m7i.large"
echo "Technique: Resume from hibernation (RAM preserved)"
echo ""

# If no instance provided, create one with hibernation enabled
if [[ -z "$INSTANCE_ID" ]]; then
  echo "Creating hibernation-enabled instance..."
  echo ""

  AMI=$(get_al2023_ami)
  SG=$(get_security_group)

  # Hibernation requires:
  # 1. Encrypted root volume
  # 2. HibernationOptions.Configured = true
  # 3. Sufficient root volume size for RAM (8GB for m7i.large)

  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI" \
    --instance-type m7i.large \
    --key-name instant-env-admin \
    --security-group-ids "$SG" \
    --hibernation-options Configured=true \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3","Encrypted":true}}]' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=hibernate}]' \
    --query 'Instances[0].InstanceId' \
    --output text)

  echo "Instance ID: $INSTANCE_ID"
  echo "Waiting for running state..."
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

  IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)
  echo "Public IP: $IP"

  # Wait for SSH to ensure fully booted
  echo "Waiting for SSH (initial boot)..."
  wait_for_ssh "$IP" "$KEY_FILE" >/dev/null
  echo "Instance fully booted."

  # Let it stabilize before hibernating
  echo "Waiting 10s for instance to stabilize..."
  sleep 10

  echo ""
  echo "Hibernating instance..."
  aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --hibernate >/dev/null

  echo "Waiting for stopped state..."
  aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
  echo "Instance hibernated."
  echo ""
fi

# Verify instance is stopped (hibernated)
STATE=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].State.Name' \
  --output text)

if [[ "$STATE" != "stopped" ]]; then
  echo "ERROR: Instance $INSTANCE_ID is not stopped (state: $STATE)"
  echo "Hibernate it first or let this script create a new one"
  exit 1
fi

# Check if it was actually hibernated
HIBERNATE_ENABLED=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].HibernationOptions.Configured' \
  --output text)

echo "Instance ID: $INSTANCE_ID"
echo "State: stopped (hibernated)"
echo "Hibernation configured: $HIBERNATE_ENABLED"
echo ""

# === BENCHMARK: Resume from hibernation ===
echo "=== Starting hibernate resume benchmark ==="
T_START=$(now_ms)

aws ec2 start-instances --instance-ids "$INSTANCE_ID" >/dev/null
T_API=$(now_ms)
echo "API returned: $((T_API - T_START))ms"

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

# Results
print_timing "HIBERNATE RESUME" "$T_START" "$T_API" "$T_RUNNING" "$T_SSH"

# Comparison
echo ""
echo "=== Comparison ==="
TOTAL_MS=$((T_SSH - T_START))
TOTAL_S=$(echo "scale=1; $TOTAL_MS / 1000" | bc)
echo "  Cold launch:       25.8s"
echo "  Start-stopped:     21.2s"
echo "  Hibernate resume:  ${TOTAL_S}s"
echo ""
SAVED_MS=$((25800 - TOTAL_MS))
SAVED_S=$(echo "scale=1; $SAVED_MS / 1000" | bc)
SAVED_PCT=$(echo "scale=0; $SAVED_MS * 100 / 25800" | bc)
echo "  Saved vs cold:     ${SAVED_S}s (${SAVED_PCT}%)"

# Options
echo ""
echo "Options:"
echo "  1) Run again (re-hibernate first)"
echo "  2) Terminate instance"
echo "  3) Keep stopped for later"
read -p "Choice [1/2/3]: " -n 1 -r
echo

case $REPLY in
  1)
    echo "Re-hibernating instance..."
    aws ec2 stop-instances --instance-ids "$INSTANCE_ID" --hibernate >/dev/null
    aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
    echo "Run again with: $0 $KEY_FILE $INSTANCE_ID"
    ;;
  2)
    cleanup_instance "$INSTANCE_ID"
    ;;
  3)
    echo "Instance $INSTANCE_ID is still running."
    echo "To hibernate: aws ec2 stop-instances --instance-ids $INSTANCE_ID --hibernate"
    ;;
esac
