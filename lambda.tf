# -- Lambda: Package both functions ------------------------------------------

data "archive_file" "terminator" {
  type        = "zip"
  source_file = "${path.module}/lambda/terminator.py"
  output_path = "${path.module}/lambda/terminator.zip"
}

data "archive_file" "notifier" {
  type        = "zip"
  source_file = "${path.module}/lambda/notifier.py"
  output_path = "${path.module}/lambda/notifier.zip"
}

# -- IAM: Lambda execution role -----------------------------------------------

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
      },
      {
        Effect   = "Allow"
        Action   = ["scheduler:DeleteSchedule"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = aws_sns_topic.lab_notifications.arn
      },
      {
        Effect   = "Allow"
        Action   = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      }
    ]
  })
}

# -- SNS: Email notification topic --------------------------------------------

resource "aws_sns_topic" "lab_notifications" {
  name = "digital-labs-notifications-${aws_instance.lab.id}"
}

resource "aws_sns_topic_subscription" "customer_email" {
  count     = var.customer_email != "" ? 1 : 0
  topic_arn = aws_sns_topic.lab_notifications.arn
  protocol  = "email"
  endpoint  = var.customer_email
}

# -- Lambda: Terminator function ----------------------------------------------

resource "aws_lambda_function" "terminator" {
  function_name    = "digital-labs-terminator-${aws_instance.lab.id}"
  role             = aws_iam_role.lambda_exec.arn
  handler          = "terminator.handler"
  runtime          = "python3.12"
  filename         = data.archive_file.terminator.output_path
  source_code_hash = data.archive_file.terminator.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      APP_REGION               = var.aws_region
      INSTANCE_ID              = aws_instance.lab.id
      TERMINATION_SCHEDULE_NAME = "digital-labs-terminate-${aws_instance.lab.id}"
      WARNING_SCHEDULE_NAME    = "digital-labs-warn-${aws_instance.lab.id}"
    }
  }
}

# -- Lambda: Notifier function ------------------------------------------------

resource "aws_lambda_function" "notifier" {
  function_name    = "digital-labs-notifier-${aws_instance.lab.id}"
  role             = aws_iam_role.lambda_exec.arn
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
      SNS_TOPIC_ARN         = aws_sns_topic.lab_notifications.arn
      WARNING_SCHEDULE_NAME = "digital-labs-warn-${aws_instance.lab.id}"
    }
  }
}

# -- Lambda permissions: allow EventBridge Scheduler to invoke ----------------

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
