import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'city_admin_application.dart';
import 'city_admin_verify_otp_screen.dart';
import 'web_portal_login_screen.dart';

class CityAdminSignupScreen extends StatefulWidget {
  const CityAdminSignupScreen({super.key});

  @override
  State<CityAdminSignupScreen> createState() => _CityAdminSignupScreenState();
}

class _CityAdminSignupScreenState extends State<CityAdminSignupScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _officeNameCtrl = TextEditingController();
  final TextEditingController _contactPersonCtrl = TextEditingController();
  String? _selectedCity;
  late Future<Set<String>> _takenCitiesFuture;
  final TextEditingController _contactNumberCtrl = TextEditingController();
  final TextEditingController _officeAddressCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  void _togglePasswordVisibility() {
    setState(() => _obscurePassword = !_obscurePassword);
  }

  void _toggleConfirmVisibility() {
    setState(() => _obscureConfirm = !_obscureConfirm);
  }

  @override
  void initState() {
    super.initState();
    _takenCitiesFuture = _fetchTakenCities();
  }

  Future<Set<String>> _fetchTakenCities() async {
    final taken = <String>{};
    try {
      final rows = await _supabase
          .from('profiles')
          .select('city')
          .eq('role', 'subtenant');
      for (final row in rows as List) {
        final city = (row as Map)['city']?.toString().trim() ?? '';
        if (city.isNotEmpty) taken.add(city);
      }
    } catch (_) {}
    try {
      final rows = await _supabase
          .from('city_tenant_registrations')
          .select('city')
          .inFilter('status', ['pending', 'approved']);
      for (final row in rows as List) {
        final city = (row as Map)['city']?.toString().trim() ?? '';
        if (city.isNotEmpty) taken.add(city);
      }
    } catch (_) {}
    return taken;
  }

  void _onCitySelected(String? city) => setState(() => _selectedCity = city);

  @override
  void dispose() {
    _officeNameCtrl.dispose();
    _contactPersonCtrl.dispose();
    _contactNumberCtrl.dispose();
    _officeAddressCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
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

  bool _validEmail(String email) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());
  }

  Future<void> _sendOtp() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final draft = CityAdminApplicationDraft(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        city: _selectedCity ?? '',
        officeName: _officeNameCtrl.text.trim(),
        contactPerson: _contactPersonCtrl.text.trim(),
        contactNumber: _contactNumberCtrl.text.trim(),
        officeAddress: _officeAddressCtrl.text.trim(),
      );

      await _supabase.auth.signInWithOtp(
        email: draft.normalizedEmail,
        shouldCreateUser: true,
      );

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => CityAdminVerifyOtpScreen(application: draft),
        ),
      );
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Application failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _openLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const WebPortalLoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;
          return Stack(
            children: [
              const Positioned.fill(child: _ApplicationBackdrop()),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 40 : 18,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: wide
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: _ApplicationCopy(onLogin: _openLogin),
                                ),
                                const SizedBox(width: 36),
                                Expanded(child: _ApplicationCard(state: this)),
                              ],
                            )
                          : Column(
                              children: [
                                _ApplicationCopy(
                                  onLogin: _openLogin,
                                  compact: true,
                                ),
                                const SizedBox(height: 20),
                                _ApplicationCard(state: this),
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

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.state});

  final _CityAdminSignupScreenState state;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.all(26),
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
                      Icons.location_city_rounded,
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
                        'City Admin Application',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Tourism office access request',
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
            const SizedBox(height: 22),
            _PortalField(
              controller: state._officeNameCtrl,
              label: 'Tourism Office Name',
              icon: Icons.account_balance_rounded,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Office name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            FutureBuilder<Set<String>>(
              future: state._takenCitiesFuture,
              builder: (context, snapshot) {
                final taken = snapshot.data ?? const <String>{};
                return _CityDropdownField(
                  takenCities: taken,
                  selectedCity: state._selectedCity,
                  onChanged: state._onCitySelected,
                );
              },
            ),
            const SizedBox(height: 14),
            _PortalField(
              controller: state._contactPersonCtrl,
              label: 'Authorized Contact Person',
              icon: Icons.badge_outlined,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Contact person is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _PortalField(
              controller: state._contactNumberCtrl,
              label: 'Contact Number',
              icon: Icons.phone_outlined,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if ((value ?? '').trim().length < 10) {
                  return 'Enter a valid contact number';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _PortalField(
              controller: state._officeAddressCtrl,
              label: 'Office Address',
              icon: Icons.home_work_outlined,
              keyboardType: TextInputType.streetAddress,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return 'Office address is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _PortalField(
              controller: state._emailCtrl,
              label: 'Official Email Address',
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (value) {
                final email = (value ?? '').trim();
                if (email.isEmpty) return 'Email is required';
                if (!state._validEmail(email)) return 'Enter a valid email';
                return null;
              },
            ),
            const SizedBox(height: 14),
            _PortalField(
              controller: state._passwordCtrl,
              label: 'Password',
              icon: Icons.lock_outline_rounded,
              obscureText: state._obscurePassword,
              textInputAction: TextInputAction.next,
              suffix: IconButton(
                onPressed: state._loading
                    ? null
                    : state._togglePasswordVisibility,
                icon: Icon(
                  state._obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              validator: (value) {
                if ((value ?? '').length < 6) {
                  return 'Password must be at least 6 characters';
                }
                return null;
              },
            ),
            const SizedBox(height: 14),
            _PortalField(
              controller: state._confirmCtrl,
              label: 'Confirm Password',
              icon: Icons.lock_reset_rounded,
              obscureText: state._obscureConfirm,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) {
                if (!state._loading) state._sendOtp();
              },
              suffix: IconButton(
                onPressed: state._loading
                    ? null
                    : state._toggleConfirmVisibility,
                icon: Icon(
                  state._obscureConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF94A3B8),
                ),
              ),
              validator: (value) {
                if ((value ?? '').isEmpty) return 'Confirm your password';
                if (value != state._passwordCtrl.text) {
                  return 'Passwords do not match';
                }
                return null;
              },
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                onPressed: state._loading ? null : state._sendOtp,
                icon: state._loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.mark_email_read_rounded),
                label: Text(
                  state._loading ? 'Sending code...' : 'Send Verification Code',
                ),
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
            const SizedBox(height: 10),
            Center(
              child: TextButton.icon(
                onPressed: state._loading ? null : state._openLogin,
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Back to sign in'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalField extends StatelessWidget {
  const _PortalField({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboardType,
    this.obscureText = false,
    this.validator,
    this.suffix,
    this.textInputAction,
    this.onFieldSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final FormFieldValidator<String>? validator;
  final Widget? suffix;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
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
        errorMaxLines: 2,
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
    );
  }
}

class _ApplicationCopy extends StatelessWidget {
  const _ApplicationCopy({required this.onLogin, this.compact = false});

  final VoidCallback onLogin;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          onPressed: onLogin,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to admin login'),
          style: TextButton.styleFrom(
            foregroundColor: const Color(0xFF2A86FF),
            padding: EdgeInsets.zero,
          ),
        ),
        const SizedBox(height: 22),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFFE2ECF8)),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_user_rounded,
                size: 18,
                color: Color(0xFF2A86FF),
              ),
              SizedBox(width: 8),
              Text(
                'Provincial approval required',
                style: TextStyle(
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Text(
          'Apply for TourisTrike city admin access.',
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
          'Submit your tourism office details and verify your official email. Your account opens only after the provincial admin approves the request.',
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
            _StepChip(icon: Icons.description_rounded, label: 'Apply'),
            _StepChip(icon: Icons.admin_panel_settings, label: 'Review'),
            _StepChip(icon: Icons.check_circle, label: 'Activate'),
          ],
        ),
      ],
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
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

// ── City dropdown ─────────────────────────────────────────────────────────────

const _kBulacanCities = [
  'Angat', 'Balagtas', 'Baliwag', 'Bocaue', 'Bulakan', 'Bustos',
  'Calumpit', 'Dona Remedios Trinidad', 'Guiguinto', 'Hagonoy',
  'Malolos', 'Marilao', 'Meycauayan', 'Norzagaray', 'Obando',
  'Pandi', 'Paombong', 'Plaridel', 'Pulilan', 'San Ildefonso',
  'San Jose del Monte', 'San Miguel', 'San Rafael', 'Santa Maria',
];

class _CityDropdownField extends StatelessWidget {
  const _CityDropdownField({
    required this.takenCities,
    required this.selectedCity,
    required this.onChanged,
  });

  final Set<String> takenCities;
  final String? selectedCity;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final available = _kBulacanCities
        .where((c) => !takenCities.contains(c))
        .toList();

    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
      borderSide: BorderSide(color: Color(0xFFE2ECF8)),
    );

    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: available.contains(selectedCity) ? selectedCity : null,
      isExpanded: true,
      hint: const Text(
        'Select city / municipality',
        style: TextStyle(color: Color(0xFF94A3B8), fontSize: 14),
      ),
      validator: (value) =>
          (value == null || value.isEmpty) ? 'City or municipality is required' : null,
      onChanged: onChanged,
      decoration: const InputDecoration(
        labelText: 'City / Municipality',
        prefixIcon: Icon(Icons.location_city_rounded, color: Color(0xFF94A3B8)),
        filled: true,
        fillColor: Color(0xFFF8FBFF),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        errorMaxLines: 2,
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          borderSide: BorderSide(color: Color(0xFF2A86FF), width: 1.2),
        ),
      ),
      items: available
          .map(
            (city) => DropdownMenuItem<String>(
              value: city,
              child: Text(city),
            ),
          )
          .toList(),
    );
  }
}

class _ApplicationBackdrop extends StatelessWidget {
  const _ApplicationBackdrop();

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
