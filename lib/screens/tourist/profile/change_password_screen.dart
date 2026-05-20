import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ChangePasswordScreen extends StatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  static final RegExp _passwordSymbolRegex = RegExp(
    r'''[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;'`~/]''',
  );

  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _currentCtrl = TextEditingController();
  final TextEditingController _newCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();
  final TextEditingController _otpCtrl = TextEditingController();

  bool _sendingOtp = false;
  bool _verifying = false;
  bool _otpSent = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  String get _email => _supabase.auth.currentUser?.email?.trim() ?? '';

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              error ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
        ),
      );
  }

  List<String> _passwordErrors(String password) {
    final errors = <String>[];
    if (password.length < 8) errors.add('At least 8 characters');
    if (!RegExp(r'[A-Z]').hasMatch(password)) {
      errors.add('At least 1 uppercase letter');
    }
    if (!RegExp(r'[a-z]').hasMatch(password)) {
      errors.add('At least 1 lowercase letter');
    }
    if (!RegExp(r'\d').hasMatch(password)) errors.add('At least 1 number');
    if (!_passwordSymbolRegex.hasMatch(password)) {
      errors.add('At least 1 special character');
    }
    return errors;
  }

  Future<void> _sendOtp() async {
    final current = _currentCtrl.text;
    final next = _newCtrl.text;
    final confirm = _confirmCtrl.text;

    if (_email.isEmpty) {
      _showSnack('No email address found for this account.', error: true);
      return;
    }
    if (current.isEmpty || next.isEmpty || confirm.isEmpty) {
      _showSnack('Please fill in all password fields.', error: true);
      return;
    }
    if (next != confirm) {
      _showSnack('New password and confirmation do not match.', error: true);
      return;
    }
    if (next == current) {
      _showSnack('Choose a new password different from the current one.', error: true);
      return;
    }
    final errors = _passwordErrors(next);
    if (errors.isNotEmpty) {
      _showSnack('Password is too weak: ${errors.first}', error: true);
      return;
    }

    setState(() => _sendingOtp = true);
    try {
      await _supabase.auth.signInWithPassword(email: _email, password: current);
      await _supabase.auth.signInWithOtp(
        email: _email,
        shouldCreateUser: false,
      );
      if (!mounted) return;
      setState(() => _otpSent = true);
      _showSnack(
        'OTP sent to $_email. The code expires based on your Supabase email OTP settings.',
      );
    } on AuthException catch (e) {
      _showSnack(e.message, error: true);
    } catch (e) {
      _showSnack('Unable to send OTP right now.', error: true);
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _verifyAndUpdate() async {
    final otp = _otpCtrl.text.trim();
    if (otp.isEmpty) {
      _showSnack('Enter the OTP code from your email.', error: true);
      return;
    }

    setState(() => _verifying = true);
    try {
      await _supabase.auth.verifyOTP(
        type: OtpType.email,
        email: _email,
        token: otp,
      );
      await _supabase.auth.updateUser(
        UserAttributes(password: _newCtrl.text),
      );
      if (!mounted) return;
      _showSnack('Password updated successfully.');
      Navigator.pop(context);
    } on AuthException catch (e) {
      _showSnack(e.message, error: true);
    } catch (e) {
      _showSnack('Unable to update password right now.', error: true);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        title: const Text(
          'Change Password',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE7EEF7)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Secure password update',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _email.isEmpty
                      ? 'We could not find an email address for this account.'
                      : 'We will verify the change by sending an OTP code to $_email.',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                _PasswordField(
                  controller: _currentCtrl,
                  label: 'Current Password',
                  obscureText: _obscureCurrent,
                  onToggle: () => setState(() => _obscureCurrent = !_obscureCurrent),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _PasswordField(
                  controller: _newCtrl,
                  label: 'New Password',
                  obscureText: _obscureNew,
                  onToggle: () => setState(() => _obscureNew = !_obscureNew),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _PasswordField(
                  controller: _confirmCtrl,
                  label: 'Confirm New Password',
                  obscureText: _obscureConfirm,
                  onToggle: () => setState(() => _obscureConfirm = !_obscureConfirm),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _PasswordRules(errors: _passwordErrors(_newCtrl.text)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _sendingOtp ? null : _sendOtp,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A86FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _sendingOtp
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Send OTP',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                  ),
                ),
              ],
            ),
          ),
          if (_otpSent) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE7EEF7)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Verify OTP',
                    style: TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter the numeric OTP code from your email to finish updating your password.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _otpCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'OTP Code',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _verifying ? null : _verifyAndUpdate,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF16A34A),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      child: _verifying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Verify OTP and Update',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: _sendingOtp ? null : _sendOtp,
                    child: const Text('Resend OTP'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscureText,
    required this.onToggle,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final bool obscureText;
  final VoidCallback onToggle;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            obscureText
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
        ),
      ),
    );
  }
}

class _PasswordRules extends StatelessWidget {
  const _PasswordRules({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    const all = [
      'At least 8 characters',
      'At least 1 uppercase letter',
      'At least 1 lowercase letter',
      'At least 1 number',
      'At least 1 special character',
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: all.map((rule) {
          final met = !errors.contains(rule);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  met
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: met
                      ? const Color(0xFF16A34A)
                      : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 8),
                Text(
                  rule,
                  style: TextStyle(
                    color: met
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
