#!/bin/bash
# Clean up all instant-env AWS resources
# WARNING: This is destructive!

set -euo pipefail

echo "=== instant-env cleanup ==="
echo "This will terminate all instances and delete all resources tagged with Project=instant-env"
read -p "Are you sure? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Aborted."
    exit 1
fi

# Terminate running instances
echo "Terminating instances..."
INSTANCE_IDS=$(aws ec2 describe-instances \
    --filters "Name=tag:Project,Values=instant-env" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text)

if [ -n "$INSTANCE_IDS" ]; then
    aws ec2 terminate-instances --instance-ids $INSTANCE_IDS
    echo "Terminated: $INSTANCE_IDS"
else
    echo "No instances to terminate"
fi

# Wait for termination
if [ -n "$INSTANCE_IDS" ]; then
    echo "Waiting for instances to terminate..."
    aws ec2 wait instance-terminated --instance-ids $INSTANCE_IDS
fi

# Delete ENIs (must be detached first)
echo "Deleting ENIs..."
ENI_IDS=$(aws ec2 describe-network-interfaces \
    --filters "Name=tag:Project,Values=instant-env" \
    --query 'NetworkInterfaces[].NetworkInterfaceId' \
    --output text)

for ENI_ID in $ENI_IDS; do
    aws ec2 delete-network-interface --network-interface-id "$ENI_ID" || true
    echo "Deleted ENI: $ENI_ID"
done

# Release EIPs
echo "Releasing EIPs..."
ALLOC_IDS=$(aws ec2 describe-addresses \
    --filters "Name=tag:Project,Values=instant-env" \
    --query 'Addresses[].AllocationId' \
    --output text)

for ALLOC_ID in $ALLOC_IDS; do
    aws ec2 release-address --allocation-id "$ALLOC_ID" || true
    echo "Released EIP: $ALLOC_ID"
done

# Deregister AMIs
echo "Deregistering AMIs..."
AMI_IDS=$(aws ec2 describe-images \
    --owners self \
    --filters "Name=tag:Project,Values=instant-env" \
    --query 'Images[].ImageId' \
    --output text)

for AMI_ID in $AMI_IDS; do
    aws ec2 deregister-image --image-id "$AMI_ID" || true
    echo "Deregistered AMI: $AMI_ID"
done

# Delete snapshots
echo "Deleting snapshots..."
SNAPSHOT_IDS=$(aws ec2 describe-snapshots \
    --owner-ids self \
    --filters "Name=tag:Project,Values=instant-env" \
    --query 'Snapshots[].SnapshotId' \
    --output text)

for SNAPSHOT_ID in $SNAPSHOT_IDS; do
    aws ec2 delete-snapshot --snapshot-id "$SNAPSHOT_ID" || true
    echo "Deleted snapshot: $SNAPSHOT_ID"
done

# Delete security group
echo "Deleting security group..."
SG_ID=$(aws ec2 describe-security-groups \
    --filters "Name=group-name,Values=instant-env-ssh" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || echo "None")

if [ "$SG_ID" != "None" ] && [ -n "$SG_ID" ]; then
    aws ec2 delete-security-group --group-id "$SG_ID" || true
    echo "Deleted security group: $SG_ID"
fi

# Delete key pair
echo "Deleting key pair..."
aws ec2 delete-key-pair --key-name "instant-env-admin" 2>/dev/null || true
echo "Deleted key pair: instant-env-admin"

echo "=== Cleanup complete ==="
