# Common functions for benchmarking
# Source this file: source bench/common.sh

# Millisecond timestamp
now_ms() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS: use python for milliseconds
    python3 -c 'import time; print(int(time.time() * 1000))'
  else
    date +%s%3N
  fi
}

# Wait for SSH with timing
# Usage: wait_for_ssh <ip> <private_key_file>
# Returns: milliseconds until SSH auth succeeded
wait_for_ssh() {
  local ip=$1
  local key=$2
  local start=$(now_ms)
  local tcp_open=""

  echo "Waiting for SSH on $ip..." >&2

  while true; do
    # Check TCP first
    if [[ -z "$tcp_open" ]]; then
      if nc -z -w2 "$ip" 22 2>/dev/null; then
        tcp_open=$(now_ms)
        echo "  TCP open: $((tcp_open - start))ms" >&2
      fi
    fi

    # Try SSH auth
    if ssh -i "$key" -o ConnectTimeout=2 -o BatchMode=yes -o StrictHostKeyChecking=no \
       ec2-user@"$ip" "true" >/dev/null 2>&1; then
      local end=$(now_ms)
      echo "  SSH auth: $((end - start))ms" >&2
      echo "$end"
      return 0
    fi

    sleep 0.5
  done
}

# Get latest Amazon Linux 2023 AMI
get_al2023_ami() {
  aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023*-x86_64" \
              "Name=state,Values=available" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text
}

# Terminate instance
cleanup_instance() {
  local instance_id=$1
  echo "Terminating $instance_id..." >&2
  aws ec2 terminate-instances --instance-ids "$instance_id" >/dev/null
}

# Get security group ID (creates if needed)
get_security_group() {
  local sg_id=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=instant-env-ssh" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null)

  if [[ "$sg_id" == "None" ]] || [[ -z "$sg_id" ]]; then
    echo "Run scripts/setup-security-group.sh first" >&2
    exit 1
  fi

  echo "$sg_id"
}

# Print timing breakdown
print_timing() {
  local label=$1
  local t_start=$2
  local t_api=$3
  local t_running=$4
  local t_ssh=$5

  echo ""
  echo "=== $label ==="
  echo "API call:     $((t_api - t_start))ms"
  echo "Running:      $((t_running - t_start))ms (+$((t_running - t_api))ms)"
  echo "SSH ready:    $((t_ssh - t_start))ms (+$((t_ssh - t_running))ms)"
  echo "---"
  echo "TOTAL:        $((t_ssh - t_start))ms"
}
