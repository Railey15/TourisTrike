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

  static const String logoUrl =
      'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/public-assets/Logo.png';

  final TextEditingController _officeNameCtrl = TextEditingController();
  final TextEditingController _contactPersonCtrl = TextEditingController();
  final TextEditingController _contactNumberCtrl = TextEditingController();
  final TextEditingController _officeAddressCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _confirmCtrl = TextEditingController();

  String? _selectedCity;
  late Future<Set<String>> _takenCitiesFuture;

  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    _takenCitiesFuture = _fetchTakenCities();
  }

  void _togglePasswordVisibility() {
    setState(() => _obscurePassword = !_obscurePassword);
  }

  void _toggleConfirmVisibility() {
    setState(() => _obscureConfirm = !_obscureConfirm);
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

  void _onCitySelected(String? city) {
    setState(() => _selectedCity = city);
  }

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
          backgroundColor:
              error ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
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
      backgroundColor: const Color(0xFFF5F9FF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 980;

          return Stack(
            children: [
              const Positioned.fill(child: _ApplicationBackdrop()),
              SafeArea(
                child: Column(
                  children: [
                    _TopBar(onLogin: _openLogin),
                    Expanded(
                      child: Center(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            wide ? 42 : 20,
                            20,
                            wide ? 42 : 20,
                            36,
                          ),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1160),
                            child: wide
                                ? Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Expanded(
                                        flex: 9,
                                        child: _ApplicationCopy(
                                          onLogin: _openLogin,
                                        ),
                                      ),
                                      const SizedBox(width: 40),
                                      Expanded(
                                        flex: 10,
                                        child: _ApplicationCard(state: this),
                                      ),
                                    ],
                                  )
                                : Column(
                                    children: [
                                      _ApplicationCopy(
                                        onLogin: _openLogin,
                                        compact: true,
                                      ),
                                      const SizedBox(height: 24),
                                      _ApplicationCard(state: this),
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
  const _TopBar({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.95),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFDCEBFF)),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withOpacity(0.06),
                      blurRadius: 18,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Image.network(
                  _CityAdminSignupScreenState.logoUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, _, _) => const Icon(
                    Icons.electric_rickshaw_rounded,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'TourisTrike',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.3,
                ),
              ),
            ],
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: onLogin,
            icon: const Icon(Icons.login_rounded, size: 18),
            label: const Text('Back to Sign In'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2563EB),
              side: const BorderSide(color: Color(0xFFBFDBFE)),
              backgroundColor: Colors.white.withOpacity(0.86),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(999),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
        ],
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
      constraints: const BoxConstraints(maxWidth: 560),
      padding: const EdgeInsets.all(30),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.96),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.95)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.08),
            blurRadius: 38,
            offset: const Offset(0, 24),
          ),
        ],
      ),
      child: Form(
        key: state._formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _FormHeader(),
            const SizedBox(height: 26),
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
            Row(
              children: [
                Expanded(
                  child: _PortalField(
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
                        return 'Minimum 6 characters';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _PortalField(
                    controller: state._confirmCtrl,
                    label: 'Confirm Password',
                    icon: Icons.lock_reset_rounded,
                    obscureText: state._obscureConfirm,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) {
                      if (!state._loading) state._sendOtp();
                    },
                    suffix: IconButton(
                      onPressed:
                          state._loading ? null : state._toggleConfirmVisibility,
                      icon: Icon(
                        state._obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                    validator: (value) {
                      if ((value ?? '').isEmpty) return 'Confirm password';
                      if (value != state._passwordCtrl.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 56,
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
            const SizedBox(height: 14),
            const Text(
              'A verification code will be sent to your official email address.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12.5,
                height: 1.4,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormHeader extends StatelessWidget {
  const _FormHeader();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 86,
          height: 86,
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: const Color(0xFFDCEBFF)),
          ),
          child: Image.network(
            _CityAdminSignupScreenState.logoUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(
              Icons.location_city_rounded,
              color: Color(0xFF2563EB),
              size: 40,
            ),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'City Admin Application',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 26,
            fontWeight: FontWeight.w900,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 7),
        const Text(
          'Submit your tourism office details for approval',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 13.5,
            height: 1.45,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
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
      style: const TextStyle(
        color: Color(0xFF0F172A),
        fontSize: 14,
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
        errorMaxLines: 2,
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
            width: 1.35,
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
            width: 1.35,
          ),
        ),
      ),
    );
  }
}

class _ApplicationCopy extends StatelessWidget {
  const _ApplicationCopy({
    required this.onLogin,
    this.compact = false,
  });

  final VoidCallback onLogin;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: compact ? Alignment.center : Alignment.centerLeft,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            compact ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFE2ECF8)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.verified_user_rounded,
                  size: 19,
                  color: Color(0xFF2563EB),
                ),
                SizedBox(width: 9),
                Text(
                  'Provincial approval required',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'Apply for city admin access.',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: TextStyle(
              color: const Color(0xFF0F172A),
              fontSize: compact ? 36 : 50,
              height: 1.04,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.2,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Register your tourism office, verify your official email, and wait for provincial admin approval before accessing the TourisTrike web portal.',
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 15.5,
              height: 1.62,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 28),
          const Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _StepChip(
                number: '01',
                icon: Icons.description_rounded,
                title: 'Apply',
                label: 'Submit office details',
              ),
              _StepChip(
                number: '02',
                icon: Icons.mark_email_read_rounded,
                title: 'Verify',
                label: 'Confirm your email',
              ),
              _StepChip(
                number: '03',
                icon: Icons.check_circle_rounded,
                title: 'Activate',
                label: 'Wait for approval',
              ),
            ],
          ),
          const SizedBox(height: 26),
          Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.86),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE2ECF8)),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF2563EB),
                  size: 22,
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Each city or municipality can only have one active or pending city admin account.',
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
          ),
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.number,
    required this.icon,
    required this.title,
    required this.label,
  });

  final String number;
  final IconData icon;
  final String title;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 156,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2ECF8)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withOpacity(0.045),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                number,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const Spacer(),
              Icon(icon, color: const Color(0xFF2563EB), size: 21),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 11.8,
              height: 1.35,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

