# Sonatype Digital Labs

Automated AWS lab environment that provisions a full Sonatype product suite on a single EC2 instance via Docker. Used by Sonatype personnel to deploy hands-on product training environments for customers.

> **Important:** Each deployment requires its own AWS account. Do not use someone else's account Ã¢â‚¬â€ you will incur charges on their behalf.

---

## What Gets Deployed

| Component | Details |
|---|---|
| **Nexus Repository CE** | Port 8082 (nginx proxy Ã¢â€ â€™ 8081 internal) Ã¢â‚¬â€ hosted Maven + npm repos, Maven Central proxy, seeded with sample artifacts |
| **IQ Server (Lifecycle + Firewall)** | Port 8072 (nginx proxy Ã¢â€ â€™ 8070 internal) Ã¢â‚¬â€ all 7 products licensed automatically at boot |
| **Lab Portal** | Port 80 Ã¢â‚¬â€ countdown timer, one-click links to Nexus and IQ Server, embedded AI tutor |
| **Lab Tutor** | Port 8090 (internal) Ã¢â‚¬â€ Claude-powered chat proxy in Learning Mode, surfaced as a popup window launched from the portal and from Nexus/IQ Server pages |
| **nginx** | Reverse proxy on ports 80, 8082, 8072 Ã¢â‚¬â€ routes `/chat` to tutor proxy, `/tutor` to popup HTML, injects beacon into Nexus and IQ pages |
| **CloudWatch Logs** | Container stdout: `/digital-labs/nexus`, `/digital-labs/iq-server` (Docker `--log-driver awslogs`). IQ Server structured logs: `/digital-labs/iq-audit`, `/digital-labs/iq-requests`, `/digital-labs/iq-server-app` (CloudWatch agent) |

**Seeded repositories:**
- `maven-hosted-lab` Ã¢â‚¬â€ sample Maven artifact (`com.sonatype.lab:sample-app:1.0.0`)
- `npm-hosted-lab` Ã¢â‚¬â€ sample npm package (`@sonatype-lab/sample-lib:1.0.0`)
- `maven-proxy-central` Ã¢â‚¬â€ proxy to Maven Central

**Default credentials:** `admin` / `admin123`

---

## Lab Lifecycle

Labs are deployed with a fixed lease period. All notifications and auto-termination are fully automated Ã¢â‚¬â€ no manual steps required after `terraform apply`.

| Event | Trigger | What Happens |
|---|---|---|
| Deploy | Sonatype runs `terraform apply` | EC2 provisions, all services start (~10 min) |
| Welcome email | T+0, Lambda polls until portal is live | Customer receives lab URL and credentials via SES |
| 48hr warning | T-48hr, EventBridge schedule | Warning email sent to customer via SES |
| Expiry | Lease end, EventBridge schedule | EC2 terminated, schedules self-deleted |

**Lease options:** `1w` / `2w` / `3w` / `1mo` Ã¢â‚¬â€ set by Sonatype at deploy time. Customers never configure this.

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

The Lab Tutor is an AI assistant powered by Claude embedded in the lab environment. It operates in **Learning Mode** Ã¢â‚¬â€ rather than giving direct answers, it guides learners to discover answers through questions and hints.

### Architecture

```
Browser (portal, Nexus, IQ Server)
      Ã¢â€â€š
      Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ "Ã°Å¸Â¤â€“ Lab Tutor" button (fixed, bottom-right)   Ã¢â€ Â injected by lab-tutor-beacon.js
      Ã¢â€â€š                                                     via nginx sub_filter on ports 8082 + 8072
      Ã¢â€â€š   OR
      Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ "Ã°Å¸Â¤â€“ Use Lab Tutor" button on portal (port 80)
      Ã¢â€â€š
      Ã¢â€“Â¼
window.open(TUTOR_URL, 'LabTutor', features)
      Ã¢â€â€š  (if named window already exists in this context: Chrome navigates + raises it)
      Ã¢â€â€š  (if not: opens fresh popup Ã¢â‚¬â€ ownership heartbeat closes old portal tutor in ~500ms)
      Ã¢â€“Â¼
  /tutor  (nginx :80, static HTML)
      Ã¢â€â€š
      Ã¢â€“Â¼  user sends message
  /chat  Ã¢â€ â€™  proxy.py :8090  Ã¢â€ â€™  Anthropic API (Claude, Learning Mode)
```

