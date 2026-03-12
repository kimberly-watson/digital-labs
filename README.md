# Sonatype Digital Labs

Automated AWS lab environment that provisions a full Sonatype product suite on a single EC2 instance via Docker. Used by Sonatype personnel to deploy hands-on product training environments for customers.

> **Important:** Each deployment requires its own AWS account. Do not use someone else's account — you will incur charges on their behalf.

---

## What Gets Deployed

| Component | Details |
|---|---|
| **Nexus Repository CE** | Port 8081 — hosted Maven + npm repos, Maven Central proxy, seeded with sample artifacts |
| **IQ Server (Lifecycle + Firewall)** | Port 8070 — all 7 products licensed automatically at boot |
| **Lab Portal** | Port 80 — countdown timer, one-click links to Nexus and IQ Server, embedded AI tutor |
| **Lab Tutor** | Port 8090 (internal) — Claude-powered chat proxy in Learning Mode, surfaced as a popup window launched from the portal and from Nexus/IQ Server pages |
| **nginx** | Reverse proxy on ports 80, 8082, 8072 — routes `/chat` to tutor proxy, `/tutor` to popup HTML, injects beacon into Nexus and IQ pages |
| **CloudWatch Logs** | `/digital-labs/nexus` and `/digital-labs/iq-server` — Docker audit logs shipped automatically |

**Seeded repositories:**
- `maven-hosted-lab` — sample Maven artifact (`com.sonatype.lab:sample-app:1.0.0`)
- `npm-hosted-lab` — sample npm package (`@sonatype-lab/sample-lib:1.0.0`)
- `maven-proxy-central` — proxy to Maven Central

**Default credentials:** `admin` / `admin123`

---

## Lab Lifecycle

Labs are deployed with a fixed lease period. All notifications and auto-termination are fully automated — no manual steps required after `terraform apply`.

| Event | Trigger | What Happens |
|---|---|---|
| Deploy | Sonatype runs `terraform apply` | EC2 provisions, all services start (~10 min) |
| Welcome email | T+0, Lambda polls until portal is live | Customer receives lab URL and credentials via SES |
| 48hr warning | T-48hr, EventBridge schedule | Warning email sent to customer via SES |
| Expiry | Lease end, EventBridge schedule | EC2 terminated, schedules self-deleted |

**Lease options:** `1w` / `2w` / `3w` / `1mo` — set by Sonatype at deploy time. Customers never configure this.

### Deploying a Customer Lab

```powershell
terraform apply -var="customer_email=customer@example.com" -var="lease_duration=2w" -auto-approve
```

Outputs the instance ID and public IP. Full provisioning takes ~10 minutes. The customer receives the welcome email automatically once the portal is live.

### Testing Email Delivery on Yourself

To validate the full email pipeline without waiting for a new deployment, invoke the welcomer Lambda directly against the running lab:

```powershell
aws lambda invoke --function-name digital-labs-welcomer-default --payload '{}' --region us-east-1 response.json
cat response.json
```

This polls the portal until it responds, then sends the welcome email to whatever `customer_email` is set in the Lambda environment. Use your own address when deploying to test end-to-end before sending to a customer.

---

## Lab Tutor

The Lab Tutor is an AI assistant powered by Claude embedded in the lab environment. It operates in **Learning Mode** — rather than giving direct answers, it guides learners to discover answers through questions and hints.

### Architecture

```
Browser (portal, Nexus, IQ Server)
      │
      ├── "🤖 Lab Tutor" button (fixed, bottom-right)   ← injected by lab-tutor-beacon.js
      │                                                     via nginx sub_filter on ports 8082 + 8072
      │   OR
      ├── "🤖 Use Lab Tutor" button on portal (port 80)
      │
      ▼
window.open('', 'LabTutor')  →  reuses existing popup if open, opens fresh if not
      │
      ▼
  /tutor  (nginx :80, static HTML)
      │
      ▼  user sends message
  /chat  →  proxy.py :8090  →  Anthropic API (Claude, Learning Mode)
```

**Popup reuse logic (beacon.js + portal):** `window.open('', 'LabTutor')` returns any existing window with that name without navigating it. If the window has content (or throws cross-origin), it is simply focused. Only when no live window is found does a fresh popup open. This prevents duplicate windows when switching between the portal and Nexus/IQ Server tabs.

