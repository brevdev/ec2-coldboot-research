#!/bin/bash
# Run cold baseline benchmark 3 times and collect results
# Usage: ./bench/run-cold-baseline.sh [key_file]

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

KEY_FILE="${1:-$HOME/.ssh/instant-env-admin.pem}"
ITERATIONS=3
RESULTS_FILE="docs/cold-baseline-results.md"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Key file not found: $KEY_FILE"
  echo "Run scripts/setup-keypair.sh first"
  exit 1
fi

echo "=== Cold Launch Baseline ==="
echo "Running $ITERATIONS iterations..."
echo ""

# Get AMI and security group
AMI=$(get_al2023_ami)
SG=$(get_security_group)
echo "AMI: $AMI"
echo "Security Group: $SG"
echo ""

# Arrays to store results
declare -a API_TIMES
declare -a RUNNING_TIMES
declare -a SSH_TIMES
declare -a TOTAL_TIMES

for i in $(seq 1 $ITERATIONS); do
  echo "=== Iteration $i/$ITERATIONS ==="

  T_START=$(now_ms)

  # Launch instance
  echo "Launching instance..."
  INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI" \
    --instance-type m7i.large \
    --key-name instant-env-admin \
    --security-group-ids "$SG" \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Project,Value=instant-env},{Key=Technique,Value=cold-baseline}]' \
    --query 'Instances[0].InstanceId' \
    --output text)

  T_API=$(now_ms)
  API_TIME=$((T_API - T_START))
  echo "Instance: $INSTANCE_ID (API: ${API_TIME}ms)"

  # Wait for running
  echo "Waiting for running..."
  aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"
  T_RUNNING=$(now_ms)
  RUNNING_TIME=$((T_RUNNING - T_START))
  echo "Running: ${RUNNING_TIME}ms"

  # Get public IP
  IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)
  echo "IP: $IP"

  # Wait for SSH
  T_SSH=$(wait_for_ssh "$IP" "$KEY_FILE")
  SSH_TIME=$((T_SSH - T_START))
  TOTAL_TIMES+=($SSH_TIME)

  # Calculate deltas
  API_TIMES+=($API_TIME)
  RUNNING_TIMES+=($((T_RUNNING - T_API)))
  SSH_TIMES+=($((T_SSH - T_RUNNING)))

  echo ""
  echo "Iteration $i results:"
  echo "  T0→T1 (API):          ${API_TIME}ms"
  echo "  T1→T2 (Pending):      $((T_RUNNING - T_API))ms"
  echo "  T2→T4 (Boot→SSH):     $((T_SSH - T_RUNNING))ms"
  echo "  TOTAL:                ${SSH_TIME}ms"
  echo ""

  # Cleanup
  echo "Terminating $INSTANCE_ID..."
  aws ec2 terminate-instances --instance-ids "$INSTANCE_ID" >/dev/null

  if [[ $i -lt $ITERATIONS ]]; then
    echo "Waiting 10s before next iteration..."
    sleep 10
  fi
done

# Calculate averages
sum_api=0; sum_pending=0; sum_boot=0; sum_total=0
for i in $(seq 0 $((ITERATIONS - 1))); do
  sum_api=$((sum_api + API_TIMES[$i]))
  sum_pending=$((sum_pending + RUNNING_TIMES[$i]))
  sum_boot=$((sum_boot + SSH_TIMES[$i]))
  sum_total=$((sum_total + TOTAL_TIMES[$i]))
done

avg_api=$((sum_api / ITERATIONS))
avg_pending=$((sum_pending / ITERATIONS))
avg_boot=$((sum_boot / ITERATIONS))
avg_total=$((sum_total / ITERATIONS))

echo ""
echo "=== SUMMARY ==="
echo "Iterations: $ITERATIONS"
echo ""
echo "Average timing breakdown:"
echo "  T0→T1 (API call):        ${avg_api}ms"
echo "  T1→T2 (Pending→Running): ${avg_pending}ms"
echo "  T2→T4 (Boot→SSH ready):  ${avg_boot}ms"
echo "  ---"
echo "  TOTAL:                   ${avg_total}ms ($((avg_total / 1000))s)"
echo ""

# Write results to markdown
mkdir -p docs
cat > "$RESULTS_FILE" << EOF
# Cold Launch Baseline Results

**Date:** $(date -u +"%Y-%m-%d %H:%M:%S UTC")
**Instance Type:** m7i.large
**AMI:** $AMI (Amazon Linux 2023)
**Technique:** cloud-init (default)

## Summary

| Phase | Description | Average | Notes |
|-------|-------------|---------|-------|
| T0→T1 | API call | ${avg_api}ms | RunInstances returns |
| T1→T2 | Pending→Running | ${avg_pending}ms | Hypervisor/scheduler |
| T2→T4 | Boot→SSH ready | ${avg_boot}ms | Kernel + cloud-init + sshd |
| **Total** | **End-to-end** | **${avg_total}ms (${avg_total%???}.${avg_total: -3:1}s)** | |

## Individual Runs

| Run | API | Pending | Boot→SSH | Total |
|-----|-----|---------|----------|-------|
EOF

for i in $(seq 0 $((ITERATIONS - 1))); do
  echo "| $((i+1)) | ${API_TIMES[$i]}ms | ${RUNNING_TIMES[$i]}ms | ${SSH_TIMES[$i]}ms | ${TOTAL_TIMES[$i]}ms |" >> "$RESULTS_FILE"
done

cat >> "$RESULTS_FILE" << EOF

## Analysis

### Where Does the Time Go?

1. **API Call (T0→T1): ~${avg_api}ms**
   - AWS receives request, validates, schedules
   - Returns instance ID immediately

2. **Pending→Running (T1→T2): ~${avg_pending}ms**
   - Instance scheduled to hypervisor
   - ENI attached, EBS attached
   - Hypervisor starts guest

3. **Boot→SSH (T2→T4): ~${avg_boot}ms** ← LARGEST CHUNK
   - Linux kernel boot
   - systemd initialization
   - cloud-init runs (fetches metadata, injects SSH keys)
   - sshd starts and accepts connections

### Optimization Opportunities

- **Pending→Running**: Largely outside our control (AWS infrastructure)
- **Boot→SSH**: PRIMARY TARGET
  - Skip cloud-init (bake keys into AMI)
  - Minimal systemd or custom init
  - Faster sshd startup

## Raw Data

\`\`\`
API_TIMES: ${API_TIMES[*]}
RUNNING_TIMES: ${RUNNING_TIMES[*]}
SSH_TIMES: ${SSH_TIMES[*]}
TOTAL_TIMES: ${TOTAL_TIMES[*]}
\`\`\`
EOF

echo "Results written to: $RESULTS_FILE"
