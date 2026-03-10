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
| **Lab Tutor** | Port 8090 (internal) — Claude-powered chat proxy, surfaced as a floating bubble on the portal |
| **nginx** | Reverse proxy on port 80 — routes `/chat` to tutor proxy, `/` to portal |
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
terraform apply -var="customer_email=customer@example.com" -var="lease_duration=2w"
```

> `customer_email` is required and validated. Terraform rejects blank or malformed addresses.

The customer receives a **single welcome email** with one URL. No confirmation step, no AWS access, no Terraform.

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
2. Add the DNS records AWS provides (TXT + CNAME for DKIM)
3. AWS Console → **SES > Account dashboard > Request production access**
   - New accounts start in sandbox and can only send to verified addresses
   - Production access is typically approved within a few hours

> Once approved, all lab emails send automatically with no customer action required.
> The sender address can be changed via the `ses_from_email` variable (default: `digital-labs@sonatype.com`).

### Step 5 — Store Claude API key in SSM

The Lab Tutor requires a Claude API key stored in SSM Parameter Store. Run once:

```powershell
aws ssm put-parameter `
  --name "/digital-labs/claude-api-key" `
  --value "sk-ant-..." `
  --type "SecureString" `
  --region us-east-1
```

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
| Nexus Repository | `http://<public_ip>:8081` | admin / admin123 |
| IQ Server | `http://<public_ip>:8070` | admin / admin123 |
| CloudWatch Logs | AWS Console → CloudWatch → Log groups | — |

Helper scripts:
- `open-nexus.ps1` — opens Nexus in your default browser
- `connect-perm.ps1` — starts an SSM shell session to the instance (no SSH key or open port 22 needed)

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
| SES email | ~$0.10 per 1,000 emails (negligible) |
| Lambda + EventBridge + S3 | Negligible (well within free tier) |

**Typical cost for a one-week lab: ~$14**

---

## Architecture

```
Customer browser
      │
      ▼
  nginx :80
  ├── /        → Lab Portal (countdown + links + AI chat bubble) :8080
  └── /chat    → Lab Tutor proxy :8090 → Anthropic API (Claude)

Direct port access:
  :8081  Nexus Repository CE
  :8070  IQ Server / Lifecycle / Firewall
```

- EC2: `t3.large`, 30GB gp3, Amazon Linux 2023
- Containers: both run with `--restart=always` and ship logs to CloudWatch via `--log-driver awslogs`
- Assets (portal HTML, proxy.py, tutor HTML) stored in S3 and downloaded at boot — keeps `user_data.sh` under the 16KB EC2 limit
- Countdown service and tutor proxy run as `labclock` (no-login system user), `chmod 500/400`
- License pulled from SSM at boot, base64-decoded, injected via IQ Server REST API (CSRF token flow)
- Claude API key pulled from SSM at boot, injected as env var into `lab-tutor.service` — never exposed to browser
- Initialization sequence: Docker install → Nexus start → IQ Server start → license upload → password set → data seeding → portal → tutor → nginx
- Auto-termination: two EventBridge one-shot schedules (T-48hr warning, T=0 termination) — self-delete after firing
- Email: AWS SES direct send — no customer confirmation step required
- Welcome Lambda polls `http://<ip>/` until 200 before sending email (up to 10 min), then sends regardless

---

## Repo Structure

```
digital-labs/
├── main.tf                    # EC2, IAM, security group, S3 asset objects, module instantiation
├── variables.tf               # All input variables (single-lab and cohort modes)
├── backend.tf                 # S3 remote state config (use_lockfile)
├── cloudwatch.tf              # CloudWatch dashboard (per-lab metrics + container log tails)
├── cohort.tfvars.example      # Example multi-lab cohort deployment file
├── user_data.sh               # EC2 boot script (~240 lines)
├── modules/
│   └── lab/
│       ├── main.tf            # EC2 instance, SSM param, IMDSv2
│       ├── lambda.tf          # Welcomer, notifier, terminator Lambda functions
│       ├── eventbridge.tf     # Three one-shot EventBridge schedules per lab
│       ├── variables.tf       # Module inputs
│       └── outputs.tf         # instance_id, public_ip, lab_url, nexus_url, iq_url, terminates_at
├── assets/
│   ├── countdown.html         # Lab portal (timer + links + AI chat bubble)
│   ├── proxy.py               # Lab tutor HTTP proxy (port 8090, internal only)
│   └── tutor.html             # Standalone tutor page
├── lambda/
│   ├── welcomer.py            # Sends branded HTML welcome email via SES when portal is ready
│   ├── notifier.py            # Sends branded HTML 48hr warning email via SES
│   └── terminator.py          # Terminates EC2 + cleans up all three schedules
├── view-labs.ps1              # Sonatype Personnel View — generates HTML dashboard from terraform output
├── open-nexus.ps1             # Opens Nexus in default browser
├── connect-perm.ps1           # Opens SSM shell session to running instance
├── setup-backend.ps1          # One-time: create S3 bucket for Terraform state
├── setup-license.ps1          # One-time: upload Sonatype license to SSM
└── CUSTOMER_GUIDE.md          # Customer-facing user guide (no internal info)
```

---

## Backlog

| Item | Status | Notes |
|---|---|---|
| Factory / cohort automation | ✅ Done | `modules/lab/` with `for_each` — deploy N labs from one `terraform apply -var-file=cohort.tfvars` |
| SES HTML email | ✅ Done | Branded HTML welcome + 48hr warning emails via SES |
| CloudWatch dashboard | ✅ Done | `cloudwatch.tf` — per-lab Lambda + EC2 metrics + container log tails |
| Sonatype Personnel View | ✅ Done | `view-labs.ps1` — local HTML dashboard from `terraform output` with live countdowns |
| SES production access | ⏳ Pending | AWS case 177316227900889 — detailed reply sent, awaiting approval |
| sonatype.com DKIM DNS | ⏳ Pending | 3 CNAME records submitted to IT — awaiting DNS propagation |
| Custom domain / HTTPS | 🔜 Blocked | Requires DNS access — Route53 + ACM cert for `https://labs.sonatype.com` |

---

## License

The Sonatype license is for **internal Sonatype use only**. Do not distribute or use in customer-facing environments without an appropriate commercial license.
