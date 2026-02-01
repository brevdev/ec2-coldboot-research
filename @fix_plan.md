# Fix Plan

## Phase 1: Baseline Measurement

- [x] **[1.1]** Create cold launch benchmark script
  - Files: `bench/cold.sh`, `bench/common.sh`
  - Acceptance: Runs full launch, reports timing breakdown

- [x] **[1.2]** Run cold baseline and document results
  - Run 3 iterations, record typical timing
  - Document: Where does the time actually go?
  - Dependencies: AWS setup complete
  - **Result:** 25.8s avg. API 19%, Pending→Running 69%, Boot→SSH 12%
  - **Key Finding:** AWS infra time (Pending→Running) dominates; boot optimization has limited impact

## Phase 2: Minimal AMI

- [x] **[2.1]** Create minimal AMI baking script
  - Files: `scripts/bake-minimal-ami.sh`
  - Strip: cloud-init, ssm-agent, unnecessary packages
  - Keep: sshd, basic networking

- [x] **[2.2]** Create minimal-ami benchmark script
  - Files: `bench/minimal-ami.sh`
  - Compare timing to cold baseline
  - **Result:** 28.8s - **SLOWER than baseline!**
  - **Key Finding:** Cloud-init actually helps boot faster (coordinates service startup)
  - Boot→SSH went from 3.2s to 9.0s without cloud-init
  - **Recommendation:** Don't strip cloud-init

## Phase 3: Infrastructure Experiments (the 69%)

Based on baseline results, Pending→Running takes 69% of total time (~18s). This phase tests hypotheses to understand/reduce AWS infrastructure time.

- [x] **[3.1]** Instance type sweep benchmark
  - Files: `bench/instance-type-sweep.sh`
  - Test: t3.medium, t3.large, m6i.large, m7i.large, c7i.large, r7i.large
  - **Result:** 680ms variance (22.6s - 23.3s) - instance type doesn't matter
  - **Key Finding:** Pending→Running is 16.4-16.6s regardless of instance family

- [x] **[3.2]** Pre-allocated ENI benchmark
  - Files: `bench/pre-eni.sh`, `scripts/setup-eni.sh`
  - Create ENI ahead of time, attach at launch
  - Hypothesis: Skip ENI creation = faster pending phase
  - **Status:** Scripts created. Run `scripts/setup-eni.sh` first, then use PRE_ENI_ID

- [x] **[3.3]** EBS volume size experiment
  - Files: `bench/ebs-size.sh`
  - Test: 8GB vs 20GB root volume (gp3)
  - Hypothesis: Smaller EBS = faster attachment
  - **Status:** Script created, ready to run

- [x] **[3.4]** Start-from-stopped benchmark (pre-warmed simulation)
  - Files: `bench/start-stopped.sh`
  - Launch instance, stop it, then benchmark start time
  - Simulates: pre-warmed disk, pre-attached ENI, pre-scheduled hypervisor
  - **Result:** 21.2s (only 18% faster than cold)
  - **Key Finding:** Pending→Running still takes 16.4s even with pre-attached EBS/ENI
  - The bottleneck is VM/hypervisor cold-start, not resource allocation

- [x] **[3.5]** Availability Zone variance test
  - Files: `bench/az-sweep.sh`
  - Run same test across all AZs via subnet placement
  - **Status:** Script created (not run - region sweep covers this)

- [x] **[3.5b]** Region sweep benchmark
  - Files: `bench/region-sweep.sh`
  - Test: us-west-2, us-east-1, us-east-2, eu-west-1, ap-northeast-1
  - **Result:** 1.5s variance (22.2s - 23.7s) - region doesn't matter
  - **Key Finding:** Pending→Running is 16.4-16.9s across all regions globally
  - Network latency (API + SSH) accounts for the variance

- [x] **[3.6]** Hibernate resume benchmark
  - Files: `bench/hibernate.sh`
  - Resume from hibernation (RAM state preserved on EBS)
  - **Result:** 20.7s - only 0.5s faster than start-stopped
  - **Key Finding:** Hibernate doesn't help significantly
  - The VM startup dominates, not kernel boot
  - Hibernate adds complexity (encrypted EBS, size requirements, 60s+ warmup)

- [x] **[3.7]** Warm pool benchmark (running instances)
  - Files: `bench/warm-pool.sh`
  - Pre-running instance + SSH key injection
  - **Result:** 1.9s - 92% faster than cold!
  - **Key Finding:** This is the only way to truly skip the 16s VM startup
  - Breakdown: keygen 130ms, key inject 846ms, SSH connect 890ms

- [x] **[3.8]** Document infrastructure findings
  - See summary below

- [x] **[3.9]** Implement warm pool with EC2 Instance Connect for key injection
  - Files: `bench/warm-pool-eic.sh`
  - Use EC2 Instance Connect API to inject key (no pre-existing access required)
  - **Result:** 3.3s - 87% faster than cold
  - **Key Finding:** 1.5s slower than SSH key injection, but more realistic
  - Breakdown: keygen 112ms, key push 1351ms, SSH connect 1878ms
  - Trade-off: Slower but production-ready (no pre-configured keys needed)

## Phase 4: Custom Init (boot time - 12%)

**STATUS: DEPRIORITIZED** - Boot optimization has minimal impact given findings.

- [ ] **[4.1]** Create init-agent (simple Go or bash)
  - Fetches pubkey from userdata or IMDS
  - Writes to authorized_keys
  - Starts sshd
  - Files: `init-agent/` or inline in bake script
  - **Note:** Minimal-ami showed cloud-init already helps; custom init unlikely to beat it

- [ ] **[4.2]** Create custom-init AMI baking script
- [ ] **[4.3]** Create custom-init benchmark script

## Phase 5: Analysis & Summary

### Benchmark Results

| Technique | Total | Pending→Running | Boot→SSH | vs Cold |
|-----------|-------|-----------------|----------|---------|
| Cold (baseline) | 25.8s | 17.8s | 3.2s | - |
| Start-stopped | 21.2s | 16.4s | 3.0s | -18% |
| Hibernate | 20.7s | 16.3s | 2.4s | -20% |
| Minimal-ami | 28.8s | 16.4s | 9.0s | **+12%** |
| **Warm pool (SSH)** | **1.9s** | **N/A** | **N/A** | **-92%** |
| **Warm pool (EIC)** | **3.3s** | **N/A** | **N/A** | **-87%** |

### Key Findings

1. **The 69% is unavoidable without warm pools**
   - Pending→Running takes ~16-18s regardless of technique
   - This is VM/hypervisor cold-start, not resource allocation
   - Pre-attached EBS/ENI doesn't help significantly

2. **Boot optimization has diminishing returns**
   - Boot→SSH is only 3.2s (12% of total)
   - Cloud-init actually helps (stripping it made it slower)
   - Hibernate saves only 0.8s vs cold boot

3. **Warm pools are the only answer for <10s**
   - Pre-running instances: 1.9s (92% reduction)
   - Cost: ~$0.10/hr per instance (m7i.large)
   - Trade-off: Instance cost vs startup speed

### Recommendations for Brownfield

1. **Implement warm pools** - Small pool of running instances
2. **Don't strip cloud-init** - It helps, not hurts
3. **Skip hibernate** - Complexity not worth 0.5s savings
4. **Hybrid approach** - Warm pool for fast access, cold launch for overflow
