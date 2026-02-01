# Warm Pool with EC2 Instance Connect Results

**Date:** 2026-01-31
**Instance Type:** m7i.large
**Technique:** Running instance + EC2 Instance Connect API key injection

## Summary

| Phase | Time | Notes |
|-------|------|-------|
| Keygen (local) | 114ms | ed25519 keypair |
| Key push (API) | 1432ms | send-ssh-public-key |
| SSH connect | 2403ms | Connect with temp key |
| **Total** | **3949ms** | **~4 seconds** |

## Comparison with Other Methods

| Method | Total | Notes |
|--------|-------|-------|
| Cold launch | 25.8s | Full RunInstances |
| Warm pool (SSH) | 1.9s | Requires existing SSH access |
| **Warm pool (EIC)** | **3.9s** | No pre-existing access needed |

## Key Finding

**EC2 Instance Connect is 2x slower than SSH-based key injection, but more practical.**

The extra ~2s comes from:
- API call overhead for SendSSHPublicKey (~0.6s slower than SSH)
- Key propagation to instance metadata service
- Slightly slower first SSH connection

## Trade-offs

### SSH-based injection (1.9s)
- ✅ Faster
- ❌ Requires existing SSH access (chicken-and-egg)
- ❌ Need to manage long-lived keys on pool instances
- ❌ Security concern: keys persist

### EC2 Instance Connect (3.9s)
- ✅ No pre-existing SSH access needed
- ✅ Keys are temporary (60 seconds)
- ✅ AWS-managed, auditable
- ✅ Works with IAM permissions
- ❌ 2x slower
- ❌ Requires ec2-instance-connect package on instance

## Production Recommendation

**Use EC2 Instance Connect for production warm pools:**
- 4 seconds is still 85% faster than cold launch
- No key management complexity
- Better security posture (ephemeral keys)
- IAM-integrated access control

## Raw Data

```
=== EC2 INSTANCE CONNECT WARM POOL RESULTS ===
Keygen:       114ms
Key push:     1432ms
SSH connect:  2403ms
---
TOTAL:        3949ms

Speedup vs cold: 84%
```

## Requirements

1. Instance must have `ec2-instance-connect` package installed (default on AL2023)
2. IAM permissions for `ec2-instance-connect:SendSSHPublicKey`
3. Instance must pass status checks before EIC works
