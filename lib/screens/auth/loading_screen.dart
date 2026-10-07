import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:touristrike/core/auth/complete_registration.dart';
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
    with SingleTickerProviderStateMixin {
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

  static const Color _ink = Color(0xFF10213F);
  static const Color _muted = Color(0xFF7A8799);

  // ===========================================================================
  // STATE
  // ===========================================================================

  final AppLinks _appLinks = AppLinks();

  late final AnimationController _controller;
  late final Future<Widget> _destinationFuture;

  bool _navigationStarted = false;

  // ===========================================================================
  // INITIALIZATION
  // ===========================================================================

  @override
  void initState() {
    super.initState();

    /*
     * Resolve the real destination while the splash animation is playing.
     *
     * This means the animation is NOT an artificial loading timer.
     * Authentication/database work happens in parallel.
     */
    _destinationFuture = _resolveDestination();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _finishSplash();
      }
    });

    _controller.forward();
  }

  // ===========================================================================
  // TIMELINE
  // ===========================================================================

  double _timeline(
    double begin,
    double end, [
    Curve curve = Curves.linear,
  ]) {
    if (_controller.value <= begin) {
      return 0;
    }

    if (_controller.value >= end) {
      return 1;
    }

    final progress =
        (_controller.value - begin) / (end - begin);

    return curve.transform(
      progress.clamp(0.0, 1.0),
    );
  }

  // ===========================================================================
  // DESTINATION / AUTH
  // ===========================================================================

  Future<Widget> _resolveDestination() async {
    /*
     * Preserve current TourisTrike web behavior.
     */
    if (kIsWeb) {
      return const WebPortalLandingScreen();
    }

    final client = Supabase.instance.client;
    final session = client.auth.currentSession;

    if (session == null) {
      return const LoginScreen();
    }

    try {
<<<<<<< HEAD
      final currentUser = client.auth.currentUser;

      if (currentUser == null) {
        return const LoginScreen();
      }

      final profile = await client
=======
      final auth = Supabase.instance.client.auth;
      final verifiedUser = (await auth.getUser()).user;
      if (verifiedUser == null || verifiedUser.emailConfirmedAt == null) {
        await auth.signOut();
        _goToLogin();
        return;
      }
      final userId = verifiedUser.id;

      var profile = await Supabase.instance.client
>>>>>>> 088045a (improved booking)
          .from('profiles')
          .select('role')
          .eq('id', currentUser.id)
          .maybeSingle()
          .timeout(
            const Duration(seconds: 10),
          );

<<<<<<< HEAD
=======
      if (profile == null) {
        await completeConfirmedRegistration(Supabase.instance.client);
        profile = await Supabase.instance.client.from('profiles')
            .select('role').eq('id', userId).maybeSingle();
      }

      if (!mounted) return;

>>>>>>> 088045a (improved booking)
      if (profile == null) {
        return const LoginScreen();
      }

      final role = AppRole.tryParse(
        profile['role'] as String?,
      );

      if (role == null) {
        return const LoginScreen();
      }

      switch (destinationForRole(role)) {
        case AppRoleDestination.touristApp:
          final bookingId =
              await _initialPaymentReturnBookingId();

          if (bookingId != null) {
            return ActivityTrackingScreen(
              bookingId: bookingId,
            );
          }

          return const TouristHomeScreen();

        case AppRoleDestination.driverApp:
          return const DriverHomeScreen();

        case AppRoleDestination.administratorPortal:
          return const AdministratorPortalScreen();

        case AppRoleDestination.mainTenantPortal:
          return const MainTenantPortalScreen();

        case AppRoleDestination.subtenantPortal:
          return const SubTenantPortalScreen();
      }
    } catch (error) {
      debugPrint(
        '[TourisTrike] splash profile lookup failed: $error',
      );

      return const LoginScreen();
    }
  }

  // ===========================================================================
  // PAYMONGO DEEP LINK
  // ===========================================================================

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

      final validUuid = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        caseSensitive: false,
      ).hasMatch(bookingId);

      if (!validUuid) {
        return null;
      }

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

  // ===========================================================================
  // FINISH SPLASH
  // ===========================================================================

  Future<void> _finishSplash() async {
    if (_navigationStarted) {
      return;
    }

    _navigationStarted = true;

    final destination = await _destinationFuture;

    if (!mounted) {
      return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(
          milliseconds: 380,
        ),
        reverseTransitionDuration: const Duration(
          milliseconds: 250,
        ),
        pageBuilder: (
          context,
          animation,
          secondaryAnimation,
        ) {
          return destination;
        },
        transitionsBuilder: (
          context,
          animation,
          secondaryAnimation,
          child,
        ) {
          final opacity = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );

          return FadeTransition(
            opacity: opacity,
            child: child,
          );
        },
      ),
    );
  }

  // ===========================================================================
  // DISPOSE
  // ===========================================================================

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;

          final desktop = width >= 900;
          final tablet = width >= 600 && width < 900;
          final compact = width < 380;
          final short = height < 650;

          final logoSize = desktop
              ? 150.0
              : tablet
                  ? 138.0
                  : compact
                      ? 105.0
                      : 122.0;

          final brandFontSize = desktop
              ? 39.0
              : tablet
                  ? 36.0
                  : compact
                      ? 28.0
                      : 32.0;

          final travellingFontSize = desktop
              ? 30.0
              : tablet
                  ? 27.0
                  : compact
                      ? 21.0
                      : 24.0;

          return AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                fit: StackFit.expand,
                children: [
                  // ===========================================================
                  // PURE WHITE BACKGROUND
                  // ===========================================================

                  const ColoredBox(
                    color: Colors.white,
                  ),

                  // ===========================================================
                  // TRAVELLING WORDS
                  // ===========================================================

                  _buildExploreWord(
                    screenWidth: width,
                    fontSize: travellingFontSize,
                  ),

                  _buildRideWord(
                    screenWidth: width,
                    fontSize: travellingFontSize,
                  ),

                  _buildExperienceWord(
                    screenWidth: width,
                    fontSize: travellingFontSize,
                  ),

                  // ===========================================================
                  // EXPERIENCE -> ROUTE TRANSFORMATION
                  // ===========================================================

                  _buildRouteTransformation(
                    desktop: desktop,
                    compact: compact,
                  ),

                  // ===========================================================
                  // FINAL TOURISTRIKE BRAND
                  // ===========================================================

                  _buildFinalBrand(
                    logoSize: logoSize,
                    brandFontSize: brandFontSize,
                    compact: compact,
                    short: short,
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  // ===========================================================================
  // EXPLORE
  // ===========================================================================

  Widget _buildExploreWord({
    required double screenWidth,
    required double fontSize,
  }) {
    /*
     * ENTER
     * 0.04 -> 0.18
     *
     * EXIT
     * 0.21 -> 0.34
     */
    final enter = _timeline(
      0.04,
      0.18,
      Curves.easeOutCubic,
    );

    final exit = _timeline(
      0.21,
      0.34,
      Curves.easeInCubic,
    );

    final fadeIn = _timeline(
      0.03,
      0.10,
      Curves.easeOut,
    );

    final fadeOut = _timeline(
      0.26,
      0.34,
      Curves.easeIn,
    );

    final opacity =
        (fadeIn * (1 - fadeOut)).clamp(0.0, 1.0);

    final x =
        (screenWidth * 0.72 * (1 - enter)) -
        (screenWidth * 0.80 * exit);

    return _travellingWord(
      text: 'Explore.',
      color: _blue,
      opacity: opacity,
      x: x,
      fontSize: fontSize,
      scale: 0.96 + (0.04 * enter),
    );
  }

  // ===========================================================================
  // RIDE
  // ===========================================================================

  Widget _buildRideWord({
    required double screenWidth,
    required double fontSize,
  }) {
    /*
     * Slight overlap with Explore creates continuous travel.
     */
    final enter = _timeline(
      0.16,
      0.30,
      Curves.easeOutCubic,
    );

    final exit = _timeline(
      0.33,
      0.45,
      Curves.easeInCubic,
    );

    final fadeIn = _timeline(
      0.15,
      0.22,
      Curves.easeOut,
    );

    final fadeOut = _timeline(
      0.38,
      0.45,
      Curves.easeIn,
    );

    final opacity =
        (fadeIn * (1 - fadeOut)).clamp(0.0, 1.0);

    final x =
        (screenWidth * 0.72 * (1 - enter)) -
        (screenWidth * 0.80 * exit);

    return _travellingWord(
      text: 'Ride.',
      color: _green,
      opacity: opacity,
      x: x,
      fontSize: fontSize,
      scale: 0.96 + (0.04 * enter),
    );
  }

  // ===========================================================================
  // EXPERIENCE
  // ===========================================================================

  Widget _buildExperienceWord({
    required double screenWidth,
    required double fontSize,
  }) {
    /*
     * Experience remains in the center longer.
     *
     * It becomes the visual transition point into the logo.
     */
    final enter = _timeline(
      0.29,
      0.43,
      Curves.easeOutCubic,
    );

    final collapse = _timeline(
      0.52,
      0.61,
      Curves.easeInCubic,
    );

    final fadeIn = _timeline(
      0.28,
      0.36,
      Curves.easeOut,
    );

    final fadeOut = _timeline(
      0.53,
      0.61,
      Curves.easeIn,
    );

    final opacity =
        (fadeIn * (1 - fadeOut)).clamp(0.0, 1.0);

    final x =
        screenWidth * 0.72 * (1 - enter);

    /*
     * Collapse horizontally toward the center.
     */
    final scaleX =
        1.0 - (0.72 * collapse);

    final scaleY =
        1.0 - (0.25 * collapse);

    return IgnorePointer(
      child: Center(
        child: Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(x, 0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..scale(
                  scaleX,
                  scaleY,
                ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Experience.',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _deepBlue,
                      fontSize: fontSize,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.65,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // COMMON TRAVELLING WORD
  // ===========================================================================

  Widget _travellingWord({
    required String text,
    required Color color,
    required double opacity,
    required double x,
    required double fontSize,
    required double scale,
  }) {
    return IgnorePointer(
      child: Center(
        child: ClipRect(
          child: Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(x, 0),
              child: Transform.scale(
                scale: scale,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      text,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: color,
                        fontSize: fontSize,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.65,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // ROUTE TRANSFORMATION
  // ===========================================================================

  Widget _buildRouteTransformation({
    required bool desktop,
    required bool compact,
  }) {
    /*
     * The Experience word collapses into this tiny route streak.
     *
     * The route then collapses into the point where the
     * TourisTrike logo emerges.
     */

    final reveal = _timeline(
      0.51,
      0.59,
      Curves.easeOutCubic,
    );

    final collapse = _timeline(
      0.61,
      0.70,
      Curves.easeInOutCubic,
    );

    final opacityIn = _timeline(
      0.51,
      0.56,
      Curves.easeOut,
    );

    final opacityOut = _timeline(
      0.64,
      0.70,
      Curves.easeIn,
    );

    final opacity =
        (opacityIn * (1 - opacityOut)).clamp(0.0, 1.0);

    final maxWidth = desktop
        ? 155.0
        : compact
            ? 92.0
            : 120.0;

    final width =
        maxWidth *
        reveal *
        (1 - collapse);

    final dotScale =
        reveal *
        (1 - collapse * 0.65);

    return IgnorePointer(
      child: Center(
        child: Opacity(
          opacity: opacity,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              // Route glow
              Container(
                width: width + 16,
                height: 12,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(
                    100,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _blue.withValues(
                        alpha: 0.10,
                      ),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              ),

              // Route line
              Container(
                width: width,
                height: 3,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      _blue,
                      _brightBlue,
                      _green,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(
                    100,
                  ),
                ),
              ),

              // Center point
              Transform.scale(
                scale: dotScale,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _green,
                      width: 2.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _green.withValues(
                          alpha: 0.18,
                        ),
                        blurRadius: 10,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // FINAL BRAND
  // ===========================================================================

  Widget _buildFinalBrand({
    required double logoSize,
    required double brandFontSize,
    required bool compact,
    required bool short,
  }) {
    /*
     * Logo begins as the route line is collapsing.
     */
    final logoOpacity = _timeline(
      0.64,
      0.76,
      Curves.easeOut,
    );

    /*
     * Main expansion.
     */
    final logoEntrance = _timeline(
      0.63,
      0.79,
      Curves.easeOutCubic,
    );

    /*
     * Very subtle final settling.
     *
     * Not a big bounce.
     */
    final settle = _timeline(
      0.79,
      0.87,
      Curves.easeOutCubic,
    );

    double logoScale;

    if (logoEntrance < 1) {
      logoScale =
          0.50 + (0.53 * logoEntrance);
    } else {
      logoScale =
          1.03 - (0.03 * settle);
    }

    /*
     * Very small upward reveal.
     */
    final logoYOffset =
        8 * (1 - logoEntrance);

    // -------------------------------------------------------------------------
    // BRAND NAME
    // -------------------------------------------------------------------------

    final titleOpacity = _timeline(
      0.73,
      0.85,
      Curves.easeOut,
    );

    final titleMove = _timeline(
      0.72,
      0.86,
      Curves.easeOutCubic,
    );

    final titleYOffset =
        10 * (1 - titleMove);

    // -------------------------------------------------------------------------
    // TAGLINE
    // -------------------------------------------------------------------------

    final taglineOpacity = _timeline(
      0.82,
      0.94,
      Curves.easeOut,
    );

    final taglineMove = _timeline(
      0.81,
      0.95,
      Curves.easeOutCubic,
    );

    final taglineYOffset =
        7 * (1 - taglineMove);

    /*
     * Slight upward compensation makes the complete
     * logo + name + tagline group look optically centered.
     */
    final groupOffset =
        short ? -4.0 : -10.0;

    return IgnorePointer(
      child: Center(
        child: Transform.translate(
          offset: Offset(
            0,
            groupOffset,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ===============================================================
              // LOGO
              // ===============================================================

              Opacity(
                opacity: logoOpacity,
                child: Transform.translate(
                  offset: Offset(
                    0,
                    logoYOffset,
                  ),
                  child: Transform.scale(
                    scale: logoScale,
                    child: _buildLogo(
                      logoSize,
                    ),
                  ),
                ),
              ),

              SizedBox(
                height: compact ? 5 : 7,
              ),

              // ===============================================================
              // TOURISTRIKE
              // ===============================================================

              Opacity(
                opacity: titleOpacity,
                child: Transform.translate(
                  offset: Offset(
                    0,
                    titleYOffset,
                  ),
                  child: Text(
                    'TourisTrike',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _ink,
                      fontSize: brandFontSize,
                      height: 1,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1.35,
                    ),
                  ),
                ),
              ),

              SizedBox(
                height: compact ? 9 : 11,
              ),

              // ===============================================================
              // EXPLORE • RIDE • EXPERIENCE
              // ===============================================================

              Opacity(
                opacity: taglineOpacity,
                child: Transform.translate(
                  offset: Offset(
                    0,
                    taglineYOffset,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: RichText(
                        maxLines: 1,
                        textAlign: TextAlign.center,
                        text: TextSpan(
                          style: TextStyle(
                            fontSize:
                                compact ? 9.5 : 10.5,
                            height: 1,
                            fontWeight:
                                FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                          children: const [
                            TextSpan(
                              text: 'EXPLORE',
                              style: TextStyle(
                                color: _blue,
                              ),
                            ),
                            TextSpan(
                              text: '  •  ',
                              style: TextStyle(
                                color: _muted,
                              ),
                            ),
                            TextSpan(
                              text: 'RIDE',
                              style: TextStyle(
                                color: _green,
                              ),
                            ),
                            TextSpan(
                              text: '  •  ',
                              style: TextStyle(
                                color: _muted,
                              ),
                            ),
                            TextSpan(
                              text: 'EXPERIENCE',
                              style: TextStyle(
                                color: _deepBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // LOGO
  // ===========================================================================

  Widget _buildLogo(
    double size,
  ) {
    /*
     * FIRST:
     * Try the bundled local logo.
     *
     * BEST FOR SPLASH:
     * No internet dependency.
     *
     * FALLBACK:
     * Existing Supabase-hosted TourisTrike logo.
     */
    return Image.network(
  logoUrl,
  width: size,
  height: size,
  fit: BoxFit.contain,
  filterQuality: FilterQuality.high,
  gaplessPlayback: true,
  errorBuilder: (
    context,
    error,
    stackTrace,
  ) {
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: Icon(
          Icons.explore_rounded,
          color: _blue,
          size: size * 0.58,
        ),
      ),
    );
  },
);
  }
}
