resource "aws_dynamodb_table" "idempotency" {
    name         = "${var.project_name}-idempotency"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "event_id"

    attribute {
      name = "event_id"
      type = "S"
    }

    ttl {
      attribute_name = "expires_at"
      enabled        = true
    }
  }

  resource "aws_dynamodb_table" "customers" {
    name         = "${var.project_name}-customers"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "customer_id"

    attribute {
      name = "customer_id"
      type = "S"
    }
  }

  resource "aws_dynamodb_table" "dunning_state" {
    name         = "${var.project_name}-dunning-state"
    billing_mode = "PAY_PER_REQUEST"
    hash_key     = "customer_id"
    range_key    = "invoice_id"

    attribute {
      name = "customer_id"
      type = "S"
    }

    attribute {
      name = "invoice_id"
      type = "S"
    }
  }
  