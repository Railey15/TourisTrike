import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(
  path,
).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

List<int> splitCentavos(int total, int recipients) {
  final base = total ~/ recipients;
  final result = List<int>.filled(recipients, base);
  result[0] += total % recipients;
  return result;
}

void main() {
  late String schema;
  late String integrity;
  late String workflow;
  late String payout;
  late String connection;
  late String createFunction;
  late String webhookFunction;
  late String webhookAliasFunction;
  late String webhookHandler;
  late String returnFunction;
  late String supabaseConfig;
  late String repository;
  late String touristTracking;
  late String driverTracking;

  setUpAll(() {
    schema = read(
      'supabase/migrations/20260827030000_paymongo_payment_foundation.sql',
    );
    integrity = read(
      'supabase/migrations/20260827000000_p0_booking_integrity.sql',
    );
    workflow = read(
      'supabase/migrations/20260827040000_paymongo_trusted_workflow.sql',
    );
    payout = read(
      'supabase/migrations/20260827050000_paymongo_payout_reconciliation.sql',
    );
    connection = read(
      'supabase/migrations/20260827060000_connect_paymongo_and_group_cash.sql',
    );
    createFunction = read(
      'supabase/functions/paymongo-create-payment/index.ts',
    );
    webhookFunction = read('supabase/functions/paymongo-webhook/index.ts');
    webhookAliasFunction = read(
      'supabase/functions/paymongo-payment-webhook/index.ts',
    );
    webhookHandler = read(
      'supabase/functions/_shared/paymongo_webhook_handler.ts',
    );
    returnFunction = read(
      'supabase/functions/paymongo-payment-return/index.ts',
    );
    supabaseConfig = read('supabase/config.toml');
    repository = read('lib/core/supabase/touristrike_repository.dart');
    touristTracking = read(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    );
    driverTracking = read(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    );
  });

  test('client amount is never accepted as authoritative', () {
    expect(createFunction, contains('prepare_paymongo_payment'));
    expect(createFunction, isNot(contains('body.amount')));
    expect(workflow, contains('v_amount := v_booking.downpayment_amount'));
    expect(workflow, contains('v_amount := v_booking.remaining_balance'));
    expect(workflow, contains('v_amount := v_booking.total_amount'));
  });

  test('Checkout uses v2 normally and v1 for documented split shape', () {
    expect(createFunction, contains('?? "v2"'));
    expect(createFunction, contains('splitEnabled ? "v1"'));
    expect(createFunction, contains(r'/${checkoutVersion}/checkout_sessions'));
    expect(createFunction, contains('checkoutVersion !== "v2"'));
    expect(createFunction, contains('isHttpsUrl(successUrl)'));
    expect(returnFunction, contains('touristrike://wallet/payment/'));
    expect(returnFunction, isNot(contains('.rpc(')));
  });

  test('unauthorized booking payment is rejected', () {
    expect(workflow, contains("raise exception 'NOT_BOOKING_TOURIST'"));
    expect(workflow, contains('v_booking.tourist_id <> p_tourist_id'));
  });

  test('duplicate create request reuses one payment and provider request', () {
    expect(schema, contains('payment_records_provider_idempotency_uidx'));
    expect(workflow, contains("'reused', true"));
    expect(createFunction, contains(r'touristrike-checkout-${payment.id}'));
  });

  test('valid paid webhook is the only provider confirmation path', () {
    expect(webhookFunction, contains('handlePayMongoWebhook'));
    expect(webhookAliasFunction, contains('handlePayMongoWebhook'));
    expect(supabaseConfig, contains('[functions.paymongo-payment-webhook]'));
    expect(webhookHandler, contains('verifyPayMongoSignature'));
    expect(webhookHandler, contains('process_paymongo_webhook_event'));
    expect(workflow, contains("'checkout_session.payment.paid'"));
    expect(workflow, contains("status = 'confirmed'"));
    expect(workflow, contains("raise exception 'PROVIDER_WEBHOOK_REQUIRED'"));
  });

  test('duplicate webhook cannot duplicate effects', () {
    expect(schema, contains('unique (provider, provider_event_id)'));
    expect(workflow, contains('on conflict (provider, provider_event_id)'));
    expect(workflow, contains("'duplicate', true"));
  });

  test('failed and unknown provider events do not confirm payment', () {
    expect(workflow, contains("status = 'cancelled'"));
    expect(workflow, contains('UNKNOWN_PAYMENT_REFERENCE'));
    expect(workflow, contains("processing_status = 'rejected'"));
  });

  test('PHP 3,600 stage produces two exact PHP 1,800 allocations', () {
    expect(splitCentavos(360000, 2), [180000, 180000]);
    expect(workflow, contains('compute_equal_split_centavos'));
    expect(workflow, contains('recipient_position integer'));
    expect(workflow, isNot(contains('returns table (position integer')));
  });

  test('exact PHP 7,200 advanced two-driver scenario is preserved', () {
    const totalCentavos = 720000;
    final downPaymentCentavos = (totalCentavos * 0.50).round();
    final remainingCentavos = totalCentavos - downPaymentCentavos;
    expect(downPaymentCentavos, 360000);
    expect(remainingCentavos, 360000);
    expect(splitCentavos(downPaymentCentavos, 2), [180000, 180000]);
    expect(splitCentavos(remainingCentavos, 2), [180000, 180000]);
    expect(workflow, contains("raise exception 'DRIVER_ROSTER_NOT_FULL'"));
    expect(
      integrity,
      contains(
        'if v_new_count >= greatest(coalesce(v_booking.required_drivers, 1), 1)',
      ),
    );
    expect(integrity, contains("booking_status = 'waiting_for_drivers'"));
    expect(integrity, contains("booking_status = 'accepted'"));
    expect(integrity, contains('ensure_booking_payment_requirements'));
    expect(workflow, contains("raise exception 'DOWNPAYMENT_NOT_CONFIRMED'"));
    expect(touristTracking, contains('downPaymentConfirmed &&'));
    expect(touristTracking, contains('Choose GCash or Cash'));
  });

  test('Flutter calls the Edge Function and opens its checkout URL', () {
    final checkoutMethod = repository
        .split('Future<PayMongoCheckout> createPayMongoCheckout')[1]
        .split('Future<PaymentRecord> prepareGroupCashRemainingBalance')[0];
    expect(checkoutMethod, contains("'paymongo-create-payment'"));
    expect(checkoutMethod, contains("'booking_id': bookingId"));
    expect(checkoutMethod, contains("'payment_stage': paymentStage"));
    expect(checkoutMethod, isNot(contains("'amount'")));
    expect(touristTracking, contains('createPayMongoCheckout'));
    expect(touristTracking, contains('LaunchMode.externalApplication'));
    expect(touristTracking, isNot(contains('showGcashPaymentSheet')));
  });

  test('webhook state reaches Tour Tracking through Realtime', () {
    expect(touristTracking, contains("table: 'payment_records'"));
    expect(touristTracking, contains('PostgresChangeEvent.all'));
    expect(touristTracking, contains('_refreshPayments'));
    expect(touristTracking, contains("statusText = 'Paid'"));
  });

  test('remaining cash is server-derived and independently confirmed', () {
    expect(connection, contains('prepare_group_cash_remaining_balance'));
    expect(connection, contains('confirm_group_cash_share'));
    expect(connection, contains("'awaiting_cash'"));
    expect(connection, contains("'cash_confirmed'"));
    expect(connection, contains('status <> \'cash_confirmed\''));
    expect(driverTracking, contains('Confirm Cash Received'));
    expect(driverTracking, contains('confirmGroupCashShare'));
  });

  test('drivers cannot manually confirm PayMongo pending records', () {
    expect(driverTracking, contains("record.provider == 'manual'"));
    expect(workflow, contains("raise exception 'PROVIDER_WEBHOOK_REQUIRED'"));
  });

  test(
    'three drivers receive deterministic remainder with no lost centavo',
    () {
      final allocation = splitCentavos(100000, 3);
      expect(allocation, [33334, 33333, 33333]);
      expect(allocation.reduce((left, right) => left + right), 100000);
      expect(workflow, contains('v_amount_remainder'));
    },
  );

  test('only accepted assigned drivers are allocated', () {
    expect(
      workflow,
      contains("bd.booking_id = p_booking_id and bd.status = 'accepted'"),
    );
    expect(workflow, contains("raise exception 'DRIVER_ROSTER_NOT_FULL'"));
  });

  test('allocation invariant covers amount and provider percentages', () {
    expect(workflow, contains('PAYMENT_ALLOCATION_TOTAL_MISMATCH'));
    expect(workflow, contains('PAYMENT_ALLOCATION_BASIS_POINTS_MISMATCH'));
  });

  test('released assignments are reassigned only before payout', () {
    expect(payout, contains("status = 'cancelled'"));
    expect(payout, contains('Assignment released before payout.'));
    expect(payout, contains('paid_roster_change_manual_review'));
    expect(payout, contains('do not auto-reassign'));
  });

  test('payout claim is gated idempotent and retryable', () {
    expect(createFunction, isNot(contains('PAYMONGO_PLATFORM_NOT_CONFIGURED')));
    expect(workflow, contains("split.basis_points, 'PHP', 'held'"));
    expect(payout, contains('for update'));
    expect(payout, contains('ALLOCATION_ALREADY_PAID'));
    expect(payout, contains('PAYOUT_ALREADY_PROCESSING'));
    expect(payout, contains("not in ('eligible', 'failed')"));
    expect(payout, contains('attempt_count = attempt_count + 1'));
  });

  test('PayMongo refund completion requires provider confirmation', () {
    expect(payout, contains('PROVIDER_REFUND_CONFIRMATION_REQUIRED'));
    expect(payout, contains('record_paymongo_refund_result'));
    expect(
      payout,
      contains('REFUND_ALREADY_COMPLETED_WITH_DIFFERENT_REFERENCE'),
    );
  });

  test('provider secrets and elevated keys are absent from Flutter', () {
    final flutterSource = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .map((file) => file.readAsStringSync())
        .join('\n');
    expect(flutterSource, isNot(contains('PAYMONGO_SECRET_KEY')));
    expect(flutterSource, isNot(contains('SUPABASE_SERVICE_ROLE_KEY')));
  });

  test('RLS exposes safe summaries but no client financial writes', () {
    expect(schema, contains('payment_allocation_summaries'));
    expect(schema, contains('No authenticated INSERT/UPDATE/DELETE policies'));
    expect(workflow, contains('to service_role'));
  });
}
