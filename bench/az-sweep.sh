#!/bin/bash
# Benchmark: Availability Zone sweep
# Tests the same instance type across all AZs to measure placement variance
#
# Hypothesis: Different AZs may have different capacity/scheduling times.
# AZs with more headroom might place instances faster.

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

KEY_FILE="${1:-$HOME/.ssh/instant-env-admin.pem}"
RUNS="${2:-1}"
INSTANCE_TYPE="${3:-m7i.large}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Usage: $0 <private_key_file> [runs_per_az] [instance_type]"
  echo "Run scripts/setup-keypair.sh first"
  exit 1
fi

echo "=== Availability Zone Sweep Benchmark ==="
echo "Instance Type: $INSTANCE_TYPE"
echo "Runs per AZ: $RUNS"
echo ""

# Get all available AZs in current region
REGION=$(aws configure get region 2>/dev/null || echo "us-west-2")
echo "Region: $REGION"

AZS=($(aws ec2 describe-availability-zones \
  --region "$REGION" \
  --filters "Name=state,Values=available" \
  --query 'AvailabilityZones[*].ZoneName' \
  --output text))

echo "Available AZs: ${AZS[*]}"
echo ""

# Get AMI and security group
AMI=$(get_al2023_ami)
SG=$(get_security_group)
echo "AMI: $AMI"
echo "Security Group: $SG"
echo ""

# Get subnet for each AZ (we need subnets to specify AZ)
declare -A AZ_SUBNETS

# Get default VPC
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=is-default,Values=true" \
  --query 'Vpcs[0].VpcId' \
  --output text)

if [[ "$VPC_ID" == "None" ]] || [[ -z "$VPC_ID" ]]; then
  echo "Error: No default VPC found. Need VPC/subnets to specify AZ."
  exit 1
fi

echo "VPC: $VPC_ID"

# Map subnets to AZs
for AZ in "${AZS[@]}"; do
  SUBNET=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=$VPC_ID" \
              "Name=availability-zone,Values=$AZ" \
    --query 'Subnets[0].SubnetId' \
    --output text)

  if [[ "$SUBNET" != "None" ]] && [[ -n "$SUBNET" ]]; then
    AZ_SUBNETS[$AZ]=$SUBNET
    echo "  $AZ -> $SUBNET"
  else
    echo "  $AZ -> (no subnet, skipping)"
  fi
done

echo ""

# Results arrays
declare -A API_TIMES
declare -A PENDING_TIMES
declare -A BOOT_TIMES
declare -A TOTAL_TIMES

# Run benchmark for each AZ
for AZ in "${!AZ_SUBNETS[@]}"; do
  SUBNET="${AZ_SUBNETS[$AZ]}"
  echo "=== Testing: $AZ ==="

  api_sum=0
  pending_sum=0
  boot_sum=0
  total_sum=0

  for ((run=1; run<=RUNS; run++)); do
    echo "  Run $run/$RUNS..."

    # Start timing
    T_START=$(now_ms)

    # Launch instance in specific AZ via subnet
    INSTANCE_ID=$(aws ec2 run-instances \
      --image-id "$AMI" \
      --instance-type "$INSTANCE_TYPE" \
      --key-name instant-env-admin \
      --security-group-ids "$SG" \
      --subnet-id "$SUBNET" \
      --associate-public-ip-address \
      --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=az-sweep}]' \
      --query 'Instances[0].InstanceId' \
      --output text)

    T_API=$(now_ms)
    api_ms=$((T_API - T_START))

    # Wait for running
    aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
    T_RUNNING=$(now_ms)
    pending_ms=$((T_RUNNING - T_API))

    # Get public IP
    IP=$(aws ec2 describe-instances \
      --instance-ids "$INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' \
      --output text)

    # Wait for SSH
    T_SSH=$(wait_for_ssh "$IP" "$KEY_FILE")
    boot_ms=$((T_SSH - T_RUNNING))
    total_ms=$((T_SSH - T_START))

    echo "    API: ${api_ms}ms, Pending: ${pending_ms}ms, Boot: ${boot_ms}ms, Total: ${total_ms}ms"

    # Accumulate
    api_sum=$((api_sum + api_ms))
    pending_sum=$((pending_sum + pending_ms))
    boot_sum=$((boot_sum + boot_ms))
    total_sum=$((total_sum + total_ms))

    # Cleanup immediately
    cleanup_instance "$INSTANCE_ID"
  done

  # Store averages
  API_TIMES[$AZ]=$((api_sum / RUNS))
  PENDING_TIMES[$AZ]=$((pending_sum / RUNS))
  BOOT_TIMES[$AZ]=$((boot_sum / RUNS))
  TOTAL_TIMES[$AZ]=$((total_sum / RUNS))

  echo "  Average: API ${API_TIMES[$AZ]}ms, Pending ${PENDING_TIMES[$AZ]}ms, Boot ${BOOT_TIMES[$AZ]}ms, Total ${TOTAL_TIMES[$AZ]}ms"
  echo ""
done

# Print summary sorted by total time
echo ""
echo "=== SUMMARY (sorted by Total) ==="
echo ""
printf "%-15s %8s %10s %8s %8s\n" "AZ" "API" "Pending" "Boot" "Total"
printf "%-15s %8s %10s %8s %8s\n" "-------------" "---" "-------" "----" "-----"

# Sort AZs by total time
SORTED_AZS=($(for AZ in "${!TOTAL_TIMES[@]}"; do
  echo "$AZ ${TOTAL_TIMES[$AZ]}"
done | sort -k2 -n | awk '{print $1}'))

for AZ in "${SORTED_AZS[@]}"; do
  printf "%-15s %7dms %9dms %7dms %7dms\n" \
    "$AZ" \
    "${API_TIMES[$AZ]}" \
    "${PENDING_TIMES[$AZ]}" \
    "${BOOT_TIMES[$AZ]}" \
    "${TOTAL_TIMES[$AZ]}"
done

echo ""
echo "Baseline (m7i.large cold, no AZ specified): ~25800ms total"

# Show variance
if [[ ${#TOTAL_TIMES[@]} -gt 1 ]]; then
  MIN=${TOTAL_TIMES[${SORTED_AZS[0]}]}
  MAX=${TOTAL_TIMES[${SORTED_AZS[-1]}]}
  DIFF=$((MAX - MIN))
  echo "Variance: ${DIFF}ms between fastest and slowest AZ"
fi
