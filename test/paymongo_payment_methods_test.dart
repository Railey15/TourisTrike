import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';

String read(String path) => File(
  path,
).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

void main() {
  late String createPayment;
  late String webhook;
  late String schema;
  late String migration;
  late String repository;
  late String tracking;

  setUpAll(() {
    createPayment = read('supabase/functions/paymongo-create-payment/index.ts');
    webhook = read('supabase/functions/_shared/paymongo_webhook_handler.ts');
    schema = read(
      'supabase/migrations/20260827030000_paymongo_payment_foundation.sql',
    );
    migration = read(
      'supabase/migrations/20261009070000_paymongo_multi_method_checkout.sql',
    );
    repository = read('lib/core/supabase/touristrike_repository.dart');
    tracking = read(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    );
  });

  test('1 GCash down payment uses the unified checkout', () {
    expect(payMongoPaymentMethods, contains('gcash'));
    expect(tracking, contains("'down_payment'"));
    expect(createPayment, contains('payment_method_types: [paymentMethod]'));
  });

  test('2 GCash full payment is available after roster acceptance', () {
    expect(tracking, contains("'full_payment'"));
    expect(migration, contains("then 'full' else p_payment_stage end"));
    expect(migration, contains('v_amount := v_booking.total_amount'));
    expect(migration, contains('is_booking_driver_roster_full'));
  });

  test('3 Maya uses PayMongo paymaya identifier and Maya label', () {
    expect(payMongoPaymentMethods, contains('paymaya'));
    expect(paymentMethodLabel('paymaya'), 'Maya');
    expect(createPayment, isNot(contains('payment_method_types: ["maya"]')));
  });

  test('4 QR Ph returns and parses hosted QR payment state', () {
    expect(paymentMethodLabel('qrph'), 'QR Ph');
    expect(createPayment, contains('payment_flow: paymentFlow(paymentMethod)'));
    final checkout = PayMongoCheckout.fromJson({
      'payment_record_id': 'payment-1',
      'checkout_url': 'https://checkout.paymongo.com/example',
      'reused': false,
      'livemode': false,
      'payment_method': 'qrph',
      'payment_flow': 'hosted_qr',
      'qr_payment': {
        'checkout_url': 'https://checkout.paymongo.com/example',
        'presentation': 'paymongo_hosted_checkout',
      },
    });
    expect(checkout.isHostedQr, isTrue);
    expect(checkout.qrPaymentUrl, checkout.checkoutUrl);
  });

  test('5 card stays on PayMongo hosted checkout without raw card fields', () {
    expect(paymentMethodLabel('card'), 'Credit / Debit Card');
    expect(payMongoPaymentMethods, contains('card'));
    expect(createPayment, isNot(contains('card_number')));
    expect(createPayment, isNot(contains('cvv')));
    expect(repository, isNot(contains('expiry_month')));
  });

  test('6 invalid payment method is rejected', () {
    expect(createPayment, contains('isPayMongoPaymentMethod(paymentMethod)'));
    expect(createPayment, contains('INVALID_PAYMENT_METHOD'));
    expect(
      migration,
      contains("v_method not in ('gcash', 'paymaya', 'qrph', 'card')"),
    );
  });

  test('7 tampered amount is not accepted from Flutter', () {
    final checkoutMethod = repository
        .split('Future<PayMongoCheckout> createPayMongoCheckout')[1]
        .split('Future<PaymentRecord> prepareGroupCashRemainingBalance')[0];
    expect(checkoutMethod, isNot(contains("'amount':")));
    expect(createPayment, isNot(contains('body.amount')));
    expect(migration, contains("raise exception 'INVALID_PAYMENT_AMOUNT'"));
  });

  test('8 duplicate webhook remains idempotent', () {
    expect(schema, contains('unique (provider, provider_event_id)'));
    expect(webhook, contains('process_paymongo_webhook_event'));
  });

  test('9 failed payment does not confirm booking', () {
    final workflow = read(
      'supabase/migrations/20260827040000_paymongo_trusted_workflow.sql',
    );
    expect(workflow, contains("status = 'cancelled'"));
    expect(workflow, contains("'confirmed', false"));
  });

  test(
    '10 successful payment creates one record and full satisfies both stages',
    () {
      expect(schema, contains('payment_records_provider_idempotency_uidx'));
      expect(migration, contains('insert into public.payment_records'));
      expect(migration, contains('trg_satisfy_full_payment_requirements'));
      expect(
        migration,
        contains("payment_stage in ('down_payment', 'remaining_balance')"),
      );
    },
  );
}
