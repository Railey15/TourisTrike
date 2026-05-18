import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'city_admin_application.dart';
import 'web_portal_login_screen.dart';

class CityAdminVerifyOtpScreen extends StatefulWidget {
  const CityAdminVerifyOtpScreen({super.key, required this.application});

  final CityAdminApplicationDraft application;

  @override
  State<CityAdminVerifyOtpScreen> createState() =>
      _CityAdminVerifyOtpScreenState();
}

class _CityAdminVerifyOtpScreenState extends State<CityAdminVerifyOtpScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _otpCtrl = TextEditingController();

  static const int _otpLength = 8;

  bool _loading = false;
  bool _submitted = false;
  String _submittedStatus = 'pending';
  String _submittedMessage =
      'Your request is now waiting for provincial admin review.';

  @override
  void dispose() {
    _otpCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool error = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(18),
        ),
      );
  }

  Future<void> _verifyAndSubmit() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != _otpLength) {
      _showSnack('Enter the $_otpLength-digit code.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    bool sessionOpened = false;
    try {
      await _supabase.auth.verifyOTP(
        type: OtpType.email,
        email: widget.application.normalizedEmail,
        token: otp,
      );
      sessionOpened = true;

      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw StateError('Verified, but no session was created.');
      }

      try {
        await _supabase.auth.updateUser(
          UserAttributes(password: widget.application.password),
        );
      } on AuthException catch (e) {
        if (!e.message.toLowerCase().contains('different')) rethrow;
        // Password is already set to this value — safe to continue.
      }

      final status = await _submitApplication(user.id);

      if (!mounted) return;
      setState(() {
        _submitted = true;
        _submittedStatus = status;
        _submittedMessage = status == 'approved'
            ? 'Your city admin account has already been approved. You can sign in now.'
            : status == 'pending'
            ? 'Your request is now waiting for provincial admin review.'
            : 'Your city admin application was submitted.';
      });
    } on AuthException catch (e) {
      _showSnack(e.message);
    } on PostgrestException catch (e) {
      _showSnack('Submission failed: ${e.message}');
    } catch (e) {
      _showSnack('Verification failed: $e');
    } finally {
      if (sessionOpened && _supabase.auth.currentUser != null) {
        await _supabase.auth.signOut();
      }
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<String> _submitApplication(String userId) async {
    try {
      final nameParts = widget.application.contactNameParts;
      final result = await _supabase.rpc(
        'submit_city_admin_application',
        params: {
          'p_city': widget.application.normalizedCity,
          'p_office_name': widget.application.displayOffice,
          'p_contact_person': widget.application.contactPerson.trim(),
          'p_contact_number': widget.application.contactNumber.trim(),
          'p_email': widget.application.normalizedEmail,
          'p_office_address': widget.application.officeAddress.trim(),
          'p_first_name': nameParts['first_name'] ?? '',
          'p_last_name': nameParts['last_name'] ?? '',
        },
      );

      if (result is Map) {
        return (result['status'] ?? 'pending').toString().toLowerCase();
      }
      return 'pending';
    } on PostgrestException catch (e) {
      final message = e.message.toLowerCase();
      final functionMissing = e.code == '42883' || message.contains('function');
      if (!functionMissing) rethrow;
      return _submitApplicationWithTables(userId);
    }
  }

  Future<String> _submitApplicationWithTables(String userId) async {
    // PostgREST may not immediately recognize auth.uid() right after OTP
    // verification. Retry once with a brief delay to handle this timing window.
    for (int attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) {
        await Future.delayed(const Duration(seconds: 2));
      }
      try {
        final latestRegistration = await _latestRegistration(userId);
        final latestStatus = latestRegistration == null
            ? ''
            : (latestRegistration['status'] ?? '').toString().toLowerCase();

        if (latestStatus == 'pending' || latestStatus == 'approved') {
          return latestStatus;
        }

        await _ensureApplicantProfile(userId);
        await _supabase
            .from('city_tenant_registrations')
            .insert(widget.application.registrationPayload(userId));
        return 'pending';
      } on PostgrestException catch (e) {
        if (attempt < 1 &&
            e.message.toLowerCase().contains('row-level security')) {
          continue;
        }
        rethrow;
      }
    }
    throw StateError('Failed to submit application after retries.');
  }

  Future<void> _ensureApplicantProfile(String userId) async {
    final existing = await _supabase
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();

    if (existing == null) {
      await _supabase
          .from('profiles')
          .insert(widget.application.profileInsertPayload(userId));
      return;
    }

    final role = (existing['role'] ?? '').toString().toLowerCase().trim();
    if (role.isNotEmpty && role != 'tourist') {
      throw StateError(
        'This email already belongs to a $role account. Use a dedicated office email or contact the main admin.',
      );
    }

    await _supabase
        .from('profiles')
        .update(widget.application.profileUpdatePayload())
        .eq('id', userId);
  }

  Future<Map<String, dynamic>?> _latestRegistration(String userId) async {
    final rows = await _supabase
        .from('city_tenant_registrations')
        .select('status, rejection_reason')
        .eq('user_id', userId)
        .order('submitted_at', ascending: false)
        .limit(1);

    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first);
  }

  Future<void> _resend() async {
    setState(() => _loading = true);
    try {
      await _supabase.auth.signInWithOtp(
        email: widget.application.normalizedEmail,
        shouldCreateUser: true,
      );
      _showSnack('Verification code sent again.', error: false);
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Resend failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openLogin() {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const WebPortalLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted) {
      return _ApplicationSubmittedView(
        status: _submittedStatus,
        message: _submittedMessage,
        onLogin: _openLogin,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 860;
          return Stack(
            children: [
              const Positioned.fill(child: _VerifyBackdrop()),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 40 : 18,
                      vertical: 24,
                    ),
                    child: Container(
                      width: double.infinity,
                      constraints: const BoxConstraints(maxWidth: 470),
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.96),
                        borderRadius: BorderRadius.circular(28),
                        border: Border.all(color: Colors.white),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 32,
                            offset: const Offset(0, 22),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEAF4FF),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.mark_email_read_rounded,
                                  color: Color(0xFF2A86FF),
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Verify Email',
                                      style: TextStyle(
                                        color: Color(0xFF0F172A),
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'City admin application',
                                      style: TextStyle(
                                        color: Color(0xFF64748B),
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            widget.application.normalizedEmail,
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _otpCtrl,
                            keyboardType: TextInputType.number,
                            maxLength: _otpLength,
                            onSubmitted: (_) {
                              if (!_loading) _verifyAndSubmit();
                            },
                            decoration: InputDecoration(
                              counterText: '',
                              labelText: '$_otpLength-digit code',
                              prefixIcon: const Icon(
                                Icons.pin_outlined,
                                color: Color(0xFF94A3B8),
                              ),
                              filled: true,
                              fillColor: const Color(0xFFF8FBFF),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2ECF8),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFFE2ECF8),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(16),
                                borderSide: const BorderSide(
                                  color: Color(0xFF2A86FF),
                                  width: 1.2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: ElevatedButton.icon(
                              onPressed: _loading ? null : _verifyAndSubmit,
                              icon: _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.verified_rounded),
                              label: Text(
                                _loading
                                    ? 'Submitting...'
                                    : 'Verify and Submit',
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF2A86FF),
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: const Color(
                                  0xFF93C5FD,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(17),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Center(
                            child: TextButton(
                              onPressed: _loading ? null : _resend,
                              child: const Text('Resend code'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ApplicationSubmittedView extends StatelessWidget {
  const _ApplicationSubmittedView({
    required this.status,
    required this.message,
    required this.onLogin,
  });

  final String status;
  final String message;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    final approved = status == 'approved';
    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFF),
      body: Stack(
        children: [
          const Positioned.fill(child: _VerifyBackdrop()),
          SafeArea(
            child: Center(
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 480),
                margin: const EdgeInsets.all(18),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.96),
                  borderRadius: BorderRadius.circular(28),
                  border: Border.all(color: Colors.white),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 32,
                      offset: const Offset(0, 22),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color:
                            (approved
                                    ? const Color(0xFF16A34A)
                                    : const Color(0xFFF59E0B))
                                .withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        approved
                            ? Icons.check_circle_rounded
                            : Icons.hourglass_top_rounded,
                        color: approved
                            ? const Color(0xFF16A34A)
                            : const Color(0xFFF59E0B),
                        size: 34,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      approved
                          ? 'Application Approved'
                          : 'Application Submitted',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 14,
                        height: 1.45,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 22),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: onLogin,
                        icon: const Icon(Icons.login_rounded),
                        label: const Text('Go to Sign In'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2A86FF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _VerifyBackdrop extends StatelessWidget {
  const _VerifyBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFEAF5FF), Color(0xFFF6FAFF), Color(0xFFEFFAF5)],
        ),
      ),
      child: SizedBox.expand(),
    );
  }
}
