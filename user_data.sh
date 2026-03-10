#!/bin/bash
set -euxo pipefail

# Read termination time from SSM Parameter Store
TERMINATION_TIME=$(aws ssm get-parameter \
  --name "/digital-labs/termination-time" \
  --region us-east-1 \
  --query "Parameter.Value" \
  --output text)

# Install Docker
dnf -y install docker zip python3
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
  sonatype/nexus3:3.68.0

# Start IQ Server (Lifecycle + Firewall)
docker run -d \
  --name iq-server \
  --restart=always \
  -p 8070:8070 \
  -p 8071:8071 \
  -v /opt/sonatype/iq-server/license.lic:/etc/nexus-iq-server/license.lic \
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

# Wait for IQ Server to initialize (~3 min additional)
sleep 180

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

# ── COUNTDOWN CLOCK ──

mkdir -p /opt/sonatype/countdown
cat > /opt/sonatype/countdown/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta http-equiv="refresh" content="60">
  <title>Sonatype Digital Lab</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; background: #1a1a2e; color: #eee; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 100vh; padding: 2rem; }
    .logo { font-size: 1.2rem; font-weight: 700; color: #00b4d8; margin-bottom: 2rem; letter-spacing: 2px; text-transform: uppercase; }
    h1 { font-size: 1.6rem; margin-bottom: 0.5rem; }
    .subtitle { color: #aaa; margin-bottom: 3rem; font-size: 0.95rem; }
    .clock { display: flex; gap: 2rem; margin-bottom: 2rem; }
    .unit { text-align: center; background: #16213e; border: 1px solid #0f3460; border-radius: 12px; padding: 1.5rem 2rem; min-width: 100px; }
    .unit.warning { border-color: #e76f51; background: #2d1b15; }
    .number { font-size: 3rem; font-weight: 700; line-height: 1; }
    .label { font-size: 0.75rem; text-transform: uppercase; letter-spacing: 1px; color: #aaa; margin-top: 0.5rem; }
    .message { color: #aaa; font-size: 0.9rem; text-align: center; max-width: 480px; line-height: 1.6; }
    .warning-msg { color: #e76f51; font-weight: 600; margin-bottom: 0.5rem; }
    .expires { margin-top: 2rem; font-size: 0.8rem; color: #666; }
  </style>
</head>
<body>
  <div class="logo">Sonatype Digital Lab</div>
  <h1>Your Lab Time Remaining</h1>
  <p class="subtitle">This environment will automatically shut down when the timer expires.</p>
  <div class="clock" id="clock">
    <div class="unit" id="unit-days"><div class="number" id="days">--</div><div class="label">Days</div></div>
    <div class="unit" id="unit-hours"><div class="number" id="hours">--</div><div class="label">Hours</div></div>
    <div class="unit" id="unit-mins"><div class="number" id="mins">--</div><div class="label">Minutes</div></div>
  </div>
  <div class="message">
    <p id="warning-msg"></p>
    <p>Need more time? Contact your Sonatype representative before expiry.</p>
  </div>
  <p class="expires">Scheduled termination: TERMINATION_PLACEHOLDER UTC</p>
  <script>
    const termination = new Date("TERMINATION_PLACEHOLDERZ");
    function update() {
      const now = new Date(); const diff = termination - now;
      if (diff <= 0) { document.getElementById("clock").innerHTML = "<p style='color:#e76f51;font-size:1.4rem;'>This lab has expired.</p>"; return; }
      const days = Math.floor(diff/86400000);
      const hours = Math.floor((diff%86400000)/3600000);
      const mins = Math.floor((diff%3600000)/60000);
      document.getElementById("days").textContent = String(days).padStart(2,"0");
      document.getElementById("hours").textContent = String(hours).padStart(2,"0");
      document.getElementById("mins").textContent = String(mins).padStart(2,"0");
      const warning = diff < 172800000;
      ["unit-days","unit-hours","unit-mins"].forEach(id => document.getElementById(id).classList.toggle("warning", warning));
      document.getElementById("warning-msg").textContent = warning ? "Warning: Less than 48 hours remaining - save your work!" : "";
    }
    update(); setInterval(update, 60000);
  </script>
</body>
</html>
HTMLEOF

# Replace placeholder with actual termination time
sed -i "s/TERMINATION_PLACEHOLDER/${TERMINATION_TIME}/g" /opt/sonatype/countdown/index.html

# Serve countdown page on port 8080 via systemd
cat > /etc/systemd/system/lab-countdown.service << 'SVCEOF'
[Unit]
Description=Sonatype Lab Countdown Clock
After=network.target
[Service]
ExecStart=/usr/bin/python3 -m http.server 8080 --directory /opt/sonatype/countdown
Restart=always
User=root
[Install]
WantedBy=multi-user.target
SVCEOF

systemctl enable --now lab-countdown
