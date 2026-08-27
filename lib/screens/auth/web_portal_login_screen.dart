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

  // ============================================================
  // COLORS
  // ============================================================

  static const Color primaryBlue = Color(0xFF2563EB);
  static const Color darkBlue = Color(0xFF0F2F6B);
  static const Color softBlue = Color(0xFFEAF3FF);
  static const Color green = Color(0xFF2FA36B);
  static const Color ink = Color(0xFF10213F);
  static const Color muted = Color(0xFF64748B);
  static const Color border = Color(0xFFDCE7F5);

  bool _obscure = true;
  bool _loading = false;

  // ============================================================
  // PASSWORD VISIBILITY
  // ============================================================

  void _togglePasswordVisibility() {
    setState(() => _obscure = !_obscure);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  // ============================================================
  // ROLE
  // ============================================================

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

  // ============================================================
  // SNACKBAR
  // ============================================================

  void _showSnack(
    String message, {
    bool error = true,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
            ),
          ),
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

  // ============================================================
  // LOGIN
  // ============================================================

  Future<void> _login() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

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
              throw TimeoutException(
                'Login request timed out.',
              );
            },
          );

      final user = auth.user;

      if (user == null) {
        _showSnack(
          'Login failed. Please try again.',
        );
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
              throw TimeoutException(
                'Profile lookup timed out.',
              );
            },
          );

      if (profile == null) {
        await _supabase.auth.signOut();

        _showSnack(
          'Admin profile not found. Contact the system owner.',
        );

        return;
      }

      final role = _parseRole(
        profile['role'] as String?,
      );

      if (role == null) {
        final registration =
            await _latestCityRegistration(user.id);

        final activated =
            await _activateApprovedCityAdminIfPossible(
          user.id,
          registration,
        );

        if (activated) {
          if (!mounted) return;

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const SubTenantDashboardScreen(),
            ),
            (_) => false,
          );

          return;
        }

        await _supabase.auth.signOut();

        _showSnack(
          _portalAccessMessage(registration),
        );

        return;
      }

      if (!mounted) return;

      switch (role) {
        case WebPortalRole.admin:
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  const ProvincialAdminDashboardScreen(),
            ),
            (_) => false,
          );

          break;

        case WebPortalRole.subtenant:
          final active =
              await _subtenantAccessActive(user.id);

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
            MaterialPageRoute(
              builder: (_) =>
                  const SubTenantDashboardScreen(),
            ),
            (_) => false,
          );

          break;
      }
    } on TimeoutException catch (e) {
      _showSnack(
        e.message ?? 'Login timed out.',
      );
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack(
        'Login error: $e',
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ============================================================
  // CITY REGISTRATION
  // ============================================================

  Future<Map<String, dynamic>?> _latestCityRegistration(
    String userId,
  ) async {
    try {
      final rows = await _supabase
          .from('city_tenant_registrations')
          .select(
            'id, status, rejection_reason, reviewed_at',
          )
          .eq('user_id', userId)
          .order(
            'submitted_at',
            ascending: false,
          )
          .limit(1);

      if (rows.isEmpty) {
        return null;
      }

      return Map<String, dynamic>.from(
        rows.first,
      );
    } on PostgrestException {
      return null;
    }
  }

  String _portalAccessMessage(
    Map<String, dynamic>? registration,
  ) {
    final status =
        (registration?['status'] ?? '')
            .toString()
            .toLowerCase();

    if (status == 'pending') {
      return 'Your city admin application is pending provincial admin approval.';
    }

    if (status == 'rejected') {
      final reason =
          (registration?['rejection_reason'] ?? '')
              .toString()
              .trim();

      return reason.isEmpty
          ? 'Your city admin application was rejected. Please submit a new request if details changed.'
          : 'Your city admin application was rejected: $reason';
    }

    if (status == 'approved') {
      return 'Your application is approved, but account activation could not finish. Ask the provincial admin to run the latest Supabase migration or approve it again.';
    }

    return 'This web portal is only for approved admin and city admin accounts. If you recently applied as a city admin and saw an error, your application may not have saved — please try applying again.';
  }

  Future<bool> _activateApprovedCityAdminIfPossible(
    String userId,
    Map<String, dynamic>? registration,
  ) async {
    final status =
        (registration?['status'] ?? '')
            .toString()
            .toLowerCase();

    if (status != 'approved') {
      return false;
    }

    try {
      await _supabase
          .rpc('activate_approved_city_admin')
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException(
                'City admin activation timed out.',
              );
            },
          );

      final profile = await _supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      if (_parseRole(
            profile?['role'] as String?,
          ) !=
          WebPortalRole.subtenant) {
        return false;
      }

      return _subtenantAccessActive(userId);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _subtenantAccessActive(
    String userId,
  ) async {
    try {
      final details = await _supabase
          .from('subtenant_details')
          .select(
            'is_active, verification_status',
          )
          .eq('id', userId)
          .maybeSingle();

      if (details == null) {
        return true;
      }

      final status =
          (details['verification_status'] ?? '')
              .toString()
              .toLowerCase()
              .trim();

      final active =
          details['is_active'] == true;

      return active ||
          status == 'approved' ||
          status == 'verified' ||
          status == 'active';
    } on PostgrestException {
      return true;
    }
  }

  // ============================================================
  // CITY ADMIN SIGNUP
  // ============================================================

  void _openCityAdminSignup() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            const CityAdminSignupScreen(),
      ),
    );
  }

  // ============================================================
  // RESET PASSWORD
  // ============================================================

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _showSnack(
        'Enter your admin email first.',
      );
      return;
    }

    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
      );

      _showSnack(
        'Password reset email sent.',
        error: false,
      );
    } catch (e) {
      _showSnack(
        'Reset failed: $e',
      );
    }
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F9FF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          final desktop = width >= 1050;
          final tablet = width >= 700 && width < 1050;
          final mobile = width < 700;
          final smallMobile = width < 390;

          return Stack(
            children: [
              const Positioned.fill(
                child: _WebLoginBackdrop(),
              ),

              SafeArea(
                child: Column(
                  children: [
                    _TopBar(
                      mobile: mobile,
                      smallMobile: smallMobile,
                      onBack: () =>
                          Navigator.maybePop(context),
                      onApply: _loading
                          ? null
                          : _openCityAdminSignup,
                    ),

                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          physics:
                              const BouncingScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            mobile
                                ? 16
                                : tablet
                                    ? 28
                                    : 40,
                            mobile
                                ? 8
                                : 20,
                            mobile
                                ? 16
                                : tablet
                                    ? 28
                                    : 40,
                            mobile
                                ? 24
                                : 36,
                          ),
                          child: ConstrainedBox(
                            constraints:
                                const BoxConstraints(
                              maxWidth: 1180,
                            ),
                            child: desktop
                                ? _DesktopLoginLayout(
                                    state: this,
                                  )
                                : tablet
                                    ? _TabletLoginLayout(
                                        state: this,
                                      )
                                    : _MobileLoginLayout(
                                        state: this,
                                        smallMobile:
                                            smallMobile,
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

// ============================================================
// DESKTOP LAYOUT
// ============================================================

class _DesktopLoginLayout
    extends StatelessWidget {
  const _DesktopLoginLayout({
    required this.state,
  });

  final _WebPortalLoginScreenState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.center,
      children: [
        const Expanded(
          flex: 11,
          child: _PortalHero(),
        ),

        const SizedBox(width: 70),

        Expanded(
          flex: 9,
          child: Align(
            alignment: Alignment.centerRight,
            child: _LoginCard(
              state: state,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// TABLET LAYOUT
// ============================================================

class _TabletLoginLayout
    extends StatelessWidget {
  const _TabletLoginLayout({
    required this.state,
  });

  final _WebPortalLoginScreenState state;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.center,
      children: [
        Expanded(
          child: _PortalHero(
            compact: true,
          ),
        ),

        const SizedBox(width: 28),

        Expanded(
          child: _LoginCard(
            state: state,
            compact: true,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// MOBILE LAYOUT
// ============================================================

class _MobileLoginLayout
    extends StatelessWidget {
  const _MobileLoginLayout({
    required this.state,
    required this.smallMobile,
  });

  final _WebPortalLoginScreenState state;
  final bool smallMobile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _MobileHero(
          smallMobile: smallMobile,
        ),

        SizedBox(
          height: smallMobile ? 18 : 24,
        ),

        _LoginCard(
          state: state,
          compact: true,
          mobile: true,
        ),
      ],
    );
  }
}

// ============================================================
// TOP BAR
// ============================================================

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.mobile,
    required this.smallMobile,
    required this.onBack,
    required this.onApply,
  });

  final bool mobile;
  final bool smallMobile;
  final VoidCallback onBack;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    if (mobile) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          smallMobile ? 14 : 18,
          12,
          smallMobile ? 14 : 18,
          4,
        ),
        child: Row(
          children: [
            _TopBarBackButton(
              onPressed: onBack,
              compact: true,
            ),

            const Spacer(),

            OutlinedButton.icon(
              onPressed: onApply,
              icon: const Icon(
                Icons.location_city_rounded,
                size: 16,
              ),
              label: const Text(
                'Apply as City Admin',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    _WebPortalLoginScreenState
                        .primaryBlue,
                backgroundColor:
                    Colors.white.withOpacity(0.86),
                side: const BorderSide(
                  color: Color(0xFFBFDBFE),
                ),
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(999),
                ),
                textStyle:
                    const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(
        smallMobile ? 18 : 28,
        18,
        smallMobile ? 18 : 28,
        8,
      ),
      child: Row(
        children: [
          _TopBarBackButton(
            onPressed: onBack,
          ),

          const Spacer(),

          OutlinedButton.icon(
            onPressed: onApply,
            icon: const Icon(
              Icons.location_city_rounded,
              size: 18,
            ),
            label: const Text(
              'Apply as City Admin',
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor:
                  _WebPortalLoginScreenState
                      .primaryBlue,
              backgroundColor:
                  Colors.white.withOpacity(0.86),
              side: const BorderSide(
                color: Color(0xFFBFDBFE),
              ),
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 13,
              ),
              shape:
                  RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(999),
              ),
              textStyle:
                  const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBarBackButton
    extends StatelessWidget {
  const _TopBarBackButton({
    required this.onPressed,
    this.compact = false,
  });

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(
        Icons.arrow_back_rounded,
        size: compact ? 17 : 19,
      ),
      label: Text(
        compact
            ? 'Back'
            : 'Back to portal',
      ),
      style: TextButton.styleFrom(
        foregroundColor:
            _WebPortalLoginScreenState
                .primaryBlue,
        padding:
            EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: 8,
        ),
        textStyle: TextStyle(
          fontSize: compact ? 11 : 12.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

// ============================================================
// MOBILE HERO
// ============================================================

class _MobileHero
    extends StatelessWidget {
  const _MobileHero({
    required this.smallMobile,
  });

  final bool smallMobile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _BrandPill(),

        SizedBox(
          height: smallMobile ? 16 : 20,
        ),

        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text:
                    'Manage tourism\n',
              ),
              const TextSpan(
                text:
                    'operations with a\n',
                style: TextStyle(
                  color:
                      _WebPortalLoginScreenState
                          .primaryBlue,
                ),
              ),
              const TextSpan(
                text:
                    'cleaner workspace.',
              ),
            ],
          ),
          textAlign: TextAlign.center,
          style: TextStyle(
            color:
                _WebPortalLoginScreenState.ink,
            fontSize:
                smallMobile ? 27 : 31,
            height: 1.06,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.1,
          ),
        ),

        const SizedBox(height: 10),

        ConstrainedBox(
          constraints:
              const BoxConstraints(
            maxWidth: 390,
          ),
          child: Text(
            'Manage tourism content, bookings, and local travel services from one secure portal.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color:
                  _WebPortalLoginScreenState
                      .muted,
              fontSize:
                  smallMobile ? 12 : 13,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        const SizedBox(height: 14),

        const Wrap(
          alignment: WrapAlignment.center,
          spacing: 7,
          runSpacing: 7,
          children: [
            _SmallAccessChip(
              icon:
                  Icons.account_balance_rounded,
              label: 'Provincial',
            ),
            _SmallAccessChip(
              icon:
                  Icons.location_city_rounded,
              label: 'City Admin',
            ),
            _SmallAccessChip(
              icon: Icons.lock_rounded,
              label: 'Secure',
            ),
          ],
        ),
      ],
    );
  }
}

// ============================================================
// DESKTOP / TABLET HERO
// ============================================================

class _PortalHero
    extends StatelessWidget {
  const _PortalHero({
    this.compact = false,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          compact
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const _BrandPill(),

        SizedBox(
          height: compact ? 20 : 28,
        ),

        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text:
                    'Manage tourism\n',
              ),
              TextSpan(
                text:
                    'operations ',
                style: const TextStyle(
                  color:
                      _WebPortalLoginScreenState
                          .primaryBlue,
                ),
              ),
              const TextSpan(
                text:
                    'with a cleaner\nadmin workspace.',
              ),
            ],
          ),
          textAlign:
              compact
                  ? TextAlign.center
                  : TextAlign.left,
          style: TextStyle(
            color:
                _WebPortalLoginScreenState.ink,
            fontSize: compact ? 37 : 50,
            height: 1.04,
            fontWeight: FontWeight.w900,
            letterSpacing:
                compact ? -1.2 : -1.8,
          ),
        ),

        SizedBox(
          height: compact ? 15 : 20,
        ),

        ConstrainedBox(
          constraints:
              const BoxConstraints(
            maxWidth: 590,
          ),
          child: Text(
            'Review travel packages, manage city-level tourism content, monitor bookings, and coordinate local tricycle-based travel services from one secure dashboard.',
            textAlign:
                compact
                    ? TextAlign.center
                    : TextAlign.left,
            style: TextStyle(
              color:
                  _WebPortalLoginScreenState
                      .muted,
              fontSize: compact ? 14 : 15.5,
              height: 1.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        SizedBox(
          height: compact ? 20 : 27,
        ),

        const Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _AccessChip(
              icon:
                  Icons.account_balance_rounded,
              label: 'Provincial Admin',
            ),
            _AccessChip(
              icon:
                  Icons.location_city_rounded,
              label: 'City Admin',
            ),
            _AccessChip(
              icon: Icons.lock_rounded,
              label: 'Secure Access',
            ),
          ],
        ),

        if (!compact) ...[
          const SizedBox(height: 34),
          const _PortalFeatureRow(),
        ],
      ],
    );
  }
}

// ============================================================
// BRAND PILL
// ============================================================

class _BrandPill
    extends StatelessWidget {
  const _BrandPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color:
            Colors.white.withOpacity(0.88),
        borderRadius:
            BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFDCEBFF),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF2563EB)
                    .withOpacity(0.05),
            blurRadius: 18,
            offset:
                const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Container(
            width: 32,
            height: 32,
            padding:
                const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color:
                  const Color(0xFFEAF3FF),
              borderRadius:
                  BorderRadius.circular(10),
            ),
            child: Image.network(
              _WebPortalLoginScreenState
                  .logoUrl,
              fit: BoxFit.contain,
              errorBuilder:
                  (_, __, ___) =>
                      const Icon(
                Icons.travel_explore_rounded,
                color:
                    _WebPortalLoginScreenState
                        .primaryBlue,
                size: 20,
              ),
            ),
          ),

          const SizedBox(width: 9),

          const Text(
            'TourisTrike Web Portal',
            style: TextStyle(
              color:
                  _WebPortalLoginScreenState
                      .primaryBlue,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// FEATURE ROW
// ============================================================

class _PortalFeatureRow
    extends StatelessWidget {
  const _PortalFeatureRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _FeatureItem(
            icon: Icons.map_rounded,
            title: 'Tourism',
            subtitle: 'Destinations',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _FeatureItem(
            icon:
                Icons.receipt_long_rounded,
            title: 'Bookings',
            subtitle: 'Reservations',
          ),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _FeatureItem(
            icon: Icons.badge_rounded,
            title: 'Partners',
            subtitle: 'Local drivers',
          ),
        ),
      ],
    );
  }
}

class _FeatureItem
    extends StatelessWidget {
  const _FeatureItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            Colors.white.withOpacity(0.62),
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFDDE8F5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color:
                  const Color(0xFFEAF3FF),
              borderRadius:
                  BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 17,
              color:
                  _WebPortalLoginScreenState
                      .primaryBlue,
            ),
          ),

          const SizedBox(width: 8),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      const TextStyle(
                    color:
                        _WebPortalLoginScreenState
                            .ink,
                    fontSize: 10.5,
                    fontWeight:
                        FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style:
                      const TextStyle(
                    color:
                        _WebPortalLoginScreenState
                            .muted,
                    fontSize: 9,
                    fontWeight:
                        FontWeight.w600,
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

// ============================================================
// ACCESS CHIPS
// ============================================================

class _AccessChip
    extends StatelessWidget {
  const _AccessChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 13,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color:
            Colors.white.withOpacity(0.88),
        borderRadius:
            BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFE0EAF6),
        ),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            color:
                _WebPortalLoginScreenState
                    .primaryBlue,
            size: 17,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color:
                  _WebPortalLoginScreenState
                      .ink,
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallAccessChip
    extends StatelessWidget {
  const _SmallAccessChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.white
            .withOpacity(0.82),
        borderRadius:
            BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFE0EAF6),
        ),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            color:
                _WebPortalLoginScreenState
                    .primaryBlue,
            size: 14,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color:
                  _WebPortalLoginScreenState
                      .ink,
              fontSize: 9.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// LOGIN CARD
// ============================================================

class _LoginCard
    extends StatelessWidget {
  const _LoginCard({
    required this.state,
    this.compact = false,
    this.mobile = false,
  });

  final _WebPortalLoginScreenState state;
  final bool compact;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints:
          BoxConstraints(
        maxWidth: mobile
            ? double.infinity
            : 445,
      ),
      padding: EdgeInsets.fromLTRB(
        mobile
            ? 20
            : compact
                ? 24
                : 30,
        mobile
            ? 22
            : compact
                ? 25
                : 30,
        mobile
            ? 20
            : compact
                ? 24
                : 30,
        mobile
            ? 20
            : compact
                ? 25
                : 30,
      ),
      decoration: BoxDecoration(
        color:
            Colors.white.withOpacity(0.97),
        borderRadius:
            BorderRadius.circular(
          mobile ? 25 : 30,
        ),
        border: Border.all(
          color: Colors.white,
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(0xFF173B72)
                    .withOpacity(0.10),
            blurRadius: mobile
                ? 28
                : 42,
            offset:
                const Offset(0, 18),
          ),
        ],
      ),
      child: Form(
        key: state._formKey,
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            // --------------------------------------------------
            // CARD HEADER
            // --------------------------------------------------

            Row(
              children: [
                Container(
                  width: mobile
                      ? 48
                      : 54,
                  height: mobile
                      ? 48
                      : 54,
                  padding:
                      const EdgeInsets.all(
                    8,
                  ),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFFEAF3FF),
                    borderRadius:
                        BorderRadius.circular(
                      15,
                    ),
                    border: Border.all(
                      color:
                          const Color(
                        0xFFDCEBFF,
                      ),
                    ),
                  ),
                  child: Image.network(
                    _WebPortalLoginScreenState
                        .logoUrl,
                    fit: BoxFit.contain,
                    errorBuilder:
                        (_, __, ___) =>
                            const Icon(
                      Icons
                          .admin_panel_settings_rounded,
                      color:
                          _WebPortalLoginScreenState
                              .primaryBlue,
                      size: 28,
                    ),
                  ),
                ),

                const SizedBox(width: 13),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Admin Login',
                        style: TextStyle(
                          color:
                              _WebPortalLoginScreenState
                                  .ink,
                          fontSize: mobile
                              ? 22
                              : 24,
                          fontWeight:
                              FontWeight.w900,
                          letterSpacing:
                              -0.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      const Text(
                        'TourisTrike management portal',
                        style: TextStyle(
                          color:
                              _WebPortalLoginScreenState
                                  .muted,
                          fontSize: 11,
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color:
                        const Color(0xFFEAF8F0),
                    borderRadius:
                        BorderRadius.circular(
                      999,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 6,
                        color:
                            _WebPortalLoginScreenState
                                .green,
                      ),
                      SizedBox(width: 5),
                      Text(
                        'SECURE',
                        style:
                            TextStyle(
                          color:
                              Color(
                            0xFF258457,
                          ),
                          fontSize: 8,
                          fontWeight:
                              FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            SizedBox(
              height: mobile
                  ? 22
                  : 28,
            ),

            // --------------------------------------------------
            // FORM
            // --------------------------------------------------

            _WebTextField(
              controller:
                  state._emailCtrl,
              label: 'Email Address',
              hint:
                  'Enter your admin email',
              icon:
                  Icons.mail_outline_rounded,
              keyboardType:
                  TextInputType.emailAddress,
              validator: (value) {
                final email =
                    (value ?? '')
                        .trim();

                if (email.isEmpty) {
                  return 'Email is required';
                }

                if (!email.contains('@')) {
                  return 'Enter a valid email';
                }

                return null;
              },
            ),

            const SizedBox(height: 14),

            _WebTextField(
              controller:
                  state._passwordCtrl,
              label: 'Password',
              hint:
                  'Enter your password',
              icon:
                  Icons.lock_outline_rounded,
              obscureText:
                  state._obscure,
              validator: (value) {
                if ((value ?? '').isEmpty) {
                  return 'Password is required';
                }

                return null;
              },
              suffix: IconButton(
                onPressed: state._loading
                    ? null
                    : state
                        ._togglePasswordVisibility,
                tooltip:
                    state._obscure
                        ? 'Show password'
                        : 'Hide password',
                icon: Icon(
                  state._obscure
                      ? Icons
                          .visibility_off_outlined
                      : Icons
                          .visibility_outlined,
                  color:
                      const Color(
                    0xFF94A3B8,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 5),

            // --------------------------------------------------
            // FORGOT PASSWORD
            // --------------------------------------------------

            Align(
              alignment:
                  Alignment.centerRight,
              child: TextButton(
                onPressed:
                    state._loading
                        ? null
                        : state
                            ._resetPassword,
                style:
                    TextButton.styleFrom(
                  foregroundColor:
                      _WebPortalLoginScreenState
                          .primaryBlue,
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  textStyle:
                      const TextStyle(
                    fontSize: 11.5,
                    fontWeight:
                        FontWeight.w800,
                  ),
                ),
                child:
                    const Text(
                  'Forgot password?',
                ),
              ),
            ),

            const SizedBox(height: 7),

            // --------------------------------------------------
            // SIGN IN BUTTON
            // --------------------------------------------------

            SizedBox(
              width: double.infinity,
              height: mobile
                  ? 52
                  : 55,
              child:
                  ElevatedButton(
                onPressed:
                    state._loading
                        ? null
                        : state._login,
                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      _WebPortalLoginScreenState
                          .primaryBlue,
                  foregroundColor:
                      Colors.white,
                  disabledBackgroundColor:
                      const Color(
                    0xFF93B4EE,
                  ),
                  elevation: 0,
                  shadowColor:
                      Colors.transparent,
                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      15,
                    ),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration:
                      const Duration(
                    milliseconds: 180,
                  ),
                  child: state._loading
                      ? const Row(
                          mainAxisAlignment:
                              MainAxisAlignment
                                  .center,
                          children: [
                            SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(
                                color:
                                    Colors.white,
                                strokeWidth:
                                    2,
                              ),
                            ),
                            SizedBox(
                              width: 10,
                            ),
                            Text(
                              'Signing in...',
                              style:
                                  TextStyle(
                                fontSize:
                                    14,
                                fontWeight:
                                    FontWeight
                                        .w900,
                              ),
                            ),
                          ],
                        )
                      : const Row(
                          mainAxisAlignment:
                              MainAxisAlignment
                                  .center,
                          children: [
                            Text(
                              'Sign In',
                              style:
                                  TextStyle(
                                fontSize:
                                    14,
                                fontWeight:
                                    FontWeight
                                        .w900,
                              ),
                            ),
                            SizedBox(
                              width: 8,
                            ),
                            Icon(
                              Icons
                                  .arrow_forward_rounded,
                              size: 18,
                            ),
                          ],
                        ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // --------------------------------------------------
            // SECURITY INFO
            // --------------------------------------------------

            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    const Color(0xFFF5F9FF),
                borderRadius:
                    BorderRadius.circular(
                  14,
                ),
                border: Border.all(
                  color:
                      const Color(0xFFE1EAF6),
                ),
              ),
              child: Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xFFE8F1FF,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        9,
                      ),
                    ),
                    child:
                        const Icon(
                      Icons
                          .verified_user_outlined,
                      color:
                          _WebPortalLoginScreenState
                              .primaryBlue,
                      size: 17,
                    ),
                  ),

                  const SizedBox(width: 9),

                  const Expanded(
                    child: Text(
                      'Only approved provincial and city admin accounts can enter this portal.',
                      style:
                          TextStyle(
                        color:
                            Color(
                          0xFF52647B,
                        ),
                        fontSize:
                            10.5,
                        height:
                            1.4,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 15),

            // --------------------------------------------------
            // CITY ADMIN CTA
            // --------------------------------------------------

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                const Text(
                  'Need city admin access?',
                  style: TextStyle(
                    color:
                        _WebPortalLoginScreenState
                            .muted,
                    fontSize: 10.5,
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 3),
                TextButton(
                  onPressed:
                      state._loading
                          ? null
                          : state
                              ._openCityAdminSignup,
                  style:
                      TextButton.styleFrom(
                    foregroundColor:
                        _WebPortalLoginScreenState
                            .primaryBlue,
                    padding:
                        const EdgeInsets
                            .symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    textStyle:
                        const TextStyle(
                      fontSize: 10.5,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                  child:
                      const Text(
                    'Apply here',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// TEXT FIELD
// ============================================================

class _WebTextField
    extends StatelessWidget {
  const _WebTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
    this.suffix,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
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
          obscureText
              ? TextInputAction.done
              : TextInputAction.next,
      style: const TextStyle(
        color:
            _WebPortalLoginScreenState.ink,
        fontSize: 13.5,
        fontWeight: FontWeight.w700,
      ),
      decoration:
          InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle:
            const TextStyle(
          color: Color(0xFFA0AEC0),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
        labelStyle:
            const TextStyle(
          color:
              _WebPortalLoginScreenState
                  .muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon:
            Icon(
          icon,
          color:
              const Color(0xFF8FA4BF),
          size: 20,
        ),
        suffixIcon: suffix,
        filled: true,
        fillColor:
            const Color(0xFFF8FBFF),
        contentPadding:
            const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 17,
        ),
        border:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            15,
          ),
          borderSide:
              const BorderSide(
            color:
                _WebPortalLoginScreenState
                    .border,
          ),
        ),
        enabledBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            15,
          ),
          borderSide:
              const BorderSide(
            color:
                _WebPortalLoginScreenState
                    .border,
          ),
        ),
        focusedBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            15,
          ),
          borderSide:
              const BorderSide(
            color:
                _WebPortalLoginScreenState
                    .primaryBlue,
            width: 1.4,
          ),
        ),
        errorBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            15,
          ),
          borderSide:
              const BorderSide(
            color:
                Color(0xFFDC2626),
          ),
        ),
        focusedErrorBorder:
            OutlineInputBorder(
          borderRadius:
              BorderRadius.circular(
            15,
          ),
          borderSide:
              const BorderSide(
            color:
                Color(0xFFDC2626),
            width: 1.4,
          ),
        ),
        errorStyle:
            const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
      onFieldSubmitted: (_) {
        if (obscureText) {
          context
              .findAncestorStateOfType<
                  _WebPortalLoginScreenState>()
              ?._login();
        }
      },
    );
  }
}

// ============================================================
// BACKGROUND
// ============================================================

class _WebLoginBackdrop
    extends StatelessWidget {
  const _WebLoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration:
                BoxDecoration(
              gradient:
                  LinearGradient(
                begin:
                    Alignment.topLeft,
                end:
                    Alignment.bottomRight,
                colors: [
                  Color(0xFFEAF5FF),
                  Color(0xFFF8FBFF),
                  Color(0xFFF3FAF7),
                ],
              ),
            ),
          ),
        ),

        const Positioned.fill(
          child: CustomPaint(
            painter:
                _LoginBackgroundPainter(),
          ),
        ),

        Positioned(
          top: -140,
          left: -100,
          child: _GlowCircle(
            size: 330,
            color:
                const Color(0xFF60A5FA),
            opacity: 0.14,
          ),
        ),

        Positioned(
          right: -150,
          bottom: -130,
          child: _GlowCircle(
            size: 350,
            color:
                const Color(0xFF34D399),
            opacity: 0.12,
          ),
        ),

        Positioned(
          top: 250,
          right: -80,
          child: _GlowCircle(
            size: 180,
            color:
                const Color(0xFF93C5FD),
            opacity: 0.07,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// BACKGROUND PAINTER
// ============================================================

class _LoginBackgroundPainter
    extends CustomPainter {
  const _LoginBackgroundPainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final gridPaint = Paint()
      ..color = const Color(
        0xFFBFD4EA,
      ).withOpacity(0.11)
      ..strokeWidth = 1;

    const spacing = 68.0;

    for (
      double x = 0;
      x < size.width;
      x += spacing
    ) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }

    for (
      double y = 0;
      y < size.height;
      y += spacing
    ) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // Subtle travel route.
    final routePaint = Paint()
      ..color = const Color(
        0xFF2563EB,
      ).withOpacity(0.055)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final route = Path();

    route.moveTo(
      -20,
      size.height * 0.70,
    );

    route.cubicTo(
      size.width * 0.20,
      size.height * 0.55,
      size.width * 0.36,
      size.height * 0.82,
      size.width * 0.55,
      size.height * 0.65,
    );

    route.cubicTo(
      size.width * 0.73,
      size.height * 0.50,
      size.width * 0.84,
      size.height * 0.62,
      size.width + 20,
      size.height * 0.40,
    );

    canvas.drawPath(
      route,
      routePaint,
    );

    final dotPaint = Paint()
      ..color = const Color(
        0xFF2FA36B,
      ).withOpacity(0.12);

    final points = [
      Offset(
        size.width * 0.20,
        size.height * 0.65,
      ),
      Offset(
        size.width * 0.55,
        size.height * 0.65,
      ),
      Offset(
        size.width * 0.83,
        size.height * 0.55,
      ),
    ];

    for (final point in points) {
      canvas.drawCircle(
        point,
        5,
        dotPaint,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter oldDelegate,
  ) {
    return false;
  }
}

// ============================================================
// GLOW CIRCLE
// ============================================================

class _GlowCircle
    extends StatelessWidget {
  const _GlowCircle({
    required this.size,
    required this.color,
    this.opacity = 0.14,
  });

  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color:
              color.withOpacity(opacity),
          boxShadow: [
            BoxShadow(
              color:
                  color.withOpacity(
                opacity * 0.7,
              ),
              blurRadius: 90,
              spreadRadius: 20,
            ),
          ],
        ),
      ),
    );
  }
}