# connect-perm.ps1
$ErrorActionPreference = "Stop"

$PERM_IID = "i-PREVIOUS-DEV-INSTANCE"

aws sts get-caller-identity | Out-Host
aws ssm start-session --target $PERM_IID
