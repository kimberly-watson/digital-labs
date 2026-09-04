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
| Wiz Runtime Sensor | - | Required by Sonatype InfoSec on all EC2 deployments (replaces Twistlock/Prisma). Installed at boot, before Docker. Credentials read from InfoSec's centrally-managed Secrets Manager secret (cross-account), never stored locally. |
| CloudWatch agent | - | Tails Nexus stdout and IQ Server audit/request/app logs |

Default credentials: `admin` / `admin123`. Lease options: 1w, 2w, 3w, 1mo.

## 4. Request Portal (New)

Live URL: https://4sz18w8vqh.execute-api.us-east-1.amazonaws.com/

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
- IQ Server pinned to version 1.203.3 (updated 2026-09-04; the prior
  pin, 1.201.0-02, was removed from Docker Hub)
- Ports 8081 and 8070 (raw Nexus/IQ) never exposed publicly, only the
  nginx-proxied 8082/8072
- Portal access code is a stopgap, not production-grade auth (see
  Section 4)
- All lab traffic is HTTP, not HTTPS. Do not enter real credentials into
  a lab. Custom domain and TLS blocked pending Route 53/ACM setup.

## 10. Known Limitations

| Item | Detail |
|---|---|
| ~~IQ Server image tag 1.201.0-02 no longer exists~~ | **Fixed 2026-09-04.** The originally pinned tag was removed from Docker Hub entirely (unrelated to the pivot; would have broken eventually regardless). `docker run` failed with `manifest unknown`, and because `provision.sh` runs under `set -e`, the whole boot aborted immediately after, leaving nginx, the portal, and Lab Tutor never installed. Repinned to `1.203.3`, the oldest currently available tag. |
| ~~IQ Server crash loop on 1.203.3~~ | **Fixed 2026-09-04.** Root cause found via CloudWatch (not `docker logs`, which is empty — the container uses `--log-driver awslogs`): `Permission denied` writing to `/var/log/nexus-iq-server/stderr.log`. 1.203.3 runs as a non-root user, unlike 1.201.0-02. Fixed with `chmod 777` on the host log directory before `docker run`. |
| ~~IQ Server seeding (org/app/vuln scan) fails silently~~ | **Fixed 2026-09-04.** Root cause: org/app/scan creation calls only sent Basic Auth, unlike the license upload step, which first fetches a CSRF cookie and sends it back with an `X-CLM-CSRF-TOKEN` header. IQ Server rejects write requests without that. Applied the same cookie/CSRF pattern to org creation, app creation, and scan submission, and added response logging so a future failure is visible instead of silent. Not yet verified end to end on a fresh instance. |
| ~~user_data.sh exceeds 16KB EC2 limit~~ | **Fixed 2026-09-04.** Split into a minimal user_data.sh (1,317 bytes) that downloads and runs assets/provision.sh (20,363 bytes) from S3 at boot. |
| IQ Server password banner | Cannot be cleared via REST API alone. Cosmetic for PoC. |
| HTTP only | No TLS. Acceptable for internal PoC only. |
| Shared PoC instance model | Each lab is its own EC2 instance per `lab_key`, but the underlying AMI/boot process is shared and not yet hardened for high volume. |
| Portal auth | Shared code, not per-user identity. |
| ~~IQ Server password/base-URL banners visible to students~~ | **Fixed 2026-09-04.** Base URL: fixed via IQ Server's documented Configuration REST API (`PUT /api/v2/config`), set right after license install. Password: IQ Server has no REST API for a user to change their own password (unlike Nexus), so this uses Playwright browser automation to drive the actual "Change Password" UI flow — selectors captured live against a running 1.203.3 instance. Changed both Nexus's and IQ Server's admin password to the same new value (`SonatypeLab2026!`, was `admin123`) to keep one unified login for students, since the lab shows a single shared credential, not per-product ones. Non-fatal: if the browser automation fails, the lab still boots and the banner just remains. Requires installing Playwright + Chromium on every boot (python3-pip, playwright, chromium, several dnf packages since Playwright's `--with-deps` doesn't support Amazon Linux) — adds real boot time. |
| Old-account labs | Labs already running in 288833448839 are not migrated; they finish their existing lease there. |
| ~~License needs SBOM Manager excluded~~ | **Resolved 2026-09-04.** Third license (c1cadd34-aed6-443a-879a-ea4ea54c2a65, expires 2027/08/01, no SBOM Manager entitlement) passed signature verification and installed successfully — confirmed via `GET /api/v2/solutions/licensed` returning `[]` (empty = no unlicensed features) instead of the prior 402 error. Stored in SSM (`/digital-labs/sonatype-license`, version 4), so every future lab created through the portal picks it up automatically at boot with no further changes needed. |
| Wiz sensor install is non-fatal | If Wiz credentials can't be retrieved or the sensor install fails, provision.sh logs a warning and continues booting the lab rather than aborting. This is a deliberate tradeoff: InfoSec requires the sensor, but a customer lab shouldn't fail entirely because a security agent couldn't reach its backend. Worth revisiting with InfoSec if this needs to be a hard requirement instead. |

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