**Beacon iframe guard:** nginx injects `lab-tutor-beacon.js` into every HTML response passing through the Nexus (8082) and IQ Server (8072) proxies, including internal iframe content. The beacon exits immediately if `window !== window.top`, preventing button duplication from iframes.

| Component | Detail |
|---|---|
| Beacon | `/var/www/html/lab-tutor-beacon.js` — injected by nginx `sub_filter` into Nexus (8082) and IQ Server (8072) pages; mounts orange "🤖 Lab Tutor" button and pulses context to localStorage every 2s |
| Popup | `/var/www/html/tutor.html` — served at `http://<ip>/tutor`; polls localStorage for product context |
| Proxy | `/opt/sonatype/tutor/proxy.py` — Python HTTPServer on port 8090 |
| Service | `systemd lab-tutor.service`, reads `/etc/lab-tutor.env` via `EnvironmentFile=` |
| API Key | Stored in SSM `/digital-labs/claude-api-key` (SecureString), fetched at instance boot |
| Env File | `/etc/lab-tutor.env` — root:root 600, never world-readable |
| nginx Routes | `/chat` → proxy :8090; `/tutor` → static tutor.html; `/lab-tutor-beacon.js` → beacon (conf.d/digital-labs.conf) |
| Model | `claude-sonnet-4-20250514` |

### Rotating the API Key

```powershell
# 1. Generate a new key at console.anthropic.com -> Settings -> API Keys
# 2. Store it in SSM (type it in the prompt - do not paste in the terminal history)
$key = Read-Host "Paste new API key"
aws ssm put-parameter --name "/digital-labs/claude-api-key" --value $key --type SecureString --overwrite --region us-east-1

# 3. On next terraform apply, user_data.sh fetches the new key automatically.
# 4. For a running instance, push it manually via SSM Run Command (see fix_key.sh pattern).
```

### Known Issues Fixed (March 2026)

| Bug | Root Cause | Fix |
|---|---|---|
| API rejected (low balance) | Key created before credits added; showed "never used" | Generate fresh key in Anthropic console |
| proxy.py crashed (boto3) | Instance ran old proxy.py that tried to import boto3 | New proxy.py reads key from env var directly |
| Service env broken | Inline `Environment=` in systemd unit breaks on strings with spaces | `EnvironmentFile=/etc/lab-tutor.env` pattern |
| API key leading space | Deploy script wrote `CLAUDE_API_KEY= sk-ant...` with a space | `trim()` in user_data.sh; fixed in fix_key.sh |
| nginx /chat 404 | `default.d/digital-labs.conf` was empty — no `/chat` route | Correct `proxy_pass` config in `conf.d/digital-labs.conf` |
| JS silent failure on send | `var history` conflicts with browser's `window.history` object | Renamed to `chatHistory` throughout |
| IQ Server opens portal | `proxy_redirect` replaced 127.0.0.1 host but dropped the path (`/assets/index.html`), causing an infinite 303 loop | Regex now captures full path: `~^http://127\.0\.0\.1(:\d+)?(.*)$` → `http://$host:8072$2` |
| Double button on Nexus | nginx injects beacon into iframe HTML responses; each iframe has its own `window`, so `__snBeaconInit` on the parent didn't block iframes | Added `if (window !== window.top) return` at top of beacon IIFE |
| Two popup windows open | Switching from portal to Nexus/IQ: `tutorWin` variable is gone; `window.open(URL,'LabTutor',features)` always creates a new window | Call `window.open('','LabTutor')` first — returns existing window by name; only open fresh if window is genuinely absent |


---

## One-Time AWS Account Setup

Complete these steps once per AWS account before your first deployment.

### Step 1 — Create an AWS account

Sign up at https://aws.amazon.com if you do not already have one.

### Step 2 — Create an IAM user with programmatic access

1. Sign into https://console.aws.amazon.com → **IAM > Users > Create user**
2. Username: `digital-labs-cli`
3. Attach these policies directly:
   - `AmazonEC2FullAccess`
   - `IAMFullAccess`
   - `AmazonSSMFullAccess`
   - `AmazonSESFullAccess`
   - `AWSLambda_FullAccess`
   - `AmazonEventBridgeSchedulerFullAccess`
   - `AmazonS3FullAccess`
4. Create the user → **Security credentials** tab → **Create access key** → **CLI**
5. Save the Access Key ID and Secret — you cannot retrieve the secret again

### Step 3 — Install and configure the AWS CLI

