# Warm Pool Results

**Date:** 2026-01-31
**Instance Type:** m7i.large
**Technique:** Running instance + SSH key injection

## Summary

| Phase | Time | Notes |
|-------|------|-------|
| Keygen (local) | 130ms | ed25519 keypair |
| Key inject (SSH) | 846ms | Add to authorized_keys |
| SSH connect | 890ms | Connect with new key |
| **Total** | **1866ms** | **1.9 seconds** |

## Key Finding

**With a pre-running instance, user access takes under 2 seconds.**

This is the theoretical floor - 92% faster than cold launch.

## Breakdown

```
=== WARM POOL RESULTS ===
Keygen:       130ms
Key inject:   846ms
SSH connect:  890ms
---
TOTAL:        1866ms
```

## Comparison

| Technique | Time | vs Cold |
|-----------|------|---------|
| Cold launch | 25.8s | baseline |
| Start-stopped | 21.2s | -18% |
| Hibernate | 20.7s | -20% |
| **Warm pool** | **1.9s** | **-92%** |

## Implications

1. **Warm pools are the answer** - Pre-running instances get us to <2s
2. **The cost tradeoff is real** - Running instances cost $$
3. **Hybrid approach** - Small warm pool + cold launch overflow
4. **Key injection is fast** - 846ms to provision access

## Cost Considerations

For m7i.large in us-west-2:
- Running: ~$0.10/hour
- Stopped/Hibernated: ~$0.008/hour (EBS only)

A 10-instance warm pool costs ~$1/hour vs ~$0.08/hour hibernated.
But provides 1.9s vs 20.7s access time.

## Production Considerations

Key injection methods:
- SSH (as tested): Requires existing access mechanism
- EC2 Instance Connect: API-based, ~2s additional
- SSM Session Manager: No SSH needed, ~3s additional
- Pre-baked agent: Could be faster with custom solution
