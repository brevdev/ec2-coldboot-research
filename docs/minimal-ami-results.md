# Minimal AMI Results

**Date:** 2026-01-31
**Instance Type:** m7i.large
**AMI:** ami-026fc59ddedfbf36c (stripped AL2023, no cloud-init)
**Technique:** Minimal AMI with cloud-init, ssm-agent, ec2-instance-connect removed

## Summary

| Phase | Cold Baseline | Minimal AMI | Difference |
|-------|---------------|-------------|------------|
| API call | 4797ms | 3359ms | -1438ms |
| Pending→Running | 17811ms | 16399ms | -1412ms |
| Boot→SSH | 3217ms | 9041ms | **+5824ms** |
| **Total** | **25825ms** | **28799ms** | **+2974ms (12% slower!)** |

## Key Finding

**The minimal AMI is 3 seconds SLOWER than baseline!**

The Boot→SSH phase went from 3.2s to 9.0s - nearly 3x slower.

### Why?

Without cloud-init, the instance loses:
- ❌ Optimized network configuration timing
- ❌ Parallel service startup orchestration
- ❌ SSH key injection coordination with sshd

Cloud-init actually helps boot faster by:
- Coordinating when sshd should start accepting connections
- Ensuring network is fully configured before SSH listens
- Running initialization tasks in parallel where possible

### Observations

- No TCP port open logged before SSH auth (suggesting delayed network/sshd)
- SSH auth took 7.7s from start of probing
- The AMI stripped 123MB of packages but hurt boot time

## Implications

1. **Cloud-init is not the bottleneck** - It actually speeds up boot
2. **Don't strip cloud-init** - The coordination it provides is valuable
3. **Focus elsewhere** - Boot→SSH is only 12% of total anyway
4. **The 69% Pending→Running is the real target**

## Raw Data

```
=== MINIMAL AMI LAUNCH ===
API call:     3359ms
Running:      19758ms (+16399ms)
SSH ready:    28799ms (+9041ms)
---
TOTAL:        28799ms
```

## Packages Removed

- amazon-ssm-agent (117 MB)
- cloud-init (5.6 MB)
- cloud-init-cfg-ec2
- ec2-instance-connect

## Next Steps

- Abandon minimal-AMI approach
- Focus on Pending→Running phase
- Test hibernate (skips kernel entirely)
- Test different instance types
