import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:touristrike/core/supabase/touristrike_repository.dart';

/// Collection-leg Checkout integration (see docs/payment-architecture.md
/// Phase C3). Reused from two contexts:
///   - The advanced+GCash booking confirm step (package_booking_screen.dart)
///     for the down payment — the booking was just created hidden from
///     drivers ('pending_payment'); [allowCancelBooking] is true there so
///     the tourist can back out of the booking entirely if they change
///     their mind or the payment doesn't go through.
///   - The Tour Tracking screen's Remaining Balance card, on an already-
///     active booking — cancelling the booking makes no sense mid-tour,
///     so [allowCancelBooking] stays false (default) there.
///
/// This screen always calls the same paymongo-create-checkout Edge Function
/// regardless of stub/live mode. Today that function is hardcoded to stub
/// mode (PAYMONGO_MODE defaults to "stub" and live mode throws), so this
/// screen shows a clearly-labeled simulator standing in for PayMongo's
/// hosted Checkout page. Tapping "Simulate Successful Payment" drives the
/// exact same `record_payment_and_create_payouts` RPC a real PayMongo
/// webhook would call — the resulting payment_records/payout_records rows
/// are indistinguishable from ones a real payment would have produced.
class PaymentCheckoutScreen extends StatefulWidget {
  const PaymentCheckoutScreen({
    super.key,
    required this.bookingId,
    required this.paymentStage,
    required this.amount,
    required this.description,
    this.allowCancelBooking = false,
  });

  final dynamic bookingId;
  final String paymentStage;
  final double amount;
  final String description;
  final bool allowCancelBooking;

  @override
  State<PaymentCheckoutScreen> createState() => _PaymentCheckoutScreenState();
}

enum _CheckoutStatus { starting, ready, resolving, succeeded, failed, error }

class _PaymentCheckoutScreenState extends State<PaymentCheckoutScreen> {
  final _repo = TourisTrikeRepository();

  _CheckoutStatus _status = _CheckoutStatus.starting;
  String? _checkoutId;
  String? _mode;
  String? _errorMessage;
  bool _cancelling = false;

  bool get _blocksBackNavigation => widget.allowCancelBooking && _status != _CheckoutStatus.succeeded;

  @override
  void initState() {
    super.initState();
    _startCheckout();
  }

  Future<void> _startCheckout() async {
    setState(() {
      _status = _CheckoutStatus.starting;
      _errorMessage = null;
    });
    try {
      final result = await _repo.createCheckoutSession(
        bookingId: widget.bookingId,
        paymentStage: widget.paymentStage,
        amount: widget.amount,
        description: widget.description,
      );
      if (!mounted) return;
      setState(() {
        _checkoutId = result['checkout_id'] as String?;
        _mode = result['mode'] as String?;
        _status = _CheckoutStatus.ready;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _CheckoutStatus.error;
        _errorMessage = 'Unable to start checkout: $e';
      });
    }
  }

