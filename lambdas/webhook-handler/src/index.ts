import Stripe from 'stripe';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, PutCommand, GetCommand } from '@aws-sdk/lib-dynamodb';
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const secretsManager = new SecretsManagerClient({});

const HARD_DECLINE_CODES = ['stolen_card', 'lost_card', 'do_not_honor', 'pickup_card'];

// Cached across warm Lambda invocations — avoids a Secrets Manager call on every request
let cachedStripeClient: Stripe | null = null;
let cachedWebhookSecret: string | null = null;

async function getSecret(secretName: string): Promise<string> {
  const response = await secretsManager.send(
    new GetSecretValueCommand({ SecretId: secretName })
  );
  return response.SecretString!;
}

async function getStripeClient(): Promise<Stripe> {
  if (!cachedStripeClient) {
    const secretKey = await getSecret(process.env.STRIPE_SECRET_KEY_NAME!);
    cachedStripeClient = new Stripe(secretKey);
  }
  return cachedStripeClient;
}

async function getWebhookSecret(): Promise<string> {
  if (!cachedWebhookSecret) {
    cachedWebhookSecret = await getSecret(process.env.STRIPE_WEBHOOK_SECRET_NAME!);
  }
  return cachedWebhookSecret;
}

interface InvoiceWithPaymentError extends Stripe.Invoice {
  last_payment_error?: { code?: string };
}

interface DunningPayload {
  customerId: string;
  invoiceId: string;
  amountDue: number;
  failureCode: string;
  declineType: 'hard' | 'soft';
  eventId: string;
}

export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  const sig = event.headers['stripe-signature'];

  if (!sig) {
    return { statusCode: 400, body: 'Missing stripe-signature header' };
  }

  const [stripe, webhookSecret] = await Promise.all([
    getStripeClient(),
    getWebhookSecret()
  ]);

  let stripeEvent: Stripe.Event;
  try {
    stripeEvent = stripe.webhooks.constructEvent(
      event.body!,
      sig,
      webhookSecret
    );
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Unknown error';
    console.error('Signature verification failed:', message);
    return { statusCode: 400, body: `Webhook Error: ${message}` };
  }

  if (stripeEvent.type !== 'invoice.payment_failed') {
    return { statusCode: 200, body: 'Event ignored' };
  }

  // Idempotency check
  const existing = await dynamodb.send(new GetCommand({
    TableName: process.env.IDEMPOTENCY_TABLE!,
    Key: { event_id: stripeEvent.id }
  }));

  if (existing.Item) {
    console.log(`Event ${stripeEvent.id} already processed, skipping`);
    return { statusCode: 200, body: 'Already processed' };
  }

  // Mark as processed (TTL: 24 hours)
  await dynamodb.send(new PutCommand({
    TableName: process.env.IDEMPOTENCY_TABLE!,
    Item: {
      event_id: stripeEvent.id,
      expires_at: Math.floor(Date.now() / 1000) + 86400
    }
  }));

  const invoice = stripeEvent.data.object as InvoiceWithPaymentError;
  const failureCode = invoice.last_payment_error?.code ?? 'unknown';
  const declineType: 'hard' | 'soft' = HARD_DECLINE_CODES.includes(failureCode) ? 'hard' : 'soft';

  const payload: DunningPayload = {
    customerId: invoice.customer as string,
    invoiceId: invoice.id!,
    amountDue: invoice.amount_due,
    failureCode,
    declineType,
    eventId: stripeEvent.id
  };

  console.log('Starting dunning sequence:', JSON.stringify(payload));

  // Step Functions wired in next
  return { statusCode: 200, body: 'OK' };
};
