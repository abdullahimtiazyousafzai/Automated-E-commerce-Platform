#!/bin/bash
set -e

# Install
yum update -y
amazon-linux-extras enable nginx1
yum install -y nginx nodejs

# API
mkdir -p /opt/payment-api
cat <<EOF > /opt/payment-api/server.js
require('http').createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'application/json'});
  res.end(JSON.stringify({ status: "Payment Processed", timestamp: new Date().toISOString() }));
}).listen(3000);
EOF

# Service
cat <<EOF > /etc/systemd/system/payment-api.service
[Unit]
Description=Payment API
After=network.target
[Service]
ExecStart=/usr/bin/node /opt/payment-api/server.js
Restart=always
User=nobody
[Install]
WantedBy=multi-user.target
EOF

systemctl enable payment-api --now

# Nginx reverse proxy
cat <<EOF > /etc/nginx/conf.d/payment.conf
server {
  listen 80;
  location / { proxy_pass http://localhost:3000; }
}
EOF

systemctl enable nginx --now

# Create AMI
AMI_ID=$(aws ec2 create-image --instance-id $(curl -s http://169.254.169.254/latest/meta-data/instance-id) \
  --name "payment-api-ami" --no-reboot --query 'ImageId' --output text)
echo $AMI_ID > ami-id.txt
