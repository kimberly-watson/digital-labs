#!/bin/bash
echo "=== NGINX MODULES ==="
nginx -V 2>&1 | grep -o "with-http_sub_module" || echo "sub_module NOT found"

echo "=== SECURITY GROUP ==="
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
MAC=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/ | head -1 | tr -d '/')
SG=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/network/interfaces/macs/$MAC/security-group-ids)
echo "SG: $SG"

echo "=== PUBLIC IP ==="
curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/public-ipv4