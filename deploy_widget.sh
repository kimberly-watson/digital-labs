#!/bin/bash
set -euo pipefail

echo "=== Deploying Lab Tutor widget + product proxy nginx config ==="

# 1. Pull updated assets from S3
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ASSETS_BUCKET="digital-labs-tfstate-${ACCOUNT_ID}"
aws s3 cp "s3://${ASSETS_BUCKET}/assets/lab-tutor-widget.js" /var/www/html/lab-tutor-widget.js
aws s3 cp "s3://${ASSETS_BUCKET}/assets/proxy.py"            /opt/sonatype/tutor/proxy.py
aws s3 cp "s3://${ASSETS_BUCKET}/assets/nginx-product-proxies.conf" /etc/nginx/conf.d/product-proxies.conf
chmod 644 /var/www/html/lab-tutor-widget.js
chmod 500 /opt/sonatype/tutor/proxy.py
chown labclock:labclock /opt/sonatype/tutor/proxy.py

# 2. Restart lab-tutor to pick up updated proxy.py
systemctl restart lab-tutor
sleep 2
systemctl is-active lab-tutor && echo "lab-tutor OK" || echo "lab-tutor FAILED"

# 3. Test nginx config then reload
nginx -t && nginx -s reload && echo "nginx reloaded OK" || echo "nginx config ERROR"

# 4. Verify ports
sleep 2
ss -tlnp | grep -E '8071|8082' || echo "WARNING: ports not listening"

echo "=== Deploy complete ==="
