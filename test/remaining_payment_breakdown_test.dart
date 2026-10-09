import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/booking_waiting_balance.dart';
import 'package:touristrike/core/models/booking_payment_prompt.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/widgets/cash_confirmation_dialog.dart';
import 'package:touristrike/widgets/tour_stay_details.dart';

void main() {
  test('server waiting balance separates finalized and accrued amounts', () {
    final zero = BookingWaitingBalance.fromJson({
      'package_remaining': 1800,
      'finalized_waiting': 0,
      'accrued_waiting': 0,
      'total_remaining': 1800,
    });
    expect(zero.finalizedTotal, 1800);
    final charged = BookingWaitingBalance.fromJson({
      'package_remaining': 1800,
      'finalized_waiting': 150,
      'accrued_waiting': 25,
      'total_remaining': 1975,
    });
    expect(charged.finalizedTotal, 1950);
    expect(charged.accruedWaiting, 25);
    final laterFee = BookingWaitingBalance.fromJson({
      'package_remaining': 0,
      'finalized_waiting': 60,
      'accrued_waiting': 0,
      'total_remaining': 20,
    });
    expect(laterFee.payableWaiting, 20);
    expect(laterFee.finalizedTotal, 20);
    final paid = BookingWaitingBalance.fromJson({
      'package_remaining': 0,
      'finalized_waiting': 60,
      'accrued_waiting': 0,
      'total_remaining': 0,
    });
    expect(paid.payableWaiting, 0);
    expect(paid.finalizedTotal, 0);
  });

  test('payment record reads immutable component snapshot', () {
    final payment = PaymentRecord({
      'amount': 1950,
      'payment_stage': 'remaining_balance',
      'remaining_package_component': 1800,
      'additional_waiting_component': 150,
    });
    expect(payment.remainingPackageComponent, 1800);
    expect(payment.additionalWaitingComponent, 150);
    expect(payment.amount, 1950);
  });

  test('later waiting fee stays payable after an older larger receipt', () {
    final booking = PackageBooking({
      'id': 'booking',
      'required_drivers': 1,
      'accepted_drivers_count': 1,
      'status': 'ongoing',
      'booking_status': 'awaiting_remaining_payment',
      'total_amount': 3600,
      'downpayment_amount': 1800,
      'remaining_balance': 20,
    });
    final waiting = BookingWaitingBalance.fromJson({
      'package_remaining': 0,
      'finalized_waiting': 60,
      'accrued_waiting': 0,
      'total_remaining': 20,
    });
    final prompt = BookingPaymentPrompt.fromRecords(
      booking,
      [
        const PaymentRecord({
          'payment_stage': 'remaining_balance',
          'status': 'confirmed',
          'amount': 1800,
        }),
      ],
      stage: 'remaining_balance',
      requirement: {'status': 'required', 'amount': 20},
      downpaymentSatisfied: true,
      itineraryComplete: true,
      waitingBalance: waiting,
    );
    expect(prompt.confirmed, isFalse);
    expect(prompt.paymentRequired, isTrue);
    expect(prompt.amount, 20);
    expect(waiting.finalizedTotal, 20);
  });

  testWidgets('cash confirmation and summary display complete breakdown', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const TourPaymentSummary(
                packageBalance: 1800,
                additionalWaiting: 150,
                totalRemaining: 1950,
              ),
              CashConfirmationDialog(
                amount: 975,
                packageBalance: 1800,
                additionalWaiting: 150,
                totalRemaining: 1950,
                onConfirm: () async {},
              ),
            ],
          ),
        ),
      ),
    );
    expect(find.text('Remaining Package Balance'), findsNWidgets(2));
    expect(find.text('Additional Waiting Fee'), findsNWidgets(2));
    expect(find.text('Total Remaining Amount'), findsNWidgets(2));
    expect(find.text('₱1,950.00'), findsNWidgets(2));
    expect(find.text('₱975.00'), findsOneWidget);
  });
}
