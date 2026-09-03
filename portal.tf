# ---------------------------------------------------------------------------
# Internal request portal: a single Lambda serves the form (GET) and handles
# submissions (POST), writing to DynamoDB and starting a CodeBuild run.
#
# Access control: internal-only, gated by a shared access code (see
# aws_ssm_parameter.portal_access_code below). This is a stopgap suitable
# for "Sonatype staff only, to start" — before opening this to customers
# directly, replace with Cognito or SSO-backed auth. See MIGRATION_RUNBOOK.md.
# ---------------------------------------------------------------------------

resource "aws_ssm_parameter" "portal_access_code" {
  name  = "/digital-labs/portal-access-code"
  type  = "SecureString"
  value = "CHANGE-ME-SET-A-REAL-CODE"

  lifecycle {
    ignore_changes = [value] # set the real value once via console/CLI, don't let terraform stomp it
  }
}

resource "aws_iam_role" "portal_lambda_exec" {
  name = "digital-labs-portal-lambda-exec"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "portal_lambda_policy" {
  name = "digital-labs-portal-lambda-policy"
  role = aws_iam_role.portal_lambda_exec.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:Scan"]
        Resource = aws_dynamodb_table.lab_requests.arn
      },
      {
        Effect   = "Allow"
        Action   = ["codebuild:StartBuild"]
        Resource = aws_codebuild_project.digital_labs_provisioner.arn
      },
      {
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = aws_ssm_parameter.portal_access_code.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:${var.aws_region}:*:log-group:/aws/lambda/digital-labs-portal:*"
      }
    ]
  })
}

data "archive_file" "portal_lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda/request_handler.py"
  output_path = "${path.module}/lambda/request_handler.zip"
}

resource "aws_lambda_function" "portal" {
  function_name    = "digital-labs-portal"
  role              = aws_iam_role.portal_lambda_exec.arn
  handler           = "request_handler.handler"
  runtime           = "python3.12"
  timeout           = 15
  filename          = data.archive_file.portal_lambda_zip.output_path
  source_code_hash  = data.archive_file.portal_lambda_zip.output_base64sha256

  environment {
    variables = {
      REQUESTS_TABLE     = aws_dynamodb_table.lab_requests.name
      CODEBUILD_PROJECT  = aws_codebuild_project.digital_labs_provisioner.name
      ACCESS_CODE_PARAM  = aws_ssm_parameter.portal_access_code.name
    }
  }
}

resource "aws_apigatewayv2_api" "portal" {
  name          = "digital-labs-portal"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_integration" "portal_lambda" {
  api_id                 = aws_apigatewayv2_api.portal.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.portal.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_form" {
  api_id    = aws_apigatewayv2_api.portal.id
  route_key = "GET /"
  target    = "integrations/${aws_apigatewayv2_integration.portal_lambda.id}"
}

resource "aws_apigatewayv2_route" "post_submit" {
  api_id    = aws_apigatewayv2_api.portal.id
  route_key = "POST /submit"
  target    = "integrations/${aws_apigatewayv2_integration.portal_lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.portal.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "apigw_invoke" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.portal.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.portal.execution_arn}/*/*"
}

output "portal_url" {
  description = "Internal lab-request form URL"
  value       = aws_apigatewayv2_stage.default.invoke_url
}
