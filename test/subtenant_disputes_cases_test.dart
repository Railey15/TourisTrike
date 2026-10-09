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

Map<String, dynamic> _complaint({
  String category = 'conduct',
  String status = 'submitted',
  String reportedRole = 'driver',
}) {
  return {
    'id': 'aaaaaaaa-1234-1234-1234-123456789012',
    'booking_id': 'bbbbbbbb-1234-1234-1234-123456789012',
    'municipality': 'Baliwag',
    'province': 'Bulacan',
    'reporter_id': 'tourist-id',
    'reporter_name': 'Tourist Reporter',
    'reported_user_id': 'driver-id',
    'reported_name': 'Driver Reported',
    'reported_role': reportedRole,
    'category': category,
    'description': 'The driver behaved unsafely during the booked tour.',
    'status': status,
    'booking_status': 'completed',
    'booking_travel_date': '2026-10-01',
    'booking_history': [
      {
        'booking_id': 'cccccccc-1234-1234-1234-123456789012',
        'travel_date': '2026-09-01',
        'booking_status': 'completed',
      },
    ],
    'evidence': [
      {
        'id': 'evidence-id',
        'storage_path': 'complaints/evidence.jpg',
        'file_name': 'evidence.jpg',
        'content_type': 'image/jpeg',
      },
    ],
    'events': [
      {
        'action': 'submitted',
        'details': 'Complaint submitted for MTO review',
        'created_at': '2026-10-02T01:00:00Z',
      },
    ],
    'created_at': '2026-10-02T01:00:00Z',
  };
}

void main() {
  const migration =
      'supabase/migrations/20260930000000_subtenant_disputes_cases.sql';
  const repairMigration =
      'supabase/migration_hold/20261001100000_repair_dispute_case_mutation_results.sql';
  const screen = 'lib/screens/subtenant/subtenant_payment_disputes_screen.dart';
  const service = 'lib/screens/subtenant/subtenant_service.dart';
  const shell = 'lib/screens/subtenant/layouts/subtenant_admin_shell.dart';
  const sidebar = 'lib/screens/subtenant/widgets/subtenant_sidebar.dart';
  late String sql;
  late String repairSql;
  late String ui;
  late String serviceSource;
  late String shellSource;
  late String sidebarSource;

  setUpAll(() {
    sql = _read(migration);
    repairSql = _read(repairMigration);
    ui = _read(screen);
    serviceSource = _read(service);
    shellSource = _read(shell);
    sidebarSource = _read(sidebar);
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

  test('municipal complaints adapt into unified cases without duplication', () {
    final complaint = SubTenantCase.fromComplaintMap(
      _complaint(),
      restrictions: [
        {
          'id': 'restriction-id',
          'complaint_id': 'aaaaaaaa-1234-1234-1234-123456789012',
          'active': true,
        },
      ],
    );

    expect(complaint.isComplaint, isTrue);
    expect(complaint.category, 'driver');
    expect(complaint.status, 'needs_review');
    expect(complaint.originalStatus, 'submitted');
    expect(complaint.reporter.role, 'tourist');
    expect(complaint.reportedUser?.role, 'driver');
    expect(complaint.bookingHistory, hasLength(1));
    expect(complaint.evidence.single.storagePath, 'complaints/evidence.jpg');
    expect(complaint.timeline.single.details, contains('MTO review'));
    expect(complaint.restrictions, hasLength(1));
  });

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
    expect(
      SubTenantCase.fromComplaintMap(_complaint()).matchesFilters(
        categoryFilter: 'driver',
        statusFilter: 'attention',
        roleFilter: 'driver',
        searchQuery: 'Tourist Reporter',
      ),
      isTrue,
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
    'case mutation repair is idempotent and notifications are best-effort',
    () {
      expect(repairSql, contains("if v_case.status = 'under_review'"));
      expect(repairSql, contains("if v_case.status = 'closed'"));
      expect(repairSql, contains("'transitioned', false"));
      expect(repairSql, contains("'notification_failures'"));
      expect(repairSql, contains('exception when others then'));
      expect(repairSql, contains("raise warning 'CASE_NOTIFICATION_FAILED"));
      expect(repairSql, contains("'start_case_review'"));
      expect(repairSql, contains("'resolve_dispute_case'"));
      expect(repairSql, contains('for update;'));
    },
  );

  test('service reconciles ambiguous RPC failures against persisted state', () {
    expect(serviceSource, contains('Future<void> _runCaseMutation'));
    expect(
      serviceSource,
      contains('final persisted = await fetchCaseDetails(caseId)'),
    );
    expect(serviceSource, contains('if (persistedMatches(persisted))'));
    expect(
      serviceSource,
      contains('Error.throwWithStackTrace(error, stackTrace)'),
    );
    expect(
      serviceSource,
      contains("stString(row, const ['status']) == 'under_review'"),
    );
    expect(
      serviceSource,
      contains("stString(row, const ['status']) == 'closed'"),
    );
  });

  test(
    'UI refreshes authoritative cases before reporting mutation success',
    () {
      final action = ui.indexOf('await action();');
      final refresh = ui.indexOf(
        'final refreshed = await _service.fetchCases();',
      );
      final success = ui.indexOf(
        'showSubTenantSnack(context, message, error: false)',
      );
      expect(action, greaterThan(-1));
      expect(refresh, greaterThan(action));
      expect(success, greaterThan(refresh));
    },
  );

  test(
    'UI exposes filters, contextual empty states and payment-only details',
    () {
      for (final label in [
        'All Types',
        'Fare / Additional Charges',
        'Safety / Tour Incident',
        'All Roles',
        'Needs Attention',
        'Search cases...',
        'Nothing here',
        'Start Review',
        'Resolve Case',
        'Report / Complaint Details',
        'Municipal Booking History',
        'Supporting Evidence',
        'Investigation / Decision History',
        'Admin Actions',
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

  test('service merges complaints and preserves their secured workflows', () {
    for (final value in [
      "'get_dispute_cases'",
      "'get_municipal_complaints'",
      "'get_municipal_restrictions'",
      "'update_municipal_complaint'",
      "'impose_municipal_restriction'",
      "'lift_municipal_restriction'",
      "'decide_municipal_restriction_appeal'",
      "'municipal-complaint-evidence'",
    ]) {
      expect(serviceSource, contains(value));
    }
  });

  test('navigation exposes one Disputes & Cases destination', () {
    expect(sidebarSource, contains("label: 'Disputes & Cases'"));
    expect(sidebarSource, isNot(contains("label: 'Complaints'")));
    expect(shellSource, contains('static const int _tabCount = 8;'));
    expect(shellSource, isNot(contains('SubTenantComplaintsScreen')));
    expect(
      File(
        'lib/screens/subtenant/subtenant_complaints_screen.dart',
      ).existsSync(),
      isFalse,
    );
  });
}