  Future<void> _resolve(bool success) async {
    final checkoutId = _checkoutId;
    if (checkoutId == null || _status == _CheckoutStatus.resolving) return;
    setState(() => _status = _CheckoutStatus.resolving);
    try {
      await _repo.resolveStubCheckout(
        checkoutId: checkoutId,
        bookingId: widget.bookingId,
        paymentStage: widget.paymentStage,
        amount: widget.amount,
        success: success,
      );
      if (!mounted) return;
      setState(() => _status = success ? _CheckoutStatus.succeeded : _CheckoutStatus.failed);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = _CheckoutStatus.error;
        _errorMessage = 'Unable to resolve checkout: $e';
      });
    }
  }

  Future<bool> _confirmCancelBooking() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: const Text(
          'No driver has been matched yet — cancelling now abandons the '
          'booking entirely. You can start a new booking any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep Booking'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _cancelBooking() async {
    if (_cancelling) return;
    final confirmed = await _confirmCancelBooking();
    if (!confirmed || !mounted) return;
    setState(() => _cancelling = true);
    try {
      await _repo.cancelPendingPaymentBooking(widget.bookingId);
      if (!mounted) return;
      Navigator.of(context).pop(false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cancelling = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Unable to cancel booking: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = NumberFormat.currency(symbol: '₱', decimalDigits: 2);
    final onCancelBooking = widget.allowCancelBooking ? _cancelBooking : null;
    return PopScope(
      canPop: !_blocksBackNavigation,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_status == _CheckoutStatus.resolving) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please wait for the payment to resolve.')),
          );
          return;
        }
        _cancelBooking();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('PayMongo Checkout'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF0F172A),
          elevation: 0,
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: switch (_status) {
              _CheckoutStatus.starting => const Center(child: CircularProgressIndicator()),
              _CheckoutStatus.error => _ErrorView(
                message: _errorMessage ?? 'Something went wrong.',
                onRetry: _startCheckout,
              ),
              _CheckoutStatus.succeeded => const _ResultView(
                icon: Icons.check_circle_rounded,
                iconColor: Color(0xFF16A34A),
                title: 'Payment successful',
                body: 'This was a simulated PayMongo payment — no real money moved. '
                    'The booking now has a confirmed payment record, exactly as a real '
                    'PayMongo webhook would have created.',
              ),
              _CheckoutStatus.failed => _ResultView(
                icon: Icons.error_rounded,
                iconColor: const Color(0xFFDC2626),
                title: 'Payment failed',
                body: 'This was a simulated failure — no payment record was created, '
                    'matching how a real declined PayMongo payment behaves.',
                onRetry: _startCheckout,
                onCancelBooking: onCancelBooking,
                cancelling: _cancelling,
              ),
              _CheckoutStatus.ready ||
              _CheckoutStatus.resolving => _StubCheckoutView(
                amount: currency.format(widget.amount),
                description: widget.description,
                checkoutId: _checkoutId ?? '',
                mode: _mode ?? 'stub',
                resolving: _status == _CheckoutStatus.resolving,
                onSucceed: () => _resolve(true),
                onFail: () => _resolve(false),
                onCancelBooking: onCancelBooking,
                cancelling: _cancelling,
              ),
            },
          ),
        ),
      ),
    );
  }
}

class _StubCheckoutView extends StatelessWidget {
  const _StubCheckoutView({
    required this.amount,
    required this.description,
    required this.checkoutId,
    required this.mode,
    required this.resolving,
    required this.onSucceed,
    required this.onFail,
    this.onCancelBooking,
    this.cancelling = false,
  });

  final String amount;
  final String description;
  final String checkoutId;
  final String mode;
  final bool resolving;
  final VoidCallback onSucceed;
  final VoidCallback onFail;
  final VoidCallback? onCancelBooking;
  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3CD),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF5C542)),
            ),
            child: Row(
              children: [
                const Icon(Icons.science_rounded, color: Color(0xFFB45309)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    mode == 'live'
                        ? 'Live PayMongo mode — this build should not reach here.'
                        : 'STUB / TEST MODE — this stands in for PayMongo\'s hosted '
                              'Checkout page. No real money moves. Every other part of '
                              'this flow (the DB rows, the split, the status you\'ll see) '
                              'is real.',
                    style: const TextStyle(
                      color: Color(0xFFB45309),
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: const [
                BoxShadow(color: Color(0x14000000), blurRadius: 12, offset: Offset(0, 4)),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'Amount due',
                  style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  amount,
                  style: const TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF2A86FF),
                  ),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Checkout ID: $checkoutId',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              onPressed: resolving ? null : onSucceed,
              icon: resolving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Simulate Successful Payment'),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF16A34A)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: resolving ? null : onFail,
              icon: const Icon(Icons.highlight_off_rounded),
              label: const Text('Simulate Failed Payment'),
              style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFDC2626)),
            ),
          ),
          if (onCancelBooking != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 44,
              child: TextButton(
                onPressed: (resolving || cancelling) ? null : onCancelBooking,
                child: cancelling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Text(
                        'Cancel Booking',
                        style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
    this.onRetry,
    this.onCancelBooking,
    this.cancelling = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;
  final VoidCallback? onRetry;
  final VoidCallback? onCancelBooking;
  final bool cancelling;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 64, color: iconColor),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Color(0xFF0F172A)),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600, height: 1.4),
          ),
          const SizedBox(height: 24),
          if (onRetry != null)
            OutlinedButton(onPressed: onRetry, child: const Text('Try Again'))
          else
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFF2A86FF)),
              child: const Text('Done'),
            ),
          if (onCancelBooking != null) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: cancelling ? null : onCancelBooking,
              child: cancelling
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    )
                  : Text(
                      'Cancel Booking',
                      style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w700),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, size: 56, color: Color(0xFFDC2626)),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 20),
          FilledButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
