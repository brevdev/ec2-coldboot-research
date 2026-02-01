# Instance Type Sweep Results

**Date:** 2026-01-31
**Region:** us-west-2
**Technique:** Cold launch across different instance types

## Summary

| Instance Type | API | Pending→Running | Boot→SSH | Total |
|--------------|-----|-----------------|----------|-------|
| t3.medium | 3718ms | 16620ms | 2744ms | 23082ms |
| t3.large | 3885ms | 16457ms | 2979ms | 23321ms |
| m6i.large | 3727ms | 16553ms | 2672ms | 22952ms |
| m7i.large | 3789ms | 16368ms | 2584ms | 22741ms |
| c7i.large | 3581ms | 16368ms | 2727ms | 22676ms |
| r7i.large | 3464ms | 16477ms | 2700ms | 22641ms |

**Fastest:** r7i.large (22641ms)
**Slowest:** t3.large (23321ms)
**Variance:** 680ms (2.6%)

## Key Finding

**Instance type has minimal impact on startup time.**

The Pending→Running phase is remarkably consistent across all instance types:
- Range: 16.4s - 16.6s
- Variance: ~250ms

This suggests the VM startup overhead is:
- Independent of instance family (burstable vs general vs compute vs memory)
- Independent of instance size (at least for "large" variants)
- A fixed cost in the AWS infrastructure layer

## Implications

1. **Don't optimize instance type for speed** - Pick based on workload, not startup
2. **The 16s floor is universal** - Applies to all tested instance families
3. **Burstable (t3) slightly slower** - But only by ~300ms
4. **Newer generations not faster** - m7i same as m6i

## Raw Data

```
Instance Type        API    Pending     Boot    Total
-------------        ---    -------     ----    -----
t3.medium          3718ms     16620ms    2744ms   23082ms
t3.large           3885ms     16457ms    2979ms   23321ms
m6i.large          3727ms     16553ms    2672ms   22952ms
m7i.large          3789ms     16368ms    2584ms   22741ms
c7i.large          3581ms     16368ms    2727ms   22676ms
r7i.large          3464ms     16477ms    2700ms   22641ms
```
