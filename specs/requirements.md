# instant-env Requirements

## Overview

A benchmarking tool and service to measure EC2 instance deployment speed. The goal is to find the fastest path from "user provides SSH public key" to "user can SSH into instance."

## Hypothesis

With aggressive optimization (minimal AMI, pre-allocated networking, bypassing cloud-init), we can achieve 5-10 second deployment times. The baseline cold deploy is typically 30-60 seconds.

## Core Requirements

### Functional

1. **Benchmark CLI**: Run controlled benchmarks of different launch techniques
   - Specify technique (cold, minimal-ami, prealloc-eni, warm-stopped, custom-init)
   - Specify instance type (m7i.large, m7g.large, etc.)
   - Specify iteration count
   - Output timing breakdown

2. **HTTP API Service**: On-demand instance provisioning
   - Accept SSH public key
   - Select technique (or auto-select fastest available)
   - Return IP, port, and timing metrics
   - Clean up instances after TTL

3. **Timing Accuracy**: Millisecond precision for all phases
   - `t0`: Request received
   - `t1`: EC2 API call returns (instance ID obtained)
   - `t2`: Instance state = "running"
   - `t3`: TCP port 22 accepts connection
   - `t4`: SSH authentication succeeds

4. **Multi-architecture**: Support both x86_64 (m7i) and arm64 (m7g)

### Non-Functional

1. **Cleanup**: All benchmark instances must be terminated after runs
2. **Tagging**: All resources tagged with `Project=instant-env`
3. **Cost awareness**: Default to spot instances for benchmarks
4. **Idempotent setup**: Scripts can be re-run safely

## Techniques to Benchmark

### Control: Cold Deploy
- Standard RunInstances with Amazon Linux 2023
- Default VPC, auto-assign public IP
- cloud-init injects SSH key
- Expected: 30-60 seconds

### Technique 1: Minimal AMI
- Strip Amazon Linux 2023 to bare minimum
- Remove: cloud-init, ssm-agent, unnecessary packages
- Bake in a minimal init that just starts sshd
- Expected improvement: 10-20 seconds saved

### Technique 2: Pre-allocated ENI
- Create ENI in advance with public IP
- Attach at instance launch
- Eliminates network setup time
- Expected improvement: 2-5 seconds saved

### Technique 3: Warm Stopped Pool
- Pre-create instances in "stopped" state
- StartInstances is faster than RunInstances
- Key injection via userdata or instance metadata
- Expected improvement: 10-15 seconds saved

### Technique 4: Custom Init Binary
- Bake a Go binary into AMI that:
  - Fetches pubkey from instance metadata or parameter store
  - Writes to authorized_keys
  - Starts sshd
- No systemd, no cloud-init, no shell scripts
- Expected: Fastest cold-start possible

### Technique 5: Warm Hibernated (Research)
- Hibernate instance with memory state preserved
- Resume should be near-instant
- Requires EBS-backed, specific instance types
- Research: Does this work for our use case?

## Out of Scope (V1)

- Windows instances
- GPU instances
- Container-based alternatives (ECS, Fargate)
- Lambda-based SSH proxying
- Multi-region deployment
- Production hardening (this is a benchmarking tool)

## Success Criteria

1. Cold deploy baseline established with repeatable measurements
2. At least one technique achieves <15 second deploy time
3. Timing breakdown identifies where time is spent
4. Clear recommendation for production optimization path

## AWS Resources Required

- VPC with public subnet (can use default)
- Security group allowing SSH (port 22)
- IAM role for EC2 (SSM, if needed)
- S3 bucket (optional, for AMI baking artifacts)
- AMIs: Amazon Linux 2023 (baseline), custom minimal AMIs

## Open Questions

1. Does IMDSv2 hop limit affect boot time?
2. Can we pre-warm the Nitro hypervisor?
3. What's the actual breakdown of cloud-init execution time?
4. Is there a difference between regions for boot time?
