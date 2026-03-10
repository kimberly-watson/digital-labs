data "archive_file" "terminator" {
  type        = "zip"
  source_file = "${path.root}/lambda/terminator.py"
  output_path = "${path.root}/lambda/terminator-${var.lab_key}.zip"
}

data "archive_file" "notifier" {
  type        = "zip"
  source_file = "${path.root}/lambda/notifier.py"
  output_path = "${path.root}/lambda/notifier-${var.lab_key}.zip"
}

data "archive_file" "welcomer" {
  type        = "zip"
  source_file = "${path.root}/lambda/welcomer.py"
  output_path = "${path.root}/lambda/welcomer-${var.lab_key}.zip"
}

resource "aws_lambda_function" "terminator" {
  function_name    = "digital-labs-terminator-${var.lab_key}"
  role             = var.lambda_exec_role_arn
  handler          = "terminator.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.terminator.output_path
  source_code_hash = data.archive_file.terminator.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      APP_REGION                = var.aws_region
      INSTANCE_ID               = aws_instance.lab.id
      TERMINATION_SCHEDULE_NAME = "digital-labs-terminate-${var.lab_key}"
      WARNING_SCHEDULE_NAME     = "digital-labs-warn-${var.lab_key}"
      WELCOME_SCHEDULE_NAME     = "digital-labs-welcome-${var.lab_key}"
    }
  }
}

resource "aws_lambda_function" "notifier" {
  function_name    = "digital-labs-notifier-${var.lab_key}"
  role             = var.lambda_exec_role_arn
  handler          = "notifier.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.notifier.output_path
  source_code_hash = data.archive_file.notifier.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      APP_REGION            = var.aws_region
      CUSTOMER_EMAIL        = var.customer_email
      INSTANCE_ID           = aws_instance.lab.id
      TERMINATION_TIME      = local.termination_time
      SES_FROM_EMAIL        = var.ses_from_email
      WARNING_SCHEDULE_NAME = "digital-labs-warn-${var.lab_key}"
    }
  }
}

resource "aws_lambda_function" "welcomer" {
  function_name    = "digital-labs-welcomer-${var.lab_key}"
  role             = var.lambda_exec_role_arn
  handler          = "welcomer.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.welcomer.output_path
  source_code_hash = data.archive_file.welcomer.output_base64sha256
  timeout          = 660

  environment {
    variables = {
      APP_REGION       = var.aws_region
      CUSTOMER_EMAIL   = var.customer_email
      INSTANCE_ID      = aws_instance.lab.id
      TERMINATION_TIME = local.termination_time
      SES_FROM_EMAIL   = var.ses_from_email
    }
  }
}

resource "aws_lambda_permission" "allow_scheduler_terminator" {
  statement_id  = "AllowSchedulerInvokeTerminator"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.terminator.function_name
  principal     = "scheduler.amazonaws.com"
}

resource "aws_lambda_permission" "allow_scheduler_notifier" {
  statement_id  = "AllowSchedulerInvokeNotifier"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notifier.function_name
  principal     = "scheduler.amazonaws.com"
}

resource "aws_lambda_permission" "allow_scheduler_welcomer" {
  statement_id  = "AllowSchedulerInvokeWelcomer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.welcomer.function_name
  principal     = "scheduler.amazonaws.com"
}
