import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File(
    'supabase/migrations/20260827020000_atomic_package_booking_creation.sql',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  final repository = File(
    'lib/core/supabase/touristrike_repository.dart',
  ).readAsStringSync().replaceAll('\r\n', '\n');

  test('booking and both snapshot collections use one RPC transaction', () {
    expect(repository, contains("'create_package_booking'"));
    expect(repository, contains("'p_customized_spots': customizedSpots"));
    expect(repository, contains("'p_itinerary_items': itineraryItems"));
    expect(migration, contains('insert into public.package_bookings'));
    expect(migration, contains('insert into public.customized_package_spots'));
    expect(migration, contains('insert into public.booking_itinerary_items'));
  });

  test('RPC owns tourist identity and canonical initial state', () {
    expect(migration, contains('v_tourist_id uuid := auth.uid()'));
    expect(migration, contains("'waiting_for_drivers'"));
    expect(migration, contains("'pending'"));
  });

  test('activity remains trigger-owned with no swallowed partial failure', () {
    expect(
      migration,
      contains(
        'trg_sync_package_activity; this RPC deliberately does not duplicate it',
      ),
    );
    final createMethod = repository.substring(
      repository.indexOf('Future<PackageBooking> createPackageBooking'),
      repository.indexOf('Future<void> replaceBookingItinerary'),
    );
    expect(createMethod, isNot(contains('packageActivities')));
    expect(createMethod, isNot(contains('catch (_)')));
  });
}
