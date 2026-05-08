data "aws_caller_identity" "current" {}

# ── webhook-handler ────────────────────────────────────────────────────────────

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
      STATE_MACHINE_ARN          = aws_sfn_state_machine.dunning.arn
    }
  }
}

# ── enricher ───────────────────────────────────────────────────────────────────

data "archive_file" "enricher" {
  type        = "zip"
  output_path = "${path.module}/../lambdas/enricher/enricher.zip"
  source_dir  = "${path.module}/../lambdas/enricher"
  excludes = [
    "src",
    "tsconfig.json",
    "package.json",
    "package-lock.json",
    "enricher.zip"
  ]
}

resource "aws_lambda_function" "enricher" {
  filename         = data.archive_file.enricher.output_path
  function_name    = "${var.project_name}-enricher"
  role             = aws_iam_role.enricher.arn
  handler          = "dist/index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.enricher.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      CUSTOMERS_TABLE = aws_dynamodb_table.customers.name
    }
  }
}

# ── payment-checker ────────────────────────────────────────────────────────────

data "archive_file" "payment_checker" {
  type        = "zip"
  output_path = "${path.module}/../lambdas/payment-checker/payment-checker.zip"
  source_dir  = "${path.module}/../lambdas/payment-checker"
  excludes = [
    "src",
    "tsconfig.json",
    "package.json",
    "package-lock.json",
    "payment-checker.zip"
  ]
}

resource "aws_lambda_function" "payment_checker" {
  filename         = data.archive_file.payment_checker.output_path
  function_name    = "${var.project_name}-payment-checker"
  role             = aws_iam_role.payment_checker.arn
  handler          = "dist/index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.payment_checker.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      STRIPE_SECRET_KEY_NAME = aws_secretsmanager_secret.stripe_secret_key.name
    }
  }
}

# ── canceller ──────────────────────────────────────────────────────────────────

data "archive_file" "canceller" {
  type        = "zip"
  output_path = "${path.module}/../lambdas/canceller/canceller.zip"
  source_dir  = "${path.module}/../lambdas/canceller"
  excludes = [
    "src",
    "tsconfig.json",
    "package.json",
    "package-lock.json",
    "canceller.zip"
  ]
}

resource "aws_lambda_function" "canceller" {
  filename         = data.archive_file.canceller.output_path
  function_name    = "${var.project_name}-canceller"
  role             = aws_iam_role.canceller.arn
  handler          = "dist/index.handler"
  runtime          = "nodejs20.x"
  source_code_hash = data.archive_file.canceller.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      DUNNING_STATE_TABLE = aws_dynamodb_table.dunning_state.name
      SES_SENDER_EMAIL    = var.ses_sender_email
    }
  }
}
