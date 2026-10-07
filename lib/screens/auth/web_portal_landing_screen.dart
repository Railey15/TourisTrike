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

  void _openTourismOfficeSignup(BuildContext context) {
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

          final page = _LandingPageContent(
            isDesktop: isDesktop,
            isTablet: isTablet,
            isMobile: isMobile,
            onLogin: () => _openLogin(context),
            onApply: () => _openTourismOfficeSignup(context),
          );

          return Stack(
            children: [
              const Positioned.fill(
                child: _LandingBackground(),
              ),
              SafeArea(
                child: SingleChildScrollView(
                  physics: isMobile
                      ? const BouncingScrollPhysics()
                      : const ClampingScrollPhysics(),
                  child: page,
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
// PAGE
// ============================================================

class _LandingPageContent extends StatelessWidget {
  const _LandingPageContent({
    required this.isDesktop,
    required this.isTablet,
    required this.isMobile,
    required this.onLogin,
    required this.onApply,
  });

  final bool isDesktop;
  final bool isTablet;
  final bool isMobile;
  final VoidCallback onLogin;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final horizontalPadding = isDesktop
        ? 46.0
        : isTablet
            ? 30.0
            : 18.0;

    final verticalPadding = isDesktop ? 20.0 : 16.0;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 1320,
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TopNavigation(
                isMobile: isMobile,
                onLogin: onLogin,
                onApply: onApply,
              ),

              SizedBox(
                height: isDesktop ? 24 : 28,
              ),

              if (isDesktop)
                _DesktopHero(
                  onApply: onApply,
                )
              else
                _ResponsiveHero(
                  onApply: onApply,
                ),

              SizedBox(
                height: isDesktop ? 18 : 24,
              ),

              const _BottomTrustBar(),

              if (isMobile) const SizedBox(height: 20),
            ],
          ),
        ),
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
    required this.onLogin,
    required this.onApply,
  });

  final bool isMobile;
  final VoidCallback onLogin;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    if (isMobile) {
      return Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: _Brand(),
              ),
              const SizedBox(width: 12),
              _SignInButton(
                onPressed: onLogin,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _ApplyButton(
              onPressed: onApply,
            ),
          ),
        ],
      );
    }

    return Row(
      children: [
        const Expanded(child: _Brand()),

        const SizedBox(width: 12),

        _ApplyButton(
          onPressed: onApply,
        ),

        const SizedBox(width: 12),

        _SignInButton(
          onPressed: onLogin,
        ),
      ],
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: const Color(0xFFDDE8F5),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF10213F).withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Image.network(
            WebPortalLandingScreen.logoUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) {
              return const Icon(
                Icons.electric_rickshaw_rounded,
                color: WebPortalLandingScreen.primaryBlue,
              );
            },
          ),
        ),

        const SizedBox(width: 11),

        const Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TourisTrike',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: WebPortalLandingScreen.ink,
                  fontSize: 18,
                  height: 1,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -0.4,
                ),
              ),
              SizedBox(height: 5),
              Text(
                'Tourism Administration Portal',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: WebPortalLandingScreen.muted,
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

class _SignInButton extends StatelessWidget {
  const _SignInButton({
    required this.onPressed,
    this.compact = false,
  });

  final VoidCallback onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: const Icon(
        Icons.login_rounded,
        size: 17,
      ),
      label: const Text('Sign In'),
      style: ElevatedButton.styleFrom(
        elevation: 0,
        backgroundColor: WebPortalLandingScreen.primaryBlue,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 15 : 19,
          vertical: 14,
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
  }
}

class _ApplyButton extends StatelessWidget {
  const _ApplyButton({
    required this.onPressed,
  });

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(
        Icons.account_balance_rounded,
        size: 17,
      ),
      label: const Text(
        'Apply as Tourism Office',
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF087B67),
        backgroundColor: Colors.white.withValues(alpha: 0.78),
        side: const BorderSide(
          color: Color(0xFFA7E4D3),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: 18,
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
  }
}

// ============================================================
// DESKTOP HERO
// ============================================================

class _DesktopHero extends StatelessWidget {
  const _DesktopHero({
    required this.onApply,
  });

  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 11,
          child: _HeroInformation(
            onApply: onApply,
          ),
        ),

        const SizedBox(width: 64),

        const Expanded(
          flex: 9,
          child: Align(
            alignment: Alignment.centerRight,
            child: _SystemFlowCard(),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// TABLET / MOBILE
// ============================================================

class _ResponsiveHero extends StatelessWidget {
  const _ResponsiveHero({
    required this.onApply,
  });

  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _HeroInformation(
          centered: true,
          onApply: onApply,
        ),

        const SizedBox(height: 32),

        const _SystemFlowCard(),
      ],
    );
  }
}