**Raise logic Ã¢â‚¬â€ Chrome 88+ noopener constraint:**
Chrome 88+ enforces `noopener` on cross-origin `window.open()` calls, which means `window.opener` is always `null` in Nexus/IQ tabs and named-window lookup (`window.open('','LabTutor')`) always returns a blank window Ã¢â‚¬â€ the Nexus/IQ beacon can never find or raise a tutor that was opened from the portal.

All raising is therefore handled exclusively by the portal:

| Trigger | What Happens |
|---|---|
| User clicks Nexus or IQ card on portal | Card `onclick` calls `window.open(product,'_blank')` **and** `raiseTutorIfOpen()` in the same user gesture |
| User switches back to portal tab | `visibilitychange` fires with `visible`; debounced 300ms; calls `raiseTutorIfOpen()` Ã¢â‚¬â€ safe because raising a popup does not change the portal tab's `visibilityState`, so no loop |
| User clicks **Ã°Å¸Â¤â€“ Lab Tutor** button on Nexus/IQ | Single `window.open(TUTOR_URL,'LabTutor',feat)` Ã¢â‚¬â€ if 'LabTutor' exists in that browsing context, Chrome raises it; if not, opens fresh popup in front |

**Single-instance ownership:** The tutor writes a unique owner ID to port-80 localStorage on load and refreshes a timestamp every 500ms. If a newer tutor window claims the slot, the old one closes itself Ã¢â‚¬â€ conversation history is preserved in `snTutorHistory`.

**Session-end detection:** The portal writes `snPortalAlive` to port-80 localStorage every 2s. The tutor polls every 5s. Once the portal has been seen alive (`_portalEverSeen` latch), when it goes stale (>15s), the tutor resets its DOM and clears history Ã¢â‚¬â€ the session is over.

