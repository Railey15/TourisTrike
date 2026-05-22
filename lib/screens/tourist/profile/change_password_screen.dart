import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/auth/login_screen.dart';

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

  bool _saving = false;
  bool _obscureCurrent = true;
  bool _obscureNew = true;
  bool _obscureConfirm = true;

  User? get _user => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_user == null && mounted) {
        _showError('Your session has expired. Please log in again.');
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    });
  }

  @override
  void dispose() {
    _currentCtrl.dispose();
    _newCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _showSuccess(String message) => _showSnack(message, isError: false);

  void _showError(String message) => _showSnack(message, isError: true);

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
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

  Future<void> _saveData() async {
    final user = _user;
    if (user == null) {
      _showError('Your session has expired. Please log in again.');
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      return;
    }

    final currentPassword = _currentCtrl.text;
    final newPassword = _newCtrl.text;
    final confirmPassword = _confirmCtrl.text;

    if (currentPassword.trim().isEmpty) {
      _showError('Please enter your current password for confirmation.');
      return;
    }
    if (newPassword.length < 8) {
      _showError('New password must be at least 8 characters long.');
      return;
    }
    if (newPassword != confirmPassword) {
      _showError('New password and confirmation do not match.');
      return;
    }
    if (newPassword == currentPassword) {
      _showError('Please choose a different new password.');
      return;
    }

    final passwordErrors = _passwordErrors(newPassword);
    if (passwordErrors.isNotEmpty) {
      _showError('Password is too weak: ${passwordErrors.first}');
      return;
    }

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      await _supabase.auth.updateUser(UserAttributes(password: newPassword));
      if (!mounted) return;
      setState(() => _saving = false);
      _showSuccess('Password updated successfully.');
      Navigator.of(context).pop();
    } on AuthException catch (error, stackTrace) {
      debugPrint('ChangePasswordScreen auth error: ${error.message}');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _saving = false);
      _showError(error.message);
    } catch (error, stackTrace) {
      debugPrint('ChangePasswordScreen _saveData error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Unable to update your password right now.');
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
                const Text(
                  'Your current password is used as a confirmation field. Supabase Auth will update your password directly for this account.',
                  style: TextStyle(
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
                  onToggle: () => setState(() {
                    _obscureCurrent = !_obscureCurrent;
                  }),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _PasswordField(
                  controller: _newCtrl,
                  label: 'New Password',
                  obscureText: _obscureNew,
                  onToggle: () => setState(() {
                    _obscureNew = !_obscureNew;
                  }),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _PasswordField(
                  controller: _confirmCtrl,
                  label: 'Confirm New Password',
                  obscureText: _obscureConfirm,
                  onToggle: () => setState(() {
                    _obscureConfirm = !_obscureConfirm;
                  }),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                _PasswordRules(errors: _passwordErrors(_newCtrl.text)),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveData,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A86FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Update Password',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                  ),
                ),
              ],
            ),
          ),
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
