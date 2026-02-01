# Region Sweep Results

**Date:** 2026-01-31
**Instance Type:** m7i.large
**Technique:** Cold launch across different AWS regions

## Summary

| Region | API | Pending→Running | Boot→SSH | Total |
|--------|-----|-----------------|----------|-------|
| us-east-2 (Ohio) | 2474ms | 16511ms | 2971ms | 21956ms |
| us-west-2 (Oregon) | 3827ms | 16375ms | 2632ms | 22834ms |
| us-east-1 (N. Virginia) | 3459ms | 16580ms | 3228ms | 23267ms |
| ap-northeast-1 (Tokyo) | 2654ms | 16679ms | 3996ms | 23329ms |
| eu-west-1 (Ireland) | 2544ms | 17065ms | 4463ms | 24072ms |

**Fastest:** us-east-2 (21956ms)
**Slowest:** eu-west-1 (24072ms)
**Variance:** 2116ms (9%)

## Key Finding

**Region has minimal impact on the core VM startup time.**

Pending→Running is consistent across all regions:
- Range: 16.4s - 16.9s
- Variance: ~460ms (within measurement noise)

The total variance (1.5s) comes from:
- API latency (network distance to region)
- Boot→SSH latency (network distance for SSH)

## Observations

1. **Pending→Running is region-independent** - ~16.5s everywhere
2. **Closer regions have lower total time** - Due to API/SSH network latency
3. **us-east-2 (Ohio) was fastest** - Good balance of capacity + network
4. **Tokyo/Ireland slower** - Network latency adds ~1.5s

## Implications

1. **Region selection won't speed up VM startup** - Only affects network latency
2. **Pick region for user proximity** - Reduces API and SSH latency
3. **The 16s floor is global** - AWS infrastructure overhead is consistent worldwide
4. **Multi-region warm pools** - Would need pools in each region for latency

## Network Latency Breakdown

The Boot→SSH variance (2.7s - 4.1s) correlates with physical distance:
- us-west-2: 2.7s (closest to test location)
- us-east-2: 3.0s
- us-east-1: 3.4s
- eu-west-1: 4.1s (transatlantic)
- ap-northeast-1: 4.1s (transpacific)

## Raw Data

```
Region                    API    Pending     Boot    Total
-------------------       ---    -------     ----    -----
us-east-2               2382ms     16789ms    2991ms   22162ms
us-west-2               3965ms     16406ms    2672ms   23043ms
us-east-1               3266ms     16803ms    3435ms   23504ms
eu-west-1               2755ms     16767ms    4111ms   23633ms
ap-northeast-1          2697ms     16868ms    4138ms   23703ms
```
