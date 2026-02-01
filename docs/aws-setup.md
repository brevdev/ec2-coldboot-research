# AWS Setup

One-time infrastructure setup using AWS CLI. All scripts are idempotent.

## Prerequisites

```bash
# Verify AWS CLI is configured
aws sts get-caller-identity

# Required permissions:
# - ec2:RunInstances, TerminateInstances, DescribeInstances
# - ec2:CreateSecurityGroup, AuthorizeSecurityGroupIngress
# - ec2:CreateKeyPair, DescribeKeyPairs
# - ec2:CreateImage, DescribeImages (for AMI baking)
```

## 1. Security Group

```bash
./scripts/setup-security-group.sh
```

Creates `instant-env-ssh` security group:
- Inbound: TCP 22 from 0.0.0.0/0
- Uses default VPC

## 2. Key Pair

```bash
./scripts/setup-keypair.sh
```

Creates `instant-env-admin` key pair. Private key saved to `~/.ssh/instant-env-admin.pem`.

## Resource Tagging

All resources tagged with:
- `Project=instant-env`
- `Purpose=benchmark`

## Cleanup

```bash
./scripts/cleanup-all.sh
```

Terminates all instances and deletes resources tagged `Project=instant-env`.

## Cost Notes

- On-demand instances only (no spot complexity)
- Terminate instances immediately after benchmarks
- m7i.large is ~$0.10/hr

## Region

Uses default region from AWS CLI config. Override with:

```bash
AWS_REGION=us-west-2 ./scripts/setup-security-group.sh
```
