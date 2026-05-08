import Stripe from 'stripe';
import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';

const secretsManager = new SecretsManagerClient({});
let cachedStripeClient: Stripe | null = null;

async function getStripeClient(): Promise<Stripe> {
  if (!cachedStripeClient) {
    const response = await secretsManager.send(
      new GetSecretValueCommand({ SecretId: process.env.STRIPE_SECRET_KEY_NAME! })
    );
    cachedStripeClient = new Stripe(response.SecretString!);
  }
  return cachedStripeClient;
}

interface DunningPayload {
  customerId: string;
  invoiceId: string;
  amountDue: number;
  failureCode: string;
  declineType: 'hard' | 'soft';
  eventId: string;
  tier: string;
}

export const handler = async (event: DunningPayload) => {
  const stripe = await getStripeClient();
  const invoice = await stripe.invoices.retrieve(event.invoiceId);
  const isPaid = invoice.status === 'paid';

  console.log(`Invoice ${event.invoiceId} status: ${invoice.status}, isPaid: ${isPaid}`);

  return { ...event, isPaid };
};
