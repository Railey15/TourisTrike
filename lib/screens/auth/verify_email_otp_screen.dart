// lib/screens/auth/verify_email_otp_screen.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'complete_profile_screen.dart';
import 'complete_profile_driver_screen.dart';

class VerifyEmailOtpScreen extends StatefulWidget {
  const VerifyEmailOtpScreen({
    super.key,
    required this.email,
    required this.roleString,
    required this.password, // ✅ needed to set password after OTP verify
  });

  final String email;
  final String roleString; // 'tourist' or 'driver'
  final String password;

  @override
  State<VerifyEmailOtpScreen> createState() => _VerifyEmailOtpScreenState();
}

class _VerifyEmailOtpScreenState extends State<VerifyEmailOtpScreen> {
  final supabase = Supabase.instance.client;

  // ✅ based on your React Native app (OTP_LEN = 8)
  static const int _otpLen = 8;

  final _otpCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _verify() async {
    final otp = _otpCtrl.text.trim();

    if (otp.length != _otpLen) {
      _showSnack('Enter the $_otpLen-digit code.');
      return;
    }

    setState(() => _loading = true);

    try {
      // 1) Verify OTP (creates session)
      await supabase.auth.verifyOTP(
        type: OtpType.email,
        email: widget.email,
        token: otp,
      );

      final user = supabase.auth.currentUser;
      if (user == null) {
        _showSnack('Verified, but no session found. Please try again.');
        return;
      }

      // 2) ✅ Set password so they can login later with email+password
      await supabase.auth.updateUser(
        UserAttributes(password: widget.password),
      );

      // 3) Upsert profile row (role)
      await supabase.from('profiles').upsert({
        'id': user.id,
        'role': widget.roleString,
      });

      // 4) ✅ Navigate based on role
      if (!mounted) return;

      if (widget.roleString == 'driver') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CompleteProfileDriverScreen()),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CompleteProfileScreen()),
        );
      }
    } on AuthException catch (e) {
      _showSnack(e.message);
    } on PostgrestException catch (e) {
      _showSnack('DB error: ${e.message}');
    } catch (e) {
      _showSnack('Verify failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _loading = true);
    try {
      await supabase.auth.signInWithOtp(
        email: widget.email,
        shouldCreateUser: true, // ✅ same as RN mode === "signup"
      );
      _showSnack('OTP sent again. Check your email.');
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Resend failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Verify Email',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
          ),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              Text(
                'Enter the $_otpLen-digit code sent to:',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF64748B).withOpacity(0.95),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.email,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 18),

              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: _otpLen,
                  decoration: InputDecoration(
                    counterText: '',
                    border: InputBorder.none,
                    hintText: '0' * _otpLen,
                  ),
                ),
              ),

              const SizedBox(height: 14),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _verify,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A86FF),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _loading ? 'Verifying...' : 'Verify',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              TextButton(
                onPressed: _loading ? null : _resend,
                child: const Text('Resend code'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}