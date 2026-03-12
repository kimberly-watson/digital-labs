#!/bin/bash
set -euo pipefail

echo "=== Deploying Lab Tutor widget + product proxy nginx config ==="

# 1. Pull updated assets from S3
aws s3 cp s3://digital-labs-tfstate-YOUR-AWS-ACCOUNT-ID/assets/lab-tutor-widget.js /var/www/html/lab-tutor-widget.js
aws s3 cp s3://digital-labs-tfstate-YOUR-AWS-ACCOUNT-ID/assets/proxy.py            /opt/sonatype/tutor/proxy.py
aws s3 cp s3://digital-labs-tfstate-YOUR-AWS-ACCOUNT-ID/assets/nginx-product-proxies.conf /etc/nginx/conf.d/product-proxies.conf
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
