# Documentation

Bash spike to measure EC2 deployment speed. Goal: learn where time goes, apply to brownfield backend.

## Quick Start

```bash
# 1. Setup AWS resources
./scripts/setup-security-group.sh
./scripts/setup-keypair.sh

# 2. Run baseline benchmark
./bench/cold.sh ~/.ssh/instant-env-admin.pem

# 3. Cleanup when done
./scripts/cleanup-all.sh
```

## Contents

- [AWS Setup](aws-setup.md) - One-time infrastructure setup

## Timing Phases

```
T0  Script starts
 │
 ├─ aws ec2 run-instances
 │
T1  Instance ID returned
 │
 ├─ aws ec2 wait instance-running
 │
T2  State = "running"
 │
 ├─ nc -z (TCP probe)
 │
T3  TCP port 22 open
 │
 ├─ ssh (auth handshake)
 │
T4  SSH auth success

Total = T4 - T0
```

## Techniques

| Script | Description | Status |
|--------|-------------|--------|
| `bench/cold.sh` | Baseline with cloud-init | Ready |
| `bench/minimal-ami.sh` | Stripped AMI, no cloud-init | TODO |
| `bench/custom-init.sh` | Go/bash init binary | TODO |

## Instance Type

Fixed to **m7i.large** for consistent benchmarking.
