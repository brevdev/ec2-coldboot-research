# AWS Setup

One-time infrastructure setup using AWS CLI. All scripts are idempotent.

## Prerequisites

```bash
# Verify AWS CLI is configured
aws sts get-caller-identity

# Required permissions:
# - ec2:* (instances, AMIs, ENIs, security groups)
# - iam:PassRole (for instance profiles)
# - ssm:GetParameter (for key distribution, optional)
```

## 1. Security Group

```bash
# Create security group for SSH access
./scripts/setup-security-group.sh
```

Creates `instant-env-ssh` security group allowing:
- Inbound: TCP 22 from 0.0.0.0/0 (benchmarking only, restrict in production)
- Outbound: All traffic

## 2. Key Pair (for admin access during AMI baking)

```bash
# Create admin key pair for AMI baking
./scripts/setup-keypair.sh
```

Creates `instant-env-admin` key pair. Private key saved to `~/.ssh/instant-env-admin.pem`.

## 3. IAM Instance Profile (optional)

```bash
# Create instance profile for SSM access
./scripts/setup-iam.sh
```

Creates `instant-env-instance` role with SSM permissions for debugging.

## 4. Minimal AMI

```bash
# Bake minimal AMI from Amazon Linux 2023
./scripts/bake-minimal-ami.sh
```

This script:
1. Launches a temporary instance
2. Strips unnecessary packages
3. Removes cloud-init
4. Installs minimal init script
5. Creates AMI
6. Terminates temporary instance

Output: AMI ID saved to `scripts/.ami-minimal-x86_64` and `scripts/.ami-minimal-arm64`

## 5. Custom Init AMI

```bash
# Bake AMI with custom Go init binary
./scripts/bake-custom-init-ami.sh
```

This script:
1. Cross-compiles the init binary for both architectures
2. Bakes into AMI with systemd service
3. Creates both x86_64 and arm64 variants

## Resource Tagging

All resources are tagged with:
- `Project=instant-env`
- `Purpose=benchmark`
- `ManagedBy=cli`

## Cleanup

```bash
# Remove all instant-env resources
./scripts/cleanup-all.sh
```

**Warning**: This terminates all instances and deletes all resources tagged with `Project=instant-env`.

## Cost Notes

- Use spot instances for benchmarks (default)
- Terminate instances immediately after benchmarks
- AMIs incur storage costs (~$0.05/GB/month for snapshots)
- Pre-allocated ENIs/EIPs incur costs when not attached

## Region

Default region from AWS CLI config is used. Override with:

```bash
AWS_REGION=us-west-2 ./scripts/setup-security-group.sh
```