Download: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

```powershell
aws configure
# AWS Access Key ID:     <your key>
# AWS Secret Access Key: <your secret>
# Default region name:   us-east-1
# Default output format: json

aws sts get-caller-identity  # verify
```

### Step 4 — Verify SES sender domain

Lab emails are sent from `digital-labs@sonatype.com` via AWS SES. Complete this once:

1. AWS Console → **SES > Identities > Create identity** → Domain: `sonatype.com`
2. Add the 3 DKIM CNAME records AWS provides to sonatype.com DNS
3. AWS Console → **SES > Account dashboard > Request production access**
   - New accounts start in sandbox and can only send to verified addresses
   - Production access is typically approved within a few hours

> **Status (March 2026):** sonatype.com DKIM verified ✅ and SES production access approved ✅ in us-east-1. This step is complete for the current AWS account — no action required.

### Step 5 — Store Claude API key in SSM

The Lab Tutor requires a Claude API key stored in SSM Parameter Store. Enter the key interactively — do not paste secrets into shell history.

```powershell
$key = Read-Host "Paste Claude API key"
aws ssm put-parameter `
  --name "/digital-labs/claude-api-key" `
  --value $key `
  --type "SecureString" `
  --region us-east-1
```

Requirements for the key's Anthropic account:
- Org: one org, one workspace (Default)
- Tier 1 or higher (requires phone verification + credit purchase)
- Available credit balance > $0
- Monthly spend limit > $0 (Settings → Limits)

### Step 6 — Set up remote Terraform state backend

Creates the S3 bucket and DynamoDB table for shared Terraform state. Safe to re-run.

```powershell
.\setup-backend.ps1
```

### Step 7 — Store your Sonatype license in SSM

```powershell
.\setup-license.ps1 -LicensePath "C:\path\to\your-license.lic"
```

> Uses SSM Advanced tier (~$0.05/month). Required because the encoded license exceeds the 4096-character Standard limit.
> License expiry: **August 1, 2026** — re-run this script with an updated `.lic` file to renew. No Terraform changes needed.

---

## Prerequisites (Per Contributor)

1. AWS CLI configured (see above)
2. Terraform ≥ 1.x — https://developer.hashicorp.com/terraform/install
3. Git with SSH configured (see SSH Setup below)

---

## SSH Setup

### Step 1 — Generate an SSH key

```powershell
ssh-keygen -t ed25519 -C "your.name@sonatype.com" -f "$env:USERPROFILE\.ssh\id_ed25519" -N ''
```

### Step 2 — Add to GitHub

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"  # copy this output
```

Go to https://github.com/settings/ssh/new → paste the key → **Add SSH key**

### Step 3 — Clone the repo

```powershell
git clone git@github.com:kimberly-watson/digital-labs.git
cd digital-labs
terraform init
```

---

## Deploying a Lab

```powershell
terraform apply -var="customer_email=customer@example.com" -var="lease_duration=2w" -auto-approve
```

Outputs the instance ID and public IP. Full provisioning takes ~10 minutes. The customer receives the welcome email automatically once the portal is live.

---

## Accessing the Lab (Sonatype Internal)

| Interface | URL | Credentials |
|---|---|---|
| Lab Portal | `http://<public_ip>` | — |
| Nexus Repository | `http://<public_ip>:8082` | admin / admin123 |
| IQ Server | `http://<public_ip>:8072` | admin / admin123 |
| Lab Tutor | Click **🤖 Use Lab Tutor** on portal, or **🤖 Lab Tutor** button on any product page | — |
| CloudWatch Logs | AWS Console → CloudWatch → Log groups | — |

Helper scripts:
- `open-nexus.ps1` — opens Nexus in your default browser
- `connect-perm.ps1` — starts an SSM shell session to the instance (no SSH key or open port 22 needed)
- `view-labs.ps1` — generates a local HTML dashboard showing all running labs with live countdowns


---

## Configuration

Override defaults by creating a `terraform.tfvars` file in the repo root (do **not** commit this file):

