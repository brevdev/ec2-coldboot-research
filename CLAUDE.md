# instant-env

Bash spike to measure EC2 deployment speed. Learning rig before applying to brownfield backend.

## Quick Reference

```bash
# One-time setup
./scripts/setup-security-group.sh
./scripts/setup-keypair.sh

# Run cold baseline benchmark
./bench/cold.sh ~/.ssh/instant-env-admin.pem

# Cleanup everything
./scripts/cleanup-all.sh
```

## Directory Structure

```
bench/              # Benchmark scripts
  common.sh         # Shared functions (timing, SSH probe)
  cold.sh           # Baseline: full cloud-init
  start-stopped.sh  # Pre-warmed EBS/ENI (simulates warm pool)
  minimal-ami.sh    # Stripped AMI, no cloud-init
  custom-init.sh    # TODO: Go binary init
scripts/            # AWS setup (idempotent)
docs/               # Documentation
```

## What We're Measuring

```
T0: API request
T1: RunInstances returns (instance ID)
T2: Instance state = "running"
T3: TCP port 22 open
T4: SSH auth succeeds
```

Target: Get T4-T0 under 10 seconds (baseline is 30-60s).

## Techniques

| Technique | Description | Result |
|-----------|-------------|--------|
| `cold` | Full RunInstances + cloud-init | 25.8s (baseline) |
| `start-stopped` | Pre-warmed EBS/ENI | 21.2s (-18%) |
| `hibernate` | Resume from hibernation | 20.7s (-20%) |
| `minimal-ami` | Stripped AL2023, no cloud-init | 28.8s (+12% slower!) |
| `warm-pool` | Running instance + SSH key inject | **1.9s (-92%)** |
| `warm-pool-eic` | Running instance + EC2 Instance Connect | **3.9s (-85%)** |

## Sweep Results

| Factor | Variance | Finding |
|--------|----------|---------|
| Instance type | 680ms | t3→r7i all ~22-23s; Pending→Running fixed at 16.4s |
| Region | 2116ms | us-east-2→eu-west-1; Pending→Running fixed globally |

**Conclusion:** Instance type and region don't matter. Warm pools are the only lever.

## Conventions

- All scripts use `set -euo pipefail`
- Timing in milliseconds
- Instance type fixed to m7i.large
- All resources tagged `Project=instant-env`
