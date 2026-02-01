# Documentation

Bash spike to measure EC2 deployment speed. Goal: learn where time goes, apply to brownfield backend.

## Key Findings

**The ~16s Pending→Running phase is fixed AWS infrastructure overhead.** It cannot be reduced by:
- Instance type selection (680ms variance across t3→r7i)
- Region selection (2.1s variance, mostly network latency)
- Stripping cloud-init (made it slower!)
- Hibernate vs stop/start (only 0.5s difference)

**The only way to achieve <10s startup is warm pools with running instances.**

## Results Summary

| Technique | Time | vs Baseline |
|-----------|------|-------------|
| Cold launch | 25.8s | baseline |
| Stop/start | 21.2s | -18% |
| Hibernate | 20.7s | -20% |
| Minimal AMI | 28.8s | +12% (slower!) |
| **Warm pool (EIC)** | **3.9s** | **-85%** |
| Warm pool (SSH) | 1.9s | -92% |

## Detailed Results

- [Cold Baseline](cold-baseline-results.md) - Where does the time go?
- [Start-Stopped](start-stopped-results.md) - Pre-warmed EBS/ENI
- [Hibernate](hibernate-results.md) - Resume from hibernation
- [Minimal AMI](minimal-ami-results.md) - Stripped cloud-init (don't do this)
- [Warm Pool (SSH)](warm-pool-results.md) - Theoretical floor
- [Warm Pool (EIC)](warm-pool-eic-results.md) - Production recommended
- [Instance Type Sweep](instance-type-sweep-results.md) - t3→r7i comparison
- [Region Sweep](region-sweep-results.md) - Cross-region comparison

## Quick Start

```bash
# 1. Setup AWS resources
./scripts/setup-security-group.sh
./scripts/setup-keypair.sh

# 2. Run baseline benchmark
./bench/cold.sh ~/.ssh/instant-env-admin.pem

# 3. Run warm pool benchmark (production approach)
./bench/warm-pool-eic.sh

# 4. Cleanup when done
./scripts/cleanup-all.sh
```

## Timing Phases

```
T0  Script starts
 │
 ├─ aws ec2 run-instances
 │
T1  Instance ID returned (~5s)
 │
 ├─ aws ec2 wait instance-running
 │
T2  State = "running" (~18s) ← THE BOTTLENECK
 │
 ├─ nc -z (TCP probe)
 │
T3  TCP port 22 open
 │
 ├─ ssh (auth handshake)
 │
T4  SSH auth success (~3s)

Cold Total = ~26s
Warm Pool = ~4s (skips T0→T2)
```

## Recommendation

For production: **Use EC2 Instance Connect with warm pools**
- 3.9s access time (85% faster than cold)
- No pre-existing SSH access needed
- Ephemeral keys (60s validity)
- IAM-integrated, auditable
