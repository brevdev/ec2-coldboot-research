#!/bin/bash
# Benchmark: Instance type sweep
# Tests different instance types to measure placement time variance
#
# Hypothesis: Different instance families/sizes may have different
# scheduling times in the Pending→Running phase.

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

KEY_FILE="${1:-$HOME/.ssh/instant-env-admin.pem}"
RUNS="${2:-1}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Usage: $0 <private_key_file> [runs_per_type]"
  echo "Run scripts/setup-keypair.sh first"
  exit 1
fi

# Instance types to test
# Mix of families and sizes to see if there's variance
INSTANCE_TYPES=(
  "t3.medium"      # Burstable, very common
  "t3.large"       # Burstable, larger
  "m6i.large"      # Previous gen general purpose
  "m7i.large"      # Current gen (baseline)
  "c7i.large"      # Compute optimized
  "r7i.large"      # Memory optimized
)

echo "=== Instance Type Sweep Benchmark ==="
echo "Testing: ${INSTANCE_TYPES[*]}"
echo "Runs per type: $RUNS"
echo ""

# Get AMI and security group
AMI=$(get_al2023_ami)
SG=$(get_security_group)
echo "AMI: $AMI"
echo "Security Group: $SG"
echo ""

# Results file (using temp file instead of associative arrays for bash 3 compat)
RESULTS_FILE=$(mktemp)
trap "rm -f $RESULTS_FILE" EXIT

# Run benchmark for each instance type
for INSTANCE_TYPE in "${INSTANCE_TYPES[@]}"; do
  echo "=== Testing: $INSTANCE_TYPE ==="

  api_sum=0
  pending_sum=0
  boot_sum=0
  total_sum=0

  for ((run=1; run<=RUNS; run++)); do
    echo "  Run $run/$RUNS..."

    # Start timing
    T_START=$(now_ms)

    # Launch instance
    INSTANCE_ID=$(aws ec2 run-instances \
      --image-id "$AMI" \
      --instance-type "$INSTANCE_TYPE" \
      --key-name instant-env-admin \
      --security-group-ids "$SG" \
      --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=instance-sweep}]' \
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

  # Calculate and store averages
  api_avg=$((api_sum / RUNS))
  pending_avg=$((pending_sum / RUNS))
  boot_avg=$((boot_sum / RUNS))
  total_avg=$((total_sum / RUNS))

  echo "  Average: API ${api_avg}ms, Pending ${pending_avg}ms, Boot ${boot_avg}ms, Total ${total_avg}ms"
  echo ""

  # Store in results file
  echo "$INSTANCE_TYPE $api_avg $pending_avg $boot_avg $total_avg" >> "$RESULTS_FILE"
done

# Print summary
echo ""
echo "=== SUMMARY ==="
echo ""
printf "%-15s %8s %10s %8s %8s\n" "Instance Type" "API" "Pending" "Boot" "Total"
printf "%-15s %8s %10s %8s %8s\n" "-------------" "---" "-------" "----" "-----"

while read -r type api pending boot total; do
  printf "%-15s %7dms %9dms %7dms %7dms\n" "$type" "$api" "$pending" "$boot" "$total"
done < "$RESULTS_FILE"

echo ""
echo "Baseline (m7i.large cold): ~25800ms total (~17800ms pending)"

# Show fastest and slowest
FASTEST=$(sort -k5 -n "$RESULTS_FILE" | head -1)
SLOWEST=$(sort -k5 -n "$RESULTS_FILE" | tail -1)
FAST_TYPE=$(echo "$FASTEST" | awk '{print $1}')
FAST_TOTAL=$(echo "$FASTEST" | awk '{print $5}')
SLOW_TYPE=$(echo "$SLOWEST" | awk '{print $1}')
SLOW_TOTAL=$(echo "$SLOWEST" | awk '{print $5}')
DIFF=$((SLOW_TOTAL - FAST_TOTAL))

echo ""
echo "Fastest: $FAST_TYPE (${FAST_TOTAL}ms)"
echo "Slowest: $SLOW_TYPE (${SLOW_TOTAL}ms)"
echo "Variance: ${DIFF}ms"
