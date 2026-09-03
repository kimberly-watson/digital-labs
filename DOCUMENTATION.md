# Digital Labs: Full Functionality Documentation

Last updated: 2026-09-03

This document covers every component of Digital Labs as it exists after
the pivot to the CS AWS account. It is updated each time functionality
changes.

---

## 1. What Digital Labs Is

An automated AWS lab environment. One EC2 instance runs the full Sonatype
product suite (Nexus Repository CE, IQ Server Lifecycle and Firewall) via
Docker. Sonatype staff request a lab through an internal web portal; the
lab provisions itself, emails the customer, and auto-terminates at the end
of its lease. No step in that chain runs from anyone's laptop.

## 2. AWS Account and Region

- Account: 216953896714 (CS AWS space, same account as CEDA/CE Pipeline)
- Region: us-east-1
- Access: Company SSO, profile name `sonatype` locally, role
  `AWSReservedSSO_CSAdministratorAccess`

## 3. Components Running on the EC2 Instance

| Component | Port | Detail |
|---|---|---|
| Nexus Repository CE | 8082 (proxy to 8081) | Hosted Maven and npm repos, Maven Central proxy, seeded sample artifacts |
| IQ Server (Lifecycle + Firewall) | 8072 (proxy to 8070) | All 7 products licensed automatically at boot |
| Lab Portal | 80 | Countdown timer, product links, embedded AI tutor |
| Lab Tutor | 8090 (internal only) | Claude-powered chat proxy, Learning Mode |
| nginx | 80, 8082, 8072 | Reverse proxy, beacon injection, rate limiting |
| CloudWatch agent | - | Tails Nexus stdout and IQ Server audit/request/app logs |

Default credentials: `admin` / `admin123`. Lease options: 1w, 2w, 3w, 1mo.

## 4. Request Portal (New)

Internal-only web form. Staff enter an access code, customer email, and
lease duration.

- Frontend and backend: single Lambda function `digital-labs-portal`,
  serving HTML on GET and handling submission on POST
- Fronted by API Gateway (HTTP API), URL is the `portal_url` Terraform
  output
- Auth: shared access code, checked against SSM parameter
  `/digital-labs/portal-access-code`. This is a stopgap for staff-only
  use. Not real identity-based auth. Replace with Cognito or SSO before
  any customer-facing exposure.
- On submit: writes a request to DynamoDB, starts a CodeBuild run,
  returns a confirmation page with the generated lab_key

## 5. Request Queue (New)

DynamoDB table `digital-labs-requests`. Every request ever submitted is
a row here (`lab_key`, `customer_email`, `lease_duration`, `requested_at`,
`status`). Status moves from `pending` to `provisioned` once
`terraform apply` succeeds. This table is the single source of truth for
which labs exist. It replaces tracking lab keys by hand across separate
Terraform runs.

## 6. Provisioning (New)

CodeBuild project `digital-labs-provisioner` runs `terraform apply`
server-side.

1. Pulls the repo fresh from GitHub (`kimberly-watson/digital-labs`)
2. Runs `scripts/build_cohort_vars.py`, which scans DynamoDB for every
   non-terminated request and writes `cohort.auto.tfvars.json`
3. Runs `terraform init` and `terraform apply -auto-approve
   -var-file=cohort.auto.tfvars.json`
4. Runs `scripts/mark_requests_provisioned.py`, flipping newly-applied
   requests to `provisioned`

IAM role `digital-labs-codebuild-exec` holds broad permissions
(`ec2:*`, `iam:*`, `lambda:*`, etc.) because it stands in for the
admin-level SSO role that used to run these applies by hand. Flagged in
the runbook as a candidate for tightening later.

## 7. Lab Lifecycle (Unchanged)

| Event | Trigger | What happens |
|---|---|---|
| Deploy | CodeBuild applies Terraform | EC2 provisions, services start (about 10 minutes) |
| Welcome email | T+0, Lambda polls until portal is live | Customer receives lab URL and credentials via SES |
| 48hr warning | T-48hr, EventBridge schedule | Warning email sent via SES |
| Expiry | Lease end, EventBridge schedule | EC2 terminated, schedules self-delete |

Lambdas: `welcomer.py`, `notifier.py`, `terminator.py`. Unchanged from the
original design, now running in 216953896714.

## 8. Lab Tutor

AI assistant embedded in the lab, powered by Claude via the Anthropic API
(key stored in SSM, injected at boot, never exposed to browser or logs).
Operates in Learning Mode: guides through questions and hints rather than
giving direct answers.

Architecture detail (Chrome 88+ `noopener` constraint and how popup
raising is handled) is unchanged from the original design; see README.md
in the repo for the full sequence diagram.

## 9. Security Notes

- Prompt injection allowlist and sanitization on the tutor chat endpoint
- Rate limit: 10 req/min on `/chat`
- CORS locked to same-origin
- System prompt base64-encoded
- IQ Server pinned to version 1.201.0-02
- Ports 8081 and 8070 (raw Nexus/IQ) never exposed publicly, only the
  nginx-proxied 8082/8072
- Portal access code is a stopgap, not production-grade auth (see
  Section 4)
- All lab traffic is HTTP, not HTTPS. Do not enter real credentials into
  a lab. Custom domain and TLS blocked pending Route 53/ACM setup.

## 10. Known Limitations

| Item | Detail |
|---|---|
| IQ Server password banner | Cannot be cleared via REST API alone. Cosmetic for PoC. |
| HTTP only | No TLS. Acceptable for internal PoC only. |
| Shared PoC instance model | Each lab is its own EC2 instance per `lab_key`, but the underlying AMI/boot process is shared and not yet hardened for high volume. |
| Portal auth | Shared code, not per-user identity. |
| Old-account labs | Labs already running in 288833448839 are not migrated; they finish their existing lease there. |

## 11. Testing

See the day's task list for step-by-step commands. Summary of what to
verify after any change:

1. `terraform validate` before any apply
2. Bootstrap apply succeeds and produces a `portal_url` output
3. Portal Lambda handles GET/POST correctly under invalid input
   (wrong access code, malformed email, invalid lease) without reaching
   CodeBuild
4. A real test submission produces a DynamoDB row, a running CodeBuild
   build, a live EC2 instance, and a welcome email
5. Terminator Lambda successfully tears down a test instance on demand
   (no need to wait a full lease period)

## 12. Change Log

- 2026-09-04: SES sender temporarily switched to kimberly.watson@sonatype.com
  (verified directly) until mailbox access for digital-labs@sonatype.com is
  confirmed and that address is re-verified in 216953896714.
- 2026-09-03: Initial pivot from single-account/laptop-triggered model to
  CS account (216953896714) with portal, DynamoDB request queue, and
  CodeBuild-based provisioning.