```hcl
aws_region     = "us-west-2"
instance_type  = "t3.xlarge"
ses_from_email = "digital-labs@sonatype.com"
```

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region |
| `instance_type` | `t3.large` | EC2 type (minimum t3.large — 8GB RAM required) |
| `volume_size_gb` | `30` | Root EBS volume in GB |
| `ssm_parameter_path` | `/digital-labs/sonatype-license` | SSM path for license |
| `lab_name` | `digital-labs-instance` | EC2 Name tag |
| `lease_duration` | — | **Required.** `1w`, `2w`, `3w`, or `1mo` |
| `customer_email` | — | **Required.** Customer email for notifications |
| `ses_from_email` | `digital-labs@sonatype.com` | Verified SES sender address |

---

## Tearing Down

```powershell
terraform destroy
```

Removes: EC2 instance, Lambda functions, EventBridge schedules, IAM roles, S3 asset objects.
Does **not** remove: SSM license parameter, SSM Claude API key, S3 state bucket.

> Labs auto-terminate at lease expiry, but manual destroy is faster and avoids residual charges.

---

## Cost Estimate

| Resource | Cost |
|---|---|
| EC2 t3.large (us-east-1) | ~$0.08/hr (~$1.92/day) |
| 30GB gp3 EBS | ~$2.40/month |
| SSM Advanced Parameter | ~$0.05/month |
| Anthropic API (Claude) | ~$0.01–$0.05 per learner session (varies by usage) |
| SES email | ~$0.10 per 1,000 emails (negligible) |
| Lambda + EventBridge + S3 | Negligible (well within free tier) |

**Typical cost for a one-week lab: ~$14 + Anthropic usage**

---

## Architecture

```
Customer browser
      │
      ▼
  nginx :80
  ├── /           → Lab Portal (countdown + product links + "🤖 Use Lab Tutor" button)
  ├── /tutor      → Lab Tutor popup (standalone HTML)
  └── /chat       → Lab Tutor proxy :8090 → Anthropic API (Claude, Learning Mode)

Proxied product ports (nginx sub_filter injects beacon into every HTML response):
  :8082  → Nexus Repository CE (:8081)   — beacon mounts "🤖 Lab Tutor" button
  :8072  → IQ Server / Lifecycle (:8070) — beacon mounts "🤖 Lab Tutor" button

Direct container ports (not browser-accessible — blocked by nginx UA enforcement):
  :8081  Nexus Repository CE (internal)
  :8070  IQ Server (internal)
```

- EC2: `t3.large`, 30GB gp3, Amazon Linux 2023
- Containers: both run with `--restart=always` and ship logs to CloudWatch via `--log-driver awslogs`
- Assets (portal HTML, proxy.py, tutor HTML) stored in S3 and downloaded at boot — keeps `user_data.sh` under the 16KB EC2 limit
- Lab Tutor proxy runs as `labclock` (no-login system user); env file `/etc/lab-tutor.env` is root:root 600
- License pulled from SSM at boot, base64-decoded, injected via IQ Server REST API (CSRF token flow)
- Claude API key pulled from SSM at boot, written to `/etc/lab-tutor.env`, injected via `EnvironmentFile=` in systemd — never exposed to browser or logs
- Initialization sequence: Docker install → Nexus start → IQ Server start → license upload → password set → data seeding → portal → tutor → nginx
- Auto-termination: two EventBridge one-shot schedules (T-48hr warning, T=0 termination) — self-delete after firing
- Email: AWS SES direct send — no customer confirmation step required
- Welcome Lambda polls `http://<ip>/` until 200 before sending email (up to 10 min), then sends regardless

---

## user_data.sh Boot Sequence

| Step | Action |
|---|---|
| 1 | IMDSv2 token + read `lab_key` and `termination_time` from instance tags + SSM |
| 2 | `dnf install docker zip python3 nginx` |
| 3 | Fetch `CLAUDE_API_KEY` from SSM `/digital-labs/claude-api-key` (trimmed, no whitespace) |
| 4 | Write `/etc/lab-tutor.env` (root:root 600) with API key + Learning Mode system prompt |
| 5 | Start Nexus CE on port 8081 |
| 6 | Start IQ Server on ports 8070/8071 with license volume mount |
| 7 | Wait for IQ Server → CSRF token → POST license via REST API |
| 8 | Wait for Nexus → read generated password → set to `admin123` |
| 9 | Seed: `lab-blob-store`, `maven-hosted-lab`, `npm-hosted-lab`, `maven-proxy-central` |
| 10 | Seed: `sample-app` JAR + `@sonatype-lab/sample-lib` npm package |
| 11 | Deploy `countdown.html` from S3, `sed`-replace `TERMINATION_PLACEHOLDER` |
| 12 | Deploy `proxy.py` + `tutor.html` from S3 to `/opt/sonatype/tutor/` |
| 13 | Write `systemd lab-tutor.service` with `EnvironmentFile=/etc/lab-tutor.env` |
| 14 | Write `nginx conf.d/digital-labs.conf` with `/chat` and `/` routes |
| 15 | `systemctl enable --now lab-tutor nginx` |

