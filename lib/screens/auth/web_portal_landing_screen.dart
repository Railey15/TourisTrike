import 'package:flutter/material.dart';

import 'city_admin_signup_screen.dart';
import 'web_portal_login_screen.dart';

class WebPortalLandingScreen extends StatelessWidget {
  const WebPortalLandingScreen({super.key});

  static const String logoUrl =
      'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/public-assets/Logo.png';

  static const Color primaryBlue = Color(0xFF1557D6);
  static const Color deepBlue = Color(0xFF0B2E75);
  static const Color green = Color(0xFF39A447);
  static const Color yellow = Color(0xFFFFC107);
  static const Color ink = Color(0xFF10213F);
  static const Color muted = Color(0xFF64748B);
  static const Color pageBackground = Color(0xFFF4F8FD);

  void _openLogin(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const WebPortalLoginScreen(),
      ),
    );
  }

  void _openCityAdminSignup(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const CityAdminSignupScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: pageBackground,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;

          final isDesktop = width >= 1050;
          final isTablet = width >= 700 && width < 1050;
          final isMobile = width < 700;
          final isSmallMobile = width < 390;

          return Stack(
            children: [
              const Positioned.fill(
                child: _BackgroundDecoration(),
              ),

              SafeArea(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: 1240,
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: isDesktop
                              ? 42
                              : isTablet
                                  ? 28
                                  : 18,
                          vertical: isDesktop
                              ? 24
                              : isTablet
                                  ? 20
                                  : 14,
                        ),
                        child: Column(
                          children: [
                            _Header(
                              isMobile: isMobile,
                              isSmallMobile: isSmallMobile,
                              onLogin: () => _openLogin(context),
                              onApply: () =>
                                  _openCityAdminSignup(context),
                            ),

                            SizedBox(
                              height: isDesktop
                                  ? 48
                                  : isTablet
                                      ? 38
                                      : 28,
                            ),

                            if (isDesktop)
                              _DesktopHero(
                                onLogin: () => _openLogin(context),
                                onApply: () =>
                                    _openCityAdminSignup(context),
                              )
                            else
                              _ResponsiveHero(
                                isSmallMobile: isSmallMobile,
                                onLogin: () => _openLogin(context),
                                onApply: () =>
                                    _openCityAdminSignup(context),
                              ),

                            SizedBox(
                              height: isDesktop
                                  ? 55
                                  : isTablet
                                      ? 42
                                      : 34,
                            ),

                            _TrustStrip(
                              isMobile: isMobile,
                              isSmallMobile: isSmallMobile,
                            ),

                            const SizedBox(height: 20),

                            _FooterNote(
                              isMobile: isMobile,
                            ),

                            const SizedBox(height: 6),
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
// HEADER
// ============================================================

class _Header extends StatelessWidget {
  const _Header({
    required this.isMobile,
    required this.isSmallMobile,
    required this.onLogin,
    required this.onApply,
  });

  final bool isMobile;
  final bool isSmallMobile;
  final VoidCallback onLogin;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final brand = Row(
      children: [
        Container(
          width: isSmallMobile ? 42 : 48,
          height: isSmallMobile ? 42 : 48,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: const Color(0xFFDDE9F8),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF173B72).withOpacity(0.07),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Image.network(
            WebPortalLandingScreen.logoUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) {
              return const Icon(
                Icons.electric_rickshaw_rounded,
                color: WebPortalLandingScreen.primaryBlue,
              );
            },
          ),
        ),
        const SizedBox(width: 11),
        Flexible(
          child: Text(
            'TourisTrike Admin Portal',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: WebPortalLandingScreen.ink,
              fontSize: isSmallMobile ? 15 : 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.35,
            ),
          ),
        ),
      ],
    );

    final signInButton = ElevatedButton.icon(
      onPressed: onLogin,
      icon: const Icon(
        Icons.login_rounded,
        size: 17,
      ),
      label: const Text('Sign In'),
      style: ElevatedButton.styleFrom(
        backgroundColor: WebPortalLandingScreen.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: EdgeInsets.symmetric(
          horizontal: isSmallMobile ? 14 : 19,
          vertical: 13,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
        textStyle: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
        ),
      ),
    );

    final applyButton = SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onApply,
        icon: const Icon(
          Icons.location_city_rounded,
          size: 17,
        ),
        label: const Text('Apply as City Admin'),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF087B67),
          backgroundColor: Colors.white.withOpacity(0.78),
          side: const BorderSide(
            color: Color(0xFFA7E4D3),
          ),
          padding: const EdgeInsets.symmetric(
            vertical: 13,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
          textStyle: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // TOP ROW
        Row(
          children: [
            Expanded(
              child: brand,
            ),
            const SizedBox(width: 14),
            signInButton,
          ],
        ),

        const SizedBox(height: 10),

        // FULL-WIDTH APPLY BUTTON
        applyButton,
      ],
    );
  }
}

