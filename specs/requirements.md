# instant-env Requirements

## Overview

Bash spike to measure EC2 instance deployment speed. Goal: learn where the 30-60 seconds goes, then apply learnings to brownfield backend.

## Hypothesis

With aggressive optimization (minimal AMI, bypassing cloud-init), we can achieve 5-10 second deployment times.

## What We're Measuring

```
T0 → T1: RunInstances API latency
T1 → T2: Pending → Running (hypervisor boot)
T2 → T3: Running → TCP 22 open (OS + sshd startup)
T3 → T4: TCP → SSH auth (sshd ready + key accepted)
```

## Techniques (Simplified)

### 1. Cold (Baseline)
- Amazon Linux 2023 default AMI
- cloud-init injects SSH key
- Expected: 30-60 seconds

### 2. Minimal AMI
- Strip AL2023: remove cloud-init, ssm-agent, extras
- Keep: kernel, sshd, networking
- Expected: 15-25 seconds

### 3. Custom Init
- Bake init script/binary into AMI
- Fetches key from userdata, writes authorized_keys, starts sshd
- No cloud-init, minimal systemd
- Expected: 5-15 seconds (target)

## Constraints

- **Instance type**: m7i.large (fixed)
- **No spot**: Keep it simple
- **No HTTP API**: CLI benchmarks only
- **Single region**: Default from AWS CLI

## Success Criteria

1. Baseline timing documented with breakdown
2. Identify where time actually goes
3. At least one technique under 15 seconds
4. Clear learnings for production backend

## Out of Scope

- Multi-architecture (arm64)
- Warm pools / stopped instances
- Pre-allocated ENI/EIP
- HTTP API service
- Production hardening
