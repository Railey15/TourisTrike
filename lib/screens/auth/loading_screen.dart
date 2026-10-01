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
  // ===========================================================================
  // BRAND
  // ===========================================================================

  static const String logoUrl =
      'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/public-assets/logo_wobg.png';

  static const Color _blue = Color(0xFF1557D6);
  static const Color _brightBlue = Color(0xFF2A82F2);
  static const Color _deepBlue = Color(0xFF0B2E75);

  static const Color _green = Color(0xFF39A447);
  static const Color _darkGreen = Color(0xFF16855B);
  static const Color _lightGreen = Color(0xFF79CC75);

  static const Color _yellow = Color(0xFFFFC431);
  static const Color _orange = Color(0xFFFFA43B);

  static const Color _ink = Color(0xFF10213F);
  static const Color _muted = Color(0xFF708097);

  // ===========================================================================
  // STATE
  // ===========================================================================

  int _progress = 0;

  Timer? _timer;

  bool _navigationStarted = false;

  final AppLinks _appLinks = AppLinks();

  // ===========================================================================
  // ANIMATION
  // ===========================================================================

  late final AnimationController _introController;
  late final AnimationController _ambientController;
  late final AnimationController _vehicleController;
  late final AnimationController _pulseController;

  late final Animation<double> _brandOpacity;
  late final Animation<double> _brandScale;
  late final Animation<Offset> _brandSlide;
  late final Animation<double> _sceneOpacity;

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _ambientController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8000),
    )..repeat();

    _vehicleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _brandOpacity = CurvedAnimation(
      parent: _introController,
      curve: const Interval(
        0.0,
        0.50,
        curve: Curves.easeOut,
      ),
    );

    _brandScale = Tween<double>(
      begin: 0.82,
      end: 1,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(
          0,
          0.65,
          curve: Curves.easeOutBack,
        ),
      ),
    );

    _brandSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _introController,
        curve: const Interval(
          0.18,
          0.72,
          curve: Curves.easeOutCubic,
        ),
      ),
    );

    _sceneOpacity = CurvedAnimation(
      parent: _introController,
      curve: const Interval(
        0.32,
        1,
        curve: Curves.easeOut,
      ),
    );

    _introController.forward();

    _startLoading();
  }

  // ===========================================================================
  // LOADING
  // ===========================================================================

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
    if (_progress < 18) {
      return kIsWeb
          ? 'Starting your tourism portal...'
          : 'Getting your journey ready...';
    }

    if (_progress < 38) {
      return kIsWeb
          ? 'Preparing tourism services...'
          : 'Discovering places around Bulacan...';
    }

    if (_progress < 58) {
      return kIsWeb
          ? 'Connecting tourism offices...'
          : 'Mapping your adventure...';
    }

    if (_progress < 78) {
      return kIsWeb
          ? 'Organizing tourism operations...'
          : 'Preparing tours and rides...';
    }

    if (_progress < 94) {
      return kIsWeb
          ? 'Your workspace is almost ready...'
          : 'Almost ready to explore...';
    }

    return kIsWeb
        ? 'Welcome to TourisTrike!'
        : 'Your journey is ready!';
  }

  String get _loadingCaption {
    if (_progress < 25) {
      return kIsWeb
          ? 'Setting up your secure workspace'
          : 'A new adventure is about to begin';
    }

    if (_progress < 50) {
      return kIsWeb
          ? 'Bringing tourism services together'
          : 'Finding the best route for your journey';
    }

    if (_progress < 75) {
      return kIsWeb
          ? 'Coordinating local tourism services'
          : 'Connecting destinations and experiences';
    }

    if (_progress < 94) {
      return kIsWeb
          ? 'Just a little more preparation'
          : 'Only a few more stops to go';
    }

    return kIsWeb
        ? 'Everything is ready'
        : 'Explore • Ride • Discover';
  }

  // ===========================================================================
  // EXISTING NAVIGATION / AUTH
  // ===========================================================================

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
          .timeout(
            const Duration(seconds: 10),
          );

      if (!mounted) return;

      if (profile == null) {
        _goToLogin();
        return;
      }

      final role = AppRole.tryParse(
        profile['role'] as String?,
      );

      Widget destination;

      if (role == null) {
        destination = const LoginScreen();
      } else {
        switch (destinationForRole(role)) {
          case AppRoleDestination.touristApp:
            final bookingId =
                await _initialPaymentReturnBookingId();

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
            destination =
                const AdministratorPortalScreen();
            break;

          case AppRoleDestination.mainTenantPortal:
            destination =
                const MainTenantPortalScreen();
            break;

          case AppRoleDestination.subtenantPortal:
            destination =
                const SubTenantPortalScreen();
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

      final bookingId =
          uri.queryParameters['booking_id'] ?? '';

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
    _ambientController.dispose();
    _vehicleController.dispose();
    _pulseController.dispose();

    super.dispose();
  }

  // ===========================================================================
  // SCREEN
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FCFF),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          final desktop = width >= 900;
          final compact = width < 390;
          final short = height < 720;

          return Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(
                  painter: _TourisTrikeBackgroundPainter(),
                ),
              ),

              Positioned.fill(
                child: _AmbientDecorations(
                  controller: _ambientController,
                ),
              ),

              SafeArea(
                child: Center(
                  child: SizedBox(
                    width: double.infinity,
                    height: double.infinity,
                    child: desktop
                        ? _buildDesktopLayout(
                            width: width,
                            height: height,
                            short: short,
                          )
                        : _buildMobileLayout(
                            compact: compact,
                            short: short,
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

  // ===========================================================================
  // DESKTOP
  // ===========================================================================

  Widget _buildDesktopLayout({
    required double width,
    required double height,
    required bool short,
  }) {
    final maxContentWidth =
        math.min(width * 0.76, 1180.0);

    return Center(
      child: SizedBox(
        width: maxContentWidth,
        height: math.min(
          height - 40,
          790,
        ),
        child: Column(
          children: [
            SizedBox(
              height: short ? 12 : 24,
            ),

            _buildBrand(
              logoSize: short ? 108 : 128,
              titleSize: short ? 31 : 36,
            ),

            const Spacer(),

            FadeTransition(
              opacity: _sceneOpacity,
              child: SizedBox(
                width: math.min(
                  maxContentWidth,
                  900,
                ),
                height: short ? 275 : 330,
                child: _buildJourneyScene(
                  desktop: true,
                ),
              ),
            ),

            SizedBox(
              height: short ? 6 : 12,
            ),

            FadeTransition(
              opacity: _sceneOpacity,
              child: _buildLoadingInformation(
                desktop: true,
              ),
            ),

            const Spacer(),

            FadeTransition(
              opacity: _sceneOpacity,
              child: _buildFooter(),
            ),

            SizedBox(
              height: short ? 8 : 18,
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // MOBILE
  // ===========================================================================

  Widget _buildMobileLayout({
    required bool compact,
    required bool short,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 24,
      ),
      child: Column(
        children: [
          SizedBox(
            height: short ? 12 : 26,
          ),

          _buildBrand(
            logoSize: short
                ? 82
                : compact
                    ? 94
                    : 106,
            titleSize: compact ? 29 : 32,
          ),

          const Spacer(),

          FadeTransition(
            opacity: _sceneOpacity,
            child: SizedBox(
              width: double.infinity,
              height: short ? 215 : 255,
              child: _buildJourneyScene(
                desktop: false,
              ),
            ),
          ),

          SizedBox(
            height: short ? 6 : 14,
          ),

          FadeTransition(
            opacity: _sceneOpacity,
            child: _buildLoadingInformation(
              desktop: false,
            ),
          ),

          const Spacer(),

          FadeTransition(
            opacity: _sceneOpacity,
            child: _buildFooter(),
          ),

          SizedBox(
            height: short ? 10 : 20,
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // BRAND
  // ===========================================================================

  Widget _buildBrand({
    required double logoSize,
    required double titleSize,
  }) {
    return SlideTransition(
      position: _brandSlide,
      child: FadeTransition(
        opacity: _brandOpacity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: _brandScale,
              child: AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  final floating =
                      math.sin(
                            _pulseController.value *
                                math.pi,
                          ) *
                          2.5;

                  return Transform.translate(
                    offset: Offset(
                      0,
                      -floating,
                    ),
                    child: child,
                  );
                },

                // IMPORTANT:
                // No Container.
                // No white background.
                // No card.
                // No border.
                // No clipping.
                child: Image.network(
                  logoUrl,
                  width: logoSize,
                  height: logoSize,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                  errorBuilder: (
                    context,
                    error,
                    stackTrace,
                  ) {
                    return SizedBox(
                      width: logoSize,
                      height: logoSize,
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 4),

            Text(
              'TourisTrike',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ink,
                fontSize: titleSize,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -1.35,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              kIsWeb
                  ? 'Bulacan Tourism Administration'
                  : 'EXPLORE  •  RIDE  •  DISCOVER',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _muted,
                fontSize: kIsWeb ? 11.5 : 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing:
                    kIsWeb ? 0.25 : 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // JOURNEY SCENE
  // ===========================================================================

  Widget _buildJourneyScene({
    required bool desktop,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return AnimatedBuilder(
          animation: Listenable.merge([
            _ambientController,
            _vehicleController,
            _pulseController,
          ]),
          builder: (context, _) {
            final width = constraints.maxWidth;
            final height = constraints.maxHeight;

            final progress =
                (_progress / 100).clamp(0.0, 1.0);

            final startX =
                desktop ? width * 0.10 : width * 0.08;

            final endX =
                desktop ? width * 0.89 : width * 0.91;

            final roadY =
                desktop ? height * 0.72 : height * 0.73;

            final trikeWidth =
                desktop ? 86.0 : 66.0;

            final usableDistance =
                endX - startX - trikeWidth;

            final vehicleX =
                startX +
                usableDistance * progress;

            final vehicleBounce =
                math.sin(
                      _vehicleController.value *
                          math.pi *
                          2,
                    ) *
                    2.2;

            return Stack(
              clipBehavior: Clip.none,
              children: [
                // -------------------------------------------------------------
                // SKY ELEMENTS
                // -------------------------------------------------------------

                Positioned(
                  top: desktop ? 10 : 4,
                  right: desktop
                      ? width * 0.12
                      : width * 0.06,
                  child: _SunIllustration(
                    pulse: _pulseController.value,
                    large: desktop,
                  ),
                ),

                Positioned(
                  top: desktop ? 28 : 20,
                  left: width * 0.08,
                  child: _CloudIllustration(
                    width: desktop ? 92 : 62,
                    offset:
                        math.sin(
                              _ambientController.value *
                                  math.pi *
                                  2,
                            ) *
                            8,
                  ),
                ),

                Positioned(
                  top: desktop ? 75 : 62,
                  right: width * 0.30,
                  child: _CloudIllustration(
                    width: desktop ? 61 : 44,
                    offset:
                        -math.sin(
                              _ambientController.value *
                                  math.pi *
                                  2,
                            ) *
                            5,
                  ),
                ),

                Positioned(
                  top: desktop ? 70 : 55,
                  left: width * 0.42,
                  child: CustomPaint(
                    size: Size(
                      desktop ? 58 : 42,
                      desktop ? 24 : 18,
                    ),
                    painter: const _BirdPainter(),
                  ),
                ),

                // -------------------------------------------------------------
                // LANDMARK
                // -------------------------------------------------------------

                Positioned(
                  left: width * 0.46 -
                      (desktop ? 45 : 32),
                  bottom: height - roadY + 5,
                  child: _BulacanLandmark(
                    width: desktop ? 90 : 64,
                  ),
                ),

                // -------------------------------------------------------------
                // TREES / NATURE
                // -------------------------------------------------------------

                Positioned(
                  left: startX - 18,
                  bottom: height - roadY + 1,
                  child: _TreeIllustration(
                    size: desktop ? 67 : 50,
                  ),
                ),

                Positioned(
                  left: width * 0.26,
                  bottom: height - roadY + 1,
                  child: _BushIllustration(
                    width: desktop ? 63 : 46,
                  ),
                ),

                Positioned(
                  right: width * 0.25,
                  bottom: height - roadY + 1,
                  child: _BushIllustration(
                    width: desktop ? 67 : 48,
                  ),
                ),

                Positioned(
                  right: width - endX - 25,
                  bottom: height - roadY + 1,
                  child: _TreeIllustration(
                    size: desktop ? 72 : 53,
                  ),
                ),

                // -------------------------------------------------------------
                // ROAD
                // -------------------------------------------------------------

                Positioned(
                  left: startX,
                  right: width - endX,
                  top: roadY,
                  child: _JourneyRoad(
                    progress: progress,
                    desktop: desktop,
                  ),
                ),

                // -------------------------------------------------------------
                // CHECKPOINT 1
                // -------------------------------------------------------------

                Positioned(
                  left: startX - 13,
                  top: roadY - 13,
                  child: _CheckpointMarker(
                    completed: true,
                    active: progress < 0.34,
                    size: desktop ? 34 : 28,
                    type: _CheckpointType.start,
                  ),
                ),

                // -------------------------------------------------------------
                // CHECKPOINT 2
                // -------------------------------------------------------------

                Positioned(
                  left: width * 0.49 -
                      (desktop ? 17 : 14),
                  top: roadY - (desktop ? 17 : 14),
                  child: _CheckpointMarker(
                    completed: progress >= 0.50,
                    active:
                        progress >= 0.34 &&
                        progress < 0.72,
                    size: desktop ? 34 : 28,
                    type: _CheckpointType.landmark,
                  ),
                ),

                // -------------------------------------------------------------
                // DESTINATION MARKER
                // -------------------------------------------------------------

                Positioned(
                  left: endX - (desktop ? 22 : 18),
                  top: roadY -
                      (desktop ? 82 : 67),
                  child: _DestinationMarker(
                    reached: progress >= 0.94,
                    pulse: _pulseController.value,
                    desktop: desktop,
                  ),
                ),

                // -------------------------------------------------------------
                // MOVING TRICYCLE
                // -------------------------------------------------------------

                Positioned(
                  left: vehicleX,
                  top: roadY -
                      (desktop ? 63 : 49) +
                      vehicleBounce,
                  child: _CartoonTricycle(
                    controller:
                        _vehicleController,
                    desktop: desktop,
                  ),
                ),

                // -------------------------------------------------------------
                // LABELS
                // -------------------------------------------------------------

                Positioned(
                  left: startX - 16,
                  top: roadY +
                      (desktop ? 35 : 28),
                  child: const _JourneyLabel(
                    text: 'START',
                  ),
                ),

                Positioned(
                  left: width * 0.49 - 27,
                  top: roadY +
                      (desktop ? 35 : 28),
                  child: const _JourneyLabel(
                    text: 'EXPLORE',
                  ),
                ),

                Positioned(
                  right: width - endX - 30,
                  top: roadY +
                      (desktop ? 35 : 28),
                  child: _JourneyLabel(
                    text: progress >= 0.94
                        ? 'READY!'
                        : 'DESTINATION',
                    highlighted:
                        progress >= 0.94,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ===========================================================================
  // LOADING INFORMATION
  // ===========================================================================

  Widget _buildLoadingInformation({
    required bool desktop,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(
            milliseconds: 180,
          ),
          child: Text(
            '$_progress%',
            key: ValueKey(_progress),
            style: TextStyle(
              color: _blue,
              fontSize: desktop ? 42 : 33,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -1.6,
            ),
          ),
        ),

        SizedBox(
          height: desktop ? 9 : 7,
        ),

        AnimatedSwitcher(
          duration: const Duration(
            milliseconds: 280,
          ),
          transitionBuilder: (
            child,
            animation,
          ) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(
                    0,
                    0.12,
                  ),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: Text(
            _loadingMessage,
            key: ValueKey(
              _loadingMessage,
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _ink,
              fontSize: desktop ? 16 : 14,
              height: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),

        const SizedBox(height: 5),

        AnimatedSwitcher(
          duration: const Duration(
            milliseconds: 280,
          ),
          child: Text(
            _loadingCaption,
            key: ValueKey(
              _loadingCaption,
            ),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _muted,
              fontSize: desktop ? 11.5 : 10.5,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        SizedBox(
          height: desktop ? 14 : 11,
        ),

        _LoadingDots(
          controller:
              _vehicleController,
        ),
      ],
    );
  }

  // ===========================================================================
  // FOOTER
  // ===========================================================================

  Widget _buildFooter() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            color: _green,
            shape: BoxShape.circle,
          ),
        ),

        const SizedBox(width: 7),

        Text(
          kIsWeb
              ? 'Connecting Bulacan tourism'
              : 'See more of Bulacan',
          style: TextStyle(
            color: _muted.withValues(
              alpha: 0.78,
            ),
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.15,
          ),
        ),
      ],
    );
  }
}

// =============================================================================
// ROAD
// =============================================================================

class _JourneyRoad extends StatelessWidget {
  const _JourneyRoad({
    required this.progress,
    required this.desktop,
  });

  final double progress;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final height =
        desktop ? 14.0 : 11.0;

    return SizedBox(
      height: height,
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final fullWidth =
              constraints.maxWidth;

          return Stack(
            alignment: Alignment.centerLeft,
            children: [
              Container(
                width: fullWidth,
                height:
                    desktop ? 7 : 6,
                decoration: BoxDecoration(
                  color:
                      const Color(
                        0xFFD9E4EC,
                      ),
                  borderRadius:
                      BorderRadius.circular(
                        100,
                      ),
                ),
              ),

              AnimatedContainer(
                duration: const Duration(
                  milliseconds: 150,
                ),
                curve: Curves.easeOut,
                width:
                    fullWidth * progress,
                height:
                    desktop ? 7 : 6,
                decoration: BoxDecoration(
                  gradient:
                      const LinearGradient(
                    colors: [
                      Color(
                        0xFF39A447,
                      ),
                      Color(
                        0xFF168E78,
                      ),
                      Color(
                        0xFF1557D6,
                      ),
                    ],
                  ),
                  borderRadius:
                      BorderRadius.circular(
                        100,
                      ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(
                            0xFF1557D6,
                          ).withValues(
                            alpha: 0.14,
                          ),
                      blurRadius: 9,
                    ),
                  ],
                ),
              ),

              Positioned.fill(
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment
                          .spaceEvenly,
                  children:
                      List.generate(
                    desktop ? 16 : 11,
                    (index) {
                      return Container(
                        width:
                            desktop ? 9 : 6,
                        height: 2,
                        decoration:
                            BoxDecoration(
                          color: Colors
                              .white
                              .withValues(
                            alpha: 0.85,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            20,
                          ),
                        ),
                      );
                    },
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

// =============================================================================
// TRICYCLE
// =============================================================================

class _CartoonTricycle
    extends StatelessWidget {
  const _CartoonTricycle({
    required this.controller,
    required this.desktop,
  });

  final AnimationController controller;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final width =
        desktop ? 86.0 : 66.0;

    final height =
        desktop ? 66.0 : 52.0;

    return SizedBox(
      width: width,
      height: height,
      child: AnimatedBuilder(
        animation: controller,
        builder: (
          context,
          child,
        ) {
          final rotation =
              controller.value *
                  math.pi *
                  2;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Ground shadow
              Positioned(
                left: width * 0.12,
                right: width * 0.04,
                bottom: 0,
                child: Container(
                  height:
                      desktop ? 7 : 5,
                  decoration: BoxDecoration(
                    color: Colors.black
                        .withValues(
                      alpha: 0.08,
                    ),
                    borderRadius:
                        BorderRadius
                            .circular(
                      100,
                    ),
                  ),
                ),
              ),

              // Motion streak
              Positioned(
                left: -12,
                top: height * 0.47,
                child: Row(
                  children: [
                    _motionLine(13),
                    const SizedBox(
                      width: 3,
                    ),
                    _motionLine(7),
                  ],
                ),
              ),

              // Main body
              Positioned(
                left: width * 0.12,
                top: height * 0.20,
                child: CustomPaint(
                  size: Size(
                    width * 0.72,
                    height * 0.54,
                  ),
                  painter:
                      const _TricycleBodyPainter(),
                ),
              ),

              // Roof
              Positioned(
                left: width * 0.14,
                top: height * 0.12,
                child: Container(
                  width: width * 0.55,
                  height:
                      desktop ? 9 : 7,
                  decoration: BoxDecoration(
                    gradient:
                        const LinearGradient(
                      colors: [
                        Color(
                          0xFF0B2E75,
                        ),
                        Color(
                          0xFF1557D6,
                        ),
                      ],
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      20,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(
                              0xFF1557D6,
                            ).withValues(
                              alpha: 0.18,
                            ),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                ),
              ),

              // Headlight
              Positioned(
                right: width * 0.12,
                top: height * 0.43,
                child: Container(
                  width:
                      desktop ? 9 : 7,
                  height:
                      desktop ? 9 : 7,
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                          0xFFFFC431,
                        ),
                    shape:
                        BoxShape.circle,
                    border: Border.all(
                      color: Colors.white,
                      width: 1.3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            const Color(
                              0xFFFFC431,
                            ).withValues(
                              alpha: 0.35,
                            ),
                        blurRadius: 7,
                      ),
                    ],
                  ),
                ),
              ),

              // Back wheel
              Positioned(
                left: width * 0.20,
                bottom: 2,
                child: Transform.rotate(
                  angle: rotation,
                  child: _TricycleWheel(
                    size: desktop
                        ? 20
                        : 16,
                  ),
                ),
              ),

              // Front wheel
              Positioned(
                right: width * 0.13,
                bottom: 2,
                child: Transform.rotate(
                  angle: rotation,
                  child: _TricycleWheel(
                    size: desktop
                        ? 20
                        : 16,
                  ),
                ),
              ),

              // GO flag
              Positioned(
                left: width * 0.30,
                top: -1,
                child: Transform.rotate(
                  angle: -0.07,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(
                      horizontal:
                          desktop ? 7 : 5,
                      vertical:
                          desktop ? 3 : 2,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                            0xFFFFC431,
                          ),
                      borderRadius:
                          BorderRadius
                              .circular(
                        20,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors
                              .black
                              .withValues(
                            alpha: 0.07,
                          ),
                          blurRadius: 4,
                          offset:
                              const Offset(
                            0,
                            2,
                          ),
                        ),
                      ],
                    ),
                    child: Text(
                      'GO!',
                      style: TextStyle(
                        color:
                            const Color(
                              0xFF0B2E75,
                            ),
                        fontSize:
                            desktop ? 8 : 6,
                        fontWeight:
                            FontWeight.w900,
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

  Widget _motionLine(
    double width,
  ) {
    return Container(
      width: width,
      height: 2,
      decoration: BoxDecoration(
        color:
            const Color(
              0xFF2A82F2,
            ).withValues(
              alpha: 0.30,
            ),
        borderRadius:
            BorderRadius.circular(
          20,
        ),
      ),
    );
  }
}

class _TricycleBodyPainter
    extends CustomPainter {
  const _TricycleBodyPainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final body = Paint()
      ..shader =
          const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFF2584ED),
          Color(0xFF1557D6),
          Color(0xFF0B459F),
        ],
      ).createShader(
        Offset.zero & size,
      );

    final bodyPath = Path()
      ..moveTo(
        size.width * 0.05,
        size.height * 0.28,
      )
      ..quadraticBezierTo(
        size.width * 0.08,
        size.height * 0.10,
        size.width * 0.27,
        size.height * 0.10,
      )
      ..lineTo(
        size.width * 0.58,
        size.height * 0.10,
      )
      ..quadraticBezierTo(
        size.width * 0.70,
        size.height * 0.12,
        size.width * 0.76,
        size.height * 0.30,
      )
      ..lineTo(
        size.width * 0.91,
        size.height * 0.43,
      )
      ..quadraticBezierTo(
        size.width,
        size.height * 0.52,
        size.width * 0.94,
        size.height * 0.70,
      )
      ..lineTo(
        size.width * 0.79,
        size.height * 0.78,
      )
      ..quadraticBezierTo(
        size.width * 0.71,
        size.height * 0.53,
        size.width * 0.57,
        size.height * 0.78,
      )
      ..lineTo(
        size.width * 0.34,
        size.height * 0.78,
      )
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.51,
        size.width * 0.10,
        size.height * 0.77,
      )
      ..lineTo(
        0,
        size.height * 0.69,
      )
      ..close();

    canvas.drawPath(
      bodyPath,
      body,
    );

    // Passenger window
    final windowPaint = Paint()
      ..color =
          const Color(
            0xFFE7F5FF,
          );

    final window = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * 0.18,
        size.height * 0.22,
        size.width * 0.24,
        size.height * 0.25,
      ),
      const Radius.circular(4),
    );

    canvas.drawRRect(
      window,
      windowPaint,
    );

    // Driver window
    final frontWindow =
        Path()
          ..moveTo(
            size.width * 0.48,
            size.height * 0.22,
          )
          ..lineTo(
            size.width * 0.61,
            size.height * 0.22,
          )
          ..lineTo(
            size.width * 0.70,
            size.height * 0.44,
          )
          ..lineTo(
            size.width * 0.48,
            size.height * 0.44,
          )
          ..close();

    canvas.drawPath(
      frontWindow,
      windowPaint,
    );

    // Green TourisTrike accent
    final accentPaint = Paint()
      ..color =
          const Color(
            0xFF39A447,
          );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.10,
          size.height * 0.58,
          size.width * 0.53,
          size.height * 0.08,
        ),
        const Radius.circular(5),
      ),
      accentPaint,
    );

    // Tiny yellow accent
    final yellow = Paint()
      ..color =
          const Color(
            0xFFFFC431,
          );

    canvas.drawCircle(
      Offset(
        size.width * 0.19,
        size.height * 0.57,
      ),
      size.width * 0.025,
      yellow,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter
        oldDelegate,
  ) {
    return false;
  }
}

class _TricycleWheel
    extends StatelessWidget {
  const _TricycleWheel({
    required this.size,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color:
            const Color(
              0xFF0B2E75,
            ),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black
                .withValues(
              alpha: 0.12,
            ),
            blurRadius: 4,
          ),
        ],
      ),
      child: Center(
        child: Stack(
          alignment:
              Alignment.center,
          children: [
            Container(
              width: size * 0.48,
              height: 2,
              color:
                  const Color(
                    0xFFA9C9E8,
                  ),
            ),
            Container(
              width: 2,
              height: size * 0.48,
              color:
                  const Color(
                    0xFFA9C9E8,
                  ),
            ),
            Container(
              width: size * 0.18,
              height: size * 0.18,
              decoration:
                  const BoxDecoration(
                color:
                    Color(
                      0xFF2A82F2,
                    ),
                shape:
                    BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// BULACAN LANDMARK
// =============================================================================

class _BulacanLandmark
    extends StatelessWidget {
  const _BulacanLandmark({
    required this.width,
  });

  final double width;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(
        width,
        width * 0.82,
      ),
      painter:
          const _BulacanLandmarkPainter(),
    );
  }
}

class _BulacanLandmarkPainter
    extends CustomPainter {
  const _BulacanLandmarkPainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final white = Paint()
      ..color = Colors.white;

    final cream = Paint()
      ..color =
          const Color(
            0xFFFFF3D1,
          );

    final yellow = Paint()
      ..color =
          const Color(
            0xFFFFC431,
          );

    final blue = Paint()
      ..color =
          const Color(
            0xFF1557D6,
          );

    final shadow = Paint()
      ..color =
          const Color(
            0xFF0B2E75,
          ).withValues(
            alpha: 0.07,
          );

    canvas.drawOval(
      Rect.fromLTWH(
        size.width * 0.08,
        size.height * 0.90,
        size.width * 0.84,
        size.height * 0.09,
      ),
      shadow,
    );

    // Main building
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.17,
          size.height * 0.38,
          size.width * 0.66,
          size.height * 0.55,
        ),
        Radius.circular(
          size.width * 0.04,
        ),
      ),
      white,
    );

    // Roof
    final roof = Path()
      ..moveTo(
        size.width * 0.10,
        size.height * 0.40,
      )
      ..lineTo(
        size.width * 0.50,
        size.height * 0.17,
      )
      ..lineTo(
        size.width * 0.90,
        size.height * 0.40,
      )
      ..close();

    canvas.drawPath(
      roof,
      yellow,
    );

    // Central tower
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.39,
          size.height * 0.15,
          size.width * 0.22,
          size.height * 0.63,
        ),
        Radius.circular(
          size.width * 0.025,
        ),
      ),
      cream,
    );

    // Tower roof
    final towerRoof = Path()
      ..moveTo(
        size.width * 0.35,
        size.height * 0.17,
      )
      ..lineTo(
        size.width * 0.50,
        0,
      )
      ..lineTo(
        size.width * 0.65,
        size.height * 0.17,
      )
      ..close();

    canvas.drawPath(
      towerRoof,
      yellow,
    );

    // Door
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.45,
          size.height * 0.64,
          size.width * 0.10,
          size.height * 0.29,
        ),
        Radius.circular(
          size.width * 0.04,
        ),
      ),
      blue,
    );

    // Windows
    for (final x in [
      0.26,
      0.67,
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * x,
            size.height * 0.56,
            size.width * 0.09,
            size.height * 0.15,
          ),
          Radius.circular(
            size.width * 0.02,
          ),
        ),
        blue,
      );
    }

    // Tiny sun emblem
    canvas.drawCircle(
      Offset(
        size.width * 0.50,
        size.height * 0.32,
      ),
      size.width * 0.035,
      yellow,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter
        oldDelegate,
  ) {
    return false;
  }
}

// =============================================================================
// DESTINATION
// =============================================================================

class _DestinationMarker
    extends StatelessWidget {
  const _DestinationMarker({
    required this.reached,
    required this.pulse,
    required this.desktop,
  });

  final bool reached;
  final double pulse;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final size =
        desktop ? 46.0 : 37.0;

    final floating =
        math.sin(
              pulse * math.pi,
            ) *
            3;

    return Transform.translate(
      offset: Offset(
        0,
        -floating,
      ),
      child: Column(
        children: [
          Stack(
            alignment:
                Alignment.center,
            children: [
              Container(
                width:
                    size + 16,
                height:
                    size + 16,
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                        0xFF39A447,
                      ).withValues(
                        alpha: reached
                            ? 0.14
                            : 0.07,
                      ),
                  shape:
                      BoxShape.circle,
                ),
              ),

              CustomPaint(
                size: Size(
                  size,
                  size,
                ),
                painter:
                    _MapPinPainter(
                  reached: reached,
                ),
              ),
            ],
          ),

          Container(
            width: 3,
            height:
                desktop ? 18 : 13,
            decoration:
                BoxDecoration(
              color:
                  const Color(
                    0xFF39A447,
                  ).withValues(
                    alpha: 0.28,
                  ),
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapPinPainter
    extends CustomPainter {
  const _MapPinPainter({
    required this.reached,
  });

  final bool reached;

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = reached
          ? const Color(
              0xFF16855B,
            )
          : const Color(
              0xFF39A447,
            );

    final path = Path()
      ..moveTo(
        size.width * 0.50,
        size.height,
      )
      ..cubicTo(
        size.width * 0.37,
        size.height * 0.78,
        size.width * 0.12,
        size.height * 0.56,
        size.width * 0.12,
        size.height * 0.36,
      )
      ..cubicTo(
        size.width * 0.12,
        size.height * 0.14,
        size.width * 0.29,
        0,
        size.width * 0.50,
        0,
      )
      ..cubicTo(
        size.width * 0.71,
        0,
        size.width * 0.88,
        size.height * 0.14,
        size.width * 0.88,
        size.height * 0.36,
      )
      ..cubicTo(
        size.width * 0.88,
        size.height * 0.56,
        size.width * 0.63,
        size.height * 0.78,
        size.width * 0.50,
        size.height,
      )
      ..close();

    canvas.drawShadow(
      path,
      Colors.black
          .withValues(
            alpha: 0.12,
          ),
      5,
      false,
    );

    canvas.drawPath(
      path,
      paint,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.50,
        size.height * 0.35,
      ),
      size.width * 0.15,
      Paint()
        ..color = Colors.white,
    );

    if (reached) {
      final check = Paint()
        ..color =
            const Color(
              0xFF16855B,
            )
        ..style =
            PaintingStyle.stroke
        ..strokeWidth =
            size.width * 0.06
        ..strokeCap =
            StrokeCap.round;

      final checkPath =
          Path()
            ..moveTo(
              size.width * 0.43,
              size.height * 0.35,
            )
            ..lineTo(
              size.width * 0.48,
              size.height * 0.40,
            )
            ..lineTo(
              size.width * 0.59,
              size.height * 0.28,
            );

      canvas.drawPath(
        checkPath,
        check,
      );
    }
  }

  @override
  bool shouldRepaint(
    covariant _MapPinPainter
        oldDelegate,
  ) {
    return reached !=
        oldDelegate.reached;
  }
}

// =============================================================================
// CHECKPOINT
// =============================================================================

enum _CheckpointType {
  start,
  landmark,
}

class _CheckpointMarker
    extends StatelessWidget {
  const _CheckpointMarker({
    required this.completed,
    required this.active,
    required this.size,
    required this.type,
  });

  final bool completed;
  final bool active;
  final double size;
  final _CheckpointType type;

  @override
  Widget build(BuildContext context) {
    final color = completed
        ? const Color(
            0xFF39A447,
          )
        : active
            ? const Color(
                0xFF1557D6,
              )
            : const Color(
                0xFFD9E3ED,
              );

    return AnimatedContainer(
      duration: const Duration(
        milliseconds: 300,
      ),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: color,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(
              alpha:
                  active ? 0.20 : 0.10,
            ),
            blurRadius:
                active ? 12 : 6,
            spreadRadius:
                active ? 2 : 0,
          ),
        ],
      ),
      child: CustomPaint(
        painter:
            _CheckpointPainter(
          color: color,
          completed: completed,
          type: type,
        ),
      ),
    );
  }
}

class _CheckpointPainter
    extends CustomPainter {
  const _CheckpointPainter({
    required this.color,
    required this.completed,
    required this.type,
  });

  final Color color;
  final bool completed;
  final _CheckpointType type;

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color = color
      ..style =
          PaintingStyle.stroke
      ..strokeWidth =
          size.width * 0.09
      ..strokeCap =
          StrokeCap.round
      ..strokeJoin =
          StrokeJoin.round;

    if (completed) {
      final check = Path()
        ..moveTo(
          size.width * 0.29,
          size.height * 0.52,
        )
        ..lineTo(
          size.width * 0.44,
          size.height * 0.66,
        )
        ..lineTo(
          size.width * 0.72,
          size.height * 0.34,
        );

      canvas.drawPath(
        check,
        paint,
      );

      return;
    }

    if (type ==
        _CheckpointType.start) {
      canvas.drawLine(
        Offset(
          size.width * 0.37,
          size.height * 0.28,
        ),
        Offset(
          size.width * 0.37,
          size.height * 0.73,
        ),
        paint,
      );

      final flag = Path()
        ..moveTo(
          size.width * 0.39,
          size.height * 0.30,
        )
        ..lineTo(
          size.width * 0.69,
          size.height * 0.38,
        )
        ..lineTo(
          size.width * 0.39,
          size.height * 0.49,
        );

      canvas.drawPath(
        flag,
        paint,
      );

      return;
    }

    // Tiny tourism landmark
    final roof = Path()
      ..moveTo(
        size.width * 0.27,
        size.height * 0.43,
      )
      ..lineTo(
        size.width * 0.50,
        size.height * 0.28,
      )
      ..lineTo(
        size.width * 0.73,
        size.height * 0.43,
      );

    canvas.drawPath(
      roof,
      paint,
    );

    canvas.drawLine(
      Offset(
        size.width * 0.34,
        size.height * 0.44,
      ),
      Offset(
        size.width * 0.34,
        size.height * 0.70,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(
        size.width * 0.50,
        size.height * 0.44,
      ),
      Offset(
        size.width * 0.50,
        size.height * 0.70,
      ),
      paint,
    );

    canvas.drawLine(
      Offset(
        size.width * 0.66,
        size.height * 0.44,
      ),
      Offset(
        size.width * 0.66,
        size.height * 0.70,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _CheckpointPainter
        oldDelegate,
  ) {
    return color !=
            oldDelegate.color ||
        completed !=
            oldDelegate.completed ||
        type != oldDelegate.type;
  }
}

// =============================================================================
// TREE
// =============================================================================

class _TreeIllustration
    extends StatelessWidget {
  const _TreeIllustration({
    required this.size,
  });

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(
        size,
        size,
      ),
      painter:
          const _TreePainter(),
    );
  }
}

class _TreePainter
    extends CustomPainter {
  const _TreePainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final trunk = Paint()
      ..color =
          const Color(
            0xFF9C744D,
          );

    final green1 = Paint()
      ..color =
          const Color(
            0xFF39A447,
          );

    final green2 = Paint()
      ..color =
          const Color(
            0xFF69C76E,
          );

    final green3 = Paint()
      ..color =
          const Color(
            0xFF8AD27F,
          );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.45,
          size.height * 0.55,
          size.width * 0.11,
          size.height * 0.40,
        ),
        Radius.circular(
          size.width * 0.04,
        ),
      ),
      trunk,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.42,
        size.height * 0.40,
      ),
      size.width * 0.27,
      green1,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.63,
        size.height * 0.36,
      ),
      size.width * 0.23,
      green2,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.50,
        size.height * 0.22,
      ),
      size.width * 0.23,
      green3,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter
        oldDelegate,
  ) {
    return false;
  }
}

// =============================================================================
// BUSH
// =============================================================================

class _BushIllustration
    extends StatelessWidget {
  const _BushIllustration({
    required this.width,
  });

  final double width;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(
        width,
        width * 0.50,
      ),
      painter:
          const _BushPainter(),
    );
  }
}

class _BushPainter
    extends CustomPainter {
  const _BushPainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final green1 = Paint()
      ..color =
          const Color(
            0xFF39A447,
          );

    final green2 = Paint()
      ..color =
          const Color(
            0xFF75CC78,
          );

    canvas.drawCircle(
      Offset(
        size.width * 0.26,
        size.height * 0.65,
      ),
      size.height * 0.34,
      green2,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.52,
        size.height * 0.48,
      ),
      size.height * 0.45,
      green1,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.77,
        size.height * 0.65,
      ),
      size.height * 0.33,
      green2,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter
        oldDelegate,
  ) {
    return false;
  }
}

// =============================================================================
// SUN
// =============================================================================

class _SunIllustration
    extends StatelessWidget {
  const _SunIllustration({
    required this.pulse,
    required this.large,
  });

  final double pulse;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size =
        large ? 72.0 : 53.0;

    return Transform.scale(
      scale:
          0.97 + pulse * 0.035,
      child: CustomPaint(
        size: Size(
          size,
          size,
        ),
        painter:
            const _SunPainter(),
      ),
    );
  }
}

class _SunPainter
    extends CustomPainter {
  const _SunPainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    final glow = Paint()
      ..color =
          const Color(
            0xFFFFC431,
          ).withValues(
            alpha: 0.11,
          );

    canvas.drawCircle(
      center,
      size.width * 0.48,
      glow,
    );

    final sun = Paint()
      ..shader =
          const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFFFD65C),
          Color(0xFFFFB817),
        ],
      ).createShader(
        Offset.zero & size,
      );

    canvas.drawCircle(
      center,
      size.width * 0.29,
      sun,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter
        oldDelegate,
  ) {
    return false;
  }
}

