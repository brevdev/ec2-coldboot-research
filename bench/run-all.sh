#!/bin/bash
# Run all benchmarks and compare results

set -euo pipefail
cd "$(dirname "$0")/.."
source bench/common.sh

KEY_FILE="${1:-$HOME/.ssh/instant-env-admin.pem}"
ITERATIONS="${2:-1}"

if [[ ! -f "$KEY_FILE" ]]; then
  echo "Usage: $0 <private_key_file> [iterations]"
  exit 1
fi

echo "=== Instant-Env Benchmark Suite ==="
echo "Iterations: $ITERATIONS"
echo "Key: $KEY_FILE"
echo ""

# Results file
RESULTS_FILE="bench/results-$(date +%Y%m%d-%H%M%S).csv"
echo "technique,iteration,api_ms,running_ms,ssh_ms,total_ms" > "$RESULTS_FILE"

run_benchmark() {
  local technique=$1
  local script=$2

  for i in $(seq 1 $ITERATIONS); do
    echo ""
    echo ">>> $technique (iteration $i/$ITERATIONS)"

    # Run and capture output
    # TODO: parse timings from output and append to CSV
    bash "$script" "$KEY_FILE"
  done
}

# For now, just run cold
# Add minimal-ami and custom-init when ready
run_benchmark "cold" "bench/cold.sh"

echo ""
echo "Results saved to: $RESULTS_FILE"