// ============================================================
// DESKTOP HERO
// ============================================================

class _DesktopHero extends StatelessWidget {
  const _DesktopHero({
    required this.onLogin,
    required this.onApply,
  });

  final VoidCallback onLogin;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 11,
          child: _HeroCopy(
            onLogin: onLogin,
            onApply: onApply,
            compact: false,
          ),
        ),
        const SizedBox(width: 54),
        const Expanded(
          flex: 9,
          child: _DashboardPreview(
            compact: false,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// TABLET / MOBILE HERO
// ============================================================

class _ResponsiveHero extends StatelessWidget {
  const _ResponsiveHero({
    required this.isSmallMobile,
    required this.onLogin,
    required this.onApply,
  });

  final bool isSmallMobile;
  final VoidCallback onLogin;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HeroCopy(
          onLogin: onLogin,
          onApply: onApply,
          compact: true,
          isSmallMobile: isSmallMobile,
        ),

        SizedBox(
          height: isSmallMobile ? 25 : 32,
        ),

        const _DashboardPreview(
          compact: true,
        ),
      ],
    );
  }
}

// ============================================================
// HERO COPY
// ============================================================

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.onLogin,
    required this.onApply,
    this.compact = false,
    this.isSmallMobile = false,
  });

  final VoidCallback onLogin;
  final VoidCallback onApply;
  final bool compact;
  final bool isSmallMobile;

  @override
  Widget build(BuildContext context) {
    final alignment =
        compact ? CrossAxisAlignment.center : CrossAxisAlignment.start;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignment,
      children: [
        const _PortalBadge(),

        SizedBox(
          height: compact ? 17 : 23,
        ),

        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Manage Bulacan tourism\n',
              ),
              TextSpan(
                text: 'operations ',
                style: TextStyle(
                  color: WebPortalLandingScreen.primaryBlue,
                ),
              ),
              const TextSpan(
                text: 'from one\nsecure portal.',
              ),
            ],
          ),
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: TextStyle(
            color: WebPortalLandingScreen.ink,
            fontSize: isSmallMobile
                ? 32
                : compact
                    ? 39
                    : 54,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: isSmallMobile ? -1.2 : -1.8,
          ),
        ),

        SizedBox(
          height: compact ? 15 : 19,
        ),

        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 620,
          ),
          child: Text(
            'A centralized workspace for provincial and local tourism teams to manage destinations, packages, bookings, and accredited drivers.',
            textAlign: compact ? TextAlign.center : TextAlign.left,
            style: TextStyle(
              color: WebPortalLandingScreen.muted,
              fontSize: isSmallMobile ? 13.5 : 15.5,
              height: 1.6,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        SizedBox(
          height: compact ? 23 : 28,
        ),

        _RoleSummary(
          compact: compact,
          isSmallMobile: isSmallMobile,
        ),

      ],
    );
  }
}

// ============================================================
// BADGE
// ============================================================

