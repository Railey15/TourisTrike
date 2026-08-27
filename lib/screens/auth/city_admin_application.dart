import 'package:flutter/material.dart';

import 'web_portal_login_screen.dart';

class CityAdminApplicationDraft {
  const CityAdminApplicationDraft({
    required this.email,
    required this.password,
    required this.city,
    required this.officeName,
    required this.contactPerson,
    required this.contactNumber,
    required this.officeAddress,
  });

  final String email;
  final String password;
  final String city;
  final String officeName;
  final String contactPerson;
  final String contactNumber;
  final String officeAddress;

  String get displayOffice =>
      officeName.trim().isEmpty ? '$city Tourism Office' : officeName.trim();

  String get normalizedCity => city.trim();

  String get normalizedEmail => email.trim().toLowerCase();

  Map<String, String> get contactNameParts {
    final parts = contactPerson.trim().split(RegExp(r'\s+'));

    if (parts.isEmpty || parts.first.isEmpty) {
      return const {
        'first_name': '',
        'last_name': '',
      };
    }

    if (parts.length == 1) {
      return {
        'first_name': parts.first,
        'last_name': '',
      };
    }

    return {
      'first_name': parts.first,
      'last_name': parts.sublist(1).join(' '),
    };
  }

  Map<String, dynamic> profileInsertPayload(String userId) {
    final nameParts = contactNameParts;

    return {
      'id': userId,
      'role': 'tourist',
      'first_name': nameParts['first_name'],
      'last_name': nameParts['last_name'],
      'full_name': contactPerson.trim(),
      'mobile': contactNumber.trim(),
      'address': officeAddress.trim(),
      'city': normalizedCity,
      'province': 'Bulacan',
    };
  }

  Map<String, dynamic> profileUpdatePayload() {
    final payload = profileInsertPayload('');
    payload.remove('id');
    payload.remove('role');

    return payload;
  }

  Map<String, dynamic> registrationPayload(String userId) {
    return {
      'user_id': userId,
      'city': normalizedCity,
      'office_name': displayOffice,
      'contact_person': contactPerson.trim(),
      'contact_number': contactNumber.trim(),
      'email': normalizedEmail,
      'office_address': officeAddress.trim(),
      'status': 'pending',
    };
  }
}

// ============================================================
// CITY ADMIN APPLICATION SCREEN
// ============================================================

class CityAdminSignupScreen extends StatefulWidget {
  const CityAdminSignupScreen({
    super.key,
  });

  @override
  State<CityAdminSignupScreen> createState() =>
      _CityAdminSignupScreenState();
}

class _CityAdminSignupScreenState extends State<CityAdminSignupScreen> {
  static const String logoUrl =
      'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/public-assets/Logo.png';

  static const Color primaryBlue = Color(0xFF1557D6);
  static const Color deepBlue = Color(0xFF0B2E75);
  static const Color green = Color(0xFF31A56B);
  static const Color ink = Color(0xFF10213F);
  static const Color muted = Color(0xFF64748B);
  static const Color border = Color(0xFFDCE7F4);
  static const Color background = Color(0xFFF5F9FE);

  final _formKey = GlobalKey<FormState>();

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _cityController = TextEditingController();
  final _officeNameController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _contactNumberController = TextEditingController();
  final _officeAddressController = TextEditingController();

  bool _obscurePassword = true;
  bool _agreeToApplication = false;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _cityController.dispose();
    _officeNameController.dispose();
    _contactPersonController.dispose();
    _contactNumberController.dispose();
    _officeAddressController.dispose();

