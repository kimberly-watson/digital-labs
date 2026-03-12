terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# ---------------------------------------------------------------------------
# Locals: resolve lab map
# ---------------------------------------------------------------------------
# Supports two deploy modes:
#   Single lab:  -var customer_email=x@y.com -var lease_duration=1w
#   Cohort:      -var-file=cohort.tfvars   (var.labs map populated)
# ---------------------------------------------------------------------------

locals {
  labs_resolved = length(var.labs) > 0 ? var.labs : {
    "default" = {
      customer_email = var.customer_email
      lease_duration = var.lease_duration
      lab_name       = var.lab_name
    }
  }
}

# ---------------------------------------------------------------------------
# Shared IAM: EC2 role (SSM + S3 assets + CloudWatch)
# ---------------------------------------------------------------------------

resource "aws_iam_role" "lab_ssm_role" {
  name = "digital-labs-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_policy" {
  role       = aws_iam_role.lab_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_policy" "parameter_store_read" {
  name = "digital-labs-parameter-store-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:${var.aws_region}:*:parameter/digital-labs/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "parameter_store_policy" {
  role       = aws_iam_role.lab_ssm_role.name
  policy_arn = aws_iam_policy.parameter_store_read.arn
}

resource "aws_iam_role_policy_attachment" "cloudwatch_policy" {
  role       = aws_iam_role.lab_ssm_role.name
  policy_arn = aws_iam_policy.cloudwatch_logs_scoped.arn
}

# Scoped CloudWatch Logs policy — EC2 instances only need write access to
# /digital-labs/* log groups. CloudWatchLogsFullAccess grants account-wide
# read+write which is excessive for a lab instance.
resource "aws_iam_policy" "cloudwatch_logs_scoped" {
  name = "digital-labs-cloudwatch-logs"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams"
        ]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/digital-labs/*"
      },
      {
        # cloudwatch:PutMetricData and logs:DescribeLogGroups are list/global
        # operations — AWS does not support scoping them to specific log groups.
        Effect = "Allow"
        Action = [
          "cloudwatch:PutMetricData",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_policy" "s3_assets_read" {
  name = "digital-labs-s3-assets-read"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject"]
      Resource = "arn:aws:s3:::digital-labs-tfstate-YOUR-AWS-ACCOUNT-ID/assets/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "s3_assets_policy" {
  role       = aws_iam_role.lab_ssm_role.name
  policy_arn = aws_iam_policy.s3_assets_read.arn
}

resource "aws_iam_instance_profile" "lab_profile" {
  name = "digital-labs-instance-profile"
  role = aws_iam_role.lab_ssm_role.name
}

# ---------------------------------------------------------------------------
# Shared IAM: Lambda execution role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "lambda_exec" {
  name = "digital-labs-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "digital-labs-lambda-policy"
  role = aws_iam_role.lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["ec2:TerminateInstances"]
        Resource = "*"
        # Scope termination to instances tagged as Digital Labs resources only.
        # This prevents a Lambda bug from accidentally terminating non-lab EC2 instances.
        Condition = {
          StringLike = {
            "ec2:ResourceTag/lab_key" = "*"
          }
        }
      },
      {
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["scheduler:DeleteSchedule"]
        Resource = "arn:aws:scheduler:${var.aws_region}:*:schedule/default/digital-labs-*"
      },
      {
        Effect   = "Allow"
        Action   = ["ses:SendEmail", "ses:SendRawEmail"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/digital-labs-*:*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Shared IAM: EventBridge Scheduler role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "scheduler_exec" {
  name = "digital-labs-scheduler-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "scheduler.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "scheduler_policy" {
  name = "digital-labs-scheduler-policy"
  role = aws_iam_role.scheduler_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["lambda:InvokeFunction"]
      Resource = "arn:aws:lambda:*:*:function:digital-labs-*"
    }]
  })
}

# ---------------------------------------------------------------------------
# Shared security group
# ---------------------------------------------------------------------------

resource "aws_security_group" "lab_sg" {
  name        = "digital-labs-sg"
  description = "Allow lab ports and outbound traffic"

  ingress {
    description = "HTTP / nginx"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Ports 8081 (Nexus raw) and 8070 (IQ raw) are intentionally NOT exposed.
  # All browser access goes through nginx on 8082/8072 which injects the beacon,
  # enforces browser-only UA policy, and applies rate limiting.
  ingress {
    description = "Nexus Repository + Lab Tutor widget proxy"
    from_port   = 8082
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "IQ Server + Lab Tutor widget proxy"
    from_port   = 8072
    to_port     = 8072
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  # Port 8090 (tutor proxy) intentionally NOT exposed externally.
  # nginx proxies /chat → localhost:8090 internally. No public access needed.
  # Port 8071 is used internally by IQ Server docker-proxy — do not open.
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------------------------------------------------------------------------
# Shared S3 assets (uploaded once, downloaded by every lab at boot)
# ---------------------------------------------------------------------------

resource "aws_s3_object" "countdown_html" {
  bucket = "digital-labs-tfstate-YOUR-AWS-ACCOUNT-ID"
  key    = "assets/countdown.html"
  source = "${path.module}/assets/countdown.html"
  etag   = filemd5("${path.module}/assets/countdown.html")
}

resource "aws_s3_object" "proxy_py" {
  bucket = "digital-labs-tfstate-YOUR-AWS-ACCOUNT-ID"
  key    = "assets/proxy.py"
  source = "${path.module}/assets/proxy.py"
  etag   = filemd5("${path.module}/assets/proxy.py")
}

resource "aws_s3_object" "tutor_html" {
  bucket = "digital-labs-tfstate-YOUR-AWS-ACCOUNT-ID"
  key    = "assets/tutor.html"
  source = "${path.module}/assets/tutor.html"
  etag   = filemd5("${path.module}/assets/tutor.html")
}

# ---------------------------------------------------------------------------
# Lab module instances
# ---------------------------------------------------------------------------

module "lab" {
  for_each = local.labs_resolved
  source   = "./modules/lab"

  lab_key        = each.key
  customer_email = each.value.customer_email
  lease_duration = each.value.lease_duration
  lab_name       = each.value.lab_name != null ? each.value.lab_name : "digital-labs-${each.key}"

  aws_region     = var.aws_region
  instance_type  = var.instance_type
  volume_size_gb = var.volume_size_gb
  ses_from_email = var.ses_from_email

  # Shared resources
  lambda_exec_role_arn    = aws_iam_role.lambda_exec.arn
  scheduler_exec_role_arn = aws_iam_role.scheduler_exec.arn
  security_group_id       = aws_security_group.lab_sg.id
  instance_profile_name   = aws_iam_instance_profile.lab_profile.name

  depends_on = [
    aws_s3_object.countdown_html,
    aws_s3_object.proxy_py,
    aws_s3_object.tutor_html,
  ]
}

# ---------------------------------------------------------------------------
# Outputs (map over all labs)
# ---------------------------------------------------------------------------

output "labs" {
  description = "Per-lab connection info. For a single lab, key is 'default'."
  value = {
    for k, v in module.lab : k => {
      instance_id  = v.instance_id
      public_ip    = v.public_ip
      lab_url      = v.lab_url
      nexus_url    = v.nexus_url
      iq_url       = v.iq_url
      terminates_at = v.terminates_at
    }
  }
}
