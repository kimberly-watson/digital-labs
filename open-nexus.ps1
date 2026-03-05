# open-nexus.ps1
# Starts SSM port forwarding for Nexus (8081 -> localhost:8081)

$ErrorActionPreference = "Stop"

cd $PSScriptRoot

$iid = terraform output -raw instance_id
if ([string]::IsNullOrWhiteSpace($iid)) {
  throw "Terraform output 'instance_id' is empty. Run start-lab.ps1 first."
}

Write-Host "Starting port forward to Nexus on instance: $iid"
Write-Host "Open http://localhost:8081 after this starts."

aws ssm start-session --target $iid `
  --document-name AWS-StartPortForwardingSession `
  --parameters '{"portNumber":["8081"],"localPortNumber":["8081"]}'
