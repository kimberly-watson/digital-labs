terraform {
  backend "s3" {
    bucket         = "digital-labs-tfstate-YOUR-AWS-ACCOUNT-ID"
    key            = "digital-labs/terraform.tfstate"
    region         = "us-east-1"
    use_lockfile   = true
    encrypt        = true
  }
}