- 2026-09-04: Fixed the IQ Server "base URL not configured" and "change
  administrator password" banners students were seeing. Base URL set via
  IQ Server's Configuration REST API. Password: added Playwright browser
  automation (IQ Server has no API for this) to drive the real UI
  password-change flow, with selectors verified live against a running
  instance. Changed the shared admin password from admin123 to
  SonatypeLab2026! for both Nexus and IQ Server (one unified login,
  matching how credentials are shown to students), updating
  countdown.html, welcomer.py, README.md, and CUSTOMER_GUIDE.md
  accordingly. The Playwright install is a real addition to boot time
  and non-fatal by design.
- 2026-09-04: License issue resolved. Third license (c1cadd34-aed6-443a-
  879a-ea4ea54c2a65, no SBOM Manager) passed signature verification and
  installed successfully on the running instance, confirmed via
  GET /api/v2/solutions/licensed returning [] instead of a 402 error.
  Stored in SSM (version 4) — all future portal-created labs get this
  license automatically. This is the first Terraform apply/test done
  using direct Windows PowerShell execution (Windows-MCP) rather than
  relaying commands through the person.
- 2026-09-04: Tested a second renewed license (0365ab49-ff9a-45e1-b4fe-
  1080cd509ca5). Passed signature verification (progress over the first
  attempt), but rejected because it includes SBOM Manager, which requires
  an external database IQ Server isn't configured with in this
  environment. Decided to request a license without SBOM Manager for lab
  use rather than add external DB infrastructure. Not yet obtained.
- 2026-09-04: Added Wiz Runtime Sensor, required by Sonatype InfoSec on
  all EC2 deployments (Confluence SEC space, "EC2/AMI Deployment
  Instruction", v1.1, 2026-09-03). Added IAM policy granting lab instances
  secretsmanager:GetSecretValue and kms:Decrypt on InfoSec's centrally
  managed Wiz credentials (cross-account, 193494411491). Added sensor
  install to provision.sh, before Docker setup. Install failures are
  non-fatal (see Known Limitations) so a lab still boots if Wiz is
  unreachable. Not yet verified end to end.
- 2026-09-04: Fixed IQ Server seeding CSRF bug. Org/app/scan creation
  calls only sent Basic Auth, unlike the license upload step which fetches
  a CSRF cookie first. Applied the same cookie/X-CLM-CSRF-TOKEN pattern to
  all three write calls in the seeding block, and added response logging
  (org/app/scan response bodies) so a future failure is visible instead of
  silent. Not yet verified end to end.
- 2026-09-04: Confirmed full pipeline working end to end on a fresh
  instance (i-0446028bceb0c1ed3): portal submission, DynamoDB, CodeBuild,
  Terraform apply, EC2 boot, Nexus, IQ Server, nginx, and Lab Tutor all
  functioning. Remaining known items: IQ Server license needs a renewed
  file from Sonatype's license source (not yet obtained); no TLS (known,
  out of scope for today, blocked on Route 53/ACM per Section 9).
- 2026-09-04: Fixed Lab Tutor 404. Two bugs: (1) lab-tutor-beacon.js was
  never downloaded to /var/www/html/ anywhere in provision.sh, only
  lab-tutor-widget.js was; added the missing download. (2) nginx's
  /tutor location aliased a static file (/var/www/html/tutor.html) that
  is never created there — proxy.py actually serves the HTML directly on
  any GET request to port 8090. Changed the location to proxy_pass
  instead of alias.
