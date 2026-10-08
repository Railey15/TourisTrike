// lib/screens/auth/verify_email_otp_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/auth/complete_registration.dart';
import '../../widgets/email_otp_input.dart';

import 'complete_profile_screen.dart';
import 'complete_profile_driver_screen.dart';
import 'signup_screen.dart';

class VerifyEmailOtpScreen extends StatefulWidget {
  const VerifyEmailOtpScreen({
    super.key,
    required this.email,
  });

  final String email;

  @override
  State<VerifyEmailOtpScreen> createState() => _VerifyEmailOtpScreenState();
}

class _VerifyEmailOtpScreenState extends State<VerifyEmailOtpScreen> {
  final supabase = Supabase.instance.client;

  // Matches the linked project's hosted Auth mailer_otp_length setting.
  static const int _otpLen = 8;

  final _otpCtrl = TextEditingController();
  bool _loading = false;
  int _resendSeconds = 60;
  Timer? _resendTimer;

  @override
  void initState() {
    super.initState();
    _otpCtrl.addListener(_onCodeChanged);
    _startCooldown();
  }

  void _onCodeChanged() => setState(() {});

  void _startCooldown() {
    _resendTimer?.cancel();
    _resendSeconds = 60;
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      setState(() => _resendSeconds--);
      if (_resendSeconds <= 0) timer.cancel();
    });
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpCtrl.removeListener(_onCodeChanged);
    _otpCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  Future<void> _verify() async {
    final otp = _otpCtrl.text.trim();

    if (otp.length != _otpLen) {
      _showSnack('Enter the $_otpLen-digit code.');
      return;
    }

    setState(() => _loading = true);

    try {
      final response = await supabase.auth.verifyOTP(
        type: OtpType.email,
        email: widget.email,
        token: otp,
      );
      assert(() {
        debugPrint('[Signup OTP] verify response userReturned=${response.user != null} '
            'sessionReturned=${response.session != null}');
        return true;
      }());

      final user = (await supabase.auth.getUser()).user;
      if (response.session == null || user == null ||
          user.emailConfirmedAt == null ||
          user.email?.toLowerCase() != widget.email.toLowerCase()) {
        _showSnack('We could not verify your email right now. Please try again.');
        return;
      }
      final role = await completeConfirmedRegistration(supabase);
      if (role != 'tourist' && role != 'driver') {
        _showSnack('We could not complete registration. Please contact support.');
        return;
      }

      if (!mounted) return;

      _showSnack('Email Verified. Your TourisTrike account has been verified.', isError: false);

      await Future.delayed(const Duration(milliseconds: 350));

      if (!mounted) return;

      if (role == 'driver') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const CompleteProfileDriverScreen(),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CompleteProfileScreen()),
        );
      }
    } on AuthException catch (e) {
      assert(() {
        debugPrint('[Signup OTP] verify rejected code=${e.code} status=${e.statusCode}');
        return true;
      }());
      final message = e.message.toLowerCase();
      _showSnack(e.statusCode == '429' || message.contains('rate limit')
          ? 'Please wait before requesting another verification code.'
          : message.contains('expired')
              ? 'This verification code has expired. Request a new code to continue.'
              : message.contains('invalid') || message.contains('incorrect')
                  ? 'The verification code is incorrect. Please try again.'
                  : "We couldn't verify your email right now. Please try again.");
    } catch (_) {
      _showSnack("We couldn't verify your email right now. Please try again.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_loading || _resendSeconds > 0) return;
    setState(() => _loading = true);

    try {
      assert(() {
        debugPrint('[Signup OTP] resend requested');
        return true;
      }());
      await supabase.auth.resend(
        type: OtpType.signup,
        email: widget.email,
      );
      assert(() {
        debugPrint('[Signup OTP] resend accepted');
        return true;
      }());
      if (mounted) setState(_startCooldown);
      _showSnack('OTP sent again. Check your email.', isError: false);
    } on AuthException catch (e) {
      assert(() {
        debugPrint('[Signup OTP] resend rejected code=${e.code} status=${e.statusCode}');
        return true;
      }());
      _showSnack(e.statusCode == '429'
          ? 'Please wait before requesting another verification code.'
          : "We couldn't send a new code right now. Please try again.");
    } catch (_) {
      _showSnack("We couldn't send a new code right now. Please try again.");
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Stack(
          children: [
            const Positioned.fill(child: _VerifyBackdrop()),
            SafeArea(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(20, 18, 20, bottomInset + 26),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TopBar(onBack: () => Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (_) => const SignupScreen()),
                        )),
                        const SizedBox(height: 28),
                        const _HeroIcon(),
                        const SizedBox(height: 24),
                        const Text(
                          'Verify Your Email',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 32,
                            height: 1.08,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'We sent a verification code to your email.\nEnter the code below to complete your registration.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 15,
                            height: 1.45,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _EmailPill(email: widget.email),
                        const SizedBox(height: 24),
                        _VerifyCard(
                          otpCtrl: _otpCtrl,
                          otpLength: _otpLen,
                          loading: _loading,
                          resendSeconds: _resendSeconds,
                          onVerify: _verify,
                          onResend: _resend,
                        ),
                        TextButton(
                          onPressed: _loading ? null : () => Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (_) => const SignupScreen()),
                          ),
                          child: const Text('Wrong email? Go Back'),
                        ),
                        const SizedBox(height: 18),
                        const _SecurityNote(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: Colors.white.withValues(alpha: 0.94),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onBack,
            customBorder: const CircleBorder(),
            child: const SizedBox(
              width: 48,
              height: 48,
              child: Icon(
                Icons.arrow_back_rounded,
                color: Color(0xFF0F172A),
                size: 25,
              ),
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE2ECF8)),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.mark_email_read_rounded,
                color: Color(0xFF2A86FF),
                size: 17,
              ),
              SizedBox(width: 7),
              Text(
                'Email OTP',
                style: TextStyle(
                  color: Color(0xFF475569),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 104,
        height: 104,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEAF5FF), Color(0xFFFFFFFF)],
          ),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(color: Colors.white, width: 1.4),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2A86FF).withValues(alpha: 0.16),
              blurRadius: 30,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: const Icon(
          Icons.lock_clock_rounded,
          color: Color(0xFF2A86FF),
          size: 48,
        ),
      ),
    );
  }
}

