data "aws_caller_identity" "current" {}

data "archive_file" "webhook_handler" {
  type        = "zip"
  output_path = "${path.module}/../lambdas/webhook-handler/webhook-handler.zip"
  source_dir  = "${path.module}/../lambdas/webhook-handler"
  excludes = [
    "src",
    "tsconfig.json",
    "package.json",
    "package-lock.json",
    "webhook-handler.zip"
  ]
}

resource "aws_lambda_function" "webhook_handler" {
  filename         = data.archive_file.webhook_handler.output_path
  function_name    = "${var.project_name}-webhook-handler"
  role             = aws_iam_role.webhook_handler.arn
  handler          = "dist/index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.webhook_handler.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      IDEMPOTENCY_TABLE          = aws_dynamodb_table.idempotency.name
      STRIPE_SECRET_KEY_NAME     = aws_secretsmanager_secret.stripe_secret_key.name
      STRIPE_WEBHOOK_SECRET_NAME = aws_secretsmanager_secret.stripe_webhook_secret.name
    }
  }
}
