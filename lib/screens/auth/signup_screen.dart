import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../theme/app_theme.dart';
import 'verify_email_otp_screen.dart';

enum SignupUserRole { tourist, driver }

enum PasswordStrength { weak, normal, strong }

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  static const String welcomeImageUrl =
      'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/public-assets/welcome.png';

  static final RegExp _passwordSymbolRegex = RegExp(
    r'''[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;'`~/]''',
  );

  final supabase = Supabase.instance.client;

  SignupUserRole _role = SignupUserRole.tourist;

  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _loading = false;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();

  final _scrollCtrl = ScrollController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmFocus = FocusNode();

  final _emailKey = GlobalKey();
  final _passwordKey = GlobalKey();
  final _confirmKey = GlobalKey();

  PasswordStrength? _strength;
  List<String> _passwordErrors = [];

  @override
  void initState() {
    super.initState();
    _passwordCtrl.addListener(_recalcStrength);
    _emailFocus.addListener(() {
      if (_emailFocus.hasFocus) _ensureVisible(_emailKey);
    });
    _passwordFocus.addListener(() {
      if (_passwordFocus.hasFocus) _ensureVisible(_passwordKey);
    });
    _confirmFocus.addListener(() {
      if (_confirmFocus.hasFocus) _ensureVisible(_confirmKey);
    });
  }

  @override
  void dispose() {
    _passwordCtrl.removeListener(_recalcStrength);
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    _scrollCtrl.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  void _recalcStrength() {
    final password = _passwordCtrl.text;

    setState(() {
      if (password.isEmpty) {
        _strength = null;
        _passwordErrors = [];
        return;
      }

      _strength = _computeStrength(password);
      _passwordErrors = _getPasswordErrors(password);
    });
  }

  List<String> _getPasswordErrors(String p) {
    final errors = <String>[];
    if (p.length < 8) errors.add('At least 8 characters');
    if (!RegExp(r'[A-Z]').hasMatch(p)) {
      errors.add('At least 1 uppercase letter');
    }
    if (!RegExp(r'[a-z]').hasMatch(p)) {
      errors.add('At least 1 lowercase letter');
    }
    if (!RegExp(r'\d').hasMatch(p)) errors.add('At least 1 number');
    if (!_passwordSymbolRegex.hasMatch(p)) {
      errors.add('At least 1 special character');
    }
    return errors;
  }

  bool _isStrongPassword(String p) => _getPasswordErrors(p).isEmpty;

  PasswordStrength _computeStrength(String p) {
    if (p.length < 8) return PasswordStrength.weak;
    final hasLower = RegExp(r'[a-z]').hasMatch(p);
    final hasUpper = RegExp(r'[A-Z]').hasMatch(p);
    final hasDigit = RegExp(r'\d').hasMatch(p);
    final hasSymbol = _passwordSymbolRegex.hasMatch(p);
    int score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (hasLower) score++;
    if (hasUpper) score++;
    if (hasDigit) score++;
    if (hasSymbol) score++;
    if (score >= 6) return PasswordStrength.strong;
    if (score >= 4) return PasswordStrength.normal;
    return PasswordStrength.weak;
  }

  String _strengthLabel(PasswordStrength s) {
    switch (s) {
      case PasswordStrength.weak:
        return 'Weak';
      case PasswordStrength.normal:
        return 'Fair';
      case PasswordStrength.strong:
        return 'Strong';
    }
  }

  Color _strengthColor(PasswordStrength s) {
    switch (s) {
      case PasswordStrength.weak:
        return const Color(0xFFEF4444);
      case PasswordStrength.normal:
        return const Color(0xFFF59E0B);
      case PasswordStrength.strong:
        return const Color(0xFF22C55E);
    }
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim());

  Future<void> _signup() async {
    FocusScope.of(context).unfocus();

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirm = _confirmCtrl.text;

    if (email.isEmpty || password.isEmpty || confirm.isEmpty) {
      _showSnack('Please fill in all fields.');
      return;
    }

    if (!_isValidEmail(email)) {
      _showSnack('Please enter a valid email address.');
      return;
    }

    final errors = _getPasswordErrors(password);
    if (errors.isNotEmpty) {
      _showSnack('Password is too weak: ${errors.first}');
      return;
    }

    if (!_isStrongPassword(password)) {
      _showSnack(
        'Password must have 8+ characters, uppercase, lowercase, number and special character.',
      );
      return;
    }

    if (password != confirm) {
      _showSnack('Passwords do not match.');
      return;
    }

    setState(() => _loading = true);

    try {
      await supabase.auth.signInWithOtp(email: email, shouldCreateUser: true);

      final roleString =
          _role == SignupUserRole.tourist ? 'tourist' : 'driver';

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => VerifyEmailOtpScreen(
            email: email,
            roleString: roleString,
            password: password,
          ),
        ),
      );
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Signup failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _ensureVisible(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.25,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF7FBFF),
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final height = constraints.maxHeight;
            final headerHeight = (height * 0.42).clamp(315.0, 410.0);

            return SingleChildScrollView(
              controller: _scrollCtrl,
              physics: const BouncingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(bottom: bottomInset + 24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: height),
                child: Stack(
                  children: [
                    const Positioned.fill(child: _SignupBackdrop()),
                    Column(
                      children: [
                        _Header(height: headerHeight),
                        Transform.translate(
                          offset: const Offset(0, -34),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                _SignupCard(
                                  role: _role,
                                  emailCtrl: _emailCtrl,
                                  passwordCtrl: _passwordCtrl,
                                  confirmCtrl: _confirmCtrl,
                                  emailFocus: _emailFocus,
                                  passwordFocus: _passwordFocus,
                                  confirmFocus: _confirmFocus,
                                  emailKey: _emailKey,
                                  passwordKey: _passwordKey,
                                  confirmKey: _confirmKey,
                                  obscurePassword: _obscurePassword,
                                  obscureConfirm: _obscureConfirm,
                                  loading: _loading,
                                  strength: _strength,
                                  strengthLabel: _strength == null
                                      ? ''
                                      : _strengthLabel(_strength!),
                                  strengthColor: _strength == null
                                      ? const Color(0xFFE2E8F0)
                                      : _strengthColor(_strength!),
                                  passwordErrors: _passwordErrors,
                                  onRoleChanged: (role) =>
                                      setState(() => _role = role),
                                  onTogglePassword: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                  onToggleConfirm: () => setState(
                                    () => _obscureConfirm = !_obscureConfirm,
                                  ),
                                  onLogin: () => Navigator.pop(context),
                                  onSignup: _loading ? null : _signup,
                                ),
                                const SizedBox(height: 18),
                                _TermsText(context: context),
                                const SizedBox(height: 28),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            _SignupScreenState.welcomeImageUrl,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) {
              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFEAF5FF),
                      Color(0xFFDDF1FF),
                      Color(0xFFF7FBFF),
                    ],
                  ),
                ),
              );
            },
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.white.withValues(alpha: 0.02),
                  Colors.white.withValues(alpha: 0.08),
                  const Color(0xFFF7FBFF),
                ],
                stops: const [0.0, 0.68, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignupCard extends StatelessWidget {
  const _SignupCard({
    required this.role,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.confirmCtrl,
    required this.emailFocus,
    required this.passwordFocus,
    required this.confirmFocus,
    required this.emailKey,
    required this.passwordKey,
    required this.confirmKey,
    required this.obscurePassword,
    required this.obscureConfirm,
    required this.loading,
    required this.strength,
    required this.strengthLabel,
    required this.strengthColor,
    required this.passwordErrors,
    required this.onRoleChanged,
    required this.onTogglePassword,
    required this.onToggleConfirm,
    required this.onLogin,
    required this.onSignup,
  });

  final SignupUserRole role;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final TextEditingController confirmCtrl;
  final FocusNode emailFocus;
  final FocusNode passwordFocus;
  final FocusNode confirmFocus;
  final GlobalKey emailKey;
  final GlobalKey passwordKey;
  final GlobalKey confirmKey;
  final bool obscurePassword;
  final bool obscureConfirm;
  final bool loading;
  final PasswordStrength? strength;
  final String strengthLabel;
  final Color strengthColor;
  final List<String> passwordErrors;
  final ValueChanged<SignupUserRole> onRoleChanged;
  final VoidCallback onTogglePassword;
  final VoidCallback onToggleConfirm;
  final VoidCallback onLogin;
  final VoidCallback? onSignup;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withValues(alpha: 0.92)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.08),
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AuthTabs(onLogin: onLogin),
          const SizedBox(height: 20),
          const _InfoBanner(),
          const SizedBox(height: 20),
          const _Label(text: 'Select Your Role'),
          const SizedBox(height: 9),
          _RoleSegment(role: role, onChanged: onRoleChanged),
          const SizedBox(height: 17),
          const _Label(text: 'Email Address'),
          const SizedBox(height: 9),
          KeyedSubtree(
            key: emailKey,
            child: _FancyInputField(
              focusNode: emailFocus,
              controller: emailCtrl,
              hintText: 'you@example.com',
              prefixIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => passwordFocus.requestFocus(),
            ),
          ),
          const SizedBox(height: 15),
          const _Label(text: 'Password'),
          const SizedBox(height: 9),
          KeyedSubtree(
            key: passwordKey,
            child: _FancyInputField(
              focusNode: passwordFocus,
              controller: passwordCtrl,
              hintText: 'Enter your password',
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: obscurePassword,
              textInputAction: TextInputAction.next,
              onSubmitted: (_) => confirmFocus.requestFocus(),
              suffix: IconButton(
                onPressed: onTogglePassword,
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
          ),
          if (strength != null) ...[
            const SizedBox(height: 10),
            _PasswordStrengthRow(
              strength: strength!,
              label: strengthLabel,
              color: strengthColor,
            ),
          ],
          if (passwordErrors.isNotEmpty) ...[
            const SizedBox(height: 10),
            _PasswordRequirements(errors: passwordErrors),
          ],
          const SizedBox(height: 15),
          const _Label(text: 'Confirm Password'),
          const SizedBox(height: 9),
          KeyedSubtree(
            key: confirmKey,
            child: _FancyInputField(
              focusNode: confirmFocus,
              controller: confirmCtrl,
              hintText: 'Confirm your password',
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: obscureConfirm,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                if (!loading && onSignup != null) onSignup!();
              },
              suffix: IconButton(
                onPressed: onToggleConfirm,
                icon: Icon(
                  obscureConfirm
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: _GradientButton(
              text: loading ? 'Sending OTP...' : 'Create Account',
              loading: loading,
              onPressed: onSignup,
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordRequirements extends StatelessWidget {
  const _PasswordRequirements({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    final allRequirements = [
      'At least 8 characters',
      'At least 1 uppercase letter',
      'At least 1 lowercase letter',
      'At least 1 number',
      'At least 1 special character',
    ];

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7F7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFFD6D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: allRequirements.map((req) {
          final met = !errors.contains(req);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2.5),
            child: Row(
              children: [
                Icon(
                  met
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color:
                      met ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    req,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: met
                          ? const Color(0xFF22C55E)
                          : const Color(0xFF64748B),
                    ),
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

class _AuthTabs extends StatelessWidget {
  const _AuthTabs({required this.onLogin});

  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onLogin,
              borderRadius: BorderRadius.circular(17),
              child: SizedBox(
                height: 50,
                child: Center(
                  child: Text(
                    'Log In',
                    style: AppTextStyles.tab(context, selected: false),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 50,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.055),
                    blurRadius: 14,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                'Sign Up',
                style: AppTextStyles.tab(context, selected: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFF6FF), Color(0xFFF0FDF4)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFD6E8FF)),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.verified_user_rounded,
              color: Color(0xFF2A86FF),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Choose your role, verify your email, and complete your TourisTrike profile.',
              style: AppTextStyles.helper(context).copyWith(
                fontSize: 13.2,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF1E3A5F),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleSegment extends StatelessWidget {
  const _RoleSegment({required this.role, required this.onChanged});

  final SignupUserRole role;
  final ValueChanged<SignupUserRole> onChanged;

  @override
  Widget build(BuildContext context) {
    final isTourist = role == SignupUserRole.tourist;

    return Container(
      height: 58,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(22),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final pillWidth = constraints.maxWidth / 2;
          return Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                alignment:
                    isTourist ? Alignment.centerLeft : Alignment.centerRight,
                child: Container(
                  width: pillWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.055),
                        blurRadius: 14,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onChanged(SignupUserRole.tourist),
                      child: _RoleChip(
                        icon: Icons.travel_explore_rounded,
                        label: 'Tourist',
                        selected: isTourist,
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => onChanged(SignupUserRole.driver),
                      child: _RoleChip(
                        icon: Icons.badge_outlined,
                        label: 'Driver',
                        selected: !isTourist,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.icon,
    required this.label,
    required this.selected,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? const Color(0xFF0F172A) : const Color(0xFF64748B);
    return Center(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 19, color: color),
          const SizedBox(width: 8),
          Text(label, style: AppTextStyles.roleChip(context, color: color)),
        ],
      ),
    );
  }
}

class _PasswordStrengthRow extends StatelessWidget {
  const _PasswordStrengthRow({
    required this.strength,
    required this.label,
    required this.color,
  });

  final PasswordStrength strength;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    double fill = 0.25;
    if (strength == PasswordStrength.normal) fill = 0.65;
    if (strength == PasswordStrength.strong) fill = 1.0;

    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Container(
              height: 8,
              color: const Color(0xFFE2E8F0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: fill,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    color: color,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(label, style: AppTextStyles.status(context, color: color)),
      ],
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({
    required this.text,
    required this.onPressed,
    this.loading = false,
  });

  final String text;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: onPressed == null
            ? const LinearGradient(
                colors: [Color(0xFFCBD5E1), Color(0xFF94A3B8)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF5BB2FF),
                  Color(0xFF2A86FF),
                  Color(0xFF1D4ED8),
                ],
              ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A86FF).withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          shadowColor: Colors.transparent,
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(text, style: AppTextStyles.button(context)),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: AppTextStyles.fieldLabel(context).copyWith(
          fontWeight: FontWeight.w900,
          color: const Color(0xFF0F172A),
        ),
      ),
    );
  }
}

class _FancyInputField extends StatefulWidget {
  const _FancyInputField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_FancyInputField> createState() => _FancyInputFieldState();
}

class _FancyInputFieldState extends State<_FancyInputField> {
  final _localFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    (widget.focusNode ?? _localFocus).addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    (widget.focusNode ?? _localFocus).removeListener(_onFocusChanged);
    _localFocus.dispose();
    super.dispose();
  }

  void _onFocusChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final focus = widget.focusNode ?? _localFocus;
    final focused = focus.hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: const Color(0xFF2A86FF).withValues(alpha: 0.13),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : [],
      ),
      child: TextField(
        focusNode: focus,
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        obscureText: widget.obscureText,
        textInputAction: widget.textInputAction,
        onSubmitted: widget.onSubmitted,
        style: AppTextStyles.input(context),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: AppTextStyles.hint(context),
          prefixIcon: Icon(
            widget.prefixIcon,
            color: focused ? const Color(0xFF2A86FF) : const Color(0xFF94A3B8),
          ),
          suffixIcon: widget.suffix,
          filled: true,
          fillColor: focused ? Colors.white : const Color(0xFFF8FAFC),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 19,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFF2A86FF), width: 1.5),
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      ),
    );
  }
}

class _TermsText extends StatelessWidget {
  const _TermsText({required this.context});

  final BuildContext context;

  @override
  Widget build(BuildContext context) {
    return RichText(
      textAlign: TextAlign.center,
      text: TextSpan(
        style: TextStyle(
          fontSize: 12.5,
          height: 1.45,
          color: AppTextStyles.textSecondary.withValues(alpha: 0.95),
          fontWeight: FontWeight.w600,
          fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
        ),
        children: [
          const TextSpan(
            text: 'By creating an account, you agree to TourisTrike\'s ',
          ),
          TextSpan(
            text: 'Terms of Service',
            style: AppTextStyles.link(context).copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: AppTextStyles.link(context).copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}

class _SignupBackdrop extends StatelessWidget {
  const _SignupBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFFF7FBFF),
                Color(0xFFEAF5FF),
                Color(0xFFF8FAFC),
              ],
            ),
          ),
          child: SizedBox.expand(),
        ),
        Positioned(
          top: -90,
          right: -70,
          child: _BlurCircle(
            size: 230,
            color: const Color(0xFF2A86FF).withValues(alpha: 0.09),
          ),
        ),
        Positioned(
          top: 220,
          left: -95,
          child: _BlurCircle(
            size: 190,
            color: const Color(0xFF38BDF8).withValues(alpha: 0.10),
          ),
        ),
        Positioned(
          bottom: -100,
          right: -90,
          child: _BlurCircle(
            size: 230,
            color: const Color(0xFF16A34A).withValues(alpha: 0.08),
          ),
        ),
      ],
    );
  }
}

class _BlurCircle extends StatelessWidget {
  const _BlurCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
