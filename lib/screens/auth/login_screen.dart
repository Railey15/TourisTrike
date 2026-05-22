import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/driver/profile/driver_profile_completion_screen.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';

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

  static const String welcomeImageUrl =
      'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/public-assets/welcome.png';

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
          final bundle = await DriverProfileService().fetchProfileBundle(
            user.id,
          );
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => bundle.isFullyComplete
                  ? const DriverHomeScreen()
                  : const DriverProfileCompletionScreen(finishToHome: true),
            ),
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
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resetPassword() async {
    final emailInField = _emailCtrl.text.trim();
    final emailCtrl = TextEditingController(text: emailInField);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _ForgotPasswordDialog(controller: emailCtrl),
    );

    if (confirmed != true || !mounted) return;

    final email = emailCtrl.text.trim();
    emailCtrl.dispose();

    if (email.isEmpty || !email.contains('@')) {
      _showSnack('Please enter a valid email address.');
      return;
    }

    try {
      await supabase.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      _showSnack(
        'Password reset email sent to $email. Check your inbox.',
        isError: false,
      );
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (e) {
      _showSnack('Reset failed: $e');
    }
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
            final headerHeight = (height * 0.45).clamp(330.0, 430.0);

            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(bottom: bottomInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: height),
                child: Stack(
                  children: [
                    const Positioned.fill(child: _LoginBackdrop()),
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
            _LoginScreenState.welcomeImageUrl,
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
      child: Form(
        key: formKey,
        child: Column(
          children: [
            _AuthTabs(onSignUp: onSignUp),
            const SizedBox(height: 20),
            const _Label(text: 'Email Address'),
            const SizedBox(height: 9),
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
            const SizedBox(height: 15),
            const _Label(text: 'Password'),
            const SizedBox(height: 9),
            _FancyInputField(
              controller: passwordCtrl,
              hintText: 'Enter your password',
              prefixIcon: Icons.lock_outline_rounded,
              obscureText: obscure,
              textInputAction: TextInputAction.done,
              validator: (value) {
                if ((value ?? '').isEmpty) return 'Please enter your password.';
                return null;
              },
              onSubmitted: (_) {
                if (!loading && onLogin != null) onLogin!();
              },
              suffix: IconButton(
                onPressed: onTogglePassword,
                icon: Icon(
                  obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: const Color(0xFF94A3B8),
                ),
              ),
            ),
            const SizedBox(height: 7),
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
                  ).copyWith(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 58,
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
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
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
                'Log In',
                style: AppTextStyles.tab(context, selected: true),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onSignUp,
              borderRadius: BorderRadius.circular(17),
              child: SizedBox(
                height: 50,
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
        style: AppTextStyles.fieldLabel(
          context,
        ).copyWith(fontWeight: FontWeight.w900, color: const Color(0xFF0F172A)),
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
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.2),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
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
          fontSize: 12.5,
          height: 1.45,
          color: AppTextStyles.textSecondary.withValues(alpha: 0.95),
          fontWeight: FontWeight.w600,
          fontFamily: Theme.of(context).textTheme.bodySmall?.fontFamily,
        ),
        children: [
          const TextSpan(text: 'By logging in, you agree to TourisTrike\'s '),
          TextSpan(
            text: 'Terms of Service',
            style: AppTextStyles.link(
              context,
            ).copyWith(fontWeight: FontWeight.w900),
          ),
          const TextSpan(text: ' and '),
          TextSpan(
            text: 'Privacy Policy',
            style: AppTextStyles.link(
              context,
            ).copyWith(fontWeight: FontWeight.w900),
          ),
          const TextSpan(text: '.'),
        ],
      ),
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF7FBFF), Color(0xFFEAF5FF), Color(0xFFF8FAFC)],
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

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.controller});

  final TextEditingController controller;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.lock_reset_rounded,
              color: Color(0xFF2A86FF),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Reset Password',
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Enter the email address linked to your account. We\'ll send you a password reset link.',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF64748B),
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: widget.controller,
            focusNode: _focus,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => Navigator.pop(context, true),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              hintText: 'you@example.com',
              hintStyle: const TextStyle(
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
              prefixIcon: const Icon(
                Icons.mail_outline_rounded,
                color: Color(0xFF2A86FF),
              ),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(
                  color: Color(0xFF2A86FF),
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text(
            'Cancel',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
            ),
          ),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF2A86FF),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: const Text(
            'Send Reset Link',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}