- 2026-09-04: Fixed missing S3 asset uploads. lab-tutor-widget.js and
  lab-tutor-beacon.js were never registered as aws_s3_object resources
  in Terraform (unlike countdown.html, tutor.html, provision.sh), so
  they never existed in the new account's S3 bucket. provision.sh's
  fetch of lab-tutor-widget.js failed with 403 (S3 returns 403 rather
  than 404 for a HeadObject on a missing key when the caller lacks
  ListBucket, to avoid leaking existence). Added both as proper
  Terraform-managed uploads.
- 2026-09-04: Fixed IQ Server crash loop on 1.203.3. Found via CloudWatch
  (not docker logs, which is empty because the container uses --log-driver
  awslogs): "Permission denied" writing to
  /var/log/nexus-iq-server/stderr.log. The 1.203.3 image runs as a
  non-root user, unlike 1.201.0-02. Fixed with chmod 777 on the host log
  directory before docker run.
- 2026-09-04: **Incident:** a local `terraform apply` with no var-file
  destroyed the test lab (lab-9f1ec74c, instance i-01c61e6fd6c4a89c6).
  Root cause: local applies default to zero labs while CodeBuild always
  passes the full DynamoDB-derived cohort; running apply locally without
  that var-file tells Terraform every existing lab should be destroyed.
  No production labs existed yet, so impact was limited to the one test
  instance. Documented the required command sequence for any future local
  apply in MIGRATION_RUNBOOK.md. Considering a stronger structural fix
  (e.g. a lifecycle prevent_destroy on module.lab, or a wrapper script
  that's the only sanctioned way to run apply locally) as a follow-up.
- 2026-09-04: Fixed dead IQ Server Docker tag. sonatype/nexus-iq-server:
  1.201.0-02 no longer exists on Docker Hub (confirmed via tag list API);
  docker run failed with "manifest unknown", and set -e aborted the rest
  of provision.sh (nginx, portal, Lab Tutor never installed). Repinned to
  1.203.3, the oldest currently available tag. Not yet verified this
  version behaves identically to the original for licensing/seeding.
- 2026-09-04: Broadened CodeBuild IAM policy to dynamodb:*, added
  apigateway:*, added codebuild:* (Terraform re-applies the entire config
  each run, including the DynamoDB table and API Gateway resources
  themselves, so the role needs full access to those services, not just
  the narrow item-level DynamoDB actions originally granted).
- 2026-09-04: Fixed CodeBuild Terraform version. buildspec.yml pinned
  1.9.8, which doesn't support `use_lockfile` in the S3 backend block
  (requires 1.10+). Bumped to 1.14.5 to match the version used locally.
- 2026-09-04: Bootstrap apply completed successfully. Portal live at
  https://4sz18w8vqh.execute-api.us-east-1.amazonaws.com/. All
  infrastructure (portal Lambda, API Gateway, CodeBuild project, DynamoDB
  request queue, CloudWatch dashboard) created in 216953896714. Zero EC2
  instances exist at this point, as expected.
- 2026-09-04: Fixed the 16KB user_data.sh bug. Split into a minimal
  user_data.sh (fetches boot variables, downloads provision.sh from S3,
  executes it) and assets/provision.sh (the full Docker/Nexus/IQ/nginx/
  Lab Tutor/CloudWatch setup, uploaded to S3 with no size limit). Added
  aws_s3_object.provision_sh to main.tf and to the module's depends_on
  list.
- 2026-09-04: Fixed main.tf locals so the bootstrap apply (no customer_email,
  no labs map) creates zero lab instances instead of one stray "default"
  lab with a blank customer email.
- 2026-09-04: Discovered user_data.sh is 21,408 bytes, over EC2's 16,384-byte
  user_data limit. Blocks all lab creation until fixed. See Known
  Limitations.
- 2026-09-04: SES sender temporarily switched to kimberly.watson@sonatype.com
  (verified directly) until mailbox access for digital-labs@sonatype.com is
  confirmed and that address is re-verified in 216953896714.
- 2026-09-03: Initial pivot from single-account/laptop-triggered model to
  CS account (216953896714) with portal, DynamoDB request queue, and
  CodeBuild-based provisioning.
