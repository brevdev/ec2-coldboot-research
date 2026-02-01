#!/bin/bash
# Benchmark: EBS volume size experiment
# Tests whether smaller root volumes reduce Pending→Running time
#
# Hypothesis: EBS attachment is part of the ~18s pending phase.
# Smaller volumes may attach faster.
#
# Tests: 8GB (minimum for AL2023) vs 20GB (common default)

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

KEY_FILE="${1:-$HOME/.ssh/instant-env-admin.pem}"
RUNS="${2:-1}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Usage: $0 <private_key_file> [runs_per_size]"
  echo "Run scripts/setup-keypair.sh first"
  exit 1
fi

# Volume sizes to test (in GB)
# AL2023 minimum is ~8GB, testing small vs medium
VOLUME_SIZES=(8 20)

echo "=== EBS Volume Size Benchmark ==="
echo "Testing root volume sizes: ${VOLUME_SIZES[*]} GB"
echo "Runs per size: $RUNS"
echo ""

# Get AMI and security group
AMI=$(get_al2023_ami)
SG=$(get_security_group)
echo "AMI: $AMI"
echo "Security Group: $SG"
echo ""

# Results arrays
declare -A API_TIMES
declare -A PENDING_TIMES
declare -A BOOT_TIMES
declare -A TOTAL_TIMES

# Run benchmark for each volume size
for SIZE in "${VOLUME_SIZES[@]}"; do
  echo "=== Testing: ${SIZE}GB root volume ==="

  api_sum=0
  pending_sum=0
  boot_sum=0
  total_sum=0

  for ((run=1; run<=RUNS; run++)); do
    echo "  Run $run/$RUNS..."

    # Start timing
    T_START=$(now_ms)

    # Launch instance with specified root volume size
    # AL2023 uses xvda as root device
    INSTANCE_ID=$(aws ec2 run-instances \
      --image-id "$AMI" \
      --instance-type m7i.large \
      --key-name instant-env-admin \
      --security-group-ids "$SG" \
      --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":${SIZE},\"VolumeType\":\"gp3\",\"DeleteOnTermination\":true}}]" \
      --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=ebs-size}]' \
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
  API_TIMES[$SIZE]=$((api_sum / RUNS))
  PENDING_TIMES[$SIZE]=$((pending_sum / RUNS))
  BOOT_TIMES[$SIZE]=$((boot_sum / RUNS))
  TOTAL_TIMES[$SIZE]=$((total_sum / RUNS))

  echo "  Average: API ${API_TIMES[$SIZE]}ms, Pending ${PENDING_TIMES[$SIZE]}ms, Boot ${BOOT_TIMES[$SIZE]}ms, Total ${TOTAL_TIMES[$SIZE]}ms"
  echo ""
done

# Print summary
echo ""
echo "=== SUMMARY ==="
echo ""
printf "%-12s %8s %10s %8s %8s\n" "Volume Size" "API" "Pending" "Boot" "Total"
printf "%-12s %8s %10s %8s %8s\n" "-----------" "---" "-------" "----" "-----"

for SIZE in "${VOLUME_SIZES[@]}"; do
  printf "%-12s %7dms %9dms %7dms %7dms\n" \
    "${SIZE}GB" \
    "${API_TIMES[$SIZE]}" \
    "${PENDING_TIMES[$SIZE]}" \
    "${BOOT_TIMES[$SIZE]}" \
    "${TOTAL_TIMES[$SIZE]}"
done

# Calculate difference
if [[ ${#VOLUME_SIZES[@]} -ge 2 ]]; then
  SMALL=${VOLUME_SIZES[0]}
  LARGE=${VOLUME_SIZES[1]}
  PENDING_DIFF=$((PENDING_TIMES[$LARGE] - PENDING_TIMES[$SMALL]))
  TOTAL_DIFF=$((TOTAL_TIMES[$LARGE] - TOTAL_TIMES[$SMALL]))
  echo ""
  echo "Difference (${LARGE}GB - ${SMALL}GB):"
  echo "  Pending: ${PENDING_DIFF}ms"
  echo "  Total: ${TOTAL_DIFF}ms"
fi

echo ""
echo "Baseline (m7i.large cold): ~25800ms total (~17800ms pending)"
