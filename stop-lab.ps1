# stop-lab.ps1
# Destroys the lab resources.

$ErrorActionPreference = "Stop"

Write-Host "Destroying lab resources..."
terraform destroy -auto-approve
Write-Host "Done."