// =============================================================================
// CLOUD
// =============================================================================

class _CloudIllustration
    extends StatelessWidget {
  const _CloudIllustration({
    required this.width,
    required this.offset,
  });

  final double width;
  final double offset;

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(
        offset,
        0,
      ),
      child: CustomPaint(
        size: Size(
          width,
          width * 0.42,
        ),
        painter:
            const _CloudPainter(),
      ),
    );
  }
}

class _CloudPainter
    extends CustomPainter {
  const _CloudPainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final cloud = Paint()
      ..color =
          Colors.white.withValues(
            alpha: 0.88,
          );

    final shadow = Paint()
      ..color =
          const Color(
            0xFF1557D6,
          ).withValues(
            alpha: 0.035,
          );

    canvas.drawOval(
      Rect.fromLTWH(
        size.width * 0.09,
        size.height * 0.65,
        size.width * 0.82,
        size.height * 0.20,
      ),
      shadow,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.32,
        size.height * 0.58,
      ),
      size.width * 0.20,
      cloud,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.51,
        size.height * 0.39,
      ),
      size.width * 0.26,
      cloud,
    );

    canvas.drawCircle(
      Offset(
        size.width * 0.72,
        size.height * 0.57,
      ),
      size.width * 0.18,
      cloud,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * 0.18,
          size.height * 0.52,
          size.width * 0.65,
          size.height * 0.28,
        ),
        Radius.circular(
          size.width,
        ),
      ),
      cloud,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter
        oldDelegate,
  ) {
    return false;
  }
}

