import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/widgets/payment_email_verification_sheet.dart';

class _VerificationRepository extends TourisTrikeRepository {
  _VerificationRepository()
    : super(
        client: SupabaseClient(
          'https://example.supabase.co',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
        ),
      );

  final actions = <String>[];

  @override
  Future<void> paymentEmailVerification({
    required String action,
    required String bookingId,
    required String paymentStage,
    String? code,
  }) async {
    expect(bookingId, 'booking-1');
    expect(paymentStage, 'remaining_balance');
    actions.add(action);
    if (action == 'verify' && code != '123456') {
      throw const PaymentProviderException('INCORRECT');
    }
  }
}

void main() {
  testWidgets('invalid code blocks checkout and valid code continues once', (
    tester,
  ) async {
    final repository = _VerificationRepository();
    bool? verified;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                verified = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => PaymentEmailVerificationSheet(
                    repository: repository,
                    bookingId: 'booking-1',
                    paymentStage: 'remaining_balance',
                    registeredEmail: 'tourist@example.com',
                  ),
                );
              },
              child: const Text('Pay'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Pay'));
    await tester.pumpAndSettle();
    expect(repository.actions, ['request']);
    expect(find.text('Verify Before Payment'), findsOneWidget);
    expect(find.text('tourist@example.com'), findsNothing);
    expect(verified, isNull);

    await tester.enterText(find.byType(TextField), '000000');
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
    await tester.tap(find.text('Verify & Continue'));
    await tester.pumpAndSettle();
    expect(repository.actions, ['request', 'verify']);
    expect(find.textContaining('incorrect'), findsOneWidget);
    expect(verified, isNull);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verify & Continue'));
    await tester.pumpAndSettle();
    expect(repository.actions, ['request', 'verify', 'verify']);
    expect(verified, isTrue);
  });
}