class _EmailPill extends StatelessWidget {
  const _EmailPill({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2ECF8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.05),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: const BoxDecoration(
              color: Color(0xFFEAF2FF),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.mail_outline_rounded,
              color: Color(0xFF2A86FF),
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              maskVerificationEmail(email),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 14.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifyCard extends StatelessWidget {
  const _VerifyCard({
    required this.otpCtrl,
    required this.otpLength,
    required this.loading,
    required this.resendSeconds,
    required this.onVerify,
    required this.onResend,
  });

  final TextEditingController otpCtrl;
  final int otpLength;
  final bool loading;
  final int resendSeconds;
  final VoidCallback onVerify;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Verification Code',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 15,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(height: 10),
          EmailOtpInput(controller: otpCtrl, length: otpLength),
          const SizedBox(height: 18),
          SizedBox(
            height: 58,
            width: double.infinity,
            child: _GradientButton(
              text: loading ? 'Verifying...' : 'Verify Email',
              loading: loading,
              onPressed: loading || otpCtrl.text.length != otpLength ? null : onVerify,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text(
                'Didn’t receive the code?',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              TextButton(
                onPressed: loading || resendSeconds > 0 ? null : onResend,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(10, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: const Color(0xFF2A86FF),
                ),
                child: Text(
                  resendSeconds > 0 ? 'Resend code in ${resendSeconds}s' : 'Resend Code',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SecurityNote extends StatelessWidget {
  const _SecurityNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD6E8FF)),
      ),
      child: const Row(
        children: [
          Icon(Icons.verified_user_rounded, color: Color(0xFF2A86FF), size: 22),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'This step protects your account and confirms that the email belongs to you.',
              style: TextStyle(
                color: Color(0xFF475569),
                fontSize: 12.8,
                height: 1.4,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.text,
    required this.onPressed,
    this.loading = false,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: onPressed == null
            ? const LinearGradient(
                colors: [Color(0xFFCBD5E1), Color(0xFF94A3B8)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF5BB2FF),
                  Color(0xFF2A86FF),
                  Color(0xFF1D4ED8),
                ],
              ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: onPressed == null
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFF2A86FF).withValues(alpha: 0.28),
                  blurRadius: 22,
                  offset: const Offset(0, 12),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ),
      ),
    );
  }
}

class _VerifyBackdrop extends StatelessWidget {
  const _VerifyBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF7FBFF), Color(0xFFEAF5FF), Color(0xFFF8FAFC)],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned(
          top: -100,
          right: -80,
          child: _BlurCircle(
            size: 240,
            color: const Color(0xFF2A86FF).withValues(alpha: 0.10),
          ),
        ),
        Positioned(
          top: 250,
          left: -90,
          child: _BlurCircle(
            size: 190,
            color: const Color(0xFF38BDF8).withValues(alpha: 0.10),
          ),
        ),
        Positioned(
          bottom: -95,
          right: -90,
          child: _BlurCircle(
            size: 230,
            color: const Color(0xFF16A34A).withValues(alpha: 0.08),
          ),
        ),
      ],
    );
  }
}

class _BlurCircle extends StatelessWidget {
  const _BlurCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
