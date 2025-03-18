#!/bin/bash
set -e

REGION="us-east-1"
AZ1="us-east-1a"
AZ2="us-east-1b"
TAG="Application=Payment-Processing"

# Load AMI
AMI_ID=$(cat scripts/ami-id.txt)

# Create VPC
vpc_id=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --tag-specifications "ResourceType=vpc,Tags=[{Key=Application,Value=Payment-Processing}]" --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id $vpc_id --enable-dns-hostnames "{\"Value\":true}"

# Internet Gateway
igw_id=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id $vpc_id --internet-gateway-id $igw_id

# Subnets
subnet_pub_a=$(aws ec2 create-subnet --vpc-id $vpc_id --cidr-block 10.0.1.0/24 --availability-zone $AZ1 --query 'Subnet.SubnetId' --output text)
subnet_pub_b=$(aws ec2 create-subnet --vpc-id $vpc_id --cidr-block 10.0.3.0/24 --availability-zone $AZ2 --query 'Subnet.SubnetId' --output text)
subnet_priv_a=$(aws ec2 create-subnet --vpc-id $vpc_id --cidr-block 10.0.2.0/24 --availability-zone $AZ1 --query 'Subnet.SubnetId' --output text)
subnet_priv_b=$(aws ec2 create-subnet --vpc-id $vpc_id --cidr-block 10.0.4.0/24 --availability-zone $AZ2 --query 'Subnet.SubnetId' --output text)

# Public Route Table
rtb_pub=$(aws ec2 create-route-table --vpc-id $vpc_id --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $rtb_pub --destination-cidr-block 0.0.0.0/0 --gateway-id $igw_id
aws ec2 associate-route-table --route-table-id $rtb_pub --subnet-id $subnet_pub_a
aws ec2 associate-route-table --route-table-id $rtb_pub --subnet-id $subnet_pub_b

# Elastic IPs for NAT
eip1=$(aws ec2 allocate-address --query 'AllocationId' --output text)
eip2=$(aws ec2 allocate-address --query 'AllocationId' --output text)

# NAT Gateways
nat1=$(aws ec2 create-nat-gateway --subnet-id $subnet_pub_a --allocation-id $eip1 --query 'NatGateway.NatGatewayId' --output text)
nat2=$(aws ec2 create-nat-gateway --subnet-id $subnet_pub_b --allocation-id $eip2 --query 'NatGateway.NatGatewayId' --output text)
sleep 60  # wait for NAT

# Private Route Tables
rtb_priv_a=$(aws ec2 create-route-table --vpc-id $vpc_id --query 'RouteTable.RouteTableId' --output text)
rtb_priv_b=$(aws ec2 create-route-table --vpc-id $vpc_id --query 'RouteTable.RouteTableId' --output text)
aws ec2 create-route --route-table-id $rtb_priv_a --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $nat1
aws ec2 create-route --route-table-id $rtb_priv_b --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $nat2
aws ec2 associate-route-table --route-table-id $rtb_priv_a --subnet-id $subnet_priv_a
aws ec2 associate-route-table --route-table-id $rtb_priv_b --subnet-id $subnet_priv_b

# Security Groups
sg_alb=$(aws ec2 create-security-group --group-name alb-sg --description "ALB SG" --vpc-id $vpc_id --query 'GroupId' --output text)
sg_app=$(aws ec2 create-security-group --group-name payment-api-sg --description "App SG" --vpc-id $vpc_id --query 'GroupId' --output text)


aws ec2 authorize-security-group-ingress --group-id $sg_alb --protocol tcp --port 80 --cidr 0.0.0.0/0
# Allow sg-alb to access sg-app on port 80
aws ec2 authorize-security-group-ingress \
  --group-id $sg_app \
  --protocol tcp \
  --port 80 \
  --source-group $sg_alb


aws ec2 authorize-security-group-egress --group-id $sg_alb --protocol tcp --port 80 --cidr 10.0.0.0/16
aws ec2 authorize-security-group-egress --group-id $sg_app --protocol -1 --cidr 0.0.0.0/0

# Launch EC2 Instances
instance1=$(aws ec2 run-instances --image-id $AMI_ID --count 1 --instance-type t3.small --subnet-id $subnet_priv_a --security-group-ids $sg_app --tag-specifications "ResourceType=instance,Tags=[{Key=Role,Value=Payment-Server}]" --query 'Instances[0].InstanceId' --output text)
instance2=$(aws ec2 run-instances --image-id $AMI_ID --count 1 --instance-type t3.small --subnet-id $subnet_priv_b --security-group-ids $sg_app --tag-specifications "ResourceType=instance,Tags=[{Key=Role,Value=Payment-Server}]" --query 'Instances[0].InstanceId' --output text)

# Target Group
tg=$(aws elbv2 create-target-group --name payment-api-tg --protocol HTTP --port 80 --vpc-id $vpc_id --target-type instance --query 'TargetGroups[0].TargetGroupArn' --output text)

aws elbv2 register-targets --target-group-arn $tg --targets Id=$instance1 Id=$instance2

# ALB
alb=$(aws elbv2 create-load-balancer --name payment-alb --subnets $subnet_pub_a $subnet_pub_b --security-groups $sg_alb --query 'LoadBalancers[0].LoadBalancerArn' --output text)

# Listener
aws elbv2 create-listener --load-balancer-arn $alb --protocol HTTP --port 80 --default-actions Type=forward,TargetGroupArn=$tg

# Output ALB DNS
aws elbv2 describe-load-balancers --load-balancer-arns $alb --query 'LoadBalancers[0].DNSName' --output text
