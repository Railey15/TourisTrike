import 'dart:async';
import 'dart:math' as math;

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/auth/app_role.dart';
import 'package:touristrike/core/auth/app_role_destination.dart';
import 'package:touristrike/screens/administrator/administrator_portal_screen.dart';

import 'login_screen.dart';
import 'web_portal_landing_screen.dart';
import '../tourist/tourist_home_screen.dart';
import '../tourist/tourist_activity_tracking_screen.dart';
import '../driver/driver_home_screen.dart';
import '../main_tenant/layouts/main_tenant_shell.dart';
import '../subtenant/layouts/subtenant_admin_shell.dart';

class TourisTrikeLoadingScreen extends StatefulWidget {
  const TourisTrikeLoadingScreen({super.key});

  @override
  State<TourisTrikeLoadingScreen> createState() =>
      _TourisTrikeLoadingScreenState();
}

class _TourisTrikeLoadingScreenState extends State<TourisTrikeLoadingScreen>
    with TickerProviderStateMixin {
  static const String logoUrl =
      'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/public-assets/Logo.png';

  static const Color _blue = Color(0xFF1557D6);
  static const Color _brightBlue = Color(0xFF168AFB);
  static const Color _deepBlue = Color(0xFF0B2E75);
  static const Color _green = Color(0xFF39A447);
  static const Color _yellow = Color(0xFFFFC107);
  static const Color _ink = Color(0xFF10213F);
  static const Color _muted = Color(0xFF6B7A90);

  int _progress = 0;
  Timer? _timer;
  bool _navigationStarted = false;

  late final AnimationController _introController;
  late final AnimationController _driveController;
  late final AnimationController _pulseController;

  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _contentOpacity;

  final AppLinks _appLinks = AppLinks();

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1050),
    );

    _driveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _logoScale = Tween<double>(
      begin: 0.78,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(
          0.00,
          0.62,
          curve: Curves.easeOutBack,
        ),
      ),
    );

    _logoOpacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(
          0.00,
          0.42,
          curve: Curves.easeOut,
        ),
      ),
    );

    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.18),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(
          0.25,
          0.78,
          curve: Curves.easeOutCubic,
        ),
      ),
    );

    _contentOpacity = Tween<double>(
      begin: 0,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(
          0.45,
          1,
          curve: Curves.easeOut,
        ),
      ),
    );

    _introController.forward();
    _startLoading();
  }

  // ---------------------------------------------------------------------------
  // LOADING
  // ---------------------------------------------------------------------------

  void _startLoading() {
    _timer = Timer.periodic(
      const Duration(milliseconds: 30),
      (timer) {
        if (!mounted) return;

        if (_progress >= 100) {
          timer.cancel();

          if (!_navigationStarted) {
            _navigationStarted = true;
            _onLoadingComplete();
          }

          return;
        }

        setState(() {
          _progress++;
        });
      },
    );
  }

  String get _loadingMessage {
    if (_progress < 20) {
      return kIsWeb
          ? 'Starting secure tourism services...'
          : 'Starting your TourisTrike journey...';
    }

    if (_progress < 45) {
      return kIsWeb
          ? 'Loading tourism destinations...'
          : 'Loading local destinations...';
    }

    if (_progress < 70) {
      return kIsWeb
          ? 'Preparing management tools...'
          : 'Preparing routes and travel services...';
    }

    if (_progress < 92) {
      return kIsWeb
          ? 'Connecting tourism operations...'
          : 'Connecting rides and bookings...';
    }

    return kIsWeb
        ? 'TourisTrike portal is ready.'
        : 'Ready to explore Bulacan.';
  }

  // ---------------------------------------------------------------------------
  // EXISTING NAVIGATION / AUTH LOGIC
  // ---------------------------------------------------------------------------

  Future<void> _onLoadingComplete() async {
    if (!mounted) return;

    if (kIsWeb) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => const WebPortalLandingScreen(),
        ),
      );
      return;
    }

    final session = Supabase.instance.client.auth.currentSession;

    if (session == null) {
      _goToLogin();
      return;
    }

    try {
      final userId = Supabase.instance.client.auth.currentUser!.id;

      final profile = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle()
          .timeout(const Duration(seconds: 10));

      if (!mounted) return;

      if (profile == null) {
        _goToLogin();
        return;
      }

      final role = AppRole.tryParse(profile['role'] as String?);

      Widget destination;

      if (role == null) {
        destination = const LoginScreen();
      } else {
        switch (destinationForRole(role)) {
          case AppRoleDestination.touristApp:
            final bookingId = await _initialPaymentReturnBookingId();

            if (!mounted) return;

            destination = bookingId == null
                ? const TouristHomeScreen()
                : ActivityTrackingScreen(
                    bookingId: bookingId,
                  );
            break;

          case AppRoleDestination.driverApp:
            destination = const DriverHomeScreen();
            break;

          case AppRoleDestination.administratorPortal:
            destination = const AdministratorPortalScreen();
            break;

          case AppRoleDestination.mainTenantPortal:
            destination = const MainTenantPortalScreen();
            break;

          case AppRoleDestination.subtenantPortal:
            destination = const SubTenantPortalScreen();
            break;
        }
      }

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => destination,
        ),
      );
    } catch (error) {
      debugPrint(
        '[TourisTrike] splash profile lookup failed: $error',
      );

      if (!mounted) return;

      _goToLogin();
    }
  }

  Future<String?> _initialPaymentReturnBookingId() async {
    try {
      final uri = await _appLinks.getInitialLink();

      if (uri == null ||
          uri.scheme != 'touristrike' ||
          uri.host != 'wallet' ||
          uri.pathSegments.length < 2 ||
          uri.pathSegments[0] != 'payment') {
        return null;
      }

      final bookingId = uri.queryParameters['booking_id'] ?? '';

      final isUuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(bookingId);

      if (!isUuid) return null;

      debugPrint(
        '[PayMongo] payment return deep link received; '
        'opening booking=$bookingId and refreshing server state',
      );

      return bookingId;
    } catch (error) {
      debugPrint(
        '[PayMongo] initial payment deep link unavailable: $error',
      );

      return null;
    }
  }

  void _goToLogin() {
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();

    _introController.dispose();
    _driveController.dispose();
    _pulseController.dispose();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // MAIN UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;

    final isSmallHeight = size.height < 700;
    final isCompact = size.width < 390;

    return Scaffold(
      backgroundColor: const Color(0xFFF5FAFF),
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0, 0.48, 1],
            colors: [
              Color(0xFFEAF6FF),
              Color(0xFFF9FCFF),
              Color(0xFFEDF9F4),
            ],
          ),
        ),
        child: Stack(
          children: [
            _buildBackgroundDecorations(size),

            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 20 : 28,
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              height: isSmallHeight ? 20 : 34,
                            ),

                            _buildBrandSection(
                              compact: isCompact,
                            ),

                            SizedBox(
                              height: isSmallHeight ? 12 : 22,
                            ),

                            FadeTransition(
                              opacity: _contentOpacity,
                              child: _buildTravelScene(
                                compact: isCompact,
                                smallHeight: isSmallHeight,
                              ),
                            ),

                            SizedBox(
                              height: isSmallHeight ? 14 : 24,
                            ),

                            FadeTransition(
                              opacity: _contentOpacity,
                              child: _buildLoadingSection(
                                compact: isCompact,
                              ),
                            ),

                            SizedBox(
                              height: isSmallHeight ? 18 : 30,
                            ),

                            FadeTransition(
                              opacity: _contentOpacity,
                              child: _buildFooter(),
                            ),

                            SizedBox(
                              height: isSmallHeight ? 16 : 24,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BACKGROUND
  // ---------------------------------------------------------------------------

  Widget _buildBackgroundDecorations(Size size) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -110,
            right: -95,
            child: Container(
              width: 290,
              height: 290,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF5CAEFF).withValues(
                  alpha: 0.13,
                ),
              ),
            ),
          ),

          Positioned(
            top: size.height * 0.34,
            right: -100,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFB9A7FF).withValues(
                  alpha: 0.08,
                ),
              ),
            ),
          ),

          Positioned(
            bottom: -120,
            left: -105,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _green.withValues(
                  alpha: 0.10,
                ),
              ),
            ),
          ),

          Positioned(
            top: size.height * 0.16,
            left: -40,
            child: Container(
              width: 85,
              height: 85,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _yellow.withValues(
                  alpha: 0.05,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BRAND
  // ---------------------------------------------------------------------------

  Widget _buildBrandSection({
    required bool compact,
  }) {
    return Column(
      children: [
        ScaleTransition(
          scale: _logoScale,
          child: FadeTransition(
            opacity: _logoOpacity,
            child: _buildLogo(
              compact: compact,
            ),
          ),
        ),

        const SizedBox(height: 18),

        SlideTransition(
          position: _titleSlide,
          child: FadeTransition(
            opacity: _contentOpacity,
            child: Column(
              children: [
                Text(
                  'TourisTrike',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: compact ? 34 : 38,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                    letterSpacing: -1.1,
                  ),
                ),

                const SizedBox(height: 10),

                _buildPlatformBadge(),

                const SizedBox(height: 13),

                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                  ),
                  child: Text(
                    kIsWeb
                        ? 'One platform for smarter tourism management across Bulacan.'
                        : 'Discover destinations and travel around Bulacan with ease.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: compact ? 12.5 : 13.5,
                      height: 1.45,
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo({
    required bool compact,
  }) {
    final size = compact ? 102.0 : 112.0;

    return AnimatedBuilder(
      animation: _pulseController,
      builder: (context, child) {
        final floatOffset =
            math.sin(_pulseController.value * math.pi) * 3;

        return Transform.translate(
          offset: Offset(
            0,
            -floatOffset,
          ),
          child: child,
        );
      },
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(
          compact ? 12 : 13,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(
            alpha: 0.96,
          ),
          borderRadius: BorderRadius.circular(
            compact ? 29 : 32,
          ),
          border: Border.all(
            color: Colors.white,
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: _blue.withValues(
                alpha: 0.13,
              ),
              blurRadius: 32,
              spreadRadius: 1,
              offset: const Offset(
                0,
                15,
              ),
            ),
            BoxShadow(
              color: Colors.black.withValues(
                alpha: 0.025,
              ),
              blurRadius: 8,
              offset: const Offset(
                0,
                3,
              ),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: Image.network(
            logoUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) {
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFEDF5FF),
                  borderRadius: BorderRadius.circular(20),
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.electric_rickshaw_rounded,
                  size: 48,
                  color: _blue,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPlatformBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(
          alpha: 0.9,
        ),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: const Color(0xFFDCE9F6),
        ),
        boxShadow: [
          BoxShadow(
            color: _deepBlue.withValues(
              alpha: 0.04,
            ),
            blurRadius: 12,
            offset: const Offset(
              0,
              5,
            ),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.explore_rounded,
            size: 16,
            color: _brightBlue,
          ),

          const SizedBox(width: 7),

          Text(
            kIsWeb
                ? 'Tourism Management Platform'
                : 'Tourist Mobility Platform',
            style: const TextStyle(
              fontSize: 11.5,
              color: Color(0xFF506078),
              fontWeight: FontWeight.w800,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ANIMATED TOURISM SCENE
  // ---------------------------------------------------------------------------

  Widget _buildTravelScene({
    required bool compact,
    required bool smallHeight,
  }) {
    final height = smallHeight ? 145.0 : 170.0;

    return SizedBox(
      height: height,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          return AnimatedBuilder(
            animation: _driveController,
            builder: (context, _) {
              final value = _driveController.value;

              // Tricycle travels slightly beyond both sides so
              // the animation loops naturally.
              final trikeX =
                  -70 + ((width + 140) * value);

              final bounce =
                  math.sin(value * math.pi * 8) * 1.8;

              // Background elements move slower for parallax.
              final sceneryOffset =
                  (value * width * 0.16);

              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // -----------------------------------------------------------
                  // SKY
                  // -----------------------------------------------------------

                  Positioned(
                    top: 14,
                    left: 24 - sceneryOffset,
                    child: _buildCloud(
                      scale: 0.82,
                    ),
                  ),

                  Positioned(
                    top: 4,
                    right: 30 + sceneryOffset,
                    child: _buildCloud(
                      scale: 0.58,
                    ),
                  ),

                  // -----------------------------------------------------------
                  // DESTINATION PIN
                  // -----------------------------------------------------------

                  Positioned(
                    top: 14,
                    right: compact ? 18 : 30,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        final scale =
                            1 +
                            (_pulseController.value * 0.06);

                        return Transform.scale(
                          scale: scale,
                          child: child,
                        );
                      },
                      child: _buildDestinationPin(),
                    ),
                  ),

                  // -----------------------------------------------------------
                  // LANDMARKS
                  // -----------------------------------------------------------

                  Positioned(
                    bottom: 39,
                    left: 12 - sceneryOffset,
                    child: _buildTree(
                      size: 36,
                    ),
                  ),

                  Positioned(
                    bottom: 39,
                    left: width * 0.29 - sceneryOffset,
                    child: _buildLandmark(),
                  ),

                  Positioned(
                    bottom: 39,
                    right: 8 + sceneryOffset,
                    child: _buildTree(
                      size: 42,
                    ),
                  ),

                  Positioned(
                    bottom: 39,
                    right: width * 0.26 + sceneryOffset,
                    child: _buildSmallBuilding(),
                  ),

                  // -----------------------------------------------------------
                  // ROAD
                  // -----------------------------------------------------------

                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 24,
                    child: _buildRoad(),
                  ),

                  // -----------------------------------------------------------
                  // MOVING TRICYCLE
                  // -----------------------------------------------------------

                  Positioned(
                    left: trikeX,
                    bottom: 31 + bounce,
                    child: _buildTricycle(),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildCloud({
    required double scale,
  }) {
    return Transform.scale(
      scale: scale,
      child: Row(
        children: [
          Container(
            width: 29,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.white.withValues(
                alpha: 0.72,
              ),
              borderRadius: BorderRadius.circular(50),
            ),
          ),
          Transform.translate(
            offset: const Offset(-11, -6),
            child: Container(
              width: 23,
              height: 23,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: 0.78,
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(-20, 0),
            child: Container(
              width: 27,
              height: 15,
              decoration: BoxDecoration(
                color: Colors.white.withValues(
                  alpha: 0.72,
                ),
                borderRadius: BorderRadius.circular(50),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationPin() {
    return Column(
      children: [
        Container(
          width: 43,
          height: 43,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(
              color: const Color(0xFFDCEAF7),
            ),
            boxShadow: [
              BoxShadow(
                color: _blue.withValues(
                  alpha: 0.12,
                ),
                blurRadius: 18,
                offset: const Offset(
                  0,
                  7,
                ),
              ),
            ],
          ),
          child: const Icon(
            Icons.location_on_rounded,
            color: _green,
            size: 24,
          ),
        ),

        Container(
          width: 2,
          height: 17,
          color: _green.withValues(
            alpha: 0.32,
          ),
        ),
      ],
    );
  }

  Widget _buildTree({
    required double size,
  }) {
    return SizedBox(
      width: size,
      height: size + 18,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            width: 5,
            height: 21,
            decoration: BoxDecoration(
              color: const Color(0xFF9A7248),
              borderRadius: BorderRadius.circular(5),
            ),
          ),

          Positioned(
            top: 0,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: _green.withValues(
                  alpha: 0.82,
                ),
                shape: BoxShape.circle,
              ),
            ),
          ),

          Positioned(
            top: size * 0.17,
            right: 1,
            child: Container(
              width: size * 0.55,
              height: size * 0.55,
              decoration: BoxDecoration(
                color: const Color(0xFF69BE72),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLandmark() {
    return Container(
      width: 44,
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white.withValues(
          alpha: 0.82,
        ),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(14),
        ),
        border: Border.all(
          color: const Color(0xFFDCE7F2),
        ),
      ),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.account_balance_rounded,
            size: 22,
            color: _blue,
          ),
          SizedBox(height: 2),
        ],
      ),
    );
  }

  Widget _buildSmallBuilding() {
    return Container(
      width: 42,
      height: 43,
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8DC),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(8),
        ),
        border: Border.all(
          color: _yellow.withValues(
            alpha: 0.25,
          ),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 18,
            height: 5,
            decoration: BoxDecoration(
              color: _yellow,
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          const SizedBox(height: 5),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _window(),
              _window(),
            ],
          ),

          const SizedBox(height: 4),

          Container(
            width: 8,
            height: 11,
            decoration: BoxDecoration(
              color: _deepBlue.withValues(
                alpha: 0.72,
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _window() {
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: const Color(0xFF9FD4FF),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildRoad() {
    return Column(
      children: [
        Container(
          width: double.infinity,
          height: 3,
          decoration: BoxDecoration(
            color: const Color(0xFF96A6B7).withValues(
              alpha: 0.30,
            ),
            borderRadius: BorderRadius.circular(30),
          ),
        ),

        const SizedBox(height: 5),

        Row(
          children: List.generate(
            7,
            (index) => Expanded(
              child: Container(
                height: 2,
                margin: const EdgeInsets.symmetric(
                  horizontal: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFBCC8D4).withValues(
                    alpha: index.isEven ? 0.55 : 0,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTricycle() {
    return Container(
      width: 72,
      height: 54,
      alignment: Alignment.center,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // subtle shadow
          Positioned(
            left: 9,
            right: 8,
            bottom: 4,
            child: Container(
              height: 7,
              decoration: BoxDecoration(
                color: Colors.black.withValues(
                  alpha: 0.09,
                ),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),

          Positioned(
            left: 1,
            top: 0,
            child: Container(
              width: 63,
              height: 43,
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: const Color(0xFFD8E8F6),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _blue.withValues(
                      alpha: 0.10,
                    ),
                    blurRadius: 12,
                    offset: const Offset(
                      0,
                      6,
                    ),
                  ),
                ],
              ),
              child: const Icon(
                Icons.electric_rickshaw_rounded,
                size: 34,
                color: _blue,
              ),
            ),
          ),

          Positioned(
            left: 10,
            bottom: 0,
            child: _buildWheel(),
          ),

          Positioned(
            right: 9,
            bottom: 0,
            child: _buildWheel(),
          ),

          Positioned(
            top: 3,
            right: 0,
            child: Container(
              width: 11,
              height: 11,
              decoration: const BoxDecoration(
                color: _yellow,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWheel() {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: _deepBlue,
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 2,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LOADING SECTION
  // ---------------------------------------------------------------------------

  Widget _buildLoadingSection({
    required bool compact,
  }) {
    return Column(
      children: [
        Row(
          children: [
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                return Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _brightBlue.withValues(
                      alpha:
                          0.08 +
                          (_pulseController.value * 0.05),
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: child,
                );
              },
              child: const Icon(
                Icons.route_rounded,
                size: 18,
                color: _brightBlue,
              ),
            ),

            const SizedBox(width: 11),

            Expanded(
              child: Text(
                kIsWeb
                    ? 'PREPARING TOURISM PORTAL'
                    : 'PREPARING YOUR JOURNEY',
                style: TextStyle(
                  fontSize: compact ? 11 : 11.5,
                  letterSpacing: 1.15,
                  color: _ink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),

            AnimatedSwitcher(
              duration: const Duration(
                milliseconds: 200,
              ),
              child: Text(
                '$_progress%',
                key: ValueKey(_progress),
                style: const TextStyle(
                  fontSize: 14,
                  color: _brightBlue,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        _buildProgressBar(),

        const SizedBox(height: 11),

        AnimatedSwitcher(
          duration: const Duration(
            milliseconds: 260,
          ),
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(
                    0,
                    0.15,
                  ),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Row(
            key: ValueKey(_loadingMessage),
            children: [
              Icon(
                _progress >= 92
                    ? Icons.check_circle_rounded
                    : Icons.circle,
                size: _progress >= 92 ? 15 : 8,
                color: _green,
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  _loadingMessage,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProgressBar() {
    final value = _progress / 100;

    return Container(
      width: double.infinity,
      height: 7,
      decoration: BoxDecoration(
        color: const Color(0xFFDCE7F1),
        borderRadius: BorderRadius.circular(100),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Positioned.fill(
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value.clamp(
                0.0,
                1.0,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(100),
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF32A4FF),
                      _brightBlue,
                      _blue,
                    ],
                  ),
                ),
              ),
            ),
          ),

          if (_progress < 100)
            AnimatedBuilder(
              animation: _driveController,
              builder: (context, _) {
                return FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: value.clamp(
                    0.0,
                    1.0,
                  ),
                  child: Align(
                    alignment: Alignment(
                      (_driveController.value * 2) - 1,
                      0,
                    ),
                    child: Container(
                      width: 38,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(
                              alpha: 0,
                            ),
                            Colors.white.withValues(
                              alpha: 0.30,
                            ),
                            Colors.white.withValues(
                              alpha: 0,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // FOOTER
  // ---------------------------------------------------------------------------

  Widget _buildFooter() {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 1.5,
              decoration: BoxDecoration(
                color: const Color(0xFFCAD8E5),
                borderRadius: BorderRadius.circular(10),
              ),
            ),

            const SizedBox(width: 8),

            const Text(
              'Powered by TourisTrike',
              style: TextStyle(
                fontSize: 10.5,
                color: Color(0xFF91A1B5),
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(width: 8),

            Container(
              width: 24,
              height: 1.5,
              decoration: BoxDecoration(
                color: const Color(0xFFCAD8E5),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ],
        ),

        const SizedBox(height: 7),

        Text(
          kIsWeb
              ? 'Bulacan Tourism Management'
              : 'Explore • Ride • Discover',
          style: TextStyle(
            fontSize: 9.5,
            color: _muted.withValues(
              alpha: 0.72,
            ),
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}