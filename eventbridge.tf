# -- IAM: Role allowing EventBridge Scheduler to invoke Lambda ----------------

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
      Resource = [
        aws_lambda_function.terminator.arn,
        aws_lambda_function.notifier.arn
      ]
    }]
  })
}

# -- Locals: Calculate termination and warning timestamps ---------------------

locals {
  lease_seconds = {
    "1w"  = 7 * 24 * 3600
    "2w"  = 14 * 24 * 3600
    "3w"  = 21 * 24 * 3600
    "1mo" = 30 * 24 * 3600
  }

  termination_time    = timeadd(timestamp(), "${local.lease_seconds[var.lease_duration]}s")
  warning_time        = timeadd(local.termination_time, "-172800s")
}

# -- EventBridge Schedule: Termination ---------------------------------------

resource "aws_scheduler_schedule" "terminate" {
  name       = "digital-labs-terminate-${aws_instance.lab.id}"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "at(${replace(replace(local.termination_time, "/\\..*$/", ""), "Z", "")})"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.terminator.arn
    role_arn = aws_iam_role.scheduler_exec.arn

    input = jsonencode({
      instance_id = aws_instance.lab.id
    })
  }
}

# -- EventBridge Schedule: 48hr Warning ---------------------------------------

resource "aws_scheduler_schedule" "warn" {
  name       = "digital-labs-warn-${aws_instance.lab.id}"
  group_name = "default"

  flexible_time_window {
    mode = "OFF"
  }

  schedule_expression          = "at(${replace(replace(local.warning_time, "/\\..*$/", ""), "Z", "")})"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.notifier.arn
    role_arn = aws_iam_role.scheduler_exec.arn

    input = jsonencode({
      instance_id = aws_instance.lab.id
    })
  }
}
