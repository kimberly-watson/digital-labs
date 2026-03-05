# start-lab.ps1
# Creates (or ensures) the lab is up, then connects via SSM.

$ErrorActionPreference = "Stop"

Write-Host "`n[1/5] Verifying tools..."
terraform -version | Out-Host
aws --version | Out-Host

Write-Host "`n[2/5] Verifying AWS identity..."
aws sts get-caller-identity | Out-Host

Write-Host "`n[3/5] Initializing Terraform (safe to re-run)..."
terraform init -input=false | Out-Host

Write-Host "`n[4/5] Applying Terraform (creating/updating lab)..."
terraform apply -auto-approve | Out-Host

Write-Host "`n[5/5] Fetching instance id from Terraform output..."
$iid = terraform output -raw instance_id

if ([string]::IsNullOrWhiteSpace($iid)) {
  throw "Terraform output 'instance_id' is empty. Ensure output is defined in main.tf and run terraform refresh."
}

Write-Host "InstanceId: $iid"

Write-Host "`nWaiting for EC2 instance status checks to be OK..."
# Poll EC2 status checks until SystemStatus and InstanceStatus are OK
for ($i = 0; $i -lt 30; $i++) {
  $status = aws ec2 describe-instance-status --instance-ids $iid --include-all-instances `
    --query "InstanceStatuses[0].[InstanceState.Name,SystemStatus.Status,InstanceStatus.Status]" --output text

  if ($status -match "running\s+ok\s+ok") {
    Write-Host "EC2 status checks OK."
    break
  }

  Write-Host "Current status: $status  (retry $($i+1)/30)"
  Start-Sleep -Seconds 10
}

Write-Host "`nStarting SSM session..."
aws ssm start-session --target $iid
