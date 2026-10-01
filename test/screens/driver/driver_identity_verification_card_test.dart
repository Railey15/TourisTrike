import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/driver/profile/driver_identity_status.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_identity_verification_card.dart';

class _FakeDriverProfileService extends DriverProfileService {
  _FakeDriverProfileService()
    : super(
        client: SupabaseClient(
          'https://example.test',
          'test-anon-key',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  DriverIdentityStatus current = const DriverIdentityStatus('not_verified');
  Completer<({DriverIdentityStatus status, Uri? url})>? pendingStart;
  int fetches = 0;
  int starts = 0;

  @override
  Future<DriverIdentityStatus> fetchIdentityVerificationStatus() async {
    fetches++;
    return current;
  }

  @override
  Future<({DriverIdentityStatus status, Uri? url})>
  startIdentityVerification() async {
    starts++;
    return pendingStart!.future;
  }
}

void main() {
  test(
    'identity status labels keep provider approval separate from MTO approval',
    () {
      expect(const DriverIdentityStatus('approved').label, 'Identity verified');
      expect(
        const DriverIdentityStatus('approved').description,
        contains('MTO approval'),
      );
      expect(const DriverIdentityStatus('declined').canStart, isTrue);
      expect(const DriverIdentityStatus('in_review').canStart, isFalse);
    },
  );

  testWidgets(
    'button locks while loading and app resume fetches authoritative result',
    (tester) async {
      final service = _FakeDriverProfileService();
      service.pendingStart = Completer();
      var opens = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DriverIdentityVerificationCard(
              service: service,
              openUrl: (_) async {
                opens++;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Not verified'), findsOneWidget);
      await tester.tap(find.text('Verify Identity'));
      await tester.pump();
      expect(service.pendingStart!.isCompleted, isFalse);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      service.current = const DriverIdentityStatus('in_progress');
      service.pendingStart!.complete((
        status: const DriverIdentityStatus('not_started'),
        url: Uri.parse('https://verify.didit.me/session/test'),
      ));
      await tester.pump();
      await tester.pump();
      expect(opens, 1);
      expect(find.text('Identity Verified'), findsNothing);
      service.current = const DriverIdentityStatus('approved');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Identity Verified'), findsOneWidget);
      expect(service.fetches, greaterThanOrEqualTo(3));
    },
  );

  testWidgets('backend start error is visible and button can be retried', (
    tester,
  ) async {
    final service = _FakeDriverProfileService();
    service.pendingStart = Completer();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DriverIdentityVerificationCard(service: service)),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Verify Identity'));
    service.pendingStart!.completeError(StateError('backend unavailable'));
    await tester.pump();
    expect(
      find.textContaining('Could not open identity verification'),
      findsOneWidget,
    );
    expect(find.text('Verify Identity'), findsOneWidget);
  });

  testWidgets(
    'approved backend proof shows safe document class and verified date without a start action',
    (tester) async {
      final service = _FakeDriverProfileService();
      service.current = DriverIdentityStatus(
        'approved',
        verifiedAt: DateTime.utc(2026, 10, 1, 12),
        verifiedDocumentType: "Driver's License",
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DriverIdentityVerificationCard(
              service: service,
              mtoApprovalStatus: 'pending',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Identity Verified'), findsOneWidget);
      expect(find.text('Verified ✓'), findsOneWidget);
      expect(find.text("Driver's License"), findsOneWidget);
      expect(find.text('Verified on Oct 1, 2026'), findsOneWidget);
      expect(find.text('Verify Identity'), findsNothing);
      expect(find.text('Driver-Tour Guide Approval'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.textContaining('MTO'), findsOneWidget);
      expect(service.starts, 0);
      expect(find.textContaining('PRIVATE-NUMBER'), findsNothing);
      expect(find.textContaining('selfie'), findsNothing);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DriverIdentityVerificationCard(
              service: service,
              mtoApprovalStatus: 'rejected',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Identity Verified'), findsOneWidget);
      expect(find.text('Rejected'), findsOneWidget);
      expect(service.starts, 0);

      service.current = const DriverIdentityStatus('in_review');
      await tester.tap(find.text('Refresh status'));
      await tester.pump();
      expect(find.text('Identity Verified'), findsNothing);
      expect(find.text('Under review'), findsOneWidget);
      expect(service.starts, 0);

      service.current = DriverIdentityStatus(
        'approved',
        verifiedAt: DateTime.utc(2026, 10, 1, 12),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Identity Verified'), findsOneWidget);
      expect(find.text('Government-issued ID'), findsOneWidget);
      expect(find.text('Verified on Oct 1, 2026'), findsOneWidget);
      expect(find.text('Verify Identity'), findsNothing);
      expect(service.starts, 0);
    },
  );

  test('unknown or unapproved document details never become proof', () {
    expect(
      const DriverIdentityStatus(
        'approved',
        verifiedDocumentType: 'untrusted',
      ).verifiedIdLabel,
      'Government-issued ID',
    );
    for (final state in [
      'not_verified',
      'creating',
      'not_started',
      'in_progress',
      'in_review',
      'declined',
      'expired',
    ]) {
      expect(DriverIdentityStatus(state).label, isNot('Identity Verified'));
    }
  });

  testWidgets('verified proof fits a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final service = _FakeDriverProfileService();
    service.current = DriverIdentityStatus(
      'approved',
      verifiedAt: DateTime.utc(2026, 10, 1, 12),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: DriverIdentityVerificationCard(
              service: service,
              mtoApprovalStatus: 'approved',
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('Identity Verified'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);
  });
}
