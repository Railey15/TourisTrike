import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(
  path,
).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

List<int> splitCentavos(int total, int recipients) {
  final base = total ~/ recipients;
  final remainder = total % recipients;
  return List<int>.generate(
    recipients,
    (index) => base + (index < remainder ? 1 : 0),
  );
}

void main() {
  late String schema;
  late String integrity;
  late String workflow;
  late String payout;
  late String connection;
  late String authContextFix;
  late String splitRemainderFix;
  late String createFunction;
  late String webhookFunction;
  late String webhookAliasFunction;
  late String webhookHandler;
  late String returnFunction;
  late String supabaseConfig;
  late String repository;
  late String models;
  late String touristTracking;
  late String driverTracking;
  late String driverEarnings;
  late String loadingScreen;

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
    authContextFix = read(
      'supabase/migrations/20260829010000_fix_paymongo_tourist_auth_context.sql',
    );
    splitRemainderFix = read(
      'supabase/migrations/20260829020000_distribute_split_remainder_centavos.sql',
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
    models = read('lib/core/supabase/touristrike_models.dart');
    touristTracking = read(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    );
    driverTracking = read(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    );
    driverEarnings = read('lib/screens/driver/driver_earnings_screen.dart');
    loadingScreen = read('lib/screens/auth/loading_screen.dart');
  });

  test('client amount is never accepted as authoritative', () {
    expect(createFunction, contains('prepare_paymongo_payment'));
    expect(createFunction, isNot(contains('body.amount')));
    expect(workflow, contains('v_amount := v_booking.downpayment_amount'));
    expect(workflow, contains('v_amount := v_booking.remaining_balance'));
    expect(workflow, contains('v_amount := v_booking.total_amount'));
  });

  test('Checkout uses the documented PayMongo v1 hosted endpoint', () {
    expect(
      createFunction,
      contains('https://api.paymongo.com/v1/checkout_sessions'),
    );
    expect(createFunction, contains('isHttpsUrl(successUrl)'));
    expect(returnFunction, contains('touristrike://wallet/payment/'));
    expect(returnFunction, isNot(contains('.rpc(')));
  });

  test('unauthorized booking payment is rejected', () {
    expect(authContextFix, contains("raise exception 'NOT_BOOKING_TOURIST'"));
    expect(
      authContextFix,
      contains('v_authenticated_tourist_id uuid := auth.uid()'),
    );
    expect(authContextFix, contains('new.payer_id <> auth.uid()'));
    expect(authContextFix, contains('new.payer_id <> v_booking.tourist_id'));
  });

  test('tourist payment insert preserves JWT auth context', () {
    final preparation = createFunction
        .split('const { data: prepared, error: prepareError }')[1]
        .split('const payment = prepared.payment')[0];
    expect(createFunction, contains('userClient.auth.getUser()'));
    expect(createFunction, contains('.select("tourist_id")'));
    expect(preparation, contains('userClient.rpc('));
    expect(preparation, isNot(contains('serviceClient.rpc(')));
    expect(authContextFix, contains('to authenticated;'));
    expect(authContextFix, contains('PAYMONGO_PAYEE_MUST_BE_NULL'));
  });

  test('duplicate create request reuses one payment and provider request', () {
    expect(schema, contains('payment_records_provider_idempotency_uidx'));
    expect(workflow, contains("'reused', true"));
    expect(createFunction, contains(r'touristrike-checkout-${payment.id}'));
    expect(createFunction, contains('PAYMENT_ALREADY_CONFIRMED'));
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

  test('webhook logging exposes mapping and state without secrets', () {
    expect(webhookHandler, contains('webhook rejected: invalid signature'));
    expect(webhookHandler, contains(r'checkout=${providerCheckoutId'));
    expect(webhookHandler, contains('old_status='));
    expect(webhookHandler, contains('new_status='));
    expect(webhookHandler, isNot(contains('PAYMONGO_WEBHOOK_SECRET}')));
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

  test('one and three tricycle splits preserve the exact stage amount', () {
    expect(splitCentavos(360000, 1), [360000]);
    expect(splitCentavos(360000, 3), [120000, 120000, 120000]);
    expect(splitCentavos(100000, 3), [33334, 33333, 33333]);
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
    expect(createFunction, contains('success: true'));
    expect(createFunction, contains('checkout_url: checkoutUrl'));
    expect(models, contains("checkoutUrl: dbString(json['checkout_url'])"));
    expect(touristTracking, isNot(contains('showGcashPaymentSheet')));
  });

  test('payment return redirects and cold-starts the booking screen', () {
    expect(returnFunction, contains('status: 302'));
    expect(returnFunction, contains('"Location": appUrlString'));
    expect(returnFunction, isNot(contains('text/html')));
    expect(returnFunction, contains('booking_id'));
    expect(returnFunction, contains('payment_record_id'));
    expect(returnFunction, contains('touristrike://wallet/payment/'));
    expect(createFunction, contains('returnUrlWithPaymentContext'));
    expect(loadingScreen, contains('AppLinks'));
    expect(
      loadingScreen,
      contains('ActivityTrackingScreen(bookingId: bookingId)'),
    );
    expect(loadingScreen, contains('refreshing server state'));
    expect(
      touristTracking,
      contains('app resumed; refreshing server payment status'),
    );
  });

  test('driver earnings are derived from confirmed payment allocations', () {
    expect(repository, contains('fetchConfirmedDriverPaymentAllocations'));
    expect(repository, contains(".from('payment_allocations')"));
    expect(repository, contains("payment_records!inner("));
    expect(repository, contains(".eq('payment_records.status', 'confirmed')"));
    expect(driverEarnings, contains('fetchConfirmedDriverPaymentAllocations'));
    expect(driverEarnings, contains('allocation.driverAmount'));
    expect(driverEarnings, contains('_AllocationEarningTile'));
    expect(driverEarnings, contains("table: 'payment_allocations'"));
    expect(repository, contains(".eq('driver_id', requireUserId())"));
    expect(schema, contains('driver_id = auth.uid()'));
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
      expect(splitRemainderFix, contains('series <= v_amount_remainder'));
    },
  );

  test('two and four drivers receive exact even stage shares', () {
    expect(splitCentavos(360000, 2), [180000, 180000]);
    expect(splitCentavos(360000, 4), [90000, 90000, 90000, 90000]);
  });

  test('multi-cent remainder is spread one centavo per ordered driver', () {
    final allocation = splitCentavos(100001, 3);
    expect(allocation, [33334, 33334, 33333]);
    expect(allocation.reduce((left, right) => left + right), 100001);
  });

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
    expect(authContextFix, contains('to authenticated'));
  });
}
