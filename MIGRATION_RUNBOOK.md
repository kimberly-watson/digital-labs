# Digital Labs: Migration to CS Account (216953896714)

This is a one-time setup. Once these steps are done, new labs are requested
through the portal, and nothing runs from your laptop again.

## 1. Create the state bucket in the new account

```powershell
aws s3 mb s3://digital-labs-tfstate-216953896714 --region us-east-1 --profile sonatype
aws s3api put-bucket-versioning --bucket digital-labs-tfstate-216953896714 --versioning-configuration Status=Enabled --profile sonatype
```

## 2. Re-upload the Sonatype license and Claude API key to SSM (new account, they do not carry over)

```powershell
aws ssm put-parameter --name "/digital-labs/sonatype-license" --type SecureString --value "<base64 license>" --profile sonatype
aws ssm put-parameter --name "/digital-labs/claude-api-key" --type SecureString --value "<key>" --profile sonatype
```

## 3. Verify the SES sending identity in the new account

SES identity verification (domain or address) does not carry across
accounts. Verify `digital-labs@sonatype.com` (or your chosen sender) in
SES in `216953896714`, us-east-1, before the first apply, or welcome and
warning emails will silently fail to send.

## 4. Set the real portal access code

Terraform creates the SSM parameter with a placeholder value on purpose
(so a real code never sits in a file that gets committed). Set it once by
hand:

```powershell
aws ssm put-parameter --name "/digital-labs/portal-access-code" --type SecureString --value "<a real shared code for staff>" --overwrite --profile sonatype
```

Share that code only with Sonatype staff who should be able to request
labs.

## 5. Give CodeBuild access to the GitHub repo

CodeBuild's `source` block points at
`https://github.com/kimberly-watson/digital-labs.git`. If the repo is
private, connect it once via the CodeBuild console (Source provider ->
GitHub -> OAuth or a personal access token), or add a
`aws_codebuild_source_credential` resource. Public repos need nothing
extra.

## 6. First apply (from your laptop, one last time)

Everything after this point runs itself. This one apply stands up the
portal, CodeBuild project, and DynamoDB table:

```powershell
terraform init -reconfigure
terraform apply -auto-approve
```

Note the `portal_url` output. That is the internal request form.

## 7. Decommission the old account (288833448839)

Once you have confirmed a lab requested through the new portal works end
to end, tear down the old single-account setup:

```powershell
# from the OLD repo checkout, pointed at the old backend/state
terraform destroy -auto-approve
```

Leave the old state bucket alone until you are confident nothing still
references it.

## What is intentionally NOT done yet

- **Auth is a shared access code, not real identity.** Fine for "Sonatype
  staff only, to start." Before this goes anywhere near customers directly,
  replace the access-code check in `lambda/request_handler.py` with
  Cognito or your SSO provider.
- **CodeBuild's IAM role is broad** (`ec2:*`, `iam:*`, etc.) because it is
  standing in for the admin-level SSO role you were applying with by hand.
  Worth tightening to the specific actions Terraform actually calls once
  the new flow has run a few times without surprises.
- **Old-account labs already running** are not migrated. They will
  continue on their existing lease and auto-terminate as scheduled in
  `288833448839`. Only new requests go through the new portal.