class _PortalBadge extends StatelessWidget {
  const _PortalBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFD9E6F5),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 7,
            color: WebPortalLandingScreen.green,
          ),
          SizedBox(width: 7),
          Text(
            'ADMINISTRATOR ACCESS',
            style: TextStyle(
              color: Color(0xFF42617F),
              fontSize: 10.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.65,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ROLE SUMMARY
// ============================================================

class _RoleSummary extends StatelessWidget {
  const _RoleSummary({
    required this.compact,
    required this.isSmallMobile,
  });

  final bool compact;
  final bool isSmallMobile;

  @override
  Widget build(BuildContext context) {
    final width = isSmallMobile ? 150.0 : 190.0;

    final items = [
      _RoleItem(
        icon: Icons.account_balance_rounded,
        title: 'Provincial Office',
        subtitle: 'Main tenant',
        width: width,
      ),
      _RoleItem(
        icon: Icons.location_city_rounded,
        title: 'City / Municipal',
        subtitle: 'Sub-tenant',
        width: width,
      ),
    ];

    return Wrap(
      alignment:
          compact ? WrapAlignment.center : WrapAlignment.start,
      spacing: 10,
      runSpacing: 9,
      children: items,
    );
  }
}

class _RoleItem extends StatelessWidget {
  const _RoleItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.width,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.76),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFDDE8F5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 18,
              color: WebPortalLandingScreen.primaryBlue,
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WebPortalLandingScreen.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: WebPortalLandingScreen.muted,
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
// DASHBOARD PREVIEW
// ============================================================

class _DashboardPreview extends StatelessWidget {
  const _DashboardPreview({
    required this.compact,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 430;

        final outerPadding = narrow ? 11.0 : compact ? 14.0 : 18.0;
        final innerPadding = narrow ? 12.0 : compact ? 14.0 : 18.0;

        return Container(
          width: double.infinity,
          constraints: const BoxConstraints(
            maxWidth: 540,
          ),
          padding: EdgeInsets.all(outerPadding),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.84),
            borderRadius: BorderRadius.circular(
              narrow ? 21 : 26,
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.96),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF153C72).withOpacity(0.09),
                blurRadius: 32,
                offset: const Offset(0, 17),
              ),
            ],
          ),
          child: Container(
            padding: EdgeInsets.all(innerPadding),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FBFF),
              borderRadius: BorderRadius.circular(
                narrow ? 17 : 21,
              ),
              border: Border.all(
                color: const Color(0xFFE0EAF6),
              ),
            ),
            child: Column(
              children: [
                _DashboardHeader(
                  narrow: narrow,
                ),

                SizedBox(
                  height: narrow ? 12 : 15,
                ),

                _DashboardHeroCard(
                  narrow: narrow,
                ),

                SizedBox(
                  height: narrow ? 9 : 11,
                ),

                _MetricsGrid(
                  narrow: narrow,
                ),

                SizedBox(
                  height: narrow ? 10 : 13,
                ),

                const _ProgressSection(),

                SizedBox(
                  height: narrow ? 10 : 13,
                ),

                const _SecurityBanner(),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ============================================================
// DASHBOARD HEADER
// ============================================================

class _DashboardHeader extends StatelessWidget {
  const _DashboardHeader({
    required this.narrow,
  });

  final bool narrow;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: narrow ? 38 : 43,
          height: narrow ? 38 : 43,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Image.network(
            WebPortalLandingScreen.logoUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) {
              return const Icon(
                Icons.dashboard_rounded,
                color: WebPortalLandingScreen.primaryBlue,
              );
            },
          ),
        ),

        const SizedBox(width: 9),

        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Operations Overview',
                style: TextStyle(
                  color: WebPortalLandingScreen.ink,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'TourisTrike Admin Portal',
                style: TextStyle(
                  color: WebPortalLandingScreen.muted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 5,
          ),
          decoration: BoxDecoration(
            color: const Color(0xFFE9F8EF),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.circle,
                size: 6,
                color: Color(0xFF21A45A),
              ),
              SizedBox(width: 4),
              Text(
                'LIVE',
                style: TextStyle(
                  color: Color(0xFF18824A),
                  fontSize: 8.5,
                  fontWeight: FontWeight.w900,
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
// DASHBOARD HERO CARD
// ============================================================

class _DashboardHeroCard extends StatelessWidget {
  const _DashboardHeroCard({
    required this.narrow,
  });

  final bool narrow;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        narrow ? 13 : 16,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1557D6),
            Color(0xFF2674DF),
          ],
        ),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Stack(
        children: [
          Positioned(
            right: -28,
            top: -38,
            child: Container(
              width: 115,
              height: 115,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),

          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tourism activity',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),

              const SizedBox(height: 3),

              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '74%',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: narrow ? 28 : 31,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                    ),
                  ),

                  const SizedBox(width: 7),

                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        '+12.4%',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 8,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 2),

              const Text(
                'Published tourism packages',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================
// METRICS GRID
// ============================================================

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.narrow,
  });

  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final items = [
      const _MiniMetric(
        value: '128',
        label: 'Spots',
        icon: Icons.place_rounded,
      ),
      const _MiniMetric(
        value: '42',
        label: 'Packages',
        icon: Icons.inventory_2_rounded,
      ),
      const _MiniMetric(
        value: '316',
        label: 'Bookings',
        icon: Icons.receipt_long_rounded,
      ),
      const _MiniMetric(
        value: '89',
        label: 'Drivers',
        icon: Icons.badge_rounded,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 9,
        mainAxisSpacing: 9,
        childAspectRatio: 2.55,
      ),
      itemBuilder: (_, index) {
        return items[index];
      },
    );
  }
}

