import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, GetCommand } from '@aws-sdk/lib-dynamodb';

const dynamodb = DynamoDBDocumentClient.from(new DynamoDBClient({}));

interface DunningPayload {
  customerId: string;
  invoiceId: string;
  amountDue: number;
  failureCode: string;
  declineType: 'hard' | 'soft';
  eventId: string;
}

export const handler = async (event: DunningPayload) => {
  const result = await dynamodb.send(new GetCommand({
    TableName: process.env.CUSTOMERS_TABLE!,
    Key: { customer_id: event.customerId }
  }));

  const tier: string = result.Item?.tier ?? 'standard';

  console.log(`Customer ${event.customerId} resolved to tier: ${tier}`);

  return { ...event, tier };
};
