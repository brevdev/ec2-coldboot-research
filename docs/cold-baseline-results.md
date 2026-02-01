# Cold Launch Baseline Results

**Date:** 2026-02-01 00:53:43 UTC
**Instance Type:** m7i.large
**AMI:** ami-0fcee47b1475c1af3 (Amazon Linux 2023)
**Technique:** cloud-init (default)

## Summary

| Phase | Description | Average | Notes |
|-------|-------------|---------|-------|
| T0→T1 | API call | 4797ms | RunInstances returns |
| T1→T2 | Pending→Running | 17811ms | Hypervisor/scheduler |
| T2→T4 | Boot→SSH ready | 3217ms | Kernel + cloud-init + sshd |
| **Total** | **End-to-end** | **25825ms (25.8s)** | |

## Individual Runs

| Run | API | Pending | Boot→SSH | Total |
|-----|-----|---------|----------|-------|
| 1 | 4626ms | 17779ms | 3250ms | 25655ms |
| 2 | 4800ms | 17805ms | 3200ms | 25805ms |
| 3 | 4965ms | 17851ms | 3201ms | 26017ms |

## Analysis

### Where Does the Time Go?

1. **API Call (T0→T1): ~4797ms**
   - AWS receives request, validates, schedules
   - Returns instance ID immediately

2. **Pending→Running (T1→T2): ~17811ms**
   - Instance scheduled to hypervisor
   - ENI attached, EBS attached
   - Hypervisor starts guest

3. **Boot→SSH (T2→T4): ~3217ms**
   - Linux kernel boot
   - systemd initialization
   - cloud-init runs (fetches metadata, injects SSH keys)
   - sshd starts and accepts connections

### Where the Time Goes (Breakdown)

| Phase | Time | % of Total |
|-------|------|------------|
| API | 4.8s | 19% |
| Pending→Running | 17.8s | **69%** |
| Boot→SSH | 3.2s | 12% |

**Key Finding:** Pending→Running dominates at 69%. This is AWS infrastructure time (hypervisor scheduling, ENI/EBS attachment). We have limited control here.

### Optimization Opportunities

- **API (~5s)**: Minor. Could pre-warm with describe calls but won't help much.
- **Pending→Running (~18s)**: AWS infrastructure time - largely outside our control. Possible improvements:
  - Warm pools (out of scope)
  - Pre-allocated ENI (out of scope)
  - Better instance type placement
- **Boot→SSH (~3s)**: Small but fully controllable:
  - Skip cloud-init (bake keys into AMI)
  - Minimal systemd or custom init
  - Faster sshd startup

**Realistic target:** Even with perfect boot optimization (0s boot), we'd still be at ~22s due to AWS overhead. The 5-10s target from specs/requirements.md may be unrealistic without warm pools or pre-allocation.

## Raw Data

```
API_TIMES: 4626 4800 4965
RUNNING_TIMES: 17779 17805 17851
SSH_TIMES: 3250 3200 3201
TOTAL_TIMES: 25655 25805 26017
```