**Stale-load guard:** On tutor load, `checkStaleOnLoad()` reads `snPortalAlive`. If `portalTs > 0` and stale, it wipes `snTutorHistory` before `restoreHistory()` runs. If `portalTs === 0` (portal hasn't written its first heartbeat yet), it does **not** wipe Ã¢â‚¬â€ preventing history from being cleared when the tutor is raised from Nexus/IQ before the portal's 2s interval fires.

**Beacon iframe guard:** nginx injects `lab-tutor-beacon.js` into every HTML response passing through the Nexus (8082) and IQ Server (8072) proxies, including internal iframe content. The beacon exits immediately if `window !== window.top`, preventing button duplication from iframes.

| Component | Detail |
|---|---|
| Beacon | `/var/www/html/lab-tutor-beacon.js` Ã¢â‚¬â€ injected by nginx `sub_filter` into Nexus (8082) and IQ Server (8072) pages; mounts orange "Ã°Å¸Â¤â€“ Lab Tutor" button and pulses context to localStorage every 2s |
| Popup | `/var/www/html/tutor.html` Ã¢â‚¬â€ served at `http://<ip>/tutor`; polls localStorage for product context |
| Proxy | `/opt/sonatype/tutor/proxy.py` Ã¢â‚¬â€ Python HTTPServer on port 8090 |
| Service | `systemd lab-tutor.service`, reads `/etc/lab-tutor.env` via `EnvironmentFile=` |
| API Key | Stored in SSM `/digital-labs/claude-api-key` (SecureString), fetched at instance boot |
| Env File | `/etc/lab-tutor.env` Ã¢â‚¬â€ root:root 600, never world-readable |
| nginx Routes | `/chat` Ã¢â€ â€™ proxy :8090; `/tutor` Ã¢â€ â€™ static tutor.html; `/lab-tutor-beacon.js` Ã¢â€ â€™ beacon (conf.d/digital-labs.conf) |
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
| nginx /chat 404 | `default.d/digital-labs.conf` was empty Ã¢â‚¬â€ no `/chat` route | Correct `proxy_pass` config in `conf.d/digital-labs.conf` |
| JS silent failure on send | `var history` conflicts with browser's `window.history` object | Renamed to `chatHistory` throughout |
| IQ Server opens portal | `proxy_redirect` replaced 127.0.0.1 host but dropped the path, causing an infinite 303 loop | Regex captures full path: `~^http://127\.0\.0\.1(:\d+)?(.*)$` Ã¢â€ â€™ `http://$host:8072$2` |
| Double button on Nexus | nginx injects beacon into iframe HTML; each iframe has its own `window`, so `__snBeaconInit` on the parent didn't block iframes | Added `if (window !== window.top) return` at top of beacon IIFE |
| Two popup windows open | `tutorWin` is gone when tab changes context; `window.open(URL,'LabTutor',features)` always creates a new window | Call `window.open('','LabTutor')` first Ã¢â‚¬â€ returns existing window by name; only open fresh if window is genuinely absent |
| Tutor not raising on Nexus/IQ navigation | Chrome 88+ enforces `noopener` on cross-origin `window.open()` Ã¢â‚¬â€ `window.opener` is null in Nexus/IQ tabs; named-window lookup returns blank | All raises go through the portal: card `onclick` + `visibilitychange` debounced 300ms; beacon button uses single `window.open(TUTOR_URL,'LabTutor',feat)` |
| Infinite raise loop | Raising the tutor from a Nexus/IQ `visibilitychange` listener stole focus back to the tutor, which re-fired `visibilitychange`, looping infinitely | Removed `visibilitychange` from beacon entirely; portal `visibilitychange` is safe (raising a popup does not change the portal tab's `visibilityState`) |
| History cleared too early | `checkStaleOnLoad` wiped `snTutorHistory` whenever `portalTs === 0` Ã¢â‚¬â€ which is the normal state before the portal's first 2s heartbeat fires | Only wipe when `portalTs > 0 && stale` (portal was open at some point but has since gone quiet) |
| Nexus "change password" banner persisted | `admin.password` file remained on disk after password was reset â€” Nexus shows setup banner until this file is deleted | `docker exec nexus rm -f /nexus-data/admin.password` run after password reset in boot sequence |
| IQ Server license not installed at boot | `user_data.sh` made a single POST attempt before IQ was fully ready internally â€” returned non-200 silently | Added retry loop (up to 10 attempts, 20s apart) that refreshes CSRF cookie each attempt and exits on HTTP 200; commit `e418614` |
| Nexus "change password" banner persisted after reset | `admin.password` file remained on disk after API password reset — Nexus treats its presence as incomplete first-run setup | `docker exec nexus rm -f /nexus-data/admin.password` added to boot sequence after password change step |
| IQ Server license silently failed at boot | Single POST attempt made before IQ internal modules were ready — returned non-200 and continued with no license installed | Retry loop: up to 10 attempts, 20s apart, CSRF cookie refreshed each attempt, exits on HTTP 200; commit `e418614` |
| Prompt injection via product/pageUrl | Client-supplied `product` and `pageUrl` fields were concatenated directly into the Claude system prompt | `sanitize()` strips control chars + caps length; `product` allowlisted to `{"Nexus Repository", "IQ Server"}` only |
| API key open CORS | `proxy.py` returned `Access-Control-Allow-Origin: *`, allowing any origin to call the tutor proxy | CORS locked to same-origin host (`http://<ip>`) |
| System prompt truncated by systemd | Multi-line `TUTOR_SYSTEM_PROMPT` in `EnvironmentFile=` silently truncated at first newline | Base64-encoded at write time in `user_data.sh`; decoded at startup in `proxy.py` |
| Credentials in Anthropic API payload | `admin/admin123` included in system prompt, sent to Anthropic API on every chat | Credentials removed; tutor redirects credential questions to the portal |
| Raw ports 8081/8070 open externally | Security group exposed direct container ports, bypassing nginx UA enforcement and beacon injection | Ports removed from security group; all browser access via nginx proxies 8082/8072 only |
| IQ Server image unpinned | `sonatype/nexus-iq-server:latest` could pull a breaking version on next deploy | Pinned to `1.201.0-02` (version confirmed from running instance) |
| `/tmp/iq-cookies.txt` left on disk | IQ license CSRF flow wrote session cookies to world-readable `/tmp` and never cleaned up | `rm -f /tmp/iq-cookies.txt` added after license upload |
| Lambda terminator too broad | `ec2:TerminateInstances` had `Resource: "*"` Ã¢â‚¬â€ a bug could terminate non-lab instances | Scoped with `Condition: StringLike ec2:ResourceTag/lab_key "*"` |
| CloudWatch policy too broad | `CloudWatchLogsFullAccess` granted account-wide read+write | Replaced with inline policy scoped to `arn:aws:logs:*:*:log-group:/digital-labs/*` |


---

## One-Time AWS Account Setup

Complete these steps once per AWS account before your first deployment.

### Step 1 Ã¢â‚¬â€ Create an AWS account

Sign up at https://aws.amazon.com if you do not already have one.

### Step 2 Ã¢â‚¬â€ Create an IAM user with programmatic access

1. Sign into https://console.aws.amazon.com Ã¢â€ â€™ **IAM > Users > Create user**
2. Username: `digital-labs-cli`
3. Attach these policies directly:
   - `AmazonEC2FullAccess`
   - `IAMFullAccess`
   - `AmazonSSMFullAccess`
   - `AmazonSESFullAccess`
   - `AWSLambda_FullAccess`
   - `AmazonEventBridgeSchedulerFullAccess`
   - `AmazonS3FullAccess`
4. Create the user Ã¢â€ â€™ **Security credentials** tab Ã¢â€ â€™ **Create access key** Ã¢â€ â€™ **CLI**
5. Save the Access Key ID and Secret Ã¢â‚¬â€ you cannot retrieve the secret again

### Step 3 Ã¢â‚¬â€ Install and configure the AWS CLI

Download: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

```powershell
aws configure
# AWS Access Key ID:     <your key>
# AWS Secret Access Key: <your secret>
# Default region name:   us-east-1
# Default output format: json

aws sts get-caller-identity  # verify
```

### Step 4 Ã¢â‚¬â€ Verify SES sender domain

Lab emails are sent from `digital-labs@sonatype.com` via AWS SES. Complete this once:

1. AWS Console Ã¢â€ â€™ **SES > Identities > Create identity** Ã¢â€ â€™ Domain: `sonatype.com`
2. Add the 3 DKIM CNAME records AWS provides to sonatype.com DNS
3. AWS Console Ã¢â€ â€™ **SES > Account dashboard > Request production access**
   - New accounts start in sandbox and can only send to verified addresses
   - Production access is typically approved within a few hours

> **Status (March 2026):** sonatype.com DKIM verified Ã¢Å“â€¦ and SES production access approved Ã¢Å“â€¦ in us-east-1. This step is complete for the current AWS account Ã¢â‚¬â€ no action required.

### Step 5 Ã¢â‚¬â€ Store Claude API key in SSM

The Lab Tutor requires a Claude API key stored in SSM Parameter Store. Enter the key interactively Ã¢â‚¬â€ do not paste secrets into shell history.

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
- Monthly spend limit > $0 (Settings Ã¢â€ â€™ Limits)

### Step 6 Ã¢â‚¬â€ Set up remote Terraform state backend

Creates the S3 bucket and DynamoDB table for shared Terraform state. Safe to re-run.

```powershell
.\setup-backend.ps1
```

### Step 7 Ã¢â‚¬â€ Store your Sonatype license in SSM

```powershell
.\setup-license.ps1 -LicensePath "C:\path\to\your-license.lic"
```

> Uses SSM Advanced tier (~$0.05/month). Required because the encoded license exceeds the 4096-character Standard limit.
> License expiry: **August 1, 2026** Ã¢â‚¬â€ re-run this script with an updated `.lic` file to renew. No Terraform changes needed.

---

## Prerequisites (Per Contributor)

1. AWS CLI configured (see above)
2. Terraform Ã¢â€°Â¥ 1.x Ã¢â‚¬â€ https://developer.hashicorp.com/terraform/install
3. Git with SSH configured (see SSH Setup below)

---

## SSH Setup

### Step 1 Ã¢â‚¬â€ Generate an SSH key

```powershell
ssh-keygen -t ed25519 -C "your.name@sonatype.com" -f "$env:USERPROFILE\.ssh\id_ed25519" -N ''
```

### Step 2 Ã¢â‚¬â€ Add to GitHub

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"  # copy this output
```

Go to https://github.com/settings/ssh/new Ã¢â€ â€™ paste the key Ã¢â€ â€™ **Add SSH key**

### Step 3 Ã¢â‚¬â€ Clone the repo

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
| Lab Portal | `http://<public_ip>` | Ã¢â‚¬â€ |
| Nexus Repository | `http://<public_ip>:8082` | admin / admin123 |
| IQ Server | `http://<public_ip>:8072` | admin / admin123 |
| Lab Tutor | Click **Ã°Å¸Â¤â€“ Use Lab Tutor** on portal, or **Ã°Å¸Â¤â€“ Lab Tutor** button on any product page | Ã¢â‚¬â€ |
| CloudWatch Logs | AWS Console Ã¢â€ â€™ CloudWatch Ã¢â€ â€™ Log groups | Ã¢â‚¬â€ |

Helper scripts:
- `open-nexus.ps1` Ã¢â‚¬â€ opens Nexus in your default browser
- `connect-perm.ps1` Ã¢â‚¬â€ starts an SSM shell session to the instance (no SSH key or open port 22 needed)
- `view-labs.ps1` Ã¢â‚¬â€ generates a local HTML dashboard showing all running labs with live countdowns


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
| `instance_type` | `t3.large` | EC2 type (minimum t3.large Ã¢â‚¬â€ 8GB RAM required) |
| `volume_size_gb` | `30` | Root EBS volume in GB |
| `ssm_parameter_path` | `/digital-labs/sonatype-license` | SSM path for license |
| `lab_name` | `digital-labs-instance` | EC2 Name tag |
| `lease_duration` | Ã¢â‚¬â€ | **Required.** `1w`, `2w`, `3w`, or `1mo` |
| `customer_email` | Ã¢â‚¬â€ | **Required.** Customer email for notifications |
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
| Anthropic API (Claude) | ~$0.01Ã¢â‚¬â€œ$0.05 per learner session (varies by usage) |
| SES email | ~$0.10 per 1,000 emails (negligible) |
| Lambda + EventBridge + S3 | Negligible (well within free tier) |

**Typical cost for a one-week lab: ~$14 + Anthropic usage**

---

## Architecture

```
Customer browser
      Ã¢â€â€š
      Ã¢â€“Â¼
  nginx :80
  Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ /           Ã¢â€ â€™ Lab Portal (countdown + product links + "Ã°Å¸Â¤â€“ Use Lab Tutor" button)
  Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ /tutor      Ã¢â€ â€™ Lab Tutor popup (standalone HTML)
  Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ /chat       Ã¢â€ â€™ Lab Tutor proxy :8090 Ã¢â€ â€™ Anthropic API (Claude, Learning Mode)

Proxied product ports (nginx sub_filter injects beacon into every HTML response):
  :8082  Ã¢â€ â€™ Nexus Repository CE (:8081)   Ã¢â‚¬â€ beacon mounts "Ã°Å¸Â¤â€“ Lab Tutor" button
  :8072  Ã¢â€ â€™ IQ Server / Lifecycle (:8070) Ã¢â‚¬â€ beacon mounts "Ã°Å¸Â¤â€“ Lab Tutor" button

Internal container ports (NOT exposed in security group Ã¢â‚¬â€ all browser access must go via nginx proxies above):
  :8081  Nexus Repository CE (internal only)
  :8070  IQ Server (internal only)
```

- EC2: `t3.large`, 30GB gp3, Amazon Linux 2023
- Containers: both run with `--restart=always`; stdout shipped to CloudWatch via `--log-driver awslogs` (`/digital-labs/nexus`, `/digital-labs/iq-server`). IQ Server also writes structured log files tailed by the CloudWatch agent (`/digital-labs/iq-audit`, `/digital-labs/iq-requests`, `/digital-labs/iq-server-app`). Nexus 3 is stdout-only Ã¢â‚¬â€ no file-based log tailing needed.
- Assets (portal HTML, proxy.py, tutor HTML) stored in S3 and downloaded at boot Ã¢â‚¬â€ keeps `user_data.sh` under the 16KB EC2 limit
- Lab Tutor proxy runs as `labclock` (no-login system user); env file `/etc/lab-tutor.env` is root:root 600
- License pulled from SSM at boot, base64-decoded, injected via IQ Server REST API (CSRF token flow)
- Claude API key pulled from SSM at boot, written to `/etc/lab-tutor.env`, injected via `EnvironmentFile=` in systemd Ã¢â‚¬â€ never exposed to browser or logs
- Initialization sequence: Docker install Ã¢â€ â€™ Nexus start Ã¢â€ â€™ IQ Server start Ã¢â€ â€™ license upload Ã¢â€ â€™ password set Ã¢â€ â€™ data seeding Ã¢â€ â€™ portal Ã¢â€ â€™ tutor Ã¢â€ â€™ nginx
- Auto-termination: two EventBridge one-shot schedules (T-48hr warning, T=0 termination) Ã¢â‚¬â€ self-delete after firing
- Email: AWS SES direct send Ã¢â‚¬â€ no customer confirmation step required
- Welcome Lambda polls `http://<ip>/` until 200 before sending email (up to 10 min), then sends regardless

---

## user_data.sh Boot Sequence

| Step | Action |
|---|---|
| 1 | IMDSv2 token + read `lab_key` and `termination_time` from instance tags + SSM |
| 2 | `dnf install docker zip python3 nginx` |
| 3 | Fetch `CLAUDE_API_KEY` from SSM `/digital-labs/claude-api-key` (trimmed, no whitespace) |
| 4 | Fetch `CLAUDE_API_KEY` from SSM `/digital-labs/claude-api-key`; base64-encode system prompt; write `/etc/lab-tutor.env` (root:root 600) |
| 5 | Start Nexus CE on port 8081 |
| 6 | Start IQ Server on ports 8070/8071 with license volume mount |
| 7 | Wait for IQ Server Ã¢â€ â€™ CSRF token Ã¢â€ â€™ POST license via REST API |
| 8 | Wait for Nexus Ã¢â€ â€™ read generated password Ã¢â€ â€™ set to `admin123` |
| 9 | Seed: `lab-blob-store`, `maven-hosted-lab`, `npm-hosted-lab`, `maven-proxy-central` |
| 10 | Seed: `sample-app` JAR + `@sonatype-lab/sample-lib` npm package |
| 11 | Deploy `countdown.html` from S3, `sed`-replace `TERMINATION_PLACEHOLDER` |
| 12 | Deploy `proxy.py` + `tutor.html` from S3 to `/opt/sonatype/tutor/` |
| 13 | Write `systemd lab-tutor.service` with `EnvironmentFile=/etc/lab-tutor.env` |
| 14 | Write `nginx conf.d/digital-labs.conf` with `/chat` and `/` routes |
| 15 | `systemctl enable --now lab-tutor nginx` |
| 16 | Install CloudWatch agent; write config to tail IQ Server `audit.log`, `request.log`, `clm-server.log`; start agent |

---

## Repo Structure

```
digital-labs/
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ main.tf                    # EC2, IAM, security group, S3 asset objects, module instantiation
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ variables.tf               # All input variables (single-lab and cohort modes)
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ backend.tf                 # S3 remote state config
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ cloudwatch.tf              # CloudWatch dashboard (per-lab metrics + container log tails)
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ cohort.tfvars.example      # Example multi-lab cohort deployment file
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ nginx-digital-labs.conf    # nginx port 80: /chat proxy, /tutor static, /lab-tutor-beacon.js, / portal
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ nginx-product-proxies.conf # nginx ports 8082 (Nexus) and 8072 (IQ): sub_filter beacon injection, proxy_redirect
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ nginx-browser-enforce.conf # nginx http-level UA map: blocks non-browser requests on all product ports
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ user_data.sh               # EC2 boot script (~240 lines)
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ modules/
Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ lab/
Ã¢â€â€š       Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ main.tf            # EC2 instance, SSM param, IMDSv2
Ã¢â€â€š       Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ lambda.tf          # Welcomer, notifier, terminator Lambda functions
Ã¢â€â€š       Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ eventbridge.tf     # Three one-shot EventBridge schedules per lab
Ã¢â€â€š       Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ variables.tf       # Module inputs
Ã¢â€â€š       Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ outputs.tf         # instance_id, public_ip, lab_url, nexus_url, iq_url, terminates_at
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ assets/
Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ countdown.html         # Lab portal (timer + product links + "Ã°Å¸Â¤â€“ Use Lab Tutor" button)
Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ proxy.py               # Lab Tutor HTTP proxy (port 8090, internal only)
Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ tutor.html             # Standalone Lab Tutor popup (/tutor) Ã¢â‚¬â€ polls localStorage for context
Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ lab-tutor-beacon.js    # Injected by nginx into Nexus + IQ pages; mounts button + pulses localStorage
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ lambda/
Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ welcomer.py            # Sends branded HTML welcome email via SES when portal is ready
Ã¢â€â€š   Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ notifier.py            # Sends branded HTML 48hr warning email via SES
Ã¢â€â€š   Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ terminator.py          # Terminates EC2 + cleans up all three schedules
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ view-labs.ps1              # Sonatype Personnel View Ã¢â‚¬â€ HTML dashboard from terraform output
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ open-nexus.ps1             # Opens Nexus in default browser
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ connect-perm.ps1           # Opens SSM shell session to running instance
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ setup-backend.ps1          # One-time: create S3 bucket for Terraform state
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ setup-license.ps1          # One-time: upload Sonatype license to SSM
Ã¢â€Å“Ã¢â€â‚¬Ã¢â€â‚¬ CUSTOMER_GUIDE.md          # Customer-facing user guide (no internal info)
Ã¢â€â€Ã¢â€â‚¬Ã¢â€â‚¬ CUSTOMER_GUIDE.pdf         # Branded PDF version of the customer guide
```

---

## Known Limitations

| Item | Detail | Workaround |
|---|---|---|
| IQ Server "change password" banner | IQ Server's admin password cannot be changed via REST API without a full form-based browser session (Basic Auth + CSRF simultaneously is rejected). The banner shows on every login. | Dismiss manually in the IQ Server UI after logging in, or accept as cosmetic for PoC use. Will be addressed in production by provisioning a non-default password via IQ's config file before container start. |
| HTTP only | All lab traffic is unencrypted. Custom domain + TLS blocked on IT DNS access. | Acceptable for internal PoC. **Do not enter real credentials.** Production deployment requires HTTPS. |
| Shared PoC instance | The current PoC runs a single shared EC2 instance. All testers see the same data. | Production deploys one isolated instance per customer. |

---

## Backlog

| Item | Status | Notes |
|---|---|---|
| Factory / cohort automation | Ã¢Å“â€¦ Done | `modules/lab/` with `for_each` Ã¢â‚¬â€ deploy N labs from one `terraform apply -var-file=cohort.tfvars` |
| SES HTML email | Ã¢Å“â€¦ Done | Branded HTML welcome + 48hr warning emails via SES |
| CloudWatch dashboard | Ã¢Å“â€¦ Done | `cloudwatch.tf` Ã¢â‚¬â€ per-lab Lambda + EC2 metrics + container log tails |
| Sonatype Personnel View | Ã¢Å“â€¦ Done | `view-labs.ps1` Ã¢â‚¬â€ local HTML dashboard from `terraform output` with live countdowns |
| SES production access | Ã¢Å“â€¦ Done | Approved March 2026 Ã¢â‚¬â€ 50,000 msg/day, sandbox lifted in us-east-1 |
| sonatype.com DKIM DNS | Ã¢Å“â€¦ Done | Verified in us-east-1, confirmed March 2026 |
| Lab Tutor AI chat | Ã¢Å“â€¦ Done | Popup architecture Ã¢â‚¬â€ beacon injected into Nexus + IQ via nginx sub_filter; raises handled exclusively by portal (card onclick + visibilitychange); beacon button uses single `window.open(TUTOR_URL,'LabTutor',feat)`; ownership heartbeat evicts stale windows in ~500ms; session-end detection via portal localStorage heartbeat |
| Security hardening | Ã¢Å“â€¦ Done | Prompt injection allowlist + sanitize; rate limit 10 req/min on `/chat`; CORS locked to same-origin; system prompt base64-encoded; IQ Server pinned to `1.201.0-02`; credentials removed from system prompt; ports 8081/8070 closed; Lambda scoped to `lab_key` tag; CloudWatch scoped to `/digital-labs/*` |
| CloudWatch telemetry | Ã¢Å“â€¦ Done | Nexus stdout Ã¢â€ â€™ `/digital-labs/nexus` via Docker `--log-driver awslogs`. IQ Server structured files Ã¢â€ â€™ `/digital-labs/iq-audit`, `/digital-labs/iq-requests`, `/digital-labs/iq-server-app` via CloudWatch agent (tails bind-mounted log dir) |
| Custom domain / HTTPS | Ã°Å¸â€Å“ Blocked | Requires DNS access Ã¢â‚¬â€ Route 53 + ACM cert for `https://labs.sonatype.com` |

---

## License

The Sonatype license is for **internal Sonatype use only**. Do not distribute or use in customer-facing environments without an appropriate commercial license.
