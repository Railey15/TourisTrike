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

  static const String logoUrl =
      'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/public-assets/Logo.png';

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
          backgroundColor:
              error ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
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
      await _supabase.rpc('activate_approved_city_admin').timeout(
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
      backgroundColor: const Color(0xFFF5F9FF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 920;

          return Stack(
            children: [
              const Positioned.fill(child: _WebLoginBackdrop()),
              SafeArea(
                child: Column(
                  children: [
                    _TopBar(
                      onBack: () => Navigator.maybePop(context),
                      onApply: _loading ? null : _openCityAdminSignup,
                    ),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          padding: EdgeInsets.fromLTRB(
                            wide ? 40 : 20,
                            24,
                            wide ? 40 : 20,
                            36,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1120),
                            child: wide
                                ? Row(
                                    children: [
                                      const Expanded(
                                        child: _PortalHero(),
                                      ),
                                      const SizedBox(width: 44),
                                      Expanded(
                                        child: Align(
                                          alignment: Alignment.centerRight,
                                          child: _LoginCard(state: this),
                                        ),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      const _PortalHero(compact: true),
                                      const SizedBox(height: 24),
                                      _LoginCard(state: this),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.onBack,
    required this.onApply,
  });

  final VoidCallback onBack;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded),
            label: const Text('Back to portal'),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onApply,
            icon: const Icon(Icons.location_city_rounded, size: 18),
            label: const Text('Apply as City Admin'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              side: const BorderSide(color: Color(0xFFBFDBFE)),
              backgroundColor: Colors.white.withOpacity(0.85),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
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
      constraints: const BoxConstraints(maxWidth: 460),
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.9)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.08),
            blurRadius: 40,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: Form(
        key: state._formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 92,
              height: 92,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: const Color(0xFFDCEBFF)),
              ),
              child: Image.network(
                _WebPortalLoginScreenState.logoUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Color(0xFF2563EB),
                  size: 42,
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Admin Login',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Access the TourisTrike management portal',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 30),
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
                onPressed:
                    state._loading ? null : state._togglePasswordVisibility,
                icon: Icon(
                  state._obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: state._loading ? null : state._resetPassword,
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
                child: const Text('Forgot password?'),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 56,
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
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFF93C5FD),
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE2ECF8)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.verified_user_outlined,
                    color: Color(0xFF2563EB),
                    size: 21,
                  ),
                  SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      'Only approved provincial and city admin accounts can enter this portal.',
                      style: TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 12.5,
                        height: 1.4,
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
      textInputAction:
          obscureText ? TextInputAction.done : TextInputAction.next,
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 14.5,
        fontWeight: FontWeight.w700,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(icon, color: const Color(0xFF94A3B8)),
        suffixIcon: suffix,
        filled: true,
        fillColor: const Color(0xFFF8FBFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 18,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2ECF8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE2ECF8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFF2563EB),
            width: 1.4,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(
            color: Color(0xFFDC2626),
            width: 1.4,
          ),
        ),
      ),
      onFieldSubmitted: (_) {
        if (obscureText) {
          context.findAncestorStateOfType<_WebPortalLoginScreenState>()?._login();
        }
      },
    );
  }
}

class _PortalHero extends StatelessWidget {
  const _PortalHero({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.82),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFDCEBFF)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.network(
                _WebPortalLoginScreenState.logoUrl,
                width: 28,
                height: 28,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.travel_explore_rounded,
                  color: Color(0xFF2563EB),
                  size: 24,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'TourisTrike Web Portal',
                style: TextStyle(
                  color: Color(0xFF2563EB),
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Text(
          'Manage tourism operations with a cleaner admin workspace.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: TextStyle(
            color: const Color(0xFF0F172A),
            fontSize: compact ? 34 : 50,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Review travel packages, manage city-level tourism content, monitor bookings, and coordinate local tricycle-based travel services from one secure dashboard.',
          textAlign: compact ? TextAlign.center : TextAlign.start,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 15.5,
            height: 1.65,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 26),
        const Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _AccessChip(
              icon: Icons.account_balance_rounded,
              label: 'Provincial Admin',
            ),
            _AccessChip(
              icon: Icons.location_city_rounded,
              label: 'City Admin',
            ),
            _AccessChip(
              icon: Icons.lock_rounded,
              label: 'Secure Access',
            ),
          ],
        ),
      ],
    );
  }
}

class _AccessChip extends StatelessWidget {
  const _AccessChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2ECF8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF2563EB), size: 18),
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
    return Stack(
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFEAF5FF),
                Color(0xFFF8FBFF),
                Color(0xFFEFFAF5),
              ],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned(
          top: -120,
          left: -90,
          child: _GlowCircle(
            size: 280,
            color: Color(0xFF60A5FA),
          ),
        ),
        Positioned(
          right: -130,
          bottom: -110,
          child: _GlowCircle(
            size: 320,
            color: Color(0xFF34D399),
          ),
        ),
        Positioned(
          top: 160,
          right: 120,
          child: _GlowCircle(
            size: 170,
            color: Color(0xFFA78BFA),
          ),
        ),
      ],
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.22),
              blurRadius: 90,
              spreadRadius: 30,
            ),
          ],
        ),
      ),
    );
  }
}