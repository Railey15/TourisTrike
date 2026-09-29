import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';

String _read(String path) =>
    File(path).readAsStringSync().replaceAll('\r\n', '\n');

Map<String, dynamic> _case({
  String category = 'booking',
  String status = 'needs_review',
  Map<String, dynamic>? payment,
}) {
  return {
    'id': '12345678-1234-1234-1234-123456789012',
    'municipality': 'Baliwag',
    'booking_id': '87654321-1234-1234-1234-123456789012',
    'category': category,
    'subject': 'Incorrect booking assignment',
    'description': 'The assigned driver does not match the booking.',
    'priority': 'high',
    'status': status,
    'reporter': {
      'id': 'tourist-id',
      'name': 'Tourist One',
      'role': 'tourist',
      'mobile': '09123456789',
    },
    'reported_user': {
      'id': 'driver-id',
      'name': 'Driver One',
      'role': 'driver',
      'mobile': '09999999999',
    },
    'booking': {'id': '87654321', 'status': 'confirmed'},
    'tour_package': {'id': 'package-id', 'title': 'Heritage Tour'},
    'payment': payment,
    'evidence': <Map<String, dynamic>>[],
    'timeline': [
      {'label': 'Case submitted', 'at': '2026-09-30T01:00:00Z'},
      null,
    ],
    'created_at': '2026-09-30T01:00:00Z',
  };
}

void main() {
  const migration =
      'supabase/migrations/20260930000000_subtenant_disputes_cases.sql';
  const screen = 'lib/screens/subtenant/subtenant_payment_disputes_screen.dart';
  late String sql;
  late String ui;

  setUpAll(() {
    sql = _read(migration);
    ui = _read(screen);
  });

  test(
    'payment and non-payment cases parse without fabricating payment data',
    () {
      final payment = SubTenantCase.fromMap(
        _case(
          category: 'payment',
          payment: {
            'id': 'payment-id',
            'amount': 1200,
            'payment_method': 'gcash',
            'status': 'disputed',
          },
        ),
      );
      final booking = SubTenantCase.fromMap(_case());

      expect(payment.category, 'payment');
      expect(payment.payment?['amount'], 1200);
      expect(booking.category, 'booking');
      expect(booking.payment, isNull);
      expect(booking.reference, 'CASE-12345678');
    },
  );

  test(
    'case search index contains reference, subject, booking and parties',
    () {
      final item = SubTenantCase.fromMap(_case());
      for (final query in [
        'case-12345678',
        'incorrect booking',
        '87654321',
        'tourist one',
        'driver one',
        'heritage tour',
      ]) {
        expect(item.searchableText, contains(query));
      }
    },
  );

  test('category, status and search filters compose correctly', () {
    final review = SubTenantCase.fromMap(_case());
    final closed = SubTenantCase.fromMap(_case(status: 'closed'));

    expect(
      review.matchesFilters(
        categoryFilter: 'booking',
        statusFilter: 'needs_review',
        searchQuery: 'Tourist One',
      ),
      isTrue,
    );
    expect(
      review.matchesFilters(
        categoryFilter: 'payment',
        statusFilter: 'all',
        searchQuery: '',
      ),
      isFalse,
    );
    expect(
      review.matchesFilters(
        categoryFilter: 'all',
        statusFilter: 'attention',
        searchQuery: '',
      ),
      isTrue,
    );
    expect(
      closed.matchesFilters(
        categoryFilter: 'all',
        statusFilter: 'attention',
        searchQuery: '',
      ),
      isFalse,
    );
  });

  test('migration enforces municipality isolation and protected mutations', () {
    expect(sql, contains('public.current_subtenant_city()'));
    expect(sql, contains('public.cities_match('));
    expect(sql, contains('public.can_manage_dispute_case(p_case_id)'));
    expect(sql, contains("raise exception 'NOT_AUTHORIZED'"));
    expect(sql, contains('CASE_IDENTITY_FIELDS_ARE_IMMUTABLE'));
    expect(
      sql,
      contains('alter table public.dispute_evidence enable row level security'),
    );
    expect(sql, isNot(contains('for update to authenticated\nusing (true)')));
  });

  test(
    'case lifecycle validates resolution and records audit and notifications',
    () {
      expect(sql, contains('RESOLUTION_NOTES_REQUIRED'));
      expect(sql, contains('CUSTOM_RESOLUTION_REQUIRED'));
      expect(sql, contains("'start_case_review'"));
      expect(sql, contains("'resolve_dispute_case'"));
      expect(sql, contains("'Case review started'"));
      expect(sql, contains("'Case resolved'"));
      expect(sql, contains("where id = p_case_id and status = 'needs_review'"));
      expect(sql, contains("where id = p_case_id and status = 'under_review'"));
    },
  );

  test(
    'UI exposes filters, contextual empty states and payment-only details',
    () {
      for (final label in [
        'All Categories',
        'Fare / Additional Charges',
        'Safety / Incident',
        'Needs Attention',
        'Search cases...',
        'Nothing here',
        'Start Review',
        'Resolve Case',
      ]) {
        expect(ui, contains(label));
      }
      expect(
        ui,
        contains("item.category == 'payment' && item.payment != null"),
      );
      expect(ui, contains('constraints.maxWidth < 720'));
      expect(ui, contains('maxWidth: 820, maxHeight: 760'));
    },
  );
}
