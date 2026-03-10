resource "aws_scheduler_schedule" "terminate" {
  name       = "digital-labs-terminate-${var.lab_key}"
  group_name = "default"

  flexible_time_window { mode = "OFF" }

  schedule_expression          = "at(${replace(replace(local.termination_time, "/\\..*$/", ""), "Z", "")})"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.terminator.arn
    role_arn = var.scheduler_exec_role_arn

    input = jsonencode({ instance_id = aws_instance.lab.id })
  }
}

resource "aws_scheduler_schedule" "warn" {
  name       = "digital-labs-warn-${var.lab_key}"
  group_name = "default"

  flexible_time_window { mode = "OFF" }

  schedule_expression          = "at(${replace(replace(local.warning_time, "/\\..*$/", ""), "Z", "")})"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.notifier.arn
    role_arn = var.scheduler_exec_role_arn

    input = jsonencode({ instance_id = aws_instance.lab.id })
  }
}

resource "aws_scheduler_schedule" "welcome" {
  name       = "digital-labs-welcome-${var.lab_key}"
  group_name = "default"

  flexible_time_window { mode = "OFF" }

  schedule_expression          = "at(${replace(replace(local.welcome_time, "/\\..*$/", ""), "Z", "")})"
  schedule_expression_timezone = "UTC"

  target {
    arn      = aws_lambda_function.welcomer.arn
    role_arn = var.scheduler_exec_role_arn

    input = jsonencode({ instance_id = aws_instance.lab.id })
  }
}
