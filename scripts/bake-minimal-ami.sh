#!/bin/bash
# Bake a minimal AMI from Amazon Linux 2023
# Strips: cloud-init, ssm-agent, unnecessary services
# Keeps: sshd, networking
#
# Usage: ./scripts/bake-minimal-ami.sh [private_key_file]

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

KEY_FILE="${1:-$HOME/.ssh/instant-env-admin.pem}"
AMI_NAME="instant-env-minimal-$(date +%Y%m%d-%H%M%S)"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Usage: $0 <private_key_file>"
  echo "Run scripts/setup-keypair.sh first"
  exit 1
fi

echo "=== Baking Minimal AMI ==="
echo "Output AMI: $AMI_NAME"
echo ""

# Get base AMI and security group
BASE_AMI=$(get_al2023_ami)
SG=$(get_security_group)
echo "Base AMI: $BASE_AMI"
echo "Security Group: $SG"

# Launch temp instance
echo ""
echo "Launching temp instance..."
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$BASE_AMI" \
  --instance-type m7i.large \
  --key-name instant-env-admin \
  --security-group-ids "$SG" \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Purpose,Value=ami-bake}]' \
  --query 'Instances[0].InstanceId' \
  --output text)
echo "Instance ID: $INSTANCE_ID"

# Cleanup on exit
cleanup() {
  echo ""
  echo "Cleaning up temp instance..."
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null 2>&1 || true
}
trap cleanup EXIT

# Wait for running
echo "Waiting for running state..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

# Get public IP
IP=$(aws ec2 describe-instances \
  --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text)
echo "Public IP: $IP"

# Wait for SSH
echo "Waiting for SSH..."
wait_for_ssh "$IP" "$KEY_FILE" >/dev/null

# SSH helper
run_ssh() {
  ssh -i "$KEY_FILE" -o StrictHostKeyChecking=no -o BatchMode=yes ec2-user@"$IP" "$@"
}

echo ""
echo "Stripping packages..."

# Stop services we're removing
run_ssh "sudo systemctl stop amazon-ssm-agent cloud-init cloud-init-local cloud-config cloud-final 2>/dev/null || true"

# Remove cloud-init and ssm-agent
run_ssh "sudo dnf remove -y cloud-init amazon-ssm-agent ec2-instance-connect 2>/dev/null || true"

# Remove cloud-init artifacts
run_ssh "sudo rm -rf /var/lib/cloud /var/log/cloud-init* /etc/cloud"

# Disable unnecessary services
run_ssh "sudo systemctl disable amazon-ssm-agent cloud-init cloud-init-local cloud-config cloud-final 2>/dev/null || true"
run_ssh "sudo systemctl mask cloud-init cloud-init-local cloud-config cloud-final 2>/dev/null || true"

# Ensure sshd is enabled and starts fast
run_ssh "sudo systemctl enable sshd"

# Clean package cache
run_ssh "sudo dnf clean all"

# Clear logs and tmp for smaller AMI
run_ssh "sudo rm -rf /var/log/*.log /var/log/journal/* /tmp/* /var/tmp/*"

# Verify sshd still works
run_ssh "systemctl is-enabled sshd"
echo "sshd enabled: OK"

echo ""
echo "Stopping instance for AMI creation..."
aws ec2 stop-instances --instance-ids "$INSTANCE_ID" >/dev/null
aws ec2 wait instance-stopped --instance-ids "$INSTANCE_ID"
echo "Instance stopped"

echo ""
echo "Creating AMI..."
AMI_ID=$(aws ec2 create-image \
  --instance-id "$INSTANCE_ID" \
  --name "$AMI_NAME" \
  --description "Minimal AL2023 - no cloud-init, no ssm-agent" \
  --tag-specifications 'ResourceType=image,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=minimal}]' \
  --query 'ImageId' \
  --output text)
echo "AMI ID: $AMI_ID"

echo "Waiting for AMI to be available (this may take a few minutes)..."
aws ec2 wait image-available --image-ids "$AMI_ID"

echo ""
echo "=== SUCCESS ==="
echo "AMI Name: $AMI_NAME"
echo "AMI ID:   $AMI_ID"
echo ""
echo "Use this AMI ID in bench/minimal-ami.sh"
