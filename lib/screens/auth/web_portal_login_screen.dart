import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../admin/provincial_admin_dashboard_screen.dart';
import '../subtenant/subtenant_dashboard_screen.dart';
import 'city_admin_signup_screen.dart';

enum WebPortalRole { admin, subtenant }

class WebPortalLoginScreen extends StatefulWidget {
  const WebPortalLoginScreen({super.key});

  @override
  State<WebPortalLoginScreen> createState() => _WebPortalLoginScreenState();
}

class _WebPortalLoginScreenState extends State<WebPortalLoginScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;

  void _togglePasswordVisibility() {
    setState(() => _obscure = !_obscure);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  WebPortalRole? _parseRole(String? role) {
    switch ((role ?? '').trim().toLowerCase()) {
      case 'admin':
        return WebPortalRole.admin;
      case 'subtenant':
        return WebPortalRole.subtenant;
      default:
        return null;
    }
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

  Future<void> _login() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final auth = await _supabase.auth
          .signInWithPassword(
            email: _emailCtrl.text.trim(),
            password: _passwordCtrl.text,
          )
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException('Login request timed out.');
            },
          );

      final user = auth.user;
      if (user == null) {
        _showSnack('Login failed. Please try again.');
        return;
      }

      final profile = await _supabase
          .from('profiles')
          .select('role, full_name, city, province')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException('Profile lookup timed out.');
            },
          );

      if (profile == null) {
        await _supabase.auth.signOut();
        _showSnack('Admin profile not found. Contact the system owner.');
        return;
      }

      final role = _parseRole(profile['role'] as String?);
      if (role == null) {
        final registration = await _latestCityRegistration(user.id);
        final activated = await _activateApprovedCityAdminIfPossible(
          user.id,
          registration,
        );
        if (activated) {
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const SubTenantDashboardScreen()),
            (_) => false,
          );
          return;
        }
        await _supabase.auth.signOut();
        _showSnack(_portalAccessMessage(registration));
        return;
      }

      if (!mounted) return;
      switch (role) {
        case WebPortalRole.admin:
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => const ProvincialAdminDashboardScreen(),
            ),
            (_) => false,
          );
          break;
        case WebPortalRole.subtenant:
          final active = await _subtenantAccessActive(user.id);
          if (!active) {
            await _supabase.auth.signOut();
            _showSnack(
              'Your city admin account is not active yet. Please wait for provincial admin approval.',
            );
            return;
          }
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const SubTenantDashboardScreen()),
            (_) => false,
          );
          break;
      }
    } on TimeoutException catch (e) {
      _showSnack(e.message ?? 'Login timed out.');
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Login error: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<Map<String, dynamic>?> _latestCityRegistration(String userId) async {
    try {
      final rows = await _supabase
          .from('city_tenant_registrations')
          .select('id, status, rejection_reason, reviewed_at')
          .eq('user_id', userId)
          .order('submitted_at', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first);
    } on PostgrestException {
      return null;
    }
  }

  String _portalAccessMessage(Map<String, dynamic>? registration) {
    final status = (registration?['status'] ?? '').toString().toLowerCase();
    if (status == 'pending') {
      return 'Your city admin application is pending provincial admin approval.';
    }
    if (status == 'rejected') {
      final reason = (registration?['rejection_reason'] ?? '')
          .toString()
          .trim();
      return reason.isEmpty
          ? 'Your city admin application was rejected. Please submit a new request if details changed.'
          : 'Your city admin application was rejected: $reason';
    }
    if (status == 'approved') {
      return 'Your application is approved, but account activation could not finish. Ask the provincial admin to run the latest Supabase migration or approve it again.';
    }
    return 'This web portal is only for approved admin and city admin accounts. '
        'If you recently applied as a city admin and saw an error, your application may not have saved — please try applying again.';
  }

  Future<bool> _activateApprovedCityAdminIfPossible(
    String userId,
    Map<String, dynamic>? registration,
  ) async {
    final status = (registration?['status'] ?? '').toString().toLowerCase();
    if (status != 'approved') return false;

    try {
      await _supabase
          .rpc('activate_approved_city_admin')
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException('City admin activation timed out.');
            },
          );

      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      if (_parseRole(profile?['role'] as String?) != WebPortalRole.subtenant) {
        return false;
      }

      return _subtenantAccessActive(userId);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _subtenantAccessActive(String userId) async {
    try {
      final details = await _supabase
          .from('subtenant_details')
          .select('is_active, verification_status')
          .eq('id', userId)
          .maybeSingle();
      if (details == null) return true;

      final status = (details['verification_status'] ?? '')
          .toString()
          .toLowerCase()
          .trim();
      final active = details['is_active'] == true;
      return active ||
          status == 'approved' ||
          status == 'verified' ||
          status == 'active';
    } on PostgrestException {
      return true;
    }
  }

  void _openCityAdminSignup() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const CityAdminSignupScreen()),
    );
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _showSnack('Enter your admin email first.');
      return;
    }

    try {
      await _supabase.auth.resetPasswordForEmail(email);
      _showSnack('Password reset email sent.', error: false);
    } catch (e) {
      _showSnack('Reset failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 900;
          return Stack(
            children: [
              const Positioned.fill(child: _WebLoginBackdrop()),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 40 : 18,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1080),
                      child: wide
                          ? Row(
                              children: [
                                const Expanded(child: _PortalCopy()),
                                const SizedBox(width: 36),
                                Expanded(child: _LoginCard(state: this)),
                              ],
                            )
                          : Column(
                              children: [
                                const _PortalCopy(compact: true),
                                const SizedBox(height: 20),
                                _LoginCard(state: this),
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

class _LoginCard extends StatelessWidget {
  const _LoginCard({required this.state});

  final _WebPortalLoginScreenState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 440),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
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
      child: Form(
        key: state._formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF4FF),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Image.asset(
                    'assets/images/touristrike_logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.admin_panel_settings_rounded,
                      color: Color(0xFF2A86FF),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Admin Sign In',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Main tenant and city admin access',
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
            const SizedBox(height: 26),
            _WebTextField(
              controller: state._emailCtrl,
              label: 'Email Address',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              validator: (value) {
                final email = (value ?? '').trim();
                if (email.isEmpty) return 'Email is required';
                if (!email.contains('@')) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 16),
            _WebTextField(
              controller: state._passwordCtrl,
              label: 'Password',
              icon: Icons.lock_outline_rounded,
              obscureText: state._obscure,
              validator: (value) {
                if ((value ?? '').isEmpty) return 'Password is required';
                return null;
              },
              suffix: IconButton(
                onPressed: state._loading
                    ? null
                    : state._togglePasswordVisibility,
                icon: Icon(
                  state._obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: state._loading ? null : state._resetPassword,
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: state._loading ? null : state._login,
                icon: state._loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.login_rounded),
                label: Text(state._loading ? 'Signing in...' : 'Sign In'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2A86FF),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF93C5FD),
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
            const SizedBox(height: 18),
            Center(
              child: TextButton.icon(
                onPressed: state._loading ? null : state._openCityAdminSignup,
                icon: const Icon(Icons.how_to_reg_rounded, size: 18),
                label: const Text('Apply as City Admin'),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF4F8FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFF2A86FF),
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Only approved provincial and city admin accounts can enter the web portal.',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 12,
                        height: 1.35,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WebTextField extends StatelessWidget {
  const _WebTextField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final FormFieldValidator<String>? validator;
  final Widget? suffix;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      textInputAction: obscureText
          ? TextInputAction.done
          : TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF94A3B8)),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF8FBFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2ECF8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFE2ECF8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF2A86FF), width: 1.2),
        ),
      ),
      onFieldSubmitted: (_) {
        if (obscureText) stateOf(context)?._login();
      },
    );
  }

  _WebPortalLoginScreenState? stateOf(BuildContext context) {
    return context.findAncestorStateOfType<_WebPortalLoginScreenState>();
  }
}

class _PortalCopy extends StatelessWidget {
  const _PortalCopy({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: () => Navigator.maybePop(context),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to portal'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF2A86FF),
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'TourisTrike web portal',
          style: TextStyle(
            color: const Color(0xFF0F172A),
            fontSize: compact ? 32 : 44,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Built for desktop workflows: package review, city-scoped tourism management, bookings, reports, and driver coordination.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 15,
            height: 1.55,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 24),
        const Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _AccessChip(
              icon: Icons.account_balance_rounded,
              label: 'Provincial admin',
            ),
            _AccessChip(
              icon: Icons.location_city_rounded,
              label: 'Sub-tenant admin',
            ),
            _AccessChip(icon: Icons.security_rounded, label: 'Role restricted'),
          ],
        ),
      ],
    );
  }
}

class _AccessChip extends StatelessWidget {
  const _AccessChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2ECF8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF2A86FF), size: 18),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _WebLoginBackdrop extends StatelessWidget {
  const _WebLoginBackdrop();

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