// ============================================================
// MINI METRIC
// ============================================================

class _MiniMetric extends StatelessWidget {
  const _MiniMetric({
    required this.value,
    required this.label,
    required this.icon,
  });

  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE0EAF5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: const Color(0xFFEDF4FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 15,
              color: WebPortalLandingScreen.primaryBlue,
            ),
          ),

          const SizedBox(width: 7),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: WebPortalLandingScreen.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WebPortalLandingScreen.muted,
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
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
// PROGRESS
// ============================================================

class _ProgressSection extends StatelessWidget {
  const _ProgressSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE0EAF5),
        ),
      ),
      child: const Column(
        children: [
          _ProgressRow(
            title: 'Published packages',
            value: '74%',
            progress: 0.74,
          ),
          SizedBox(height: 11),
          _ProgressRow(
            title: 'Confirmed bookings',
            value: '61%',
            progress: 0.61,
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    required this.title,
    required this.value,
    required this.progress,
  });

  final String title;
  final String value;
  final double progress;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: WebPortalLandingScreen.ink,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: WebPortalLandingScreen.primaryBlue,
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            color: WebPortalLandingScreen.primaryBlue,
            backgroundColor: const Color(0xFFE7EEF8),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// SECURITY BANNER
// ============================================================

class _SecurityBanner extends StatelessWidget {
  const _SecurityBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 9,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FAF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD7F0E0),
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.verified_user_rounded,
            color: Color(0xFF239451),
            size: 17,
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Role-based access for authorized tourism offices',
              style: TextStyle(
                color: Color(0xFF397154),
                fontSize: 9,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// TRUST STRIP
// ============================================================

class _TrustStrip extends StatelessWidget {
  const _TrustStrip({
    required this.isMobile,
    required this.isSmallMobile,
  });

  final bool isMobile;
  final bool isSmallMobile;

  @override
  Widget build(BuildContext context) {
    final items = [
      const _TrustItem(
        icon: Icons.map_rounded,
        title: 'Destinations',
        subtitle: 'Tourism spots',
      ),
      const _TrustItem(
        icon: Icons.inventory_2_rounded,
        title: 'Packages',
        subtitle: 'Tour offerings',
      ),
      const _TrustItem(
        icon: Icons.receipt_long_rounded,
        title: 'Bookings',
        subtitle: 'Reservations',
      ),
      const _TrustItem(
        icon: Icons.badge_rounded,
        title: 'Drivers',
        subtitle: 'Tour partners',
      ),
    ];

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(
        isMobile ? 11 : 17,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.80),
        borderRadius: BorderRadius.circular(
          isMobile ? 18 : 20,
        ),
        border: Border.all(
          color: const Color(0xFFDDE8F5),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF153C72).withOpacity(0.045),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 700) {
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              gridDelegate:
                  const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 9,
                mainAxisSpacing: 9,
                childAspectRatio: 2.55,
              ),
              itemBuilder: (_, index) {
                return items[index];
              },
            );
          }

          return Row(
            children: [
              Expanded(child: items[0]),
              _VerticalDivider(),
              Expanded(child: items[1]),
              _VerticalDivider(),
              Expanded(child: items[2]),
              _VerticalDivider(),
              Expanded(child: items[3]),
            ],
          );
        },
      ),
    );
  }
}

