# setup-license.ps1
# One-time setup: base64-encodes your Sonatype license file and stores it in AWS SSM Parameter Store.
# Run this once before using Terraform to provision a lab instance.
#
# Prerequisites:
#   - AWS CLI installed and configured (aws configure)
#   - Your Sonatype .lic file on disk
#
# Usage:
#   .\setup-license.ps1 -LicensePath "C:\path\to\your-license.lic"
#   .\setup-license.ps1 -LicensePath "C:\path\to\your-license.lic" -Region "us-west-2" -ParameterPath "/my-team/sonatype-license"

param(
    [Parameter(Mandatory = $true)]
    [string]$LicensePath,

    [string]$Region = "us-east-1",

    [string]$ParameterPath = "/digital-labs/sonatype-license"
)

# Verify license file exists
if (-not (Test-Path $LicensePath)) {
    Write-Error "License file not found: $LicensePath"
    exit 1
}

Write-Host "Reading license file: $LicensePath"
$licenseBytes = [System.IO.File]::ReadAllBytes($LicensePath)
$licenseBase64 = [Convert]::ToBase64String($licenseBytes)

Write-Host "License encoded. Size: $($licenseBase64.Length) characters"
Write-Host "Storing in SSM Parameter Store at: $ParameterPath (region: $Region)"
Write-Host "Note: Advanced tier required (base64-encoded license exceeds Standard 4096-char limit). Cost: ~`$0.05/month."

aws ssm put-parameter `
    --name $ParameterPath `
    --value $licenseBase64 `
    --type SecureString `
    --tier Advanced `
    --overwrite `
    --region $Region

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "License stored successfully." -ForegroundColor Green
    Write-Host ""
    Write-Host "Next steps:"
    Write-Host "  1. If you used a non-default region or parameter path, create a terraform.tfvars file."
    Write-Host "     See README.md for the format."
    Write-Host "  2. Run: terraform init"
    Write-Host "  3. Run: terraform apply"
} else {
    Write-Error "Failed to store license. Check your AWS credentials and permissions."
    exit 1
}
