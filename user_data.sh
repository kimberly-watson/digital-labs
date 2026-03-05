#!/bin/bash
set -euxo pipefail

# Install Docker
dnf -y install docker zip
systemctl enable --now docker

# Create directory and pull license key from Parameter Store
mkdir -p /opt/sonatype/iq-server

aws ssm get-parameter \
  --name "/digital-labs/sonatype-license" \
  --with-decryption \
  --region us-east-1 \
  --query "Parameter.Value" \
  --output text | base64 -d > /opt/sonatype/iq-server/license.lic

# Start Nexus Repository
docker run -d \
  --name nexus \
  --restart=always \
  -p 8081:8081 \
  sonatype/nexus3:latest

# Start IQ Server (Lifecycle + Firewall)
docker run -d \
  --name iq-server \
  --restart=always \
  -p 8070:8070 \
  -p 8071:8071 \
  -v /opt/sonatype/iq-server/license.lic:/etc/nexus-iq-server/license.lic \
  sonatype/nexus-iq-server:latest

# Wait for Nexus to initialize (~2 min)
sleep 120

# Set Nexus admin password
GENERATED=$(docker exec nexus cat /nexus-data/admin.password 2>/dev/null)
curl -s \
  -u "admin:${GENERATED}" \
  -X PUT \
  -H "Content-Type: text/plain" \
  --data "admin123" \
  http://localhost:8081/service/rest/v1/security/users/admin/change-password

# Wait for IQ Server to initialize (~3 min additional)
sleep 180

# Establish session and capture CSRF token
curl -s \
  -c /tmp/iq-cookies.txt \
  -b /tmp/iq-cookies.txt \
  -u "admin:admin123" \
  http://localhost:8070/api/v2/solutions/licensed > /dev/null

# Extract CSRF token
CSRF=$(grep 'CLM-CSRF-TOKEN' /tmp/iq-cookies.txt | awk '{print $NF}')

# Upload license to correct endpoint
curl -s \
  -c /tmp/iq-cookies.txt \
  -b /tmp/iq-cookies.txt \
  -H "X-CLM-CSRF-TOKEN: $CSRF" \
  -u "admin:admin123" \
  -X POST \
  -F "file=@/opt/sonatype/iq-server/license.lic" \
  http://localhost:8070/api/v2/product/license

# ── FAKE DATA SEEDING ──

# Wait for Nexus to be fully ready
sleep 30

# Create blob store
curl -s -u "admin:admin123" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"name":"lab-blob-store","path":"lab-blob-store","softQuota":{"type":"spaceUsedQuota","limit":5368709120}}' \
  http://localhost:8081/service/rest/v1/blobstores/file

# Create Maven hosted repo
curl -s -u "admin:admin123" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"name":"maven-hosted-lab","online":true,"storage":{"blobStoreName":"lab-blob-store","strictContentTypeValidation":true,"writePolicy":"allow"},"maven":{"versionPolicy":"MIXED","layoutPolicy":"STRICT"}}' \
  http://localhost:8081/service/rest/v1/repositories/maven/hosted

# Create npm hosted repo
curl -s -u "admin:admin123" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"name":"npm-hosted-lab","online":true,"storage":{"blobStoreName":"lab-blob-store","strictContentTypeValidation":true,"writePolicy":"allow"}}' \
  http://localhost:8081/service/rest/v1/repositories/npm/hosted

# Create Maven proxy repo
curl -s -u "admin:admin123" \
  -X POST \
  -H "Content-Type: application/json" \
  -d '{"name":"maven-proxy-central","online":true,"storage":{"blobStoreName":"lab-blob-store","strictContentTypeValidation":true},"proxy":{"remoteUrl":"https://repo1.maven.org/maven2/","contentMaxAge":1440,"metadataMaxAge":1440},"negativeCache":{"enabled":true,"timeToLive":1440},"httpClient":{"blocked":false,"autoBlock":true},"maven":{"versionPolicy":"RELEASE","layoutPolicy":"STRICT"}}' \
  http://localhost:8081/service/rest/v1/repositories/maven/proxy

# Seed Maven artifact
mkdir -p /tmp/fake-maven
echo "Manifest-Version: 1.0" > /tmp/fake-maven/MANIFEST.MF
zip -j /tmp/fake-maven/sample-app-1.0.0.jar /tmp/fake-maven/MANIFEST.MF
curl -s -u "admin:admin123" \
  -X POST \
  "http://localhost:8081/service/rest/v1/components?repository=maven-hosted-lab" \
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
  -X POST \
  "http://localhost:8081/service/rest/v1/components?repository=npm-hosted-lab" \
  -F "npm.asset=@/tmp/fake-npm/sonatype-lab-sample-lib-1.0.0.tgz;type=application/x-compressed"