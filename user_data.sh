#!/bin/bash
set -euxo pipefail

REGION=us-east-1
ASSETS_BUCKET=digital-labs-tfstate-YOUR-AWS-ACCOUNT-ID
ASSETS_PREFIX=assets

# IMDSv2: get a short-lived token for all metadata calls
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")

# Discover this lab's key from the EC2 instance tag (set by Terraform at deploy time).
# The lab_key determines the SSM parameter path, allowing multiple labs to coexist.
LAB_KEY=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/tags/instance/lab_key)

# Read termination time from this lab's SSM parameter
TERMINATION_TIME=$(aws ssm get-parameter \
  --name "/digital-labs/${LAB_KEY}/termination-time" \
  --region ${REGION} \
  --query "Parameter.Value" \
  --output text)

# Install Docker
dnf -y install docker zip python3
systemctl enable --now docker

# Pull license key from Parameter Store
mkdir -p /opt/sonatype/iq-server
aws ssm get-parameter \
  --name "/digital-labs/sonatype-license" \
  --with-decryption \
  --region ${REGION} \
  --query "Parameter.Value" \
  --output text | base64 -d > /opt/sonatype/iq-server/license.lic

# Start Nexus Repository
docker run -d \
  --name nexus \
  --restart=always \
  -p 8081:8081 \
  --log-driver awslogs \
  --log-opt awslogs-region=${REGION} \
  --log-opt awslogs-group=/digital-labs/nexus \
  --log-opt awslogs-create-group=true \
  sonatype/nexus3:3.68.0

# Start IQ Server (Lifecycle + Firewall)
docker run -d \
  --name iq-server \
  --restart=always \
  -p 8070:8070 \
  -p 8071:8071 \
  -v /opt/sonatype/iq-server/license.lic:/etc/nexus-iq-server/license.lic \
  --log-driver awslogs \
  --log-opt awslogs-region=${REGION} \
  --log-opt awslogs-group=/digital-labs/iq-server \
  --log-opt awslogs-create-group=true \
  sonatype/nexus-iq-server:latest

# Wait for IQ Server to be ready, then upload license via REST API
sleep 60
IQ_CSRF_COOKIE=""
until [ -n "$IQ_CSRF_COOKIE" ]; do
  curl -s -c /tmp/iq-cookies.txt -b /tmp/iq-cookies.txt \
    -u "admin:admin123" \
    http://localhost:8070/api/v2/solutions/licensed > /dev/null 2>&1 || true
  IQ_CSRF_COOKIE=$(grep 'CLM-CSRF-TOKEN' /tmp/iq-cookies.txt | awk '{print $NF}' || true)
  [ -z "$IQ_CSRF_COOKIE" ] && sleep 15
done
curl -s \
  -c /tmp/iq-cookies.txt \
  -b /tmp/iq-cookies.txt \
  -H "X-CLM-CSRF-TOKEN: $IQ_CSRF_COOKIE" \
  -u "admin:admin123" \
  -X POST \
  -F "file=@/opt/sonatype/iq-server/license.lic" \
  http://localhost:8070/api/v2/product/license

# Wait for Nexus to be ready, then set admin password
GENERATED=""
until [ -n "$GENERATED" ]; do
  GENERATED=$(docker exec nexus cat /nexus-data/admin.password 2>/dev/null || true)
  [ -z "$GENERATED" ] && sleep 15
done
NEXUS_STATUS=""
until [ "$NEXUS_STATUS" = "200" ]; do
  NEXUS_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -u "admin:$GENERATED" http://localhost:8081/service/rest/v1/status || true)
  [ "$NEXUS_STATUS" != "200" ] && sleep 15
done
curl -s \
  -u "admin:$GENERATED" \
  -X PUT \
  -H "Content-Type: text/plain" \
  --data "admin123" \
  http://localhost:8081/service/rest/v1/security/users/admin/change-password

# Wait for IQ Server to initialize
sleep 180

# == FAKE DATA SEEDING ==
sleep 30

# Create blob store
curl -s -u "admin:admin123" \
  -X POST -H "Content-Type: application/json" \
  -d '{"name":"lab-blob-store","path":"lab-blob-store","softQuota":{"type":"spaceUsedQuota","limit":5368709120}}' \
  http://localhost:8081/service/rest/v1/blobstores/file

# Create Maven hosted repo
curl -s -u "admin:admin123" \
  -X POST -H "Content-Type: application/json" \
  -d '{"name":"maven-hosted-lab","online":true,"storage":{"blobStoreName":"lab-blob-store","strictContentTypeValidation":true,"writePolicy":"allow"},"maven":{"versionPolicy":"MIXED","layoutPolicy":"STRICT"}}' \
  http://localhost:8081/service/rest/v1/repositories/maven/hosted

# Create npm hosted repo
curl -s -u "admin:admin123" \
  -X POST -H "Content-Type: application/json" \
  -d '{"name":"npm-hosted-lab","online":true,"storage":{"blobStoreName":"lab-blob-store","strictContentTypeValidation":true,"writePolicy":"allow"}}' \
  http://localhost:8081/service/rest/v1/repositories/npm/hosted

# Create Maven proxy repo
curl -s -u "admin:admin123" \
  -X POST -H "Content-Type: application/json" \
  -d '{"name":"maven-proxy-central","online":true,"storage":{"blobStoreName":"lab-blob-store","strictContentTypeValidation":true},"proxy":{"remoteUrl":"https://repo1.maven.org/maven2/","contentMaxAge":1440,"metadataMaxAge":1440},"negativeCache":{"enabled":true,"timeToLive":1440},"httpClient":{"blocked":false,"autoBlock":true},"maven":{"versionPolicy":"RELEASE","layoutPolicy":"STRICT"}}' \
  http://localhost:8081/service/rest/v1/repositories/maven/proxy

