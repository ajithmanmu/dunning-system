variable "aws_region" {
    default = "us-west-2"
  }

  variable "project_name" {
    default = "dunning-system"
  }

  variable "stripe_webhook_secret" {
    sensitive = true
  }

  variable "stripe_secret_key" {
    sensitive = true
  }

  variable "ses_sender_email" {
    description = "Verified SES sender email address"
  }

  variable "slack_webhook_url" {
    sensitive   = true
    default     = ""
  }

  variable "vip_ltv_threshold" {
    default = 50
  }

  variable "retry_intervals_days" {
    default = [1, 3, 7]
  }