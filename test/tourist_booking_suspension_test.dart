import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/widgets/tourist_booking_suspension.dart';

const _suspension = TouristBookingSuspension(
  caseId: '11111111-1111-1111-1111-111111111111',
  reason: 'Three tourist-initiated bookings were cancelled today.',
  startsAt: null,
  endsAt: null,
  cancellationCount: 3,
  active: true,
  appealStatus: '',
);

Widget _harness({
  required Future<void> Function(String reason) submit,
  void Function(bool submitted)? completed,
}) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: FilledButton(
            onPressed: () async {
              final result = await showTouristBookingSuspensionSheet(
                context,
                suspension: _suspension,
                onSubmitAppeal: submit,
              );
              completed?.call(result);
            },
            child: const Text('Open suspension'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('suspension payload parses pending-review state', () {
    final suspension = TouristBookingSuspension.fromMap({
      'case_id': 'case-id',
      'reason': 'Same-day cancellation threshold reached.',
      'starts_at': '2026-10-10T01:00:00Z',
      'ends_at': '2026-10-13T01:00:00Z',
      'cancellation_count': 3,
      'active': true,
      'appeal_status': 'pending_review',
      'offense_number': 3,
      'manual_review_required': true,
      'risk_level': 'elevated',
    });

    expect(suspension.active, isTrue);
    expect(suspension.cancellationCount, 3);
    expect(suspension.appealPending, isTrue);
    expect(suspension.offenseNumber, 3);
    expect(suspension.manualReviewRequired, isTrue);
    expect(suspension.riskLevel, 'elevated');
    expect(suspension.endsAt, isNotNull);
  });

  testWidgets('appeal sheet can repeatedly open and close without assertions', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(submit: (_) async {}));

    for (var index = 0; index < 3; index++) {
      await tester.tap(find.text('Open suspension'));
      await tester.pumpAndSettle();
      expect(find.text('Appeal Booking Suspension'), findsOneWidget);

      await tester.ensureVisible(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Appeal Booking Suspension'), findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('appeal owns submission state and ignores duplicate taps', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    bool? result;
    await tester.pumpWidget(
      _harness(
        submit: (reason) {
          calls++;
          expect(reason, 'Please review this suspension decision.');
          return pending.future;
        },
        completed: (value) => result = value,
      ),
    );

    await tester.tap(find.text('Open suspension'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField),
      'Please review this suspension decision.',
    );
    await tester.ensureVisible(find.text('Submit Appeal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit Appeal'));
    await tester.pump();
    await tester.tap(find.byType(FilledButton).last, warnIfMissed: false);
    await tester.pump();

    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    pending.complete();
    await tester.pumpAndSettle();
    expect(result, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending appeal is read-only and cannot be resubmitted', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TouristBookingSuspensionSheet(
            suspension: const TouristBookingSuspension(
              caseId: 'case-id',
              reason: 'Same-day cancellation threshold reached.',
              startsAt: null,
              endsAt: null,
              cancellationCount: 3,
              active: true,
              appealStatus: 'pending_review',
            ),
            onSubmitAppeal: (_) async => calls++,
          ),
        ),
      ),
    );

    expect(
      find.textContaining('Your appeal is pending review'),
      findsOneWidget,
    );
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Submit Appeal'), findsNothing);
    expect(calls, 0);
  });
}
