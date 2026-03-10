locals {
  lease_seconds = {
    "1w"  = 7 * 24 * 3600
    "2w"  = 14 * 24 * 3600
    "3w"  = 21 * 24 * 3600
    "1mo" = 30 * 24 * 3600
  }

  termination_time = timeadd(timestamp(), "${local.lease_seconds[var.lease_duration]}s")
  warning_time     = timeadd(local.termination_time, "-172800s")
  welcome_time     = timeadd(timestamp(), "60s")
}

# SSM parameter: termination time, keyed per lab
resource "aws_ssm_parameter" "termination_time" {
  name      = "/digital-labs/${var.lab_key}/termination-time"
  type      = "String"
  value     = local.termination_time
  overwrite = true
}

# EC2 instance
resource "aws_instance" "lab" {
  ami                    = "ami-0f3caa1cf4417e51b"
  instance_type          = var.instance_type
  iam_instance_profile   = var.instance_profile_name
  vpc_security_group_ids = [var.security_group_id]
  user_data              = file("${path.root}/user_data.sh")

  # Enable reading instance tags from the metadata service.
  # user_data.sh reads the lab_key tag to locate its SSM param.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    instance_metadata_tags      = "enabled"
  }

  root_block_device {
    volume_size = var.volume_size_gb
    volume_type = "gp3"
  }

  tags = {
    Name    = var.lab_name
    lab_key = var.lab_key
  }

  depends_on = [aws_ssm_parameter.termination_time]
}
