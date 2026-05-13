# Dunning System

> 📝 Blog post: [When Stripe's Built-In Dunning Isn't Enough](https://dev.to/ajithmanmu/when-stripes-built-in-dunning-isnt-enough-16m2)

A custom subscription payment recovery system built on AWS. When Stripe detects a failed payment, this system routes each failure through a tiered recovery workflow — giving different customers different levels of retry patience based on their tier and the specific reason the payment failed.

## Why Build This?

Stripe's built-in dunning retries payments on a fixed schedule and sends a generic email. Every customer gets the same treatment regardless of their value, and hard declines (stolen cards, lost cards) get retried the same as soft ones (temporarily insufficient funds, expired cards).

This system gives you full control: VIP customers get more retry attempts and more time, trial users get cut off faster, and hard declines are cancelled immediately with no retries wasted.

## How It Works

An `invoice.payment_failed` webhook from Stripe triggers an AWS Step Functions state machine. The machine looks up the customer's tier in DynamoDB, classifies the decline type from the charge's outcome, and routes accordingly.

```
Stripe (invoice.payment_failed)
  → API Gateway
  → Lambda: Webhook Handler (verify signature, idempotency check, classify decline)
  → Step Functions State Machine
      → Lambda: Enricher (resolve customer tier from DynamoDB)
      → Choice: Hard Decline → immediate cancel
      → Choice: tier = vip / trial / standard → tiered wait + retry paths
      → Lambda: Payment Checker (poll Stripe between retries)
      → Lambda: Canceller (cancel subscription, record outcome in DynamoDB)
```

If payment is recovered at any retry point, the execution ends with `PaymentRecovered`. Otherwise it runs through all retries and cancels.

## Recovery Paths

| Path | Trigger | Schedule |
|------|---------|----------|
| **Hard Decline** | `stolen_card`, `lost_card`, `do_not_honor`, `pickup_card` | Immediate cancel, no retries |
| **VIP** | `tier = vip` in DynamoDB | Retry Day 1, Day 3, Day 7 → cancel |
| **Trial** | `tier = trial` in DynamoDB | Retry Day 1, Day 3 → cancel |
| **Standard** | No DynamoDB record (default) | Retry Day 3, Day 7, Day 14 → cancel |

Hard declines are detected by reading `charge.outcome.reason` from the Stripe charge object — a more reliable signal than `invoice.last_payment_error`, which isn't consistently populated in newer Stripe API versions.

## Architecture

### AWS Services

| Service | Role |
|---------|------|
| API Gateway | Receives Stripe webhook events |
| Lambda (×4) | Webhook handler, enricher, payment checker, canceller |
| Step Functions (Standard) | Orchestrates the multi-day recovery workflow |
| DynamoDB (×3) | Idempotency table, customer tier table, dunning-state table |
| Secrets Manager | Stripe API key and webhook secret |

All infrastructure is provisioned with Terraform.

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
│   └── secrets.tf
├── lambdas/
│   ├── webhook-handler/    # Entry point: signature verification, decline classification, idempotency
│   ├── enricher/           # Resolves customer tier from DynamoDB
│   ├── payment-checker/    # Queries Stripe to check if invoice has been paid
│   └── canceller/          # Cancels subscription via Stripe API, records outcome
└── scripts/
    ├── trigger-failure.js  # Demo script: creates real customers + subscriptions + triggers failures
    └── seed-customers.sh   # Utility: seed DynamoDB with test customer tiers
```

## Configuration

All secrets are driven by `terraform/terraform.tfvars` (not committed):

```hcl
aws_region            = "us-east-1"
stripe_webhook_secret = "whsec_..."
stripe_secret_key     = "sk_test_..."
ses_sender_email      = "billing@yourcompany.com"
```

## Getting Started

**Prerequisites:** AWS CLI, Terraform >= 1.5, Node.js >= 18, Stripe CLI

```bash
# 1. Clone and install Lambda dependencies
git clone https://github.com/ajithmanmu/dunning-system
cd dunning-system

# Install dependencies for each Lambda
for dir in lambdas/*/; do (cd "$dir" && npm install && npm run build); done

# 2. Configure Terraform
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Fill in your Stripe keys and SES email

# 3. Deploy
cd terraform
terraform init
terraform apply

# 4. Forward webhooks locally for testing
stripe listen --forward-to <your-api-gateway-url>/webhook

# 5. Update the webhook secret in Secrets Manager with the whsec_ from step 4
aws secretsmanager put-secret-value \
  --secret-id dunning-system/stripe-webhook-secret \
  --secret-string "whsec_..."
```

## Running the Demo

The `scripts/trigger-failure.js` script creates real Stripe customers with real subscriptions and triggers genuine payment failures — no mocked events.

```bash
export STRIPE_SECRET_KEY=sk_test_...

# Run all four scenarios
node scripts/trigger-failure.js all

# Or run individually
node scripts/trigger-failure.js vip
node scripts/trigger-failure.js trial
node scripts/trigger-failure.js standard
node scripts/trigger-failure.js hard-decline
```

Each scenario creates a fresh Stripe customer, seeds DynamoDB with the correct tier, attaches a subscription, and confirms the invoice's PaymentIntent with a declined test card. After running, check the Step Functions console to watch the executions — each is named `{customer-name}-{decline-type}-{event-id}` for easy identification.

Wait times in the state machine are shortened to seconds for demo purposes. Set the Wait state `Seconds` values to `86400` (1 day), `259200` (3 days), etc. for production use.
