#!/bin/bash
# Benchmark: Region sweep
# Tests the same instance type across multiple AWS regions
#
# Hypothesis: Different regions may have different capacity/latency characteristics.
# Newer or less-utilized regions might have faster placement.
#
# Note: This script creates temporary resources (SG, keypair) in each region
# and cleans them up after. The keypair uses the same key material as instant-env-admin.

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

KEY_FILE="${1:-$HOME/.ssh/instant-env-admin.pem}"
RUNS="${2:-1}"
INSTANCE_TYPE="${3:-m7i.large}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Usage: $0 <private_key_file> [runs_per_region] [instance_type]"
  exit 1
fi

# Regions to test - mix of major regions
# Avoid all regions to keep costs/time reasonable
REGIONS=(
  "us-west-2"      # Oregon (baseline)
  "us-east-1"      # N. Virginia (largest)
  "us-east-2"      # Ohio
  "eu-west-1"      # Ireland
  "ap-northeast-1" # Tokyo
)

echo "=== Region Sweep Benchmark ==="
echo "Instance Type: $INSTANCE_TYPE"
echo "Runs per region: $RUNS"
echo "Regions: ${REGIONS[*]}"
echo ""

# Extract public key from private key for temporary keypair creation
# Note: import-key-pair expects base64-encoded public key material
PUB_KEY_FILE=$(mktemp)
ssh-keygen -y -f "$KEY_FILE" > "$PUB_KEY_FILE"

# Results file (bash 3 compatible - no associative arrays)
RESULTS_FILE=$(mktemp)
ERRORS_FILE=$(mktemp)
trap "rm -f $RESULTS_FILE $ERRORS_FILE $PUB_KEY_FILE" EXIT

# Cleanup function for a region
cleanup_region() {
  local region=$1
  local instance_id=$2
  local sg_id=$3
  local created_sg=$4

  # Terminate instance
  if [[ -n "$instance_id" ]]; then
    aws ec2 terminate-instances --region "$region" --instance-ids "$instance_id" >/dev/null 2>&1 || true
    # Wait for termination before deleting SG
    aws ec2 wait instance-terminated --region "$region" --instance-ids "$instance_id" 2>/dev/null || true
  fi

  # Delete SG if we created it
  if [[ "$created_sg" == "true" ]] && [[ -n "$sg_id" ]]; then
    aws ec2 delete-security-group --region "$region" --group-id "$sg_id" 2>/dev/null || true
  fi

  # Delete keypair
  aws ec2 delete-key-pair --region "$region" --key-name instant-env-region-test 2>/dev/null || true
}