// ============================================================
// LEFT HERO
// ============================================================

class _HeroInformation extends StatelessWidget {
  const _HeroInformation({
    required this.onApply,
    this.centered = false,
  });

  final VoidCallback onApply;
  final bool centered;

  @override
  Widget build(BuildContext context) {
    final crossAxisAlignment = centered
        ? CrossAxisAlignment.center
        : CrossAxisAlignment.start;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        const _AdministrationBadge(),

        const SizedBox(height: 20),

        Text.rich(
          TextSpan(
            children: [
              const TextSpan(
                text: 'Manage Bulacan tourism\n',
              ),
              const TextSpan(
                text: 'operations',
                style: TextStyle(
                  color: WebPortalLandingScreen.primaryBlue,
                ),
              ),
              const TextSpan(
                text: ' from one\nsecure portal.',
              ),
            ],
          ),
          textAlign: centered ? TextAlign.center : TextAlign.left,
          style: const TextStyle(
            color: WebPortalLandingScreen.ink,
            fontSize: 52,
            height: 1.04,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.9,
          ),
        ),

        const SizedBox(height: 18),

        ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 610,
          ),
          child: Text(
            'A unified administration portal that helps Bulacan tourism offices coordinate local tourism services while maintaining clear provincial and municipal responsibilities.',
            textAlign: centered ? TextAlign.center : TextAlign.left,
            style: const TextStyle(
              color: WebPortalLandingScreen.muted,
              fontSize: 15.5,
              height: 1.55,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),

        const SizedBox(height: 27),

        _AccessCard(
          centered: centered,
        ),
      ],
    );
  }
}

class _AdministrationBadge extends StatelessWidget {
  const _AdministrationBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFDCE7F4),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_user_rounded,
            size: 15,
            color: WebPortalLandingScreen.green,
          ),
          SizedBox(width: 7),
          Text(
            'TOURISM ADMINISTRATION',
            style: TextStyle(
              color: Color(0xFF42617F),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.55,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// ACCESS CARD
// ============================================================

class _AccessCard extends StatelessWidget {
  const _AccessCard({
    required this.centered,
  });

  final bool centered;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 520,
      ),
      child: Container(
        padding: const EdgeInsets.all(17),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: const Color(0xFFDDE8F5),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF173B72).withValues(alpha: 0.045),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Built for Bulacan tourism offices',
              style: TextStyle(
                color: WebPortalLandingScreen.ink,
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),

            const SizedBox(height: 5),

            const Text(
              'Role-based workspaces keep provincial oversight and local operations organized.',
              style: TextStyle(
                color: WebPortalLandingScreen.muted,
                fontSize: 11.5,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),

            const SizedBox(height: 15),

            const Row(
              children: [
                Expanded(
                  child: _AccessType(
                    icon: Icons.account_balance_rounded,
                    title: 'Provincial Office',
                    description: 'Province-wide administration',
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _AccessType(
                    icon: Icons.location_city_rounded,
                    title: 'Local Tourism Office',
                    description: 'City or municipal operations',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessType extends StatelessWidget {
  const _AccessType({
    required this.icon,
    required this.title,
    required this.description,
  });

  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: const Color(0xFFE0E9F4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F1FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 17,
              color: WebPortalLandingScreen.primaryBlue,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: WebPortalLandingScreen.ink,
              fontSize: 11.5,
              fontWeight: FontWeight.w900,
            ),
          ),

          const SizedBox(height: 3),

          Text(
            description,
            style: const TextStyle(
              color: WebPortalLandingScreen.muted,
              fontSize: 9.5,
              height: 1.3,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// RIGHT SYSTEM FLOW
// ============================================================

class _SystemFlowCard extends StatelessWidget {
  const _SystemFlowCard();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: 525,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: Colors.white,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF153C72).withValues(alpha: 0.09),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(19),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: const Color(0xFFE0EAF5),
            ),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SystemFlowHeader(),

              SizedBox(height: 18),

              _SystemFlowHero(),

              SizedBox(height: 19),

              Text(
                'How the platform connects',
                style: TextStyle(
                  color: WebPortalLandingScreen.ink,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),

              SizedBox(height: 12),

              _Workflow(),

              SizedBox(height: 17),

              _PortalSecurityNote(),
            ],
          ),
        ),
      ),
    );
  }
}

class _SystemFlowHeader extends StatelessWidget {
  const _SystemFlowHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Image.network(
            WebPortalLandingScreen.logoUrl,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) {
              return const Icon(
                Icons.hub_rounded,
                color: WebPortalLandingScreen.primaryBlue,
              );
            },
          ),
        ),

        const SizedBox(width: 11),

        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'TourisTrike Administration',
                style: TextStyle(
                  color: WebPortalLandingScreen.ink,
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Connected tourism management',
                style: TextStyle(
                  color: WebPortalLandingScreen.muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        _SecureBadge(),
      ],
    );
  }
}

