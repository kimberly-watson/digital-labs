#!/bin/bash
set -euxo pipefail

REGION=us-east-1
ASSETS_PREFIX=assets

# IMDSv2 token is fetched below — ACCOUNT_ID and ASSETS_BUCKET are set after the token is available.

# IMDSv2: get a short-lived token for all metadata calls
IMDS_TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 300")

# Derive the S3 assets bucket name from the account ID (avoids hardcoding)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ASSETS_BUCKET="digital-labs-tfstate-${ACCOUNT_ID}"

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
# set +x: suppress xtrace so the decoded license data never appears in cloud-init logs
mkdir -p /opt/sonatype/iq-server
set +x
aws ssm get-parameter \
  --name "/digital-labs/sonatype-license" \
  --with-decryption \
  --region ${REGION} \
  --query "Parameter.Value" \
  --output text | base64 -d > /opt/sonatype/iq-server/license.lic
# Lock down the license file — 644 default would expose it to any local user
chmod 600 /opt/sonatype/iq-server/license.lic
set -x

# Start Nexus Repository
# Nexus 3 in Docker logs entirely to stdout — captured by --log-driver awslogs.
# No file bind-mount needed; log directory left to the Docker-managed volume.
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
# Version pinned — sonatype/nexus-iq-server:latest pulls unpredictably and can break labs.
# To upgrade: verify new version in staging, update the tag below, and re-test.
mkdir -p /opt/sonatype/iq-server/log
docker run -d \
  --name iq-server \
  --restart=always \
  -p 8070:8070 \
  -p 8071:8071 \
  -v /opt/sonatype/iq-server/license.lic:/etc/nexus-iq-server/license.lic \
  -v /opt/sonatype/iq-server/log:/var/log/nexus-iq-server \
  --log-driver awslogs \
  --log-opt awslogs-region=${REGION} \
  --log-opt awslogs-group=/digital-labs/iq-server \
  --log-opt awslogs-create-group=true \
  sonatype/nexus-iq-server:1.201.0-02

# Wait for IQ Server to be ready, then upload license via REST API
# Phase 1: Wait until IQ is responding and issues a CSRF cookie
sleep 60
IQ_CSRF_COOKIE=""
until [ -n "$IQ_CSRF_COOKIE" ]; do
  curl -s -c /tmp/iq-cookies.txt -b /tmp/iq-cookies.txt \
    -u "admin:admin123" \
    http://localhost:8070/api/v2/solutions/licensed > /dev/null 2>&1 || true
  IQ_CSRF_COOKIE=$(grep 'CLM-CSRF-TOKEN' /tmp/iq-cookies.txt | awk '{print $NF}' || true)
  [ -z "$IQ_CSRF_COOKIE" ] && sleep 15
done

