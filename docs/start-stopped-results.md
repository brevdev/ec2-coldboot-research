# Start-from-Stopped Results

**Date:** 2026-01-31
**Instance Type:** m7i.large
**AMI:** Amazon Linux 2023 (same as cold baseline)
**Technique:** Start pre-stopped instance (EBS/ENI already attached)

## Summary

| Phase | Cold Baseline | Start-Stopped | Difference |
|-------|---------------|---------------|------------|
| API call | 4797ms | 1764ms | -3033ms |
| Pending→Running | 17811ms | 16372ms | -1439ms |
| Boot→SSH | 3217ms | 3042ms | -175ms |
| **Total** | **25825ms** | **21178ms** | **-4647ms (18%)** |

## Key Finding

**Starting a stopped instance only saves ~4.6s (18%) vs cold launch.**

The Pending→Running phase is nearly identical:
- Cold: 17.8s
- Start-stopped: 16.4s

This means the 69% of time spent in Pending→Running is NOT primarily:
- ❌ EBS volume creation/attachment (already attached)
- ❌ ENI creation/attachment (already attached)
- ❌ Hypervisor placement/scheduling (already placed)

It IS likely:
- ✅ Hypervisor cold-start of the guest VM
- ✅ Hardware/firmware initialization
- ✅ Network path establishment (even with ENI attached)

## Implications

1. **Warm pools won't help much** - Pre-provisioned stopped instances still take ~21s
2. **The bottleneck is deeper** - Inside AWS infrastructure, not resource allocation
3. **Hibernate might help** - Skips guest cold-start entirely
4. **Instance store might help** - Different storage path

## Raw Data

```
=== START-FROM-STOPPED ===
API call:     1764ms
Running:      18136ms (+16372ms)
SSH ready:    21178ms (+3042ms)
---
TOTAL:        21178ms
```

## Next Steps

- Test hibernate resume (skips kernel boot)
- Test instance-store backed instances
- Test different instance types (smaller might be faster)
