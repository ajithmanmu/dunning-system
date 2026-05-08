import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, UpdateCommand } from '@aws-sdk/lib-dynamodb';
import { SESClient, SendEmailCommand } from '@aws-sdk/client-ses';

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({}));
const ses = new SESClient({});

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
  await dynamodb.send(new UpdateCommand({
    TableName: process.env.DUNNING_STATE_TABLE!,
    Key: { customer_id: event.customerId, invoice_id: event.invoiceId },
    UpdateExpression: 'SET #s = :s, updated_at = :now',
    ExpressionAttributeNames: { '#s': 'status' },
    ExpressionAttributeValues: {
      ':s': 'cancelled',
      ':now': new Date().toISOString()
    }
  }));

  await ses.send(new SendEmailCommand({
    Source: process.env.SES_SENDER_EMAIL!,
    Destination: { ToAddresses: [process.env.SES_SENDER_EMAIL!] },
    Message: {
      Subject: { Data: 'Your subscription has been cancelled' },
      Body: {
        Text: {
          Data: `Your subscription has been cancelled after repeated payment failures.\n\nInvoice: ${event.invoiceId}\nAmount: $${(event.amountDue / 100).toFixed(2)}`
        }
      }
    }
  }));

  console.log(`Cancellation complete for customer ${event.customerId}, invoice ${event.invoiceId}`);

  return { ...event, cancelled: true };
};
