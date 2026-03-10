# Sonatype Digital Labs

Automated AWS lab environment that provisions a full Sonatype product suite on a single EC2 instance via Docker. Used by Sonatype personnel to deploy hands-on product training environments for customers.

> **Important:** Each deployment requires its own AWS account. Do not use someone else's account -- you will incur charges on their behalf. See [AWS Account Setup](#aws-account-setup) below.

---

## What Gets Deployed

| Product | Port | Notes |
|---|---|---|
| Nexus Repository CE | 8081 | Hosted Maven + npm repos, Maven Central proxy |
| IQ Server (Lifecycle) | 8070 | All 7 products licensed automatically |
| IQ Server (Firewall) | 8070 | Included in IQ Server container |

**Default credentials:** `admin` / `admin123` (internal use only -- do not expose publicly)

**Seeded repositories:**
- `maven-hosted-lab` -- sample Maven artifact (`com.sonatype.lab:sample-app:1.0.0`)
- `npm-hosted-lab` -- sample npm package (`@sonatype-lab/sample-lib:1.0.0`)
- `maven-proxy-central` -- proxy to Maven Central

---

## Lab Lifecycle (Sonatype Personnel)

Labs are deployed with a fixed lease period. Auto-termination and customer notifications are fully automated -- no manual steps required after `terraform apply`.

| Event | Who | What Happens |
|---|---|---|
| Deploy | Sonatype | `terraform apply` with `lease_duration` and `customer_email` set |
| Confirmation | Customer | SNS subscription confirmation email arrives -- customer must click to confirm |
| T-48hr | Automated | Warning email sent to customer via SNS Lambda |
| Expiry | Automated | EC2 instance terminated, EventBridge schedules deleted |

**Lease options:** `1w`, `2w`, `3w`, `1mo` -- set by Sonatype personnel at deploy time. Customers never see or configure this value.

### Deploying a Customer Lab

```powershell
terraform apply -var="customer_email=customer@example.com" -var="lease_duration=2w"
```

> `customer_email` is required and must be a valid address. Terraform will reject blank values.

The customer will receive:
1. An SNS subscription confirmation email immediately after deploy (they must click the link)
2. A 48-hour warning email before the lab expires
3. No AWS console access, no Terraform, no credentials

---

## AWS Account Setup

You must have your own AWS account with the AWS CLI configured before proceeding.

### Step 1 -- Create an AWS account

Sign up at https://aws.amazon.com if you do not already have one.

### Step 2 -- Create an IAM user with programmatic access

1. Sign into the AWS Console at https://console.aws.amazon.com
2. Go to **IAM > Users > Create user**
3. Username: `digital-labs-cli` (or any name you prefer)
4. On the **Permissions** step, choose **Attach policies directly** and add:
   - `AmazonEC2FullAccess`
   - `IAMFullAccess`
   - `AmazonSSMFullAccess`
   - `AmazonSNSFullAccess`
   - `AWSLambda_FullAccess`
   - `AmazonEventBridgeSchedulerFullAccess`
5. Click through to **Create user**
6. Click the user > **Security credentials** tab > **Create access key**
7. Choose **Command Line Interface (CLI)**
8. Copy or download the Access Key ID and Secret Access Key -- you cannot retrieve the secret again

### Step 3 -- Install and configure the AWS CLI

Download from: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html

Then run:
```powershell
aws configure
```

Enter your credentials when prompted:
```
AWS Access Key ID:     <paste your access key>
AWS Secret Access Key: <paste your secret key>
Default region name:   us-east-1
Default output format: json
```

Verify it works:
```powershell
aws sts get-caller-identity
```

---

## Prerequisites

1. AWS CLI configured (see above)
2. Terraform -- https://developer.hashicorp.com/terraform/install -- version 1.x or higher
3. Sonatype license file -- a valid `.lic` file covering the full suite (RM, LC, FW, FWFA, ADP, ALP, IACP)
4. Git with SSH configured (see SSH Setup below)

---

## SSH Setup

This repo uses SSH for Git authentication. Each contributor needs to generate an SSH key and add it to their GitHub account once.

### Step 1 -- Generate an SSH key

```powershell
ssh-keygen -t ed25519 -C "your.name@sonatype.com" -f "$env:USERPROFILE\.ssh\id_ed25519" -N ''
```

### Step 2 -- Copy your public key

```powershell
Get-Content "$env:USERPROFILE\.ssh\id_ed25519.pub"
```

### Step 3 -- Add to GitHub

