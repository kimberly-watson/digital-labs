terraform {
  # NOTE: Terraform backend configuration cannot use variables or data sources.
  # The bucket name must be hardcoded here. This is a known Terraform limitation.
  # Before cloning and using this repo, update the bucket name to match your own
  # state bucket: digital-labs-tfstate-<your-aws-account-id>
  backend "s3" {
    bucket         = "digital-labs-tfstate-YOUR-AWS-ACCOUNT-ID"
    key            = "digital-labs/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
}
