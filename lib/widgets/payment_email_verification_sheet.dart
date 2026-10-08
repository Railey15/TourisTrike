import 'dart:async';

import 'package:flutter/material.dart';
import '../core/supabase/touristrike_repository.dart';
import 'email_otp_input.dart';

class PaymentEmailVerificationSheet extends StatefulWidget {
  const PaymentEmailVerificationSheet({
    super.key,
    required this.repository,
    required this.bookingId,
    required this.paymentStage,
    required this.registeredEmail,
  });

  final TourisTrikeRepository repository;
  final String bookingId;
  final String paymentStage;
  final String registeredEmail;

  @override
  State<PaymentEmailVerificationSheet> createState() =>
      _PaymentEmailVerificationSheetState();
}

class _PaymentEmailVerificationSheetState
    extends State<PaymentEmailVerificationSheet> {
  final _code = TextEditingController();
  Timer? _timer;
  int _seconds = 0;
  bool _sending = false;
  bool _verifying = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _code.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) => _request());
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _timer?.cancel();
    _code.removeListener(_changed);
    _code.dispose();
    super.dispose();
  }

  String _message(String code, {bool sending = false}) {
    switch (code) {
      case 'INCORRECT':
        return 'The verification code is incorrect. Please try again.';
      case 'EXPIRED':
        return 'This verification code has expired. Request a new code to continue.';
      case 'RATE_LIMITED':
        return 'Please wait before requesting another verification code.';
      case 'VERIFICATION_UNAVAILABLE':
        return sending
            ? 'We could not send a code right now. Please try again later.'
            : 'Verification is unavailable right now. Please try again later.';
      default:
        return sending
            ? "We couldn't send a code right now. Please try again."
            : "We couldn't verify the code right now. Please try again.";
    }
  }

  void _cooldown() {
    _timer?.cancel();
    setState(() => _seconds = 30);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _seconds--);
      if (_seconds <= 0) timer.cancel();
    });
  }

  Future<void> _request() async {
    if (!mounted || _sending || _verifying || _seconds > 0) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.repository.paymentEmailVerification(
        action: 'request',
        bookingId: widget.bookingId,
        paymentStage: widget.paymentStage,
      );
      if (mounted) _cooldown();
    } on PaymentProviderException catch (error) {
      if (mounted) setState(() => _error = _message(error.code, sending: true));
    } catch (_) {
      if (mounted) setState(() => _error = _message('NETWORK', sending: true));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verify() async {
    if (_verifying || _sending || _code.text.length != 6) return;
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      await widget.repository.paymentEmailVerification(
        action: 'verify',
        bookingId: widget.bookingId,
        paymentStage: widget.paymentStage,
        code: _code.text,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Email Verified')));
      Navigator.pop(context, true);
    } on PaymentProviderException catch (error) {
      if (mounted) setState(() => _error = _message(error.code));
    } catch (_) {
      if (mounted) setState(() => _error = _message('NETWORK'));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          22,
          12,
          22,
          MediaQuery.viewInsetsOf(context).bottom + 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.mark_email_read_outlined,
                  color: Color(0xFF2A86FF),
                  size: 48,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Verify Before Payment',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  'For your security, enter the verification code sent to your registered email before continuing to payment.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  maskVerificationEmail(widget.registeredEmail),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(height: 22),
                EmailOtpInput(controller: _code),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFDC2626)),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed:
                        _code.text.length == 6 && !_sending && !_verifying
                        ? _verify
                        : null,
                    child: Text(
                      _verifying ? 'Verifying...' : 'Verify & Continue',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _seconds == 0 && !_sending && !_verifying
                      ? _request
                      : null,
                  child: Text(
                    _sending
                        ? 'Sending...'
                        : _seconds > 0
                        ? 'Resend code in ${_seconds}s'
                        : 'Resend Code',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
