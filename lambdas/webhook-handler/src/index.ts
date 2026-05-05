  import Stripe from 'stripe';
  import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
  import { DynamoDBDocumentClient, PutCommand, GetCommand } from '@aws-sdk/lib-dynamodb';
  import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';

  const stripe = new Stripe(process.env.STRIPE_SECRET_KEY!);
  const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

  const HARD_DECLINE_CODES = ['stolen_card', 'lost_card', 'do_not_honor', 'pickup_card'];

  interface DunningPayload {
    customerId: string;
    invoiceId: string;
    amountDue: number;
    failureCode: string;
    declineType: 'hard' | 'soft';
    eventId: string;
  }
  interface InvoiceWithPaymentError extends Stripe.Invoice {
    last_payment_error?: { code?: string };
  }

  export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
    const sig = event.headers['stripe-signature'];

    if (!sig) {
      return { statusCode: 400, body: 'Missing stripe-signature header' };
    }

    let stripeEvent: Stripe.Event;
    try {
      stripeEvent = stripe.webhooks.constructEvent(
        event.body!,
        sig,
        process.env.STRIPE_WEBHOOK_SECRET!
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
