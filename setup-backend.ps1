param(
  [string]$Region = "us-east-1"
)

$AccountId = (aws sts get-caller-identity --query "Account" --output text)
$BucketName = "digital-labs-tfstate-$AccountId"
$TableName = "digital-labs-tfstate-lock"

Write-Host "Setting up Terraform remote state backend..."
Write-Host "Bucket: $BucketName"
Write-Host "Table:  $TableName"

# Create S3 bucket
$existing = aws s3api head-bucket --bucket $BucketName 2>&1
if ($LASTEXITCODE -ne 0) {
  if ($Region -eq "us-east-1") {
    aws s3api create-bucket --bucket $BucketName --region $Region
  } else {
    aws s3api create-bucket --bucket $BucketName --region $Region --create-bucket-configuration LocationConstraint=$Region
  }
  Write-Host "Created S3 bucket: $BucketName"
} else {
  Write-Host "S3 bucket already exists: $BucketName"
}

# Enable versioning
aws s3api put-bucket-versioning --bucket $BucketName --versioning-configuration Status=Enabled
Write-Host "Versioning enabled."

# Block all public access
aws s3api put-public-access-block --bucket $BucketName --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
Write-Host "Public access blocked."

# Enable server-side encryption
$encJson = "{`"Rules`":[{`"ApplyServerSideEncryptionByDefault`":{`"SSEAlgorithm`":`"AES256`"}}]}"
$encFile = "$env:TEMP\enc-config.json"
$encJson | Out-File -FilePath $encFile -Encoding ascii
aws s3api put-bucket-encryption --bucket $BucketName --server-side-encryption-configuration file://$encFile
Write-Host "Encryption enabled."

# Create DynamoDB table for state locking
$tableExists = aws dynamodb describe-table --table-name $TableName 2>&1
if ($LASTEXITCODE -ne 0) {
  aws dynamodb create-table --table-name $TableName --attribute-definitions AttributeName=LockID,AttributeType=S --key-schema AttributeName=LockID,KeyType=HASH --billing-mode PAY_PER_REQUEST --region $Region
  Write-Host "Created DynamoDB table: $TableName"
} else {
  Write-Host "DynamoDB table already exists: $TableName"
}

Write-Host ""
Write-Host "Backend setup complete. Now run: terraform init"
