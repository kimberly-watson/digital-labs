# ---------------------------------------------------------------------------
# CodeBuild: runs `terraform apply` on the CS AWS account. This is the piece
# that replaces Kimberly running Terraform from her laptop. The portal Lambda
# starts a build here; the build pulls the repo fresh, reads all pending
# requests from DynamoDB, and applies.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "codebuild_exec" {
  name = "digital-labs-codebuild-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codebuild.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# NOTE: Terraform for this project needs broad provisioning permissions
# (EC2, IAM, S3, Lambda, EventBridge Scheduler, SES, SSM, DynamoDB, logs)
# because it is itself an infrastructure-provisioning tool. This mirrors the
# permission scope Kimberly's own SSO role already had when running these
# applies by hand — CodeBuild is simply now the one holding it instead of
# her laptop. Tighten with resource-level conditions once usage patterns are
# clear (see MIGRATION_RUNBOOK.md).
resource "aws_iam_role_policy" "codebuild_policy" {
  name = "digital-labs-codebuild-policy"
  role = aws_iam_role.codebuild_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:*",
          "iam:*",
          "lambda:*",
          "scheduler:*",
          "ses:*",
          "ssm:*",
          "s3:*",
          "dynamodb:*",
          "apigateway:*",
          "codebuild:*",
          "logs:*",
          "cloudwatch:*",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "codebuild_logs" {
  role       = aws_iam_role.codebuild_exec.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}

resource "aws_codebuild_project" "digital_labs_provisioner" {
  name         = "digital-labs-provisioner"
  description  = "Runs terraform apply for Digital Labs requests submitted via the portal"
  service_role = aws_iam_role.codebuild_exec.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/amazonlinux2-x86_64-standard:5.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false
  }

  source {
    type      = "GITHUB"
    location  = "https://github.com/kimberly-watson/digital-labs.git"
    buildspec = "buildspec.yml"
  }

  logs_config {
    cloudwatch_logs {
      group_name = "/digital-labs/provisioner"
    }
  }
}
