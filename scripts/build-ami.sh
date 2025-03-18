#!/bin/bash
set -e

REGION="us-east-1"
INSTANCE_TYPE="t3.micro"
KEY_NAME="payment-builder-key"
SECURITY_GROUP_NAME="payment-builder-sg"
TAG="Payment-Processing"
AMI_NAME="payment-api-ami"

# 1. Create security group
vpc_id=$(aws ec2 describe-vpcs \
  --filters Name=isDefault,Values=true \
  --query "Vpcs[0].VpcId" --output text --region $REGION)

sg_id=$(aws ec2 create-security-group \
  --group-name $SECURITY_GROUP_NAME \
  --description "SG for AMI builder" \
  --vpc-id $vpc_id \
  --region $REGION \
  --output text)

aws ec2 authorize-security-group-ingress \
  --group-id $sg_id \
  --protocol tcp \
  --port 22 \
  --cidr 0.0.0.0/0 \
  --region $REGION

# 2. Launch EC2 with user-data to install the app
# Amazon Linux 2 AMI in us-east-1
instance_id=$(aws ec2 run-instances \
  --image-id ami-0c02fb55956c7d316 \
  --count 1 \
  --instance-type $INSTANCE_TYPE \
  --key-name $KEY_NAME \
  --security-group-ids $sg_id \
  --subnet-id $(aws ec2 describe-subnets \
    --filters Name=default-for-az,Values=true \
    --query "Subnets[0].SubnetId" --output text --region $REGION) \
  --user-data file://scripts/ami-user-data.sh \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Application,Value=$TAG}]" \
  --region $REGION \
  --query "Instances[0].InstanceId" \
  --output text)

echo "⏳ Waiting for instance $instance_id to initialize..."
aws ec2 wait instance-status-ok --instance-ids $instance_id --region $REGION

# 3. Create AMI
ami_id=$(aws ec2 create-image \
  --instance-id $instance_id \
  --name "$AMI_NAME-$(date +%s)" \
  --no-reboot \
  --region $REGION \
  --query "ImageId" --output text)

echo "⏳ Waiting for AMI $ami_id to become available..."
aws ec2 wait image-available --image-ids $ami_id --region $REGION

# 4. Terminate builder instance and clean up
aws ec2 terminate-instances --instance-ids $instance_id --region $REGION
aws ec2 delete-security-group --group-id $sg_id --region $REGION

echo "✅ AMI created: $ami_id"
echo $ami_id > ami-id.txt