// ============================================================
// TRUST ITEM
// ============================================================

class _TrustItem extends StatelessWidget {
  const _TrustItem({
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
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: const Color(0xFFE4ECF6),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              color: WebPortalLandingScreen.primaryBlue,
              size: 16,
            ),
          ),

          const SizedBox(width: 7),

          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WebPortalLandingScreen.ink,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: WebPortalLandingScreen.muted,
                    fontSize: 8.5,
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
// VERTICAL DIVIDER
// ============================================================

class _VerticalDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 38,
      margin: const EdgeInsets.symmetric(
        horizontal: 10,
      ),
      color: const Color(0xFFE2EAF4),
    );
  }
}

// ============================================================
// FOOTER
// ============================================================

class _FooterNote extends StatelessWidget {
  const _FooterNote({
    required this.isMobile,
  });

  final bool isMobile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 13 : 18,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.48),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFE2EAF3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: WebPortalLandingScreen.green,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              'One system. Many partners. Stronger Bulacan tourism.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: const Color(0xFF72839A),
                fontSize: isMobile ? 9.5 : 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// BACKGROUND
// ============================================================

class _BackgroundDecoration extends StatelessWidget {
  const _BackgroundDecoration();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(
          child: CustomPaint(
            painter: _BackgroundPainter(),
          ),
        ),

        Positioned(
          top: -170,
          right: -130,
          child: _SoftCircle(
            size: 420,
            color: const Color(0xFF5EA2FF),
          ),
        ),

        Positioned(
          bottom: -180,
          left: -150,
          child: _SoftCircle(
            size: 430,
            color: const Color(0xFF4ED19B),
          ),
        ),

        Positioned(
          top: 180,
          left: -80,
          child: _SoftCircle(
            size: 170,
            color: const Color(0xFFFFD45C),
            opacity: 0.045,
          ),
        ),
      ],
    );
  }
}

// ============================================================
// SOFT CIRCLE
// ============================================================

class _SoftCircle extends StatelessWidget {
  const _SoftCircle({
    required this.size,
    required this.color,
    this.opacity = 0.10,
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
              color: color.withOpacity(opacity * 0.65),
              blurRadius: 90,
              spreadRadius: 20,
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

class _BackgroundPainter extends CustomPainter {
  const _BackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFF8FBFF),
          Color(0xFFF0F7FF),
          Color(0xFFF7FBF8),
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
      background,
    );

    // --------------------------------------------------------
    // SUBTLE GRID
    // --------------------------------------------------------

    final gridPaint = Paint()
      ..color = const Color(0xFFBFD4EA).withOpacity(0.13)
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

    // --------------------------------------------------------
    // DECORATIVE TRAVEL ROUTE
    // --------------------------------------------------------

    final routePaint = Paint()
      ..color = const Color(0xFF1557D6).withOpacity(0.045)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final route = Path();

    route.moveTo(
      size.width * 0.02,
      size.height * 0.72,
    );

    route.cubicTo(
      size.width * 0.22,
      size.height * 0.56,
      size.width * 0.33,
      size.height * 0.82,
      size.width * 0.53,
      size.height * 0.64,
    );

    route.cubicTo(
      size.width * 0.70,
      size.height * 0.49,
      size.width * 0.79,
      size.height * 0.58,
      size.width * 1.02,
      size.height * 0.38,
    );

    canvas.drawPath(
      route,
      routePaint,
    );

    // --------------------------------------------------------
    // ROUTE DOTS
    // --------------------------------------------------------

    final dotPaint = Paint()
      ..color = const Color(0xFF39A447).withOpacity(0.09);

    final points = [
      Offset(
        size.width * 0.22,
        size.height * 0.67,
      ),
      Offset(
        size.width * 0.53,
        size.height * 0.64,
      ),
      Offset(
        size.width * 0.79,
        size.height * 0.53,
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