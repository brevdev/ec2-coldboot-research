# Realistic Warm Pool Results

**Date:** 2026-01-31
**Instance Type:** m7i.large
**Technique:** Full warm pool flow with EC2 Instance Connect

## Simulated Flow

1. Query for available instances (describe-instances with tag filters)
2. Claim instance (create-tags to mark as claimed)
3. Generate session keypair
4. Push key via EC2 Instance Connect
5. SSH connect

## Results

| Phase | Time | Notes |
|-------|------|-------|
| Query pool | 6476ms | describe-instances with tag filters |
| Claim instance | 1460ms | create-tags |
| Keygen | 137ms | ed25519 |
| EIC key push | 2532ms | send-ssh-public-key |
| SSH connect | 2232ms | First connection |
| **TOTAL** | **12837ms** | **12.8 seconds** |

## Grouped Breakdown

| Category | Time | % of Total |
|----------|------|------------|
| Pool management | 7936ms | 62% |
| Key injection | 2669ms | 21% |
| SSH connect | 2232ms | 17% |

## Key Finding

**Using EC2 tags for pool management adds ~8 seconds of overhead!**

The `describe-instances` API call with tag filters is slow:
- Single instance in pool: 6.5s query time
- This would likely improve with pagination/caching but is still significant

## Comparison

| Approach | Time | Notes |
|----------|------|-------|
| Cold launch | 25.8s | Full RunInstances |
| Simple EIC | 3.9s | No pool management |
| **Realistic EIC** | **12.8s** | With EC2 tag-based pool |

## Implications

**Don't use EC2 tags/API for pool management in the hot path.**

Better approaches:
1. **Local database** - Track pool state in Redis/DynamoDB
2. **Pre-fetched pool list** - Background refresh, instant lookup
3. **Dedicated pool service** - Separate service manages pool state
4. **AWS Warm Pools** - Built-in Auto Scaling feature

## Optimized Architecture

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│ User Request │────▶│ Pool Manager │────▶│ Instance DB │
└─────────────┘     │  (in-memory) │     │  (Redis)    │
                    └──────┬───────┘     └─────────────┘
                           │
                    ┌──────▼───────┐
                    │ EC2 Instance │
                    │ Connect API  │
                    └──────────────┘
```

With this architecture:
- Pool lookup: ~1ms (Redis)
- Claim update: ~5ms (Redis)
- EIC + SSH: ~5s
- **Total: ~5s** (vs 12.8s with EC2 API)

## Raw Data

```
Phase breakdown:
  1. Query pool:      6476ms
  2. Claim instance:  1460ms
  3. Keygen:          137ms
  4. EIC key push:    2532ms
  5. SSH connect:     2232ms
  ---
  TOTAL:              12837ms
```