# Phase 2: Retry license POST until IQ accepts it (it may still be initializing
# internally even though it is already returning CSRF cookies).
IQ_LIC_HTTP="000"
IQ_LIC_ATTEMPTS=0
until [ "$IQ_LIC_HTTP" = "200" ]; do
  IQ_LIC_ATTEMPTS=$((IQ_LIC_ATTEMPTS + 1))
  if [ "$IQ_LIC_ATTEMPTS" -gt 10 ]; then
    echo "ERROR: IQ Server license install failed after 10 attempts" >&2
    break
  fi
  # Refresh CSRF cookie before each attempt — it may expire between retries
  rm -f /tmp/iq-cookies.txt
  curl -s -c /tmp/iq-cookies.txt -b /tmp/iq-cookies.txt \
    -u "admin:admin123" \
    http://localhost:8070/api/v2/solutions/licensed > /dev/null 2>&1 || true
  IQ_CSRF_COOKIE=$(grep 'CLM-CSRF-TOKEN' /tmp/iq-cookies.txt | awk '{print $NF}' || true)
  IQ_LIC_HTTP=$(curl -s \
    -c /tmp/iq-cookies.txt \
    -b /tmp/iq-cookies.txt \
    -H "X-CLM-CSRF-TOKEN: $IQ_CSRF_COOKIE" \
    -u "admin:admin123" \
    -X POST \
    -F "file=@/opt/sonatype/iq-server/license.lic" \
    -o /dev/null \
    -w "%{http_code}" \
    http://localhost:8070/api/v2/product/license) || true
  echo "IQ license install attempt $IQ_LIC_ATTEMPTS: HTTP $IQ_LIC_HTTP"
  [ "$IQ_LIC_HTTP" != "200" ] && sleep 20
done

# Clean up session cookies — /tmp is world-readable on most Linux configs
rm -f /tmp/iq-cookies.txt

# Wait for Nexus to be ready, then set admin password
# set +x: suppress xtrace — GENERATED (Nexus admin.password) must not appear in cloud-init logs
set +x
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
# Delete the generated password from memory — it is no longer valid after the change above
GENERATED="cleared"
# Also delete admin.password file — Nexus re-reads it on startup if present
docker exec nexus rm -f /nexus-data/admin.password || true
set -x

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

# Clean up seeding temp files — no secrets here, but good hygiene: /tmp is world-readable
rm -rf /tmp/fake-maven /tmp/fake-npm
cd /

# == IQ SERVER SEEDING ==
# Creates an organization, an application, and submits a CycloneDX SBOM scan
# with known-vulnerable components so students have real vulnerability data to explore.
#
# Components seeded (all have known CVEs in the IQ vulnerability database):
#   log4j:log4j:1.2.17                              - multiple CVEs incl. deserialization
#   commons-collections:commons-collections:3.2.1   - Apache Commons RCE (CVE-2015-6420)
#   org.springframework:spring-core:4.3.0.RELEASE   - Spring CVEs
#   org.apache.struts:struts2-core:2.3.16            - Struts RCE (CVE-2017-5638)
#
# NOTE: Policies are not seeded via the API - IQ's REST policy endpoints require a
# full browser session (Basic Auth + CSRF simultaneously rejected on write endpoints).
# Creating a security policy is an excellent first lab exercise for students.

# Create organization under Root
IQ_ORG_RESPONSE=$(curl -s -u "admin:admin123" \
  -X POST http://localhost:8070/api/v2/organizations \
  -H "Content-Type: application/json" \
  -d '{"name":"Sonatype Lab","parentOrganizationId":"ROOT_ORGANIZATION_ID"}')
IQ_ORG_ID=$(echo "$IQ_ORG_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
echo "IQ seed: org created id=$IQ_ORG_ID"

# Create application under the org
IQ_APP_RESPONSE=$(curl -s -u "admin:admin123" \
  -X POST http://localhost:8070/api/v2/applications \
  -H "Content-Type: application/json" \
  -d "{\"publicId\":\"sample-app\",\"name\":\"Sample Application\",\"organizationId\":\"$IQ_ORG_ID\"}")
IQ_APP_ID=$(echo "$IQ_APP_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || true)
echo "IQ seed: app created id=$IQ_APP_ID"

# Build and submit CycloneDX SBOM with known-vulnerable components
IQ_SCAN_UUID=$(cat /proc/sys/kernel/random/uuid)
cat > /tmp/iq-seed-sbom.xml << SBOMEOF
<?xml version="1.0" encoding="UTF-8"?>
<bom xmlns="http://cyclonedx.org/schema/bom/1.4" version="1" serialNumber="urn:uuid:${IQ_SCAN_UUID}">
  <components>
    <component type="library">
      <group>log4j</group>
      <n>log4j</n>
      <version>1.2.17</version>
      <purl>pkg:maven/log4j/log4j@1.2.17</purl>
    </component>
    <component type="library">
      <group>commons-collections</group>
      <n>commons-collections</n>
      <version>3.2.1</version>
      <purl>pkg:maven/commons-collections/commons-collections@3.2.1</purl>
    </component>
    <component type="library">
      <group>org.springframework</group>
      <n>spring-core</n>
      <version>4.3.0.RELEASE</version>
      <purl>pkg:maven/org.springframework/spring-core@4.3.0.RELEASE</purl>
    </component>
    <component type="library">
      <group>org.apache.struts</group>
      <n>struts2-core</n>
      <version>2.3.16</version>
      <purl>pkg:maven/org.apache.struts/struts2-core@2.3.16</purl>
    </component>
  </components>
</bom>
SBOMEOF

IQ_SCAN_RESPONSE=$(curl -s -u "admin:admin123" \
  -X POST "http://localhost:8070/api/v2/scan/applications/${IQ_APP_ID}/sources/ci" \
  -H "Content-Type: application/xml" \
  --data-binary @/tmp/iq-seed-sbom.xml)
IQ_SCAN_STATUS_URL=$(echo "$IQ_SCAN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('statusUrl',''))" 2>/dev/null || true)
echo "IQ seed: scan submitted statusUrl=$IQ_SCAN_STATUS_URL"

# Wait for scan to complete (up to 10 attempts, 15s apart)
IQ_SCAN_DONE=""
IQ_SCAN_ATTEMPTS=0
until [ -n "$IQ_SCAN_DONE" ]; do
  IQ_SCAN_ATTEMPTS=$((IQ_SCAN_ATTEMPTS + 1))
  if [ "$IQ_SCAN_ATTEMPTS" -gt 10 ]; then
    echo "IQ seed: scan did not complete in time" >&2
    break
  fi
  sleep 15
  IQ_SCAN_POLL=$(curl -s -u "admin:admin123" "http://localhost:8070/${IQ_SCAN_STATUS_URL}" 2>/dev/null || true)
  IQ_SCAN_DONE=$(echo "$IQ_SCAN_POLL" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('reportHtmlUrl',''))" 2>/dev/null || true)
  echo "IQ seed: scan poll attempt $IQ_SCAN_ATTEMPTS done=$IQ_SCAN_DONE"
done

rm -f /tmp/iq-seed-sbom.xml
echo "IQ seed: complete — org=$IQ_ORG_ID app=$IQ_APP_ID"

# == COUNTDOWN CLOCK ==
# Served directly as a static file by nginx Ã¢â‚¬â€ no intermediate Python process needed.
# This avoids the single-threaded TCPServer bottleneck that caused 504s under bot scan load.
dnf -y install nginx

aws s3 cp s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}/countdown.html /usr/share/nginx/html/index.html
sed -i "s/TERMINATION_PLACEHOLDER/${TERMINATION_TIME}/g" /usr/share/nginx/html/index.html
chmod 644 /usr/share/nginx/html/index.html

# Lab Tutor widget JS Ã¢â‚¬â€ served from port 80 and both product proxy ports
aws s3 cp s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}/lab-tutor-widget.js /var/www/html/lab-tutor-widget.js
chmod 644 /var/www/html/lab-tutor-widget.js

useradd -r -s /sbin/nologin -M labclock || true

# == LAB TUTOR ==
# CLAUDE_API_KEY is fetched from SSM and written to /etc/lab-tutor.env (root:root 600).
# The systemd unit reads it via EnvironmentFile Ã¢â‚¬â€ never inline in the unit file (breaks on spaces).
mkdir -p /opt/sonatype/tutor
aws s3 cp s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}/proxy.py /opt/sonatype/tutor/proxy.py
aws s3 cp s3://${ASSETS_BUCKET}/${ASSETS_PREFIX}/tutor.html /opt/sonatype/tutor/index.html

