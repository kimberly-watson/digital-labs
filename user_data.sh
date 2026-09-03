#!/bin/bash
set -euxo pipefail

REGION=us-east-1
ASSETS_PREFIX=assets

# IMDSv2: get a short-lived token for all metadata calls
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")

# Derive the S3 assets bucket name from the account ID (avoids hardcoding)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ASSETS_BUCKET="digital-labs-tfstate-${ACCOUNT_ID}"

# Discover this lab's key from the EC2 instance tag (set by Terraform at deploy time).
LAB_KEY=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/tags/instance/lab_key)

# Read termination time from this lab's SSM parameter
TERMINATION_TIME=$(aws ssm get-parameter \
  --name "/digital-labs/${LAB_KEY}/termination-time" \
  --region ${REGION} \
  --query "Parameter.Value" \
  --output text)

export REGION ASSETS_PREFIX ASSETS_BUCKET LAB_KEY TERMINATION_TIME IMDS_TOKEN

# The full provisioning logic (Docker, Nexus, IQ Server, seeding, nginx, Lab
# Tutor, CloudWatch agent) lives in assets/provision.sh, downloaded here
# rather than inlined, to stay under EC2's 16,384-byte user_data limit.
aws s3 cp "s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}/provision.sh" /tmp/provision.sh
chmod +x /tmp/provision.sh
/tmp/provision.sh
