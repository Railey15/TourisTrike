import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'signup_screen.dart';
import 'complete_profile_screen.dart';
import '../tourist/tourist_home_screen.dart';
import '../driver/driver_home_screen.dart';
import '../admin/provincial_admin_dashboard_screen.dart';
import '../subtenant/subtenant_dashboard_screen.dart';
import '../../theme/app_theme.dart';

enum UserRole { tourist, driver, admin, subtenant }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final supabase = Supabase.instance.client;

  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
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
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  UserRole? _parseRole(String? role) {
    switch ((role ?? '').toLowerCase().trim()) {
      case 'tourist':
        return UserRole.tourist;
      case 'driver':
        return UserRole.driver;
      case 'admin':
        return UserRole.admin;
      case 'subtenant':
        return UserRole.subtenant;
      default:
        return null;
    }
  }

  Future<void> _login() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) return;

    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;

    setState(() => _loading = true);

    try {
      final authRes = await supabase.auth
          .signInWithPassword(email: email, password: password)
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException('Login request timed out.');
            },
          );

      final user = authRes.user;

      if (user == null) {
        _showSnack('Login failed. Please try again.');
        return;
      }

      final profile = await supabase
          .from('profiles')
          .select('role, first_name, last_name, full_name')
          .eq('id', user.id)
          .maybeSingle()
          .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException('Profile lookup timed out.');
            },
          );

      if (profile == null) {
        _showSnack('Profile not found. Please complete your profile.');

        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const CompleteProfileScreen()),
        );
        return;
      }

      final role = _parseRole(profile['role'] as String?);

      if (role == null) {
        _showSnack('Invalid role found in your profile. Contact support.');
        return;
      }

      if (!mounted) return;

      switch (role) {
        case UserRole.tourist:
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const TouristHomeScreen()),
          );
          break;
        case UserRole.driver:
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
          );
          break;
        case UserRole.admin:
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => const ProvincialAdminDashboardScreen(),
            ),
          );
          break;
        case UserRole.subtenant:
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const SubTenantDashboardScreen()),
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
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _showSnack('Enter your email first to reset your password.');
      return;
    }

    try {
      await supabase.auth.resetPasswordForEmail(email);
      _showSnack('Password reset email sent successfully.', isError: false);
    } catch (e) {
      _showSnack('Reset failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final headerHeight = (size.height * 0.33).clamp(245.0, 330.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF6FAFF),
      resizeToAvoidBottomInset: true,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Stack(
                  children: [
                    Positioned(
                      top: -90,
                      right: -70,
                      child: _BlurCircle(
                        size: 230,
                        color: const Color(0xFF2A86FF).withValues(alpha: 0.10),
                      ),
                    ),
                    Positioned(
                      top: 210,
                      left: -95,
                      child: _BlurCircle(
                        size: 190,
                        color: const Color(0xFF38BDF8).withValues(alpha: 0.12),
                      ),
                    ),
                    Column(
                      children: [
                        _Header(height: headerHeight),
                        Transform.translate(
                          offset: const Offset(0, -34),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                _LoginCard(
                                  formKey: _formKey,
                                  emailCtrl: _emailCtrl,
                                  passwordCtrl: _passwordCtrl,
                                  obscure: _obscure,
                                  loading: _loading,
                                  onTogglePassword: () {
                                    setState(() => _obscure = !_obscure);
                                  },
                                  onLogin: _loading ? null : _login,
                                  onResetPassword: _loading
                                      ? null
                                      : _resetPassword,
                                  onSignUp: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => const SignupScreen(),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 16),
                                _TermsText(context: context),
                                const SizedBox(height: 24),
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
          Image.asset(
            'assets/images/login_header.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) {
              return Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFFDBF0FF),
                      Color(0xFFBFE3FF),
                      Color(0xFFF6FAFF),
                    ],
                  ),
                ),
              );
            },
          ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.16),
                  Colors.black.withValues(alpha: 0.08),
                  const Color(0xFFF6FAFF),
                ],
                stops: const [0.0, 0.58, 1.0],
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.electric_rickshaw_rounded,
                      color: Color(0xFF2A86FF),
                      size: 32,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Welcome back!',
                    style: TextStyle(
                      fontSize: 34,
                      height: 1.05,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to continue your TourisTrike journey.',
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.35,
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 54),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.formKey,
    required this.emailCtrl,
    required this.passwordCtrl,
    required this.obscure,
    required this.loading,
    required this.onTogglePassword,
    required this.onLogin,
    required this.onResetPassword,
    required this.onSignUp,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController passwordCtrl;
  final bool obscure;
  final bool loading;
  final VoidCallback onTogglePassword;
  final VoidCallback? onLogin;
  final VoidCallback? onResetPassword;
  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: 0.90)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Form(
        key: formKey,
        child: Column(
          children: [
            _AuthTabs(onSignUp: onSignUp),
            const SizedBox(height: 20),
            const _InfoBanner(),
            const SizedBox(height: 18),
            const _Label(text: 'Email Address'),
            const SizedBox(height: 8),
            _FancyInputField(
              controller: emailCtrl,
              hintText: 'you@example.com',
              prefixIcon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (value) {
                final text = (value ?? '').trim();
                if (text.isEmpty) return 'Please enter your email.';
                if (!text.contains('@')) return 'Please enter a valid email.';
                return null;
              },
            ),
            const SizedBox(height: 14),
            const _Label(text: 'Password'),
            const SizedBox(height: 8),
            _FancyInputField(
              controller: passwordCtrl,
              hintText: 'Enter your password',
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: obscure,
              textInputAction: TextInputAction.done,
              validator: (value) {
                if ((value ?? '').isEmpty) {
                  return 'Please enter your password.';
                }
                return null;
              },
              onSubmitted: (_) {
                if (!loading && onLogin != null) onLogin!();
              },
              suffix: IconButton(
                onPressed: onTogglePassword,
                icon: Icon(
                  obscure
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onResetPassword,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  minimumSize: const Size(10, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Forgot Password?',
                  style: AppTextStyles.link(
                    context,
                  ).copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: _GradientButton(
                text: loading ? 'Logging in...' : 'Log In',
                loading: loading,
                onPressed: onLogin,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuthTabs extends StatelessWidget {
  const _AuthTabs({required this.onSignUp});

  final VoidCallback onSignUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                'Log In',
                style: AppTextStyles.tab(context, selected: true),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onSignUp,
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 44,
                child: Center(
                  child: Text(
                    'Sign Up',
                    style: AppTextStyles.tab(context, selected: false),
                  ),
                ),
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD6E8FF)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFF2A86FF),
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Your account opens automatically based on your saved role.',
              style: AppTextStyles.helper(context).copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w700,
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
        borderRadius: BorderRadius.circular(18),
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
            borderRadius: BorderRadius.circular(18),
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
        style: AppTextStyles.fieldLabel(
          context,
        ).copyWith(fontWeight: FontWeight.w800),
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
    this.validator,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  State<_FancyInputField> createState() => _FancyInputFieldState();
}

class _FancyInputFieldState extends State<_FancyInputField> {
  final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: focused
            ? [
                BoxShadow(
                  color: const Color(0xFF2A86FF).withValues(alpha: 0.12),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : [],
      ),
      child: TextFormField(
        focusNode: _focus,
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        obscureText: widget.obscureText,
        validator: widget.validator,
        textInputAction: widget.textInputAction,
        onFieldSubmitted: widget.onSubmitted,
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
          errorMaxLines: 2,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 18,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFF2A86FF), width: 1.5),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.4),
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
          fontSize: 12,
          height: 1.45,
          color: AppTextStyles.textSecondary.withValues(alpha: 0.95),
          fontWeight: FontWeight.w500,
          fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
        ),
        children: [
          const TextSpan(text: 'By logging in, you agree to TourisTrike\'s '),
          TextSpan(
            text: 'Terms of Service',
            style: AppTextStyles.link(context),
          ),
          const TextSpan(text: ' and '),
          TextSpan(text: 'Privacy Policy', style: AppTextStyles.link(context)),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}

class _BlurCircle extends StatelessWidget {
  const _BlurCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );
  }
}