# Run benchmark for each region
for REGION in "${REGIONS[@]}"; do
  echo "=== Testing: $REGION ==="

  CREATED_SG="false"
  SG_ID=""
  INSTANCE_ID=""

  # Setup cleanup trap for this region
  trap "cleanup_region '$REGION' '$INSTANCE_ID' '$SG_ID' '$CREATED_SG'" EXIT

  # Get AMI for this region
  AMI=$(aws ec2 describe-images \
    --region "$REGION" \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023*-x86_64" \
              "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text 2>/dev/null)

  if [[ -z "$AMI" ]] || [[ "$AMI" == "None" ]]; then
    echo "  Skipping: No AL2023 AMI found"
    echo "$REGION No AMI found" >> "$ERRORS_FILE"
    continue
  fi
  echo "  AMI: $AMI"

  # Import keypair for this region
  aws ec2 import-key-pair \
    --region "$REGION" \
    --key-name instant-env-region-test \
    --public-key-material "fileb://$PUB_KEY_FILE" >/dev/null 2>&1 || true

  # Check for existing SG (prefer instant-env-ssh, fall back to instant-env-region-test)
  SG_ID=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=group-name,Values=instant-env-ssh" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

  if [[ "$SG_ID" == "None" ]] || [[ -z "$SG_ID" ]]; then
    # Check if region-test SG exists
    SG_ID=$(aws ec2 describe-security-groups \
      --region "$REGION" \
      --filters "Name=group-name,Values=instant-env-region-test" \
      --query 'SecurityGroups[0].GroupId' \
      --output text 2>/dev/null)
  fi

  if [[ "$SG_ID" == "None" ]] || [[ -z "$SG_ID" ]]; then
    # Create temporary SG
    SG_ID=$(aws ec2 create-security-group \
      --region "$REGION" \
      --group-name instant-env-region-test \
      --description "Temporary SG for region sweep" \
      --query 'GroupId' \
      --output text)
    CREATED_SG="true"

    # Add SSH rule
    aws ec2 authorize-security-group-ingress \
      --region "$REGION" \
      --group-id "$SG_ID" \
      --protocol tcp \
      --port 22 \
      --cidr 0.0.0.0/0 >/dev/null
  fi
  echo "  Security Group: $SG_ID"

  api_sum=0
  pending_sum=0
  boot_sum=0
  total_sum=0
  success_count=0

  for ((run=1; run<=RUNS; run++)); do
    echo "  Run $run/$RUNS..."

    # Start timing
    T_START=$(now_ms)

    # Launch instance
    INSTANCE_ID=$(aws ec2 run-instances \
      --region "$REGION" \
      --image-id "$AMI" \
      --instance-type "$INSTANCE_TYPE" \
      --key-name instant-env-region-test \
      --security-group-ids "$SG_ID" \
      --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=region-sweep}]' \
      --query 'Instances[0].InstanceId' \
      --output text 2>&1) || {
        echo "    Failed to launch: $INSTANCE_ID"
        INSTANCE_ID=""
        continue
      }

    T_API=$(now_ms)
    api_ms=$((T_API - T_START))

    # Wait for running
    aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"
    T_RUNNING=$(now_ms)
    pending_ms=$((T_RUNNING - T_API))

    # Get public IP
    IP=$(aws ec2 describe-instances \
      --region "$REGION" \
      --instance-ids "$INSTANCE_ID" \
      --query 'Reservations[0].Instances[0].PublicIpAddress' \
      --output text)

    if [[ -z "$IP" ]] || [[ "$IP" == "None" ]]; then
      echo "    No public IP, skipping SSH test"
      cleanup_region "$REGION" "$INSTANCE_ID" "" "false"
      INSTANCE_ID=""
      continue
    fi

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
    ((success_count++))

    # Cleanup instance
    aws ec2 terminate-instances --region "$REGION" --instance-ids "$INSTANCE_ID" >/dev/null
    INSTANCE_ID=""
  done

  # Store averages if we had successful runs
  if [[ $success_count -gt 0 ]]; then
    api_avg=$((api_sum / success_count))
    pending_avg=$((pending_sum / success_count))
    boot_avg=$((boot_sum / success_count))
    total_avg=$((total_sum / success_count))
    echo "  Average: API ${api_avg}ms, Pending ${pending_avg}ms, Boot ${boot_avg}ms, Total ${total_avg}ms"
    echo "$REGION $api_avg $pending_avg $boot_avg $total_avg" >> "$RESULTS_FILE"
  else
    echo "$REGION All runs failed" >> "$ERRORS_FILE"
  fi

  # Cleanup region resources
  cleanup_region "$REGION" "" "$SG_ID" "$CREATED_SG"
  trap - EXIT

  echo ""
done

# Print summary
echo ""
echo "=== SUMMARY (sorted by Total) ==="
echo ""
printf "%-20s %8s %10s %8s %8s\n" "Region" "API" "Pending" "Boot" "Total"
printf "%-20s %8s %10s %8s %8s\n" "-------------------" "---" "-------" "----" "-----"

# Sort by total time and print
sort -k5 -n "$RESULTS_FILE" | while read -r region api pending boot total; do
  printf "%-20s %7dms %9dms %7dms %7dms\n" "$region" "$api" "$pending" "$boot" "$total"
done

# Show errors
if [[ -s "$ERRORS_FILE" ]]; then
  echo ""
  echo "Errors:"
  while read -r line; do
    echo "  $line"
  done < "$ERRORS_FILE"
fi

echo ""
echo "Baseline (us-west-2 m7i.large cold): ~25800ms total"

# Show variance
if [[ $(wc -l < "$RESULTS_FILE") -gt 1 ]]; then
  FASTEST=$(sort -k5 -n "$RESULTS_FILE" | head -1)
  SLOWEST=$(sort -k5 -n "$RESULTS_FILE" | tail -1)
  FAST_REGION=$(echo "$FASTEST" | awk '{print $1}')
  FAST_TOTAL=$(echo "$FASTEST" | awk '{print $5}')
  SLOW_REGION=$(echo "$SLOWEST" | awk '{print $1}')
  SLOW_TOTAL=$(echo "$SLOWEST" | awk '{print $5}')
  DIFF=$((SLOW_TOTAL - FAST_TOTAL))
  echo ""
  echo "Fastest: $FAST_REGION (${FAST_TOTAL}ms)"
  echo "Slowest: $SLOW_REGION (${SLOW_TOTAL}ms)"
  echo "Variance: ${DIFF}ms"
fi