const _kBulacanCities = [
  'Angat',
  'Balagtas',
  'Baliwag',
  'Bocaue',
  'Bulakan',
  'Bustos',
  'Calumpit',
  'Dona Remedios Trinidad',
  'Guiguinto',
  'Hagonoy',
  'Malolos',
  'Marilao',
  'Meycauayan',
  'Norzagaray',
  'Obando',
  'Pandi',
  'Paombong',
  'Plaridel',
  'Pulilan',
  'San Ildefonso',
  'San Jose del Monte',
  'San Miguel',
  'San Rafael',
  'Santa Maria',
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
    final available =
        _kBulacanCities.where((city) => !takenCities.contains(city)).toList();

    const border = OutlineInputBorder(
      borderRadius: BorderRadius.all(Radius.circular(18)),
      borderSide: BorderSide(color: Color(0xFFE2ECF8)),
    );

    return DropdownButtonFormField<String>(
      value: available.contains(selectedCity) ? selectedCity : null,
      isExpanded: true,
      hint: const Text(
        'Select city / municipality',
        style: TextStyle(
          color: Color(0xFF94A3B8),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'City or municipality is required';
        }
        return null;
      },
      onChanged: onChanged,
      decoration: const InputDecoration(
        labelText: 'City / Municipality',
        labelStyle: TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(
          Icons.location_city_rounded,
          color: Color(0xFF94A3B8),
        ),
        filled: true,
        fillColor: Color(0xFFF8FBFF),
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        errorMaxLines: 2,
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(18)),
          borderSide: BorderSide(color: Color(0xFF2563EB), width: 1.35),
        ),
      ),
      items: available
          .map(
            (city) => DropdownMenuItem<String>(
              value: city,
              child: Text(
                city,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w700,
                ),
              ),
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
        const Positioned(
          top: -120,
          right: -100,
          child: _GlowCircle(size: 320, color: Color(0xFF60A5FA)),
        ),
        const Positioned(
          bottom: -120,
          left: -110,
          child: _GlowCircle(size: 300, color: Color(0xFF34D399)),
        ),
        CustomPaint(
          painter: _GridPainter(),
          child: const SizedBox.expand(),
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
          color: color.withOpacity(0.13),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.18),
              blurRadius: 90,
              spreadRadius: 28,
            ),
          ],
        ),
      ),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = const Color(0xFFCFE2F8).withOpacity(0.34)
      ..strokeWidth = 1;

    for (var x = 0.0; x < size.width; x += 58) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), linePaint);
    }

    for (var y = 0.0; y < size.height; y += 58) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), linePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}