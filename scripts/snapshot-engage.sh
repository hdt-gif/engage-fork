#!/usr/bin/env bash
#
# Take an EBS snapshot of the Engage instance's volume, and prune old ones.
#
# RUN THIS ON YOUR OWN MACHINE, not on the instance -- it uses your AWS
# credentials, and the instance deliberately has none.
#
# Why this matters: backup-engage.sh on the instance writes dumps to the same
# disk as the database, so it cannot survive losing the volume. A snapshot is
# stored by AWS separately from the instance and captures those dumps along
# with everything else. It is the off-instance copy, until the instance is
# allowed its own IAM role and can upload to S3 directly.
#
# A snapshot of a running database is crash-consistent, not clean -- but it
# also contains last night's pg_dump, which IS clean. Restore from the dump
# inside the snapshot, not from the raw database files.
#
set -euo pipefail

REGION=us-east-2
INSTANCE=i-0c251de2dc1a35767
KEEP=10

VOLUME=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$INSTANCE" \
  --query 'Reservations[0].Instances[0].BlockDeviceMappings[0].Ebs.VolumeId' --output text)

echo "volume: $VOLUME"

SNAP=$(aws ec2 create-snapshot --region "$REGION" --volume-id "$VOLUME" \
  --description "Engage HSEO - $(date -u +%FT%TZ)" \
  --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=engage-hseo},{Key=Purpose,Value=backup}]' \
  --query 'SnapshotId' --output text)

echo "created: $SNAP"

# Prune, keeping the most recent $KEEP tagged engage-hseo
OLD=$(aws ec2 describe-snapshots --region "$REGION" --owner-ids self \
  --filters "Name=tag:Name,Values=engage-hseo" \
  --query "sort_by(Snapshots,&StartTime)[:-${KEEP}].SnapshotId" --output text)

for s in $OLD; do
  echo "deleting old snapshot: $s"
  aws ec2 delete-snapshot --region "$REGION" --snapshot-id "$s"
done

echo
echo "snapshots now held:"
aws ec2 describe-snapshots --region "$REGION" --owner-ids self \
  --filters "Name=tag:Name,Values=engage-hseo" \
  --query 'sort_by(Snapshots,&StartTime)[].{Id:SnapshotId,Started:StartTime,State:State,Progress:Progress}' \
  --output table