---

## Repo Structure

```
digital-labs/
├── main.tf                    # EC2, IAM, security group, S3 asset objects, module instantiation
├── variables.tf               # All input variables (single-lab and cohort modes)
├── backend.tf                 # S3 remote state config
├── cloudwatch.tf              # CloudWatch dashboard (per-lab metrics + container log tails)
├── cohort.tfvars.example      # Example multi-lab cohort deployment file
├── nginx-digital-labs.conf    # nginx port 80: /chat proxy, /tutor static, /lab-tutor-beacon.js, / portal
├── nginx-product-proxies.conf # nginx ports 8082 (Nexus) and 8072 (IQ): sub_filter beacon injection, proxy_redirect
├── nginx-browser-enforce.conf # nginx http-level UA map: blocks non-browser requests on all product ports
├── user_data.sh               # EC2 boot script (~240 lines)
├── modules/
│   └── lab/
│       ├── main.tf            # EC2 instance, SSM param, IMDSv2
│       ├── lambda.tf          # Welcomer, notifier, terminator Lambda functions
│       ├── eventbridge.tf     # Three one-shot EventBridge schedules per lab
│       ├── variables.tf       # Module inputs
│       └── outputs.tf         # instance_id, public_ip, lab_url, nexus_url, iq_url, terminates_at
├── assets/
│   ├── countdown.html         # Lab portal (timer + product links + "🤖 Use Lab Tutor" button)
│   ├── proxy.py               # Lab Tutor HTTP proxy (port 8090, internal only)
│   ├── tutor.html             # Standalone Lab Tutor popup (/tutor) — polls localStorage for context
│   └── lab-tutor-beacon.js    # Injected by nginx into Nexus + IQ pages; mounts button + pulses localStorage
├── lambda/
│   ├── welcomer.py            # Sends branded HTML welcome email via SES when portal is ready
│   ├── notifier.py            # Sends branded HTML 48hr warning email via SES
│   └── terminator.py          # Terminates EC2 + cleans up all three schedules
├── view-labs.ps1              # Sonatype Personnel View — HTML dashboard from terraform output
├── open-nexus.ps1             # Opens Nexus in default browser
├── connect-perm.ps1           # Opens SSM shell session to running instance
├── setup-backend.ps1          # One-time: create S3 bucket for Terraform state
├── setup-license.ps1          # One-time: upload Sonatype license to SSM
├── CUSTOMER_GUIDE.md          # Customer-facing user guide (no internal info)
└── CUSTOMER_GUIDE.pdf         # Branded PDF version of the customer guide
```

---

## Backlog

| Item | Status | Notes |
|---|---|---|
| Factory / cohort automation | ✅ Done | `modules/lab/` with `for_each` — deploy N labs from one `terraform apply -var-file=cohort.tfvars` |
| SES HTML email | ✅ Done | Branded HTML welcome + 48hr warning emails via SES |
| CloudWatch dashboard | ✅ Done | `cloudwatch.tf` — per-lab Lambda + EC2 metrics + container log tails |
| Sonatype Personnel View | ✅ Done | `view-labs.ps1` — local HTML dashboard from `terraform output` with live countdowns |
| SES production access | ✅ Done | Approved March 2026 — 50,000 msg/day, sandbox lifted in us-east-1 |
| sonatype.com DKIM DNS | ✅ Done | Verified in us-east-1, confirmed March 2026 |
| Lab Tutor AI chat | ✅ Done | Popup architecture — beacon injected into Nexus + IQ via nginx sub_filter; single popup window reused across tabs via `window.open('','LabTutor')` |
| CloudWatch telemetry | 🔜 Next | Nexus + IQ Server audit logs → CloudWatch Logs via CloudWatch agent |
| Custom domain / HTTPS | 🔜 Blocked | Requires DNS access — Route 53 + ACM cert for `https://labs.sonatype.com` |

---

## License

The Sonatype license is for **internal Sonatype use only**. Do not distribute or use in customer-facing environments without an appropriate commercial license.
