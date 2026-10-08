import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/policies/touristrike_notices.dart';
import 'package:touristrike/screens/auth/signup_screen.dart';
import 'package:touristrike/screens/tourist/profile/privacy_policy_screen.dart';
import 'package:touristrike/screens/tourist/profile/terms_screen.dart';
import 'package:touristrike/widgets/booking_review_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  testWidgets(
    'Tourist signup requires an unchecked Privacy Notice acknowledgment',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SignupScreen()));
      final checkbox = find.byType(CheckboxListTile);
      await tester.ensureVisible(checkbox);
      expect(tester.widget<CheckboxListTile>(checkbox).value, isFalse);
      await tester.tap(find.text('Create Account'));
      await tester.pump();
      expect(
        find.textContaining('Please read and acknowledge'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('TourisTrike Privacy Notice'));
      await tester.tap(find.text('TourisTrike Privacy Notice'));
      await tester.pumpAndSettle();
      expect(find.text('TOURISTRIKE PRIVACY NOTICE'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(checkbox);
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<CheckboxListTile>(checkbox).value, isTrue);
      await tester.ensureVisible(find.text('Create Account'));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();
      expect(find.text('Please fill in all fields.'), findsOneWidget);
    },
  );

  testWidgets(
    'existing Terms route contains all sections in a scrollable page',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: TermsScreen()));
      expect(
        find.text('TOURISTRIKE BOOKING TERMS AND CONDITIONS'),
        findsOneWidget,
      );
      expect(find.text('1. Booking Information'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
      await tester.scrollUntilVisible(find.text('13. Acceptance'), 500);
      expect(find.text('13. Acceptance'), findsOneWidget);
      expect(bookingTermsVersion, '1.1');
    },
  );

  testWidgets('existing Privacy route shows versioned notice', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PrivacyPolicyScreen()));
    expect(find.text('TOURISTRIKE PRIVACY NOTICE'), findsOneWidget);
    expect(find.text('1. Information We Process'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('8. Acknowledgment'), 500);
    expect(find.text('8. Acknowledgment'), findsOneWidget);
    expect(privacyNoticeVersion, '1.1');
  });

  testWidgets(
    'booking confirmation requires initially unchecked Terms acceptance',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookingReviewSheet(
              summary: const [(label: 'Tour', value: 'Sample')],
              itinerary: const [],
              onViewPolicies: () {},
              isSameDay: true,
            ),
          ),
        ),
      );
      final button = find.widgetWithText(
        FilledButton,
        'Confirm & Submit Booking',
      );
      expect(tester.widget<FilledButton>(button).onPressed, isNull);
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(
        find.textContaining('Same-day bookings do not require a downpayment'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.byType(CheckboxListTile));
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    },
  );

  test('server migration stamps version and time and enforces cutoff', () {
    final sql = File(
      'supabase/migrations/20260930020000_booking_notices_cancellation_policy.sql',
    ).readAsStringSync();
    expect(sql, contains('new.terms_accepted_at := now()'));
    expect(sql, contains('new.privacy_notice_acknowledged_at := now()'));
    expect(sql, contains("b.scheduled_start_at > now() + interval '24 hours'"));
    expect(sql, contains("pr.status='confirmed'"));
    expect(sql, contains('withdrawal_reason_code=p_reason'));
    expect(sql, contains('WITHDRAWAL_REASON_REQUIRED'));
    expect(sql, contains('NOT_BOOKING_OWNER'));
  });
}
