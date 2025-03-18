#!/bin/bash
yum update -y
yum install -y nginx
curl -fsSL https://rpm.nodesource.com/setup_18.x | bash -
yum install -y nodejs

mkdir -p /opt/payment-api
cat <<EOF > /opt/payment-api/server.js
const http = require('http');
const server = http.createServer((req, res) => {
  res.writeHead(200, {'Content-Type': 'application/json'});
  res.end(JSON.stringify({ status: "Payment Processed", timestamp: new Date().toISOString() }));
});
server.listen(3000);
EOF

cat <<EOF > /etc/systemd/system/payment-api.service
[Unit]
Description=Payment API
After=network.target

[Service]
ExecStart=/usr/bin/node /opt/payment-api/server.js
Restart=always
User=nobody
Group=nobody

[Install]
WantedBy=multi-user.target
EOF

systemctl enable payment-api
systemctl start payment-api

# Configure nginx reverse proxy
cat <<EOF > /etc/nginx/conf.d/payment.conf
server {
  listen 80;
  location / {
    proxy_pass http://127.0.0.1:3000;
  }
}
EOF

systemctl restart nginx
