# connect-perm.ps1
$ErrorActionPreference = "Stop"

# Resolve the current permanent dev instance from Terraform state
$PERM_IID = terraform -chdir $PSScriptRoot output -raw instance_id 2>$null
if (-not $PERM_IID) {
    $PERM_IID = Read-Host "Could not read instance_id from terraform output. Enter instance ID (i-...)"
}

aws sts get-caller-identity | Out-Host
aws ssm start-session --target $PERM_IID