// =============================================================================
// BIRDS
// =============================================================================

class _BirdPainter
    extends CustomPainter {
  const _BirdPainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final paint = Paint()
      ..color =
          const Color(
            0xFF7791AA,
          ).withValues(
            alpha: 0.45,
          )
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap =
          StrokeCap.round;

    final bird1 = Path()
      ..moveTo(
        0,
        size.height * 0.50,
      )
      ..quadraticBezierTo(
        size.width * 0.12,
        size.height * 0.16,
        size.width * 0.24,
        size.height * 0.50,
      )
      ..quadraticBezierTo(
        size.width * 0.36,
        size.height * 0.16,
        size.width * 0.48,
        size.height * 0.50,
      );

    canvas.drawPath(
      bird1,
      paint,
    );

    final bird2 = Path()
      ..moveTo(
        size.width * 0.58,
        size.height * 0.72,
      )
      ..quadraticBezierTo(
        size.width * 0.68,
        size.height * 0.43,
        size.width * 0.78,
        size.height * 0.72,
      )
      ..quadraticBezierTo(
        size.width * 0.88,
        size.height * 0.43,
        size.width,
        size.height * 0.72,
      );

    canvas.drawPath(
      bird2,
      paint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter
        oldDelegate,
  ) {
    return false;
  }
}