class _SecureBadge extends StatelessWidget {
  const _SecureBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFFD5E4FA),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 12,
            color: WebPortalLandingScreen.primaryBlue,
          ),
          SizedBox(width: 4),
          Text(
            'SECURE',
            style: TextStyle(
              color: WebPortalLandingScreen.primaryBlue,
              fontSize: 9,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// SYSTEM FLOW HERO
// ============================================================

class _SystemFlowHero extends StatelessWidget {
  const _SystemFlowHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF1557D6),
            Color(0xFF2677E4),
          ],
        ),
        borderRadius: BorderRadius.circular(17),
      ),
      child: const Row(
        children: [
          _FlowHeroIcon(),

          SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'One coordinated tourism platform',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Manage tourism operations through connected, role-based workspaces.',
                  style: TextStyle(
                    color: Color(0xFFDCE9FF),
                    fontSize: 10.5,
                    height: 1.4,
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

class _FlowHeroIcon extends StatelessWidget {
  const _FlowHeroIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(13),
      ),
      child: const Icon(
        Icons.account_tree_rounded,
        color: Colors.white,
        size: 23,
      ),
    );
  }
}

// ============================================================
// WORKFLOW
// ============================================================

class _Workflow extends StatelessWidget {
  const _Workflow();

  @override
  Widget build(BuildContext context) {
    return const Column(
      children: [
        _WorkflowStep(
          number: '01',
          icon: Icons.account_balance_rounded,
          title: 'Tourism offices manage operations',
          description:
              'Authorized offices maintain tourism information and services.',
        ),

        _WorkflowConnector(),

        _WorkflowStep(
          number: '02',
          icon: Icons.route_rounded,
          title: 'Tour services are coordinated',
          description:
              'Packages, bookings, destinations, and tour partners work together.',
        ),

        _WorkflowConnector(),

        _WorkflowStep(
          number: '03',
          icon: Icons.travel_explore_rounded,
          title: 'Tourists experience Bulacan',
          description:
              'Travel services are organized through one connected platform.',
        ),
      ],
    );
  }
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({
    required this.number,
    required this.icon,
    required this.title,
    required this.description,
  });

