# Hibernate Resume Results

**Date:** 2026-01-31
**Instance Type:** m7i.large
**Technique:** Resume from hibernation (RAM state preserved)

## Summary

| Phase | Time | Notes |
|-------|------|-------|
| API call | 2015ms | start-instances returns |
| Pending→Running | 16311ms | Hypervisor resume |
| Boot→SSH | 2381ms | RAM restore + network |
| **Total** | **20707ms** | **20.7 seconds** |

## Key Finding

**Hibernate resume is NOT significantly faster than start-stopped.**

- Hibernate: 20.7s
- Start-stopped: 21.2s
- Difference: 0.5s (2%)

The Pending→Running phase dominates both:
- Hibernate: 16.3s
- Start-stopped: 16.4s

## Why Hibernate Doesn't Help

The bottleneck is NOT kernel boot - it's the hypervisor/VM startup:
1. AWS needs to restore the VM to a hypervisor
2. Restore memory pages from EBS
3. Re-establish network connectivity
4. Resume the guest OS

The actual kernel boot (which hibernate skips) is only ~1s of the 3s Boot→SSH phase.

## Raw Data

```
=== HIBERNATE RESUME ===
API call:     2015ms
Running:      18326ms (+16311ms)
SSH ready:    20707ms (+2381ms)
---
TOTAL:        20707ms
```

## Comparison

| Technique | Total | Pending→Running | Boot→SSH |
|-----------|-------|-----------------|----------|
| Cold | 25.8s | 17.8s | 3.2s |
| Start-stopped | 21.2s | 16.4s | 3.0s |
| **Hibernate** | **20.7s** | **16.3s** | **2.4s** |
| Warm pool | 1.9s | N/A | N/A |

## Implications

1. **Hibernate is not worth the complexity** - Only saves 0.5s vs stop/start
2. **Hibernate has additional requirements**:
   - Encrypted EBS root volume (adds ~$0.10/GB/month)
   - Volume size must accommodate RAM
   - 60s+ wait before hibernate is ready
3. **The VM startup is the bottleneck** - Not the OS boot
4. **Focus on warm pools** - Only way to truly skip the 16s overhead

## Cost

Same as stopped instances (EBS only), but:
- Requires larger EBS volume for RAM storage
- Encrypted volume required (small additional cost)
