#!/usr/bin/env node
// Usage:
//   node scripts/trigger-failure.js vip
//   node scripts/trigger-failure.js trial
//   node scripts/trigger-failure.js standard
//   node scripts/trigger-failure.js hard-decline

const { execSync } = require('child_process');
const Stripe = require('../lambdas/webhook-handler/node_modules/stripe');

const PRICES = {
  premium: 'price_1Hd28eLOrrtGwOzJ399Cl9Nf', // $50/month
  starter: 'price_1Hd25GLOrrtGwOzJXgafQuNM', // $10/month
};

const SCENARIOS = {
  vip: {
    name: 'Alexandra Chen',
    email: 'alex.chen.vip@test.com',
    price: PRICES.premium,
    tier: 'vip',
    paymentMethod: 'pm_card_chargeDeclined',
  },
  trial: {
    name: 'Marcus Rivera',
    email: 'marcus.rivera.trial@test.com',
    price: PRICES.starter,
    tier: 'trial',
    paymentMethod: 'pm_card_chargeDeclined',
  },
  standard: {
    name: 'Sarah Johnson',
    email: 'sarah.johnson.standard@test.com',
    price: PRICES.starter,
    tier: null, // no DynamoDB entry — enricher defaults to standard
    paymentMethod: 'pm_card_chargeDeclined',
  },
  'hard-decline': {
    name: 'James Wilson',
    email: 'james.wilson.hard@test.com',
    price: PRICES.starter,
    tier: null,
    paymentMethod: 'pm_card_chargeDeclinedStolenCard',
  },
};

async function triggerScenario(stripe, scenarioKey) {
  const scenario = SCENARIOS[scenarioKey];

  console.log(`\nCreating customer: ${scenario.name}...`);
  const customer = await stripe.customers.create({
    name: scenario.name,
    email: scenario.email,
    metadata: { scenario: scenarioKey, test: 'true' },
  });
  console.log(`Customer: ${customer.id}`);

  if (scenario.tier) {
    console.log(`Seeding DynamoDB as ${scenario.tier}...`);
    const item = JSON.stringify({
      customer_id: { S: customer.id },
      tier: { S: scenario.tier },
    });
    execSync(
      `aws dynamodb put-item --table-name dunning-system-customers --region us-east-1 --item '${item}'`,
      { stdio: 'inherit' }
    );
    console.log('Seeded.');
  } else {
    console.log('No DynamoDB entry — will resolve to standard.');
  }

  console.log('Creating subscription (payment_behavior: default_incomplete)...');
  const subscription = await stripe.subscriptions.create({
    customer: customer.id,
    items: [{ price: scenario.price }],
    payment_behavior: 'default_incomplete',
    expand: ['latest_invoice.payment_intent'],
  });

  const invoice = subscription.latest_invoice;
  const paymentIntent = invoice.payment_intent;
  console.log(`Subscription: ${subscription.id}`);
  console.log(`Invoice:      ${invoice.id}`);
  console.log(`PaymentIntent:${paymentIntent.id}`);

  console.log(`Confirming with ${scenario.paymentMethod}...`);
  try {
    await stripe.paymentIntents.confirm(paymentIntent.id, {
      payment_method: scenario.paymentMethod,
    });
  } catch (err) {
    if (err.code === 'card_declined') {
      console.log('Card declined as expected — invoice.payment_failed will fire.');
    } else {
      throw err;
    }
  }

  console.log('Waiting for webhook to reach Lambda (~5s)...');
  await new Promise(r => setTimeout(r, 5000));
  console.log(`Done — check Step Functions console for the ${scenarioKey} execution.`);
}

async function main() {
  const scenarioKey = process.argv[2];
  const validKeys = Object.keys(SCENARIOS);

  if (scenarioKey === 'all') {
    const stripe = Stripe(process.env.STRIPE_SECRET_KEY);
    for (const key of validKeys) {
      await triggerScenario(stripe, key);
      console.log('\nWaiting 10s before next scenario...\n');
      await new Promise(r => setTimeout(r, 10000));
    }
    return;
  }

  if (!SCENARIOS[scenarioKey]) {
    console.error(`Usage: node trigger-failure.js <${validKeys.join('|')}|all>`);
    process.exit(1);
  }

  const stripe = Stripe(process.env.STRIPE_SECRET_KEY);
  await triggerScenario(stripe, scenarioKey);
}

main().catch(err => { console.error(err.message); process.exit(1); });
