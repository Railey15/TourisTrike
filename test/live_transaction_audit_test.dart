import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String source(String path) => File(
  path,
).readAsStringSync().replaceAll('\r\n', '\n').replaceAll('\r', '\n');

void main() {
  late String migration;
  late String repository;
  late String touristTracking;
  late String driverTracking;
  late String touristChat;
  late String driverChat;
  late String payMongo;

  setUpAll(() {
    migration = source(
      'supabase/migrations/20260902000000_live_transaction_audit.sql',
    );
    repository = source('lib/core/supabase/touristrike_repository.dart');
    touristTracking = source(
      'lib/screens/tourist/tourist_activity_tracking_screen.dart',
    );
    driverTracking = source(
      'lib/screens/driver/driver_package_tracking_screen.dart',
    );
    touristChat = source('lib/screens/tourist/tourist_messages_screen.dart');
    driverChat = source('lib/screens/driver/driver_messages_screen.dart');
    payMongo = source('supabase/functions/paymongo-create-payment/index.ts');
  });

  test('live arrival validation is server enforced and test scoped', () {
    expect(migration, contains('guard_live_driver_journey_proximity'));
    expect(migration, contains("raise exception 'DRIVER_LOCATION_STALE'"));
    expect(migration, contains("raise exception 'NOT_WITHIN_ARRIVAL_RADIUS"));
    expect(migration, contains('v_allowed_radius_meters constant'));
    expect(migration, contains('is_developer_test_booking(new.booking_id)'));
    // Arrival now consumes validated stream/recovery fixes instead of the
    // removed manual-arrival proximity helper.
    expect(driverTracking, contains('StableArrivalDetector.isUsableFix('));
    expect(driverTracking, contains('automaticArrival: true'));
  });

  test('all participants use validated realtime location rows', () {
    expect(migration, contains('booking_participant_live_locations'));
    expect(migration, contains('upsert_tourist_live_location'));
    expect(repository, contains('upsertTouristLiveLocation'));
    expect(touristTracking, contains('_lastTouristLocationUploadAt'));
    expect(driverTracking, contains("MarkerId('tourist_live')"));
    expect(touristTracking, contains('LiveMarkerMotion'));
    expect(driverTracking, contains('LiveMarkerMotion'));
  });

  test('group chat is atomic idempotent and identity enriched', () {
    expect(migration, contains('send_conversation_message'));
    expect(migration, contains('client_message_id'));
    expect(migration, contains('get_conversation_message_feed'));
    expect(migration, contains('sender_display_name'));
    expect(migration, contains('driver_number'));
    expect(migration, contains('insert_booking_system_message'));
    for (final chat in [touristChat, driverChat]) {
      expect(chat, contains('sendConversationMessage'));
      expect(chat, contains('fetchConversationMessageFeed'));
      expect(chat, isNot(contains("'receiver_id': widget")));
    }
    expect(driverChat, contains('Heading to next stop'));
  });

  test('milestones ratings and checkout customer data are persisted', () {
    expect(migration, contains('sync_driver_journey_milestones'));
    expect(migration, contains('set arrived_at = coalesce'));
    expect(migration, contains('set picked_up_at = coalesce'));
    expect(migration, contains('set dropped_off_at = coalesce'));
    expect(
      migration,
      contains('driver_reviews(booking_id, driver_id, tourist_id)'),
    );
    expect(
      repository,
      contains("onConflict: 'booking_id,driver_id,tourist_id'"),
    );
    expect(payMongo, contains('attributes.billing = billing'));
    expect(payMongo, contains('touristProfile?.mobile'));
  });
}