1. Go to https://github.com/settings/ssh/new
2. Title: your name or machine name
3. Key type: `Authentication Key`
4. Paste the full public key output
5. Click **Add SSH key**

### Step 4 -- Clone using SSH

```powershell
git clone git@github.com:kimberly-watson/digital-labs.git
cd digital-labs
```

---

## First-Time Setup

### Step 1 -- Store your license in AWS SSM

Run this once per AWS account. It base64-encodes your `.lic` file and stores it securely in SSM Parameter Store.

```powershell
.\setup-license.ps1 -LicensePath "C:\path\to\your-license.lic"
```

Optional parameters:
```powershell
.\setup-license.ps1 -LicensePath "C:\path\to\your-license.lic" -Region "us-west-2" -ParameterPath "/my-team/sonatype-license"
```

> **Note:** Uses SSM Advanced tier (~$0.05/month). Required because the encoded license exceeds the 4096-character Standard limit.

### Step 2 -- Initialize Terraform

```powershell
terraform init
```

### Step 3 -- Deploy

```powershell
terraform apply -var="customer_email=customer@example.com" -var="lease_duration=1w"
```

Terraform will output the instance ID and public IP. Full provisioning takes approximately **10 minutes**.

---

## Accessing the Lab

| Interface | URL | Credentials |
|---|---|---|
| Nexus Repository | `http://<public_ip>:8081` | admin / admin123 |
| IQ Server | `http://<public_ip>:8070` | admin / admin123 |

Helper scripts:
- `open-nexus.ps1` -- opens Nexus in your default browser
- `connect-perm.ps1` -- starts an SSM shell session to the instance

---

## Configuration

All configurable values are in `variables.tf`. Override defaults by creating a `terraform.tfvars` file in the repo root:

```hcl
# terraform.tfvars -- do NOT commit this file
aws_region         = "us-west-2"
instance_type      = "t3.xlarge"
ssm_parameter_path = "/my-team/sonatype-license"
lab_name           = "my-lab-instance"
```

| Variable | Default | Description |
|---|---|---|
| `aws_region` | `us-east-1` | AWS region to deploy into |
| `instance_type` | `t3.large` | EC2 instance type (minimum t3.large -- 8GB RAM required) |
| `volume_size_gb` | `30` | Root EBS volume size in GB |
| `ssm_parameter_path` | `/digital-labs/sonatype-license` | SSM path where your license is stored |
| `lab_name` | `digital-labs-instance` | Name tag applied to the EC2 instance |
| `lease_duration` | `1w` | Lab lease period: `1w`, `2w`, `3w`, or `1mo`. Set by Sonatype personnel. |
| `customer_email` | *(required)* | Customer email for expiry notifications. Must be a valid address. |

---

## Tearing Down

**Always destroy your instance when you are done.** A running `t3.large` costs approximately $0.08/hr. Labs with active leases will auto-terminate at expiry, but manual teardown is faster.

```powershell
terraform destroy
```

This removes the EC2 instance, Lambda functions, EventBridge schedules, and SNS topic. Your SSM license parameter is **not** deleted and can be reused for future deployments.

---

## Cost Estimate

| Resource | Cost |
|---|---|
| EC2 t3.large (us-east-1) | ~$0.08/hr (~$1.92/day if left running) |
| 30GB gp3 EBS | ~$2.40/month |
| SSM Advanced Parameter | ~$0.05/month |
| Lambda + EventBridge | Negligible (well within free tier) |
| SNS email notifications | Free (first 1,000/month) |

**Typical cost for a one-week lab: ~$14**

---

## License

The Sonatype license is for **internal Sonatype use only**. Do not distribute or use in customer-facing environments without an appropriate commercial license.

License expiry: **August 1, 2026** -- renew by re-running `setup-license.ps1` with an updated `.lic` file. No Terraform changes required.

---

## Architecture Notes

- Instance: `t3.large` (2 vCPU, 8GB RAM), 30GB gp3 EBS
- Both products run as Docker containers with `--restart=always`
- License pulled from SSM at boot, base64-decoded, injected via IQ Server REST API
- IQ Server license endpoint: `POST /api/v2/product/license` (CSRF token flow required)
- Initialization: Nexus (~2 min) > IQ Server (~3 min) > data seeding (~30 sec)
- Shell access via SSM Session Manager -- no SSH key or open port 22 needed
- Auto-termination via two EventBridge one-shot schedules (warning at T-48hr, termination at lease expiry)
- Notification via SNS email topic -- customer must confirm subscription after first deploy
- Lambda functions named with instance ID suffix and self-clean schedules after firing