# Seed Maven artifact
mkdir -p /tmp/fake-maven
echo "Manifest-Version: 1.0" > /tmp/fake-maven/MANIFEST.MF
zip -j /tmp/fake-maven/sample-app-1.0.0.jar /tmp/fake-maven/MANIFEST.MF
curl -s -u "admin:admin123" \
  -X POST "http://localhost:8081/service/rest/v1/components?repository=maven-hosted-lab" \
  -F "maven2.groupId=com.sonatype.lab" \
  -F "maven2.artifactId=sample-app" \
  -F "maven2.version=1.0.0" \
  -F "maven2.asset1=@/tmp/fake-maven/sample-app-1.0.0.jar;type=application/java-archive" \
  -F "maven2.asset1.extension=jar"

# Seed npm artifact
mkdir -p /tmp/fake-npm/package
cat > /tmp/fake-npm/package/package.json << 'PKGJSON'
{
  "name": "@sonatype-lab/sample-lib",
  "version": "1.0.0",
  "description": "Sonatype Digital Lab sample npm package",
  "main": "index.js",
  "license": "Apache-2.0"
}
PKGJSON
echo "module.exports = { hello: () => 'Sonatype Lab' };" > /tmp/fake-npm/package/index.js
cd /tmp/fake-npm && tar -czf sonatype-lab-sample-lib-1.0.0.tgz package/
curl -s -u "admin:admin123" \
  -X POST "http://localhost:8081/service/rest/v1/components?repository=npm-hosted-lab" \
  -F "npm.asset=@/tmp/fake-npm/sonatype-lab-sample-lib-1.0.0.tgz;type=application/x-compressed"

# == COUNTDOWN CLOCK ==
# Served directly as a static file by nginx — no intermediate Python process needed.
# This avoids the single-threaded TCPServer bottleneck that caused 504s under bot scan load.
dnf -y install nginx

aws s3 cp s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}/countdown.html /usr/share/nginx/html/index.html
sed -i "s/TERMINATION_PLACEHOLDER/${TERMINATION_TIME}/g" /usr/share/nginx/html/index.html
chmod 644 /usr/share/nginx/html/index.html

useradd -r -s /sbin/nologin -M labclock || true

# == LAB TUTOR ==
# CLAUDE_API_KEY is fetched from SSM and written to /etc/lab-tutor.env (root:root 600).
# The systemd unit reads it via EnvironmentFile — never inline in the unit file (breaks on spaces).
mkdir -p /opt/sonatype/tutor
aws s3 cp s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}/proxy.py /opt/sonatype/tutor/proxy.py
aws s3 cp s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}/tutor.html /opt/sonatype/tutor/index.html

PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4)

# Fetch Claude API key from SSM — never written to a world-readable location
CLAUDE_API_KEY=$(aws ssm get-parameter \
  --name "/digital-labs/claude-api-key" \
  --with-decryption \
  --region ${REGION} \
  --query "Parameter.Value" \
  --output text | tr -d '[:space:]')

TUTOR_SYSTEM_PROMPT="You are a helpful lab tutor for Sonatype Digital Labs. You are in Learning Mode: guide users to discover answers through questions and hints rather than giving direct answers. The customer is working in a hands-on lab with Nexus Repository CE at http://${PUBLIC_IP}:8081 and IQ Server at http://${PUBLIC_IP}:8070. Default credentials are admin/admin123. The lab terminates at ${TERMINATION_TIME} UTC. Help users understand and use Nexus Repository, IQ Server Lifecycle, and IQ Server Firewall. Be concise and practical. Redirect off-topic questions back to Sonatype lab topics."

# Write env file — root:root 600 so the key is never world-readable
cat > /etc/lab-tutor.env << ENVEOF
AWS_REGION=${REGION}
CLAUDE_API_KEY=${CLAUDE_API_KEY}
TUTOR_SYSTEM_PROMPT=${TUTOR_SYSTEM_PROMPT}
ENVEOF
chmod 600 /etc/lab-tutor.env
chown root:root /etc/lab-tutor.env

cat > /etc/systemd/system/lab-tutor.service << TUTORSVCEOF
[Unit]
Description=Sonatype Lab Tutor Proxy
After=network.target
[Service]
ExecStart=/usr/bin/python3 /opt/sonatype/tutor/proxy.py
Restart=always
User=labclock
EnvironmentFile=/etc/lab-tutor.env
[Install]
WantedBy=multi-user.target
TUTORSVCEOF

chown -R labclock:labclock /opt/sonatype/tutor
chmod 500 /opt/sonatype/tutor
chmod 400 /opt/sonatype/tutor/index.html
chmod 500 /opt/sonatype/tutor/proxy.py

systemctl enable --now lab-tutor

# == NGINX REVERSE PROXY ==
cat > /etc/nginx/conf.d/digital-labs.conf << 'NGINXEOF'
server {
    listen 80 default_server;

    # Lab tutor chat API
    location /chat {
        proxy_pass http://127.0.0.1:8090/chat;
        proxy_set_header Host $host;
        proxy_read_timeout 120s;
    }

    # Portal / countdown clock — served as static file (no upstream proxy needed)
    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri $uri/ /index.html;
    }
}
NGINXEOF

# Disable default nginx site
rm -f /etc/nginx/conf.d/default.conf

systemctl enable --now nginx