  final String number;
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 11,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFE0E9F4),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              size: 18,
              color: WebPortalLandingScreen.primaryBlue,
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
                    color: WebPortalLandingScreen.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),

                const SizedBox(height: 3),

                Text(
                  description,
                  style: const TextStyle(
                    color: WebPortalLandingScreen.muted,
                    fontSize: 9.5,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          Text(
            number,
            style: TextStyle(
              color:
                  WebPortalLandingScreen.primaryBlue.withValues(alpha: 0.55),
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkflowConnector extends StatelessWidget {
  const _WorkflowConnector();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 2,
      height: 10,
      color: const Color(0xFFD5E2F2),
    );
  }
}

// ============================================================
// SECURITY NOTE
// ============================================================

class _PortalSecurityNote extends StatelessWidget {
  const _PortalSecurityNote();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FAF4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFD5EFDF),
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.verified_user_rounded,
            size: 17,
            color: Color(0xFF249450),
          ),

          SizedBox(width: 8),

          Expanded(
            child: Text(
              'Role-based access helps keep tourism operations organized and controlled.',
              style: TextStyle(
                color: Color(0xFF397154),
                fontSize: 10.5,
                height: 1.35,
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
// BOTTOM TRUST BAR
// ============================================================

class _BottomTrustBar extends StatelessWidget {
  const _BottomTrustBar();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;

        if (compact) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: _bottomBarDecoration(),
            child: const Column(
              children: [
                _TrustStatement(
                  icon: Icons.shield_outlined,
                  title: 'Role-based access',
                  description: 'Access based on assigned responsibilities',
                ),
                SizedBox(height: 10),
                _TrustStatement(
                  icon: Icons.location_on_outlined,
                  title: 'Built for Bulacan',
                  description: 'Designed around provincial and local tourism',
                ),
              ],
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 13,
          ),
          decoration: _bottomBarDecoration(),
          child: const Row(
            children: [
              Expanded(
                child: _TrustStatement(
                  icon: Icons.shield_outlined,
                  title: 'Role-based administration',
                  description:
                      'Access aligned with tourism office responsibilities',
                ),
              ),

              _BottomDivider(),

              Expanded(
                child: _TrustStatement(
                  icon: Icons.account_tree_outlined,
                  title: 'Connected operations',
                  description:
                      'Provincial and local tourism offices in one platform',
                ),
              ),

              _BottomDivider(),

              Expanded(
                child: _TrustStatement(
                  icon: Icons.location_on_outlined,
                  title: 'Built for Bulacan',
                  description:
                      'Focused on coordinated local tourism management',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  BoxDecoration _bottomBarDecoration() {
    return BoxDecoration(
      color: Colors.white.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(
        color: const Color(0xFFDDE8F5),
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFF153C72).withValues(alpha: 0.035),
          blurRadius: 18,
          offset: const Offset(0, 7),
        ),
      ],
    );
  }
}

class _TrustStatement extends StatelessWidget {
  const _TrustStatement({
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
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFEDF4FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 18,
            color: WebPortalLandingScreen.primaryBlue,
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
                  color: WebPortalLandingScreen.ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                description,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: WebPortalLandingScreen.muted,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BottomDivider extends StatelessWidget {
  const _BottomDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 34,
      margin: const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      color: const Color(0xFFE1E9F3),
    );
  }
}

// ============================================================
// BACKGROUND
// ============================================================

class _LandingBackground extends StatelessWidget {
  const _LandingBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: const [
        Positioned.fill(
          child: CustomPaint(
            painter: _LandingBackgroundPainter(),
          ),
        ),

        Positioned(
          top: -170,
          right: -135,
          child: _GlowCircle(
            size: 420,
            color: Color(0xFF5EA2FF),
            opacity: 0.075,
          ),
        ),

        Positioned(
          bottom: -190,
          left: -155,
          child: _GlowCircle(
            size: 440,
            color: Color(0xFF4ED19B),
            opacity: 0.065,
          ),
        ),

        Positioned(
          top: 170,
          left: -90,
          child: _GlowCircle(
            size: 180,
            color: Color(0xFFFFD45C),
            opacity: 0.03,
          ),
        ),
      ],
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({
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
          color: color.withValues(alpha: opacity),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: opacity * 0.45),
              blurRadius: 100,
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

class _LandingBackgroundPainter extends CustomPainter {
  const _LandingBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final backgroundPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Color(0xFFF8FBFF),
          Color(0xFFF2F7FF),
          Color(0xFFF8FBF9),
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
      ..color = const Color(0xFFBFD4EA).withValues(alpha: 0.055)
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

    final routePaint = Paint()
      ..color =
          WebPortalLandingScreen.primaryBlue.withValues(alpha: 0.035)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4;

    final path = Path();

    path.moveTo(
      size.width * 0.02,
      size.height * 0.73,
    );

    path.cubicTo(
      size.width * 0.20,
      size.height * 0.56,
      size.width * 0.34,
      size.height * 0.82,
      size.width * 0.53,
      size.height * 0.64,
    );

    path.cubicTo(
      size.width * 0.70,
      size.height * 0.49,
      size.width * 0.80,
      size.height * 0.58,
      size.width * 1.02,
      size.height * 0.38,
    );

    canvas.drawPath(
      path,
      routePaint,
    );

    final dotPaint = Paint()
      ..color =
          WebPortalLandingScreen.green.withValues(alpha: 0.075);

    final dots = [
      Offset(
        size.width * 0.22,
        size.height * 0.68,
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

    for (final dot in dots) {
      canvas.drawCircle(
        dot,
        4.5,
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