    super.dispose();
  }

  void _backToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const WebPortalLoginScreen(),
      ),
    );
  }

  Future<void> _submitApplication() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_agreeToApplication) {
      _showMessage(
        'Please confirm that the information provided is accurate.',
        isError: true,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    /*
      ----------------------------------------------------------
      BACKEND INTEGRATION
      ----------------------------------------------------------

      Your existing application model can be created here:

      final draft = CityAdminApplicationDraft(
        email: _emailController.text,
        password: _passwordController.text,
        city: _cityController.text,
        officeName: _officeNameController.text,
        contactPerson: _contactPersonController.text,
        contactNumber: _contactNumberController.text,
        officeAddress: _officeAddressController.text,
      );

      Example:

      final registrationPayload =
          draft.registrationPayload(userId);

      final profilePayload =
          draft.profileInsertPayload(userId);

      Connect these payloads to your existing
      Supabase/authentication service.

      ----------------------------------------------------------
    */

    await Future.delayed(
      const Duration(milliseconds: 700),
    );

    if (!mounted) return;

    setState(() {
      _isSubmitting = false;
    });

    _showSuccessDialog();
  }

  void _showMessage(
    String message, {
    bool isError = false,
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: isError
            ? const Color(0xFFB42318)
            : const Color(0xFF167A4A),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 430,
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF8F0),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: green,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Application Submitted',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: ink,
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.6,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Your city or municipal tourism office application has been submitted for provincial review.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: muted,
                      fontSize: 14,
                      height: 1.55,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                        _backToLogin();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          vertical: 15,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(13),
                        ),
                      ),
                      child: const Text(
                        'Back to Sign In',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          final isDesktop = width >= 1050;
          final isTablet = width >= 700 && width < 1050;
          final isMobile = width < 700;
          final isSmallMobile = width < 420;

          return Stack(
            children: [
              const Positioned.fill(
                child: _ApplicationBackground(),
              ),

              SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 1180,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop
                              ? 42
                              : isTablet
                                  ? 28
                                  : 18,
                          vertical: isDesktop
                              ? 28
                              : isTablet
                                  ? 22
                                  : 16,
                        ),
                        child: Column(
                          children: [
                            _TopNavigation(
                              isMobile: isMobile,
                              isSmallMobile: isSmallMobile,
                              onBack: _backToLogin,
                            ),

                            SizedBox(
                              height: isDesktop
                                  ? 42
                                  : isTablet
                                      ? 34
                                      : 25,
                            ),

                            _PageIntro(
                              isMobile: isMobile,
                              isSmallMobile: isSmallMobile,
                            ),

                            SizedBox(
                              height: isDesktop
                                  ? 34
                                  : isTablet
                                      ? 28
                                      : 22,
                            ),

                            if (isDesktop)
                              _DesktopApplicationLayout(
                                form: _ApplicationForm(
                                  formKey: _formKey,
                                  emailController: _emailController,
                                  passwordController: _passwordController,
                                  cityController: _cityController,
                                  officeNameController:
                                      _officeNameController,
                                  contactPersonController:
                                      _contactPersonController,
                                  contactNumberController:
                                      _contactNumberController,
                                  officeAddressController:
                                      _officeAddressController,
                                  obscurePassword: _obscurePassword,
                                  agreeToApplication:
                                      _agreeToApplication,
                                  isSubmitting: _isSubmitting,
                                  onTogglePassword: () {
                                    setState(() {
                                      _obscurePassword =
                                          !_obscurePassword;
                                    });
                                  },
                                  onToggleAgreement: (value) {
                                    setState(() {
                                      _agreeToApplication =
                                          value ?? false;
                                    });
                                  },
                                  onSubmit: _submitApplication,
                                ),
                              )
                            else
                              _ApplicationForm(
                                formKey: _formKey,
                                emailController: _emailController,
                                passwordController:
                                    _passwordController,
                                cityController: _cityController,
                                officeNameController:
                                    _officeNameController,
                                contactPersonController:
                                    _contactPersonController,
                                contactNumberController:
                                    _contactNumberController,
                                officeAddressController:
                                    _officeAddressController,
                                obscurePassword: _obscurePassword,
                                agreeToApplication:
                                    _agreeToApplication,
                                isSubmitting: _isSubmitting,
                                onTogglePassword: () {
                                  setState(() {
                                    _obscurePassword =
                                        !_obscurePassword;
                                  });
                                },
                                onToggleAgreement: (value) {
                                  setState(() {
                                    _agreeToApplication =
                                        value ?? false;
                                  });
                                },
                                onSubmit: _submitApplication,
                              ),

                            const SizedBox(height: 28),

                            _BottomNote(
                              isMobile: isMobile,
                            ),
                          ],
                        ),
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

// ============================================================
// TOP NAVIGATION
// ============================================================

class _TopNavigation extends StatelessWidget {
  const _TopNavigation({
    required this.isMobile,
    required this.isSmallMobile,
    required this.onBack,
  });

  final bool isMobile;
  final bool isSmallMobile;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                width: isSmallMobile ? 43 : 48,
                height: isSmallMobile ? 43 : 48,
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: const Color(0xFFDCE8F5),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF173B72)
                          .withOpacity(0.07),
                      blurRadius: 18,
                      offset: const Offset(0, 7),
                    ),
                  ],
                ),
                child: Image.network(
                  _CityAdminSignupScreenState.logoUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) {
                    return const Icon(
                      Icons.location_city_rounded,
                      color: _CityAdminSignupScreenState.primaryBlue,
                    );
                  },
                ),
              ),
              const SizedBox(width: 11),
              Flexible(
                child: Text(
                  'TourisTrike',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _CityAdminSignupScreenState.ink,
                    fontSize: isSmallMobile ? 16 : 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(width: 12),

        OutlinedButton.icon(
          onPressed: onBack,
          icon: const Icon(
            Icons.login_rounded,
            size: 16,
          ),
          label: Text(
            isMobile ? 'Sign In' : 'Back to Sign In',
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor:
                _CityAdminSignupScreenState.primaryBlue,
            backgroundColor: Colors.white.withOpacity(0.78),
            side: const BorderSide(
              color: Color(0xFFD2E2F4),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: isSmallMobile ? 12 : 16,
              vertical: 12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
            textStyle: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// PAGE INTRO
// ============================================================

class _PageIntro extends StatelessWidget {
  const _PageIntro({
    required this.isMobile,
    required this.isSmallMobile,
  });

  final bool isMobile;
  final bool isSmallMobile;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.84),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFDCE8F5),
            ),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.verified_user_rounded,
                size: 15,
                color: _CityAdminSignupScreenState.primaryBlue,
              ),
              SizedBox(width: 7),
              Text(
                'PROVINCIAL APPROVAL REQUIRED',
                style: TextStyle(
                  color: Color(0xFF42617F),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        Text(
          'Apply for city admin\naccess.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _CityAdminSignupScreenState.ink,
            fontSize: isSmallMobile
                ? 34
                : isMobile
                    ? 38
                    : 48,
            height: 1.04,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.6,
          ),
        ),

        const SizedBox(height: 14),

        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 650,
          ),
          child: const Text(
            'Register your tourism office, verify your official contact details, and submit your application for provincial review.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _CityAdminSignupScreenState.muted,
              fontSize: 15,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        const SizedBox(height: 22),

        const _ApplicationSteps(),
      ],
    );
  }
}