PUBLIC_IP=$(curl -s -H "X-aws-ec2-metadata-token: $IMDS_TOKEN" \
  http://169.254.169.254/latest/meta-data/public-ipv4)

# set +x: suppress xtrace -- CLAUDE_API_KEY must NEVER appear in cloud-init logs or CloudWatch
set +x
# Fetch Claude API key from SSM Ã¢â‚¬â€ never written to a world-readable location
CLAUDE_API_KEY=$(aws ssm get-parameter \
  --name "/digital-labs/claude-api-key" \
  --with-decryption \
  --region ${REGION} \
  --query "Parameter.Value" \
  --output text | tr -d '[:space:]')

TUTOR_SYSTEM_PROMPT="You are a helpful lab tutor for Sonatype Digital Labs. You are in Learning Mode: guide users to discover answers through questions and hints rather than giving direct answers. The customer is working in a hands-on lab with Nexus Repository CE at http://${PUBLIC_IP}:8082 and IQ Server at http://${PUBLIC_IP}:8072. If a student asks for login credentials, direct them to check the lab portal page for access details. The lab terminates at ${TERMINATION_TIME} UTC. Help users understand and use Nexus Repository, IQ Server Lifecycle, and IQ Server Firewall. Be concise and practical. Redirect off-topic questions back to Sonatype lab topics."

# Base64-encode the system prompt — systemd EnvironmentFile silently truncates
# multi-line values at the first newline. The proxy.py reads and decodes this at startup.
TUTOR_SYSTEM_PROMPT_B64=$(printf '%s' "$TUTOR_SYSTEM_PROMPT" | base64 -w 0)

# Write env file Ã¢â‚¬â€ root:root 600 so the key is never world-readable
cat > /etc/lab-tutor.env << ENVEOF
AWS_REGION=${REGION}
CLAUDE_API_KEY=${CLAUDE_API_KEY}
TUTOR_SYSTEM_PROMPT_B64=${TUTOR_SYSTEM_PROMPT_B64}
ENVEOF
chmod 600 /etc/lab-tutor.env
chown root:root /etc/lab-tutor.env
# Wipe API key from memory -- env file is secured, variable no longer needed
CLAUDE_API_KEY="cleared"
set -x

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
cat > /etc/nginx/conf.d/rate-limit.conf << 'RATELIMITEOF'
# Rate limiting for /chat — 10 req/min per IP, burst 5
limit_req_zone $binary_remote_addr zone=chat_limit:10m rate=10r/m;
RATELIMITEOF

cat > /etc/nginx/conf.d/browser-enforce.conf << 'BROWSEREOF'
# Non-browsers get 1 (truthy), browsers get 0 (falsy) - standard nginx if() pattern
map $http_user_agent $block_non_browser {
    default      1;
    "~*Mozilla"  0;
}
BROWSEREOF

cat > /etc/nginx/conf.d/digital-labs.conf << 'NGINXEOF'
server {
    listen 80 default_server;

    # Block all non-browser clients
    if ($block_non_browser) {
        return 403 "Browser access only.";
    }

    # Lab tutor chat API - Referer check ensures only our pages call it
    location /chat {
        valid_referers server_names ~\.;
        if ($invalid_referer) {
            return 403;
        }
        proxy_pass http://127.0.0.1:8090/chat;
        proxy_set_header Host $host;
        proxy_read_timeout 120s;
    }

    # Lab Tutor standalone popup window
    location = /tutor {
        alias /var/www/html/tutor.html;
        add_header Content-Type "text/html; charset=utf-8";
        add_header X-Frame-Options "SAMEORIGIN";
    }

    # Beacon JS
    location /lab-tutor-beacon.js {
        alias /var/www/html/lab-tutor-beacon.js;
        add_header Content-Type "application/javascript; charset=utf-8";
        add_header Access-Control-Allow-Origin "*";
    }

    # Portal / countdown clock
    location / {
        root /usr/share/nginx/html;
        index index.html;
        try_files $uri $uri/ /index.html;
    }
}
NGINXEOF

# Product proxy server blocks - inject beacon into Nexus and IQ Server pages
# Beacon writes product+URL to localStorage so the tutor popup always knows context
# Port 8082 -> Nexus (8081)   Port 8072 -> IQ Server (8070)
cat > /etc/nginx/conf.d/product-proxies.conf << 'PROXIESEOF'
server {
    listen 8082;
    proxy_set_header Accept-Encoding "";
    if ($block_non_browser) { return 403 "Browser access only."; }

    location /lab-tutor-beacon.js {
        alias /var/www/html/lab-tutor-beacon.js;
        add_header Content-Type "application/javascript; charset=utf-8";
        add_header Access-Control-Allow-Origin "*";
    }
    location / {
        proxy_pass         http://127.0.0.1:8081;
        proxy_http_version 1.1;
        proxy_set_header   Host $host;
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   Accept-Encoding "";
        proxy_read_timeout 120s;
        proxy_redirect     ~^http://127\.0\.0\.1(:\d+)?/ http://$host:8082/;
        sub_filter         '</body>' '<script src="/lab-tutor-beacon.js"></script></body>';
        sub_filter_once    on;
        sub_filter_types   text/html;
    }
}
server {
    listen 8072;
    proxy_set_header Accept-Encoding "";
    if ($block_non_browser) { return 403 "Browser access only."; }

    location /lab-tutor-beacon.js {
        alias /var/www/html/lab-tutor-beacon.js;
        add_header Content-Type "application/javascript; charset=utf-8";
        add_header Access-Control-Allow-Origin "*";
    }
    location / {
        proxy_pass         http://127.0.0.1:8070;
        proxy_http_version 1.1;
        proxy_set_header   Host "127.0.0.1:8070";
        proxy_set_header   X-Real-IP $remote_addr;
        proxy_set_header   Accept-Encoding "";
        proxy_read_timeout 120s;
        proxy_redirect     ~^http://127\.0\.0\.1(:\d+)?(.*)$ http://$host:8072$2;
        sub_filter         '</body>' '<script src="/lab-tutor-beacon.js"></script></body>';
        sub_filter_once    on;
        sub_filter_types   text/html;
    }
}
PROXIESEOF

# Disable default nginx site
rm -f /etc/nginx/conf.d/default.conf

systemctl enable --now nginx

# ---------------------------------------------------------------------------
# CloudWatch Agent — ship IQ Server structured audit and request logs
#
# Nexus 3 logs entirely to stdout in Docker — already captured by the
# --log-driver awslogs flag above. No file tailing needed for Nexus.
#
# IQ Server writes structured log files to its bind-mounted log directory,
# which the agent tails from the host path below.
# ---------------------------------------------------------------------------
dnf install -y amazon-cloudwatch-agent

cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << 'CWEOF'
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/opt/sonatype/iq-server/log/audit.log",
            "log_group_name": "/digital-labs/iq-audit",
            "log_stream_name": "{instance_id}",
            "timestamp_format": "%Y-%m-%dT%H:%M:%S"
          },
          {
            "file_path": "/opt/sonatype/iq-server/log/request.log",
            "log_group_name": "/digital-labs/iq-requests",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/opt/sonatype/iq-server/log/clm-server.log",
            "log_group_name": "/digital-labs/iq-server-app",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CWEOF

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config \
  -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json \
  -s