// =============================================================================
// LABEL
// =============================================================================

class _JourneyLabel
    extends StatelessWidget {
  const _JourneyLabel({
    required this.text,
    this.highlighted = false,
  });

  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: highlighted
            ? const Color(
                0xFF39A447,
              )
            : const Color(
                0xFF8494A8,
              ),
        fontSize: 8.5,
        fontWeight:
            FontWeight.w900,
        letterSpacing: 0.75,
      ),
    );
  }
}

// =============================================================================
// LOADING DOTS
// =============================================================================

class _LoadingDots
    extends StatelessWidget {
  const _LoadingDots({
    required this.controller,
  });

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (
        context,
        child,
      ) {
        return Row(
          mainAxisSize:
              MainAxisSize.min,
          children: List.generate(
            3,
            (index) {
              final phase =
                  (controller.value +
                          index * 0.18) %
                      1;

              final intensity =
                  (math.sin(
                            phase *
                                math.pi *
                                2,
                          ) +
                          1) /
                      2;

              final size =
                  6 +
                  intensity * 2.5;

              return Container(
                width: size,
                height: size,
                margin:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 3,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                        0xFF1557D6,
                      ).withValues(
                        alpha:
                            0.30 +
                            intensity *
                                0.70,
                      ),
                  shape:
                      BoxShape.circle,
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// =============================================================================
// AMBIENT DECORATIONS
// =============================================================================

class _AmbientDecorations
    extends StatelessWidget {
  const _AmbientDecorations({
    required this.controller,
  });

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (
          context,
          child,
        ) {
          final wave =
              math.sin(
                controller.value *
                    math.pi *
                    2,
              );

          return Stack(
            children: [
              Positioned(
                top: 125 + wave * 5,
                left: 28,
                child:
                    const _Spark(
                  color: Color(
                    0xFFFFC431,
                  ),
                  size: 8,
                ),
              ),

              Positioned(
                top: 210 - wave * 5,
                right: 36,
                child:
                    const _Spark(
                  color: Color(
                    0xFF39A447,
                  ),
                  size: 7,
                ),
              ),

              Positioned(
                bottom:
                    180 + wave * 4,
                left: 38,
                child:
                    const _Spark(
                  color: Color(
                    0xFF2A82F2,
                  ),
                  size: 6,
                ),
              ),

              Positioned(
                bottom:
                    120 - wave * 4,
                right: 48,
                child:
                    const _Spark(
                  color: Color(
                    0xFFFFA43B,
                  ),
                  size: 6,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Spark
    extends StatelessWidget {
  const _Spark({
    required this.color,
    required this.size,
  });

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: math.pi / 4,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(
            alpha: 0.27,
          ),
          borderRadius:
              BorderRadius.circular(
            2,
          ),
        ),
      ),
    );
  }
}

// =============================================================================
// BACKGROUND
// =============================================================================

class _TourisTrikeBackgroundPainter
    extends CustomPainter {
  const _TourisTrikeBackgroundPainter();

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final rect =
        Offset.zero & size;

    // Main background
    final background = Paint()
      ..shader =
          const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFF2F9FF),
          Color(0xFFFAFDFF),
          Color(0xFFF4FCF7),
        ],
        stops: [
          0,
          0.54,
          1,
        ],
      ).createShader(rect);

    canvas.drawRect(
      rect,
      background,
    );

    // Top-right blue glow
    final blueGlow = Paint()
      ..color =
          const Color(
            0xFF78BAFF,
          ).withValues(
            alpha: 0.075,
          );

    canvas.drawCircle(
      Offset(
        size.width + 15,
        -25,
      ),
      math.min(
        size.width * 0.28,
        230,
      ),
      blueGlow,
    );

    // Left yellow glow
    final yellowGlow = Paint()
      ..color =
          const Color(
            0xFFFFD66B,
          ).withValues(
            alpha: 0.045,
          );

    canvas.drawCircle(
      Offset(
        -45,
        size.height * 0.33,
      ),
      math.min(
        size.width * 0.18,
        160,
      ),
      yellowGlow,
    );

    // Back hill
    final hill1 = Paint()
      ..color =
          const Color(
            0xFFB9EBC7,
          ).withValues(
            alpha: 0.25,
          );

    final hillPath1 = Path()
      ..moveTo(
        0,
        size.height,
      )
      ..lineTo(
        0,
        size.height * 0.84,
      )
      ..quadraticBezierTo(
        size.width * 0.22,
        size.height * 0.76,
        size.width * 0.46,
        size.height * 0.86,
      )
      ..quadraticBezierTo(
        size.width * 0.71,
        size.height * 0.96,
        size.width,
        size.height * 0.82,
      )
      ..lineTo(
        size.width,
        size.height,
      )
      ..close();

    canvas.drawPath(
      hillPath1,
      hill1,
    );

    // Front hill
    final hill2 = Paint()
      ..color =
          const Color(
            0xFF69C98B,
          ).withValues(
            alpha: 0.105,
          );

    final hillPath2 = Path()
      ..moveTo(
        0,
        size.height,
      )
      ..lineTo(
        0,
        size.height * 0.91,
      )
      ..quadraticBezierTo(
        size.width * 0.24,
        size.height * 0.83,
        size.width * 0.49,
        size.height * 0.94,
      )
      ..quadraticBezierTo(
        size.width * 0.74,
        size.height * 1.02,
        size.width,
        size.height * 0.90,
      )
      ..lineTo(
        size.width,
        size.height,
      )
      ..close();

    canvas.drawPath(
      hillPath2,
      hill2,
    );

    // Tiny background dots
    final dot = Paint()
      ..color =
          const Color(
            0xFF1557D6,
          ).withValues(
            alpha: 0.032,
          );

    const spacing = 54.0;

    for (
      double x = 25;
      x < size.width;
      x += spacing
    ) {
      for (
        double y = 25;
        y < size.height;
        y += spacing
      ) {
        canvas.drawCircle(
          Offset(
            x,
            y,
          ),
          1.15,
          dot,
        );
      }
    }

    // Decorative curved travel path in background
    final routePaint = Paint()
      ..color =
          const Color(
            0xFF1557D6,
          ).withValues(
            alpha: 0.035,
          )
      ..style =
          PaintingStyle.stroke
      ..strokeWidth = 2;

    final routePath = Path()
      ..moveTo(
        -20,
        size.height * 0.69,
      )
      ..cubicTo(
        size.width * 0.18,
        size.height * 0.60,
        size.width * 0.37,
        size.height * 0.79,
        size.width * 0.56,
        size.height * 0.68,
      )
      ..cubicTo(
        size.width * 0.76,
        size.height * 0.56,
        size.width * 0.86,
        size.height * 0.59,
        size.width + 30,
        size.height * 0.49,
      );

    canvas.drawPath(
      routePath,
      routePaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant CustomPainter
        oldDelegate,
  ) {
    return false;
  }
}