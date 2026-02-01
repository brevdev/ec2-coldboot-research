# Fix Plan

## Phase 1: Baseline Measurement

- [x] **[1.1]** Create cold launch benchmark script
  - Files: `bench/cold.sh`, `bench/common.sh`
  - Acceptance: Runs full launch, reports timing breakdown

- [ ] **[1.2]** Run cold baseline and document results
  - Run 3 iterations, record typical timing
  - Document: Where does the time actually go?
  - Dependencies: AWS setup complete

## Phase 2: Minimal AMI

- [ ] **[2.1]** Create minimal AMI baking script
  - Files: `scripts/bake-minimal-ami.sh`
  - Strip: cloud-init, ssm-agent, unnecessary packages
  - Keep: sshd, basic networking

- [ ] **[2.2]** Create minimal-ami benchmark script
  - Files: `bench/minimal-ami.sh`
  - Compare timing to cold baseline

## Phase 3: Custom Init

- [ ] **[3.1]** Create init-agent (simple Go or bash)
  - Fetches pubkey from userdata or IMDS
  - Writes to authorized_keys
  - Starts sshd
  - Files: `init-agent/` or inline in bake script

- [ ] **[3.2]** Create custom-init AMI baking script
  - Files: `scripts/bake-custom-init-ami.sh`
  - No cloud-init, no systemd (or minimal systemd)
  - init-agent runs on boot

- [ ] **[3.3]** Create custom-init benchmark script
  - Files: `bench/custom-init.sh`
  - This should be the fastest

## Phase 4: Analysis

- [ ] **[4.1]** Compare all techniques
  - Create summary with timing breakdown
  - Identify: What's the floor? What's unavoidable?
  - Document learnings for brownfield application
