# Dunning System

A custom subscription payment recovery system built on AWS. When Stripe detects a failed payment, this system orchestrates a multi-day, segmented recovery sequence — going beyond Stripe's native dunning to recover more revenue through smarter communication and escalation logic.

## Why Build This?

Stripe's native dunning retries payments and sends a single generic email. At scale, this recovers 20-35% of failed payments. A custom system that segments customers, sends branded multi-step sequences, and escalates high-value accounts to your team recovers 40-50%.

The gap at $1M+ ARR can mean $100K-$2M in additional recovered revenue annually.

## How It Works

A `invoice.payment_failed` webhook from Stripe triggers an AWS Step Functions state machine. The machine enriches the customer with business context (tier, LTV) that Stripe doesn't have, then routes them through the appropriate recovery path.

```
Stripe (invoice.payment_failed)
  → API Gateway
  → Lambda: Webhook Handler (verify signature, idempotency check)
  → Step Functions State Machine
      → Lambda: Enricher (fetch customer tier + LTV from DynamoDB)
      → Branch: Hard Decline / VIP / Standard / Trial
      → Wait states with payment status checks between each step
      → SES emails at each step (branded, from your domain)
      → EventBridge → SNS → Slack for VIP escalation
      → Stripe API cancel on final failure
```

If Stripe's retry succeeds at any point, an `invoice.paid` webhook stops the sequence immediately.

## Recovery Paths

| Path | Trigger | Sequence |
|------|---------|----------|
| **Hard Decline** | Stolen/blocked card | Immediate "replace card" email, no waiting |
| **VIP** | LTV above threshold | Day 1, 3, 7 emails + team Slack alert + discount offer on Day 7 |
| **Standard** | Default | Day 1, 3, 7 emails → cancel |
| **Trial** | Trial user | Day 1 email → cancel on Day 3 |

## Architecture

### AWS Services

| Service | Role |
|---------|------|
| API Gateway | Receives Stripe webhook events |
| Lambda (×4) | Webhook handler, customer enricher, payment checker, canceller |
| Step Functions | Orchestrates the multi-day recovery workflow |
| DynamoDB (×3) | Idempotency, customer data, dunning state + metrics |
| SES | Branded emails from your domain |
| EventBridge | Fires team alert events for VIP accounts |
| SNS | Delivers Slack notifications for VIP escalation |
| Secrets Manager | Stripe API key and webhook secret |
| CloudWatch | Recovery rate metrics and alarms |

### What Makes This Different From Stripe's Native Dunning

- **Segmented paths** — VIP customers get a different sequence than trial users. Stripe applies identical logic to everyone.
- **Multi-step sequences** — Stripe sends one email per failure. This sends a narrative over days with escalating urgency.
- **Early termination** — Checks payment status between each step. If Stripe's retry works, the sequence stops immediately.
- **Team escalation** — High-value accounts trigger a Slack alert so a human can reach out. Stripe has no concept of this.
- **Discount offers** — Inserts a conditional offer mid-sequence for VIP accounts. Not possible in Stripe's native flow.
- **Branded emails** — Sent from your domain via SES, not from `support@stripe.com`.
- **Hard vs soft decline awareness** — Stolen cards skip the waiting and go straight to "replace your card".

## Project Structure

```
dunning-system/
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── dynamodb.tf
│   ├── iam.tf
│   ├── lambda.tf
│   ├── api_gateway.tf
│   ├── step_functions.tf
│   ├── ses.tf
│   ├── eventbridge.tf
│   └── secrets.tf
├── lambdas/
│   ├── webhook-handler/    # Entry point, signature verification, idempotency
│   ├── enricher/           # Fetches customer tier + LTV from DynamoDB
│   ├── payment-checker/    # Queries Stripe: has invoice been paid?
│   └── canceller/          # Cancels subscription via Stripe API
├── state-machine/
│   └── dunning.asl.json    # Step Functions state machine definition
├── email-templates/
│   ├── payment-failed.html
│   ├── urgent.html
│   └── discount-offer.html
└── dunning-config.json
```

## Configuration

All key values are driven by `terraform/terraform.tfvars` (not committed):

```hcl
aws_region            = "us-east-1"
stripe_webhook_secret = "whsec_..."
stripe_secret_key     = "sk_test_..."
ses_sender_email      = "billing@yourcompany.com"
```

And `dunning-config.json` at the root:

```json
{
  "vip_ltv_threshold": 500,
  "retry_intervals_days": [1, 3, 7],
  "vip_retry_intervals_days": [1, 3, 7, 14],
  "trial_grace_period_days": 3,
  "discount_offer_percent": 50,
  "slack_webhook_url": "https://hooks.slack.com/...",
  "ses_sender": "billing@yourcompany.com"
}
```

## Getting Started

**Prerequisites:** AWS CLI, Terraform >= 1.5, Node.js >= 18, Stripe CLI

```bash
# 1. Clone and install Lambda dependencies
git clone https://github.com/ajithmanmu/dunning-system
cd dunning-system/lambdas/webhook-handler && npm install && npm run build

# 2. Configure Terraform
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Fill in your Stripe keys and SES email

# 3. Deploy
cd terraform
terraform init
terraform apply

# 4. Forward webhooks locally for testing
stripe listen --forward-to <your-api-gateway-url>/webhook

# 5. Trigger a test payment failure
stripe trigger invoice.payment_failed
```

## Demo

For demo purposes, Step Functions wait states are set to minutes instead of days. Trigger a payment failure with the Stripe CLI and watch the state machine execute in real time in the AWS Console.

Test cards:
- `4000 0000 0000 0341` — always fails (soft decline, triggers standard dunning)
- `4000 0000 0000 9995` — always fails with insufficient funds
- `4100 0000 0000 0019` — always fails with stolen card (triggers hard decline path)
