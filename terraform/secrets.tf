resource "aws_secretsmanager_secret" "stripe_secret_key" {
  name                    = "${var.project_name}/stripe-secret-key"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "stripe_secret_key" {
  secret_id     = aws_secretsmanager_secret.stripe_secret_key.id
  secret_string = var.stripe_secret_key
}

resource "aws_secretsmanager_secret" "stripe_webhook_secret" {
  name                    = "${var.project_name}/stripe-webhook-secret"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "stripe_webhook_secret" {
  secret_id     = aws_secretsmanager_secret.stripe_webhook_secret.id
  secret_string = var.stripe_webhook_secret
}
