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
  minimal-ami.sh    # TODO: stripped AMI
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

| Technique | Description | Status |
|-----------|-------------|--------|
| `cold` | Full RunInstances + cloud-init | Ready |
| `minimal-ami` | Stripped AL2023, no cloud-init | TODO |
| `custom-init` | Baked Go binary, no systemd | TODO |

## Conventions

- All scripts use `set -euo pipefail`
- Timing in milliseconds
- Instance type fixed to m7i.large
- All resources tagged `Project=instant-env`
