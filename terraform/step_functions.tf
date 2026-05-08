locals {
  # Shared retry config for Lambda task states
  lambda_retry = [
    {
      ErrorEquals     = ["Lambda.ServiceException", "Lambda.AWSLambdaException", "Lambda.SdkClientException", "Lambda.TooManyRequestsException"]
      IntervalSeconds = 2
      MaxAttempts     = 3
      BackoffRate     = 2
    }
  ]

  # ResultSelector used after every PaymentChecker invocation
  payment_check_result = {
    "customerId.$"  = "$.Payload.customerId"
    "invoiceId.$"   = "$.Payload.invoiceId"
    "amountDue.$"   = "$.Payload.amountDue"
    "failureCode.$" = "$.Payload.failureCode"
    "declineType.$" = "$.Payload.declineType"
    "eventId.$"     = "$.Payload.eventId"
    "tier.$"        = "$.Payload.tier"
    "isPaid.$"      = "$.Payload.isPaid"
  }
}

resource "aws_sfn_state_machine" "dunning" {
  name     = "${var.project_name}-dunning"
  role_arn = aws_iam_role.step_functions.arn

  definition = jsonencode({
    Comment = "Dunning orchestration — routes payment failures through tiered recovery paths"
    StartAt = "EnrichCustomer"

    States = {

      # ── 1. Enrich: resolve customer tier ──────────────────────────────────────
      EnrichCustomer = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.enricher.arn
          "Payload.$"  = "$"
        }
        ResultSelector = {
          "customerId.$"  = "$.Payload.customerId"
          "invoiceId.$"   = "$.Payload.invoiceId"
          "amountDue.$"   = "$.Payload.amountDue"
          "failureCode.$" = "$.Payload.failureCode"
          "declineType.$" = "$.Payload.declineType"
          "eventId.$"     = "$.Payload.eventId"
          "tier.$"        = "$.Payload.tier"
        }
        Retry = local.lambda_retry
        Next  = "ClassifyDecline"
      }

      # ── 2. Route based on decline type and tier ───────────────────────────────
      ClassifyDecline = {
        Type = "Choice"
        Choices = [
          {
            Variable     = "$.declineType"
            StringEquals = "hard"
            Next         = "CancelSubscription"
          },
          {
            Variable     = "$.tier"
            StringEquals = "vip"
            Next         = "VIPWait1"
          },
          {
            Variable     = "$.tier"
            StringEquals = "trial"
            Next         = "TrialWait1"
          }
        ]
        Default = "StandardWait1"
      }

      # ── Standard path: Day 3 → Day 7 → Day 14 ────────────────────────────────
      # (Wait times shortened to seconds for demo; multiply by 86400 for production)
      StandardWait1 = { Type = "Wait", Seconds = 30, Next = "StandardCheck1" }
      StandardCheck1 = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.payment_checker.arn
          "Payload.$"  = "$"
        }
        ResultSelector = local.payment_check_result
        Retry          = local.lambda_retry
        Next           = "StandardRoute1"
      }
      StandardRoute1 = {
        Type = "Choice"
        Choices = [{ Variable = "$.isPaid", BooleanEquals = true, Next = "PaymentRecovered" }]
        Default = "StandardWait2"
      }

      StandardWait2  = { Type = "Wait", Seconds = 60, Next = "StandardCheck2" }
      StandardCheck2 = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.payment_checker.arn
          "Payload.$"  = "$"
        }
        ResultSelector = local.payment_check_result
        Retry          = local.lambda_retry
        Next           = "StandardRoute2"
      }
      StandardRoute2 = {
        Type = "Choice"
        Choices = [{ Variable = "$.isPaid", BooleanEquals = true, Next = "PaymentRecovered" }]
        Default = "StandardWait3"
      }

      StandardWait3  = { Type = "Wait", Seconds = 120, Next = "StandardCheck3" }
      StandardCheck3 = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.payment_checker.arn
          "Payload.$"  = "$"
        }
        ResultSelector = local.payment_check_result
        Retry          = local.lambda_retry
        Next           = "StandardRoute3"
      }
      StandardRoute3 = {
        Type = "Choice"
        Choices = [{ Variable = "$.isPaid", BooleanEquals = true, Next = "PaymentRecovered" }]
        Default = "CancelSubscription"
      }

      # ── VIP path: Day 1 → Day 3 → Day 7 ──────────────────────────────────────
      VIPWait1  = { Type = "Wait", Seconds = 15, Next = "VIPCheck1" }
      VIPCheck1 = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.payment_checker.arn
          "Payload.$"  = "$"
        }
        ResultSelector = local.payment_check_result
        Retry          = local.lambda_retry
        Next           = "VIPRoute1"
      }
      VIPRoute1 = {
        Type = "Choice"
        Choices = [{ Variable = "$.isPaid", BooleanEquals = true, Next = "PaymentRecovered" }]
        Default = "VIPWait2"
      }

      VIPWait2  = { Type = "Wait", Seconds = 30, Next = "VIPCheck2" }
      VIPCheck2 = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.payment_checker.arn
          "Payload.$"  = "$"
        }
        ResultSelector = local.payment_check_result
        Retry          = local.lambda_retry
        Next           = "VIPRoute2"
      }
      VIPRoute2 = {
        Type = "Choice"
        Choices = [{ Variable = "$.isPaid", BooleanEquals = true, Next = "PaymentRecovered" }]
        Default = "VIPWait3"
      }

      VIPWait3  = { Type = "Wait", Seconds = 60, Next = "VIPCheck3" }
      VIPCheck3 = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.payment_checker.arn
          "Payload.$"  = "$"
        }
        ResultSelector = local.payment_check_result
        Retry          = local.lambda_retry
        Next           = "VIPRoute3"
      }
      VIPRoute3 = {
        Type = "Choice"
        Choices = [{ Variable = "$.isPaid", BooleanEquals = true, Next = "PaymentRecovered" }]
        Default = "CancelSubscription"
      }

      # ── Trial path: Day 1 → Day 3 ─────────────────────────────────────────────
      TrialWait1  = { Type = "Wait", Seconds = 30, Next = "TrialCheck1" }
      TrialCheck1 = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.payment_checker.arn
          "Payload.$"  = "$"
        }
        ResultSelector = local.payment_check_result
        Retry          = local.lambda_retry
        Next           = "TrialRoute1"
      }
      TrialRoute1 = {
        Type = "Choice"
        Choices = [{ Variable = "$.isPaid", BooleanEquals = true, Next = "PaymentRecovered" }]
        Default = "TrialWait2"
      }

      TrialWait2  = { Type = "Wait", Seconds = 60, Next = "TrialCheck2" }
      TrialCheck2 = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.payment_checker.arn
          "Payload.$"  = "$"
        }
        ResultSelector = local.payment_check_result
        Retry          = local.lambda_retry
        Next           = "TrialRoute2"
      }
      TrialRoute2 = {
        Type = "Choice"
        Choices = [{ Variable = "$.isPaid", BooleanEquals = true, Next = "PaymentRecovered" }]
        Default = "CancelSubscription"
      }

      # ── Terminal states ────────────────────────────────────────────────────────
      CancelSubscription = {
        Type     = "Task"
        Resource = "arn:aws:states:::lambda:invoke"
        Parameters = {
          FunctionName = aws_lambda_function.canceller.arn
          "Payload.$"  = "$"
        }
        Retry = local.lambda_retry
        Next  = "DunningFailed"
      }

      PaymentRecovered = { Type = "Succeed" }
      DunningFailed    = { Type = "Succeed" }
    }
  })
}