// ============================================================
// APPLICATION STEPS
// ============================================================

class _ApplicationSteps extends StatelessWidget {
  const _ApplicationSteps();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 600;

        final steps = [
          const _StepItem(
            number: '01',
            icon: Icons.edit_document,
            title: 'Apply',
            subtitle: 'Submit office details',
          ),
          const _StepItem(
            number: '02',
            icon: Icons.mark_email_read_rounded,
            title: 'Verify',
            subtitle: 'Confirm your email',
          ),
          const _StepItem(
            number: '03',
            icon: Icons.verified_rounded,
            title: 'Activate',
            subtitle: 'Wait for approval',
          ),
        ];

        return Wrap(
          alignment: WrapAlignment.center,
          spacing: 10,
          runSpacing: 10,
          children: steps
              .map(
                (step) => SizedBox(
                  width: compact ? 155 : 190,
                  child: step,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _StepItem extends StatelessWidget {
  const _StepItem({
    required this.number,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final String number;
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.78),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: const Color(0xFFDDE8F5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 17,
              color: _CityAdminSignupScreenState.primaryBlue,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  number,
                  style: const TextStyle(
                    color: Color(0xFF91A4BA),
                    fontSize: 9,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  title,
                  style: const TextStyle(
                    color: _CityAdminSignupScreenState.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _CityAdminSignupScreenState.muted,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w600,
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
// DESKTOP LAYOUT
// ============================================================

class _DesktopApplicationLayout extends StatelessWidget {
  const _DesktopApplicationLayout({
    required this.form,
  });

  final Widget form;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Expanded(
          flex: 8,
          child: _ApplicationInformation(),
        ),
        const SizedBox(width: 26),
        Expanded(
          flex: 12,
          child: form,
        ),
      ],
    );
  }
}

// ============================================================
// INFORMATION PANEL
// ============================================================

class _ApplicationInformation extends StatelessWidget {
  const _ApplicationInformation();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(
          color: Colors.white,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF173B72).withOpacity(0.07),
            blurRadius: 35,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.account_balance_rounded,
              color: _CityAdminSignupScreenState.primaryBlue,
              size: 23,
            ),
          ),

          const SizedBox(height: 18),

          const Text(
            'Before you apply',
            style: TextStyle(
              color: _CityAdminSignupScreenState.ink,
              fontSize: 21,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'City and municipal tourism offices can request access to the TourisTrike web portal through provincial approval.',
            style: TextStyle(
              color: _CityAdminSignupScreenState.muted,
              fontSize: 13.5,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 22),

          const _InfoPoint(
            icon: Icons.domain_rounded,
            title: 'Official tourism office',
            description:
                'Use the official name of your city or municipal tourism office.',
          ),

          const SizedBox(height: 14),

          const _InfoPoint(
            icon: Icons.email_rounded,
            title: 'Official contact',
            description:
                'Provide an email address that your tourism office can access.',
          ),

          const SizedBox(height: 14),

          const _InfoPoint(
            icon: Icons.verified_user_rounded,
            title: 'Provincial review',
            description:
                'Applications remain pending until reviewed and approved.',
          ),

          const SizedBox(height: 22),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FAF4),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: const Color(0xFFD7F0E0),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF208454),
                  size: 19,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Each city or municipality can only have one active or pending city admin account.',
                    style: TextStyle(
                      color: Color(0xFF397154),
                      fontSize: 11.5,
                      height: 1.45,
                      fontWeight: FontWeight.w700,
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

class _InfoPoint extends StatelessWidget {
  const _InfoPoint({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            icon,
            size: 18,
            color: _CityAdminSignupScreenState.primaryBlue,
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _CityAdminSignupScreenState.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                description,
                style: const TextStyle(
                  color: _CityAdminSignupScreenState.muted,
                  fontSize: 10.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// APPLICATION FORM
// ============================================================

class _ApplicationForm extends StatelessWidget {
  const _ApplicationForm({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.cityController,
    required this.officeNameController,
    required this.contactPersonController,
    required this.contactNumberController,
    required this.officeAddressController,
    required this.obscurePassword,
    required this.agreeToApplication,
    required this.isSubmitting,
    required this.onTogglePassword,
    required this.onToggleAgreement,
    required this.onSubmit,
  });

  final GlobalKey<FormState> formKey;

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final TextEditingController cityController;
  final TextEditingController officeNameController;
  final TextEditingController contactPersonController;
  final TextEditingController contactNumberController;
  final TextEditingController officeAddressController;

  final bool obscurePassword;
  final bool agreeToApplication;
  final bool isSubmitting;

  final VoidCallback onTogglePassword;
  final ValueChanged<bool?> onToggleAgreement;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.94),
        borderRadius: BorderRadius.circular(27),
        border: Border.all(
          color: Colors.white,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF173B72).withOpacity(0.09),
            blurRadius: 40,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _FormHeader(),

            const SizedBox(height: 24),

            const _FormSectionTitle(
              number: '01',
              title: 'Account details',
              subtitle:
                  'Create the credentials for the city admin account.',
            ),

            const SizedBox(height: 15),

            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 620;

                if (twoColumns) {
                  return Row(
                    children: [
                      Expanded(
                        child: _AppTextField(
                          controller: emailController,
                          label: 'Official Email Address',
                          hint: 'tourism@city.gov.ph',
                          icon: Icons.email_outlined,
                          keyboardType:
                              TextInputType.emailAddress,
                          validator: _validateEmail,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _AppTextField(
                          controller: passwordController,
                          label: 'Password',
                          hint: 'Create a secure password',
                          icon: Icons.lock_outline_rounded,
                          obscureText: obscurePassword,
                          suffixIcon: IconButton(
                            onPressed: onTogglePassword,
                            icon: Icon(
                              obscurePassword
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 19,
                            ),
                          ),
                          validator: _validatePassword,
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    _AppTextField(
                      controller: emailController,
                      label: 'Official Email Address',
                      hint: 'tourism@city.gov.ph',
                      icon: Icons.email_outlined,
                      keyboardType:
                          TextInputType.emailAddress,
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 13),
                    _AppTextField(
                      controller: passwordController,
                      label: 'Password',
                      hint: 'Create a secure password',
                      icon: Icons.lock_outline_rounded,
                      obscureText: obscurePassword,
                      suffixIcon: IconButton(
                        onPressed: onTogglePassword,
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 19,
                        ),
                      ),
                      validator: _validatePassword,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 27),

            const _FormSectionTitle(
              number: '02',
              title: 'Tourism office',
              subtitle:
                  'Tell us which city or municipality you represent.',
            ),

            const SizedBox(height: 15),

            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 620;

                if (twoColumns) {
                  return Row(
                    children: [
                      Expanded(
                        child: _AppTextField(
                          controller: cityController,
                          label: 'City / Municipality',
                          hint: 'e.g. Malolos',
                          icon: Icons.location_city_outlined,
                          validator: _requiredValidator,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _AppTextField(
                          controller: officeNameController,
                          label: 'Office Name',
                          hint: 'Tourism Office',
                          icon: Icons.account_balance_outlined,
                          validator: _requiredValidator,
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    _AppTextField(
                      controller: cityController,
                      label: 'City / Municipality',
                      hint: 'e.g. Malolos',
                      icon: Icons.location_city_outlined,
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 13),
                    _AppTextField(
                      controller: officeNameController,
                      label: 'Office Name',
                      hint: 'Tourism Office',
                      icon: Icons.account_balance_outlined,
                      validator: _requiredValidator,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 13),

            _AppTextField(
              controller: officeAddressController,
              label: 'Office Address',
              hint: 'Enter the complete tourism office address',
              icon: Icons.location_on_outlined,
              maxLines: 2,
              validator: _requiredValidator,
            ),

            const SizedBox(height: 27),

            const _FormSectionTitle(
              number: '03',
              title: 'Contact person',
              subtitle:
                  'Provide the authorized representative of the office.',
            ),

            const SizedBox(height: 15),

            LayoutBuilder(
              builder: (context, constraints) {
                final twoColumns = constraints.maxWidth >= 620;

                if (twoColumns) {
                  return Row(
                    children: [
                      Expanded(
                        child: _AppTextField(
                          controller:
                              contactPersonController,
                          label: 'Contact Person',
                          hint: 'Full name',
                          icon: Icons.person_outline_rounded,
                          validator: _requiredValidator,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _AppTextField(
                          controller:
                              contactNumberController,
                          label: 'Contact Number',
                          hint: '09XX XXX XXXX',
                          icon: Icons.phone_outlined,
                          keyboardType:
                              TextInputType.phone,
                          validator: _validatePhone,
                        ),
                      ),
                    ],
                  );
                }

                return Column(
                  children: [
                    _AppTextField(
                      controller: contactPersonController,
                      label: 'Contact Person',
                      hint: 'Full name',
                      icon: Icons.person_outline_rounded,
                      validator: _requiredValidator,
                    ),
                    const SizedBox(height: 13),
                    _AppTextField(
                      controller: contactNumberController,
                      label: 'Contact Number',
                      hint: '09XX XXX XXXX',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      validator: _validatePhone,
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 22),

            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFE),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: const Color(0xFFE2EAF4),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: agreeToApplication,
                    onChanged: onToggleAgreement,
                    activeColor:
                        _CityAdminSignupScreenState.primaryBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        top: 8,
                      ),
                      child: Text(
                        'I confirm that the information provided is accurate and that I am authorized to submit this application on behalf of the tourism office.',
                        style: TextStyle(
                          color:
                              _CityAdminSignupScreenState.muted,
                          fontSize: 10.5,
                          height: 1.45,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isSubmitting ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _CityAdminSignupScreenState.primaryBlue,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      const Color(0xFF9CB7E8),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(
                    milliseconds: 180,
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          key: ValueKey('loading'),
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Row(
                          key: ValueKey('button'),
                          mainAxisAlignment:
                              MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.send_rounded,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Submit Application',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline_rounded,
                  size: 13,
                  color: Color(0xFF7B8EA6),
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'Your application will remain pending until reviewed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF7B8EA6),
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required';
    }

    return null;
  }

  static String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Email is required';
    }

    final email = value.trim();

    if (!RegExp(
      r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
    ).hasMatch(email)) {
      return 'Enter a valid email address';
    }

    return null;
  }

  static String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Password is required';
    }

    if (value.length < 8) {
      return 'Use at least 8 characters';
    }

    return null;
  }

  static String? _validatePhone(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Contact number is required';
    }

    final cleaned = value.replaceAll(
      RegExp(r'[\s\-()]'),
      '',
    );

    if (cleaned.length < 10) {
      return 'Enter a valid contact number';
    }

    return null;
  }
}

// ============================================================
// FORM HEADER
// ============================================================

class _FormHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 46,
          height: 46,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Image.network(
            _CityAdminSignupScreenState.logoUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) {
              return const Icon(
                Icons.account_balance_rounded,
                color: _CityAdminSignupScreenState.primaryBlue,
              );
            },
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
                  color: _CityAdminSignupScreenState.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Submit your tourism office details for approval',
                style: TextStyle(
                  color: _CityAdminSignupScreenState.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// FORM SECTION TITLE
// ============================================================

class _FormSectionTitle extends StatelessWidget {
  const _FormSectionTitle({
    required this.number,
    required this.title,
    required this.subtitle,
  });

  final String number;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: _CityAdminSignupScreenState.primaryBlue,
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _CityAdminSignupScreenState.ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _CityAdminSignupScreenState.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================
// TEXT FIELD
// ============================================================

class _AppTextField extends StatelessWidget {
  const _AppTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    required this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.suffixIcon,
    this.maxLines = 1,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? Function(String?) validator;

  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffixIcon;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: _CityAdminSignupScreenState.ink,
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),

        const SizedBox(height: 7),

        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscureText,
          maxLines: obscureText ? 1 : maxLines,
          validator: validator,
          textInputAction: maxLines > 1
              ? TextInputAction.newline
              : TextInputAction.next,
          style: const TextStyle(
            color: _CityAdminSignupScreenState.ink,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: Color(0xFF9AAABD),
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: Icon(
              icon,
              size: 19,
              color: const Color(0xFF91A4BA),
            ),
            suffixIcon: suffixIcon,
            filled: true,
            fillColor: const Color(0xFFF8FAFD),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(
                color: Color(0xFFE0E8F2),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(
                color: Color(0xFFE0E8F2),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(
                color: _CityAdminSignupScreenState.primaryBlue,
                width: 1.4,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(
                color: Color(0xFFD92D20),
              ),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(13),
              borderSide: const BorderSide(
                color: Color(0xFFD92D20),
                width: 1.4,
              ),
            ),
            errorStyle: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// BOTTOM NOTE
// ============================================================

class _BottomNote extends StatelessWidget {
  const _BottomNote({
    required this.isMobile,
  });

  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: _CityAdminSignupScreenState.green,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            'TourisTrike • Connecting local tourism offices across Bulacan.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: const Color(0xFF7A8BA0),
              fontSize: isMobile ? 9.5 : 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// BACKGROUND
// ============================================================

class _ApplicationBackground extends StatelessWidget {
  const _ApplicationBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: CustomPaint(
            painter: _ApplicationBackgroundPainter(),
          ),
        ),

        Positioned(
          top: -150,
          right: -120,
          child: _SoftBackgroundCircle(
            size: 390,
            color: const Color(0xFF4C9AFF),
            opacity: 0.10,
          ),
        ),

        Positioned(
          bottom: -170,
          left: -130,
          child: _SoftBackgroundCircle(
            size: 400,
            color: const Color(0xFF42D5A0),
            opacity: 0.10,
          ),
        ),

        Positioned(
          top: 280,
          left: -100,
          child: _SoftBackgroundCircle(
            size: 170,
            color: const Color(0xFFFFC94A),
            opacity: 0.035,
          ),
        ),
      ],
    );
  }
}

class _SoftBackgroundCircle extends StatelessWidget {
  const _SoftBackgroundCircle({
    required this.size,
    required this.color,
    required this.opacity,
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
          color: color.withOpacity(opacity),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(opacity * 0.55),
              blurRadius: 85,
              spreadRadius: 18,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// BACKGROUND PAINTER
// ============================================================

class _ApplicationBackgroundPainter extends CustomPainter {
  const _ApplicationBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFF8FBFF),
          Color(0xFFF1F7FE),
          Color(0xFFF7FBF9),
        ],
      ).createShader(
        Rect.fromLTWH(
          0,
          0,
          size.width,
          size.height,
        ),
      );

    canvas.drawRect(
      Offset.zero & size,
      backgroundPaint,
    );

    final gridPaint = Paint()
      ..color = const Color(0xFFB9D0E8).withOpacity(0.14)
      ..strokeWidth = 1;

    const spacing = 64.0;

    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        gridPaint,
      );
    }

    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }

    // Subtle tourism route.
    final routePaint = Paint()
      ..color = const Color(0xFF1557D6).withOpacity(0.045)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final route = Path();

    route.moveTo(
      size.width * 0.02,
      size.height * 0.76,
    );

    route.cubicTo(
      size.width * 0.20,
      size.height * 0.58,
      size.width * 0.35,
      size.height * 0.86,
      size.width * 0.52,
      size.height * 0.67,
    );

    route.cubicTo(
      size.width * 0.69,
      size.height * 0.49,
      size.width * 0.81,
      size.height * 0.62,
      size.width * 1.02,
      size.height * 0.39,
    );

    canvas.drawPath(
      route,
      routePaint,
    );

    final dotPaint = Paint()
      ..color = const Color(0xFF39A447).withOpacity(0.10);

    final points = [
      Offset(
        size.width * 0.21,
        size.height * 0.67,
      ),
      Offset(
        size.width * 0.52,
        size.height * 0.67,
      ),
      Offset(
        size.width * 0.80,
        size.height * 0.56,
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