import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/city_tenants_screen.dart';
import 'package:touristrike/screens/admin/feedback_trends_screen.dart';
import 'package:touristrike/screens/admin/province_packages_screen.dart';
import 'package:touristrike/screens/admin/province_reports_screen.dart';
import 'package:touristrike/screens/admin/provincial_admin_dashboard_screen.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/provincial_admin_settings_screen.dart';
import 'package:touristrike/screens/admin/provincial_spots_screen.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/admin_empty_state.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_sidebar.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';
import 'package:touristrike/screens/auth/web_portal_login_screen.dart';

class ProvincialAdminShell extends StatefulWidget {
  const ProvincialAdminShell({
    super.key,
    required this.current,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.floatingActionButton,
  });

  final ProvincialAdminDestination current;
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  State<ProvincialAdminShell> createState() => _ProvincialAdminShellState();
}

class _ProvincialAdminShellState extends State<ProvincialAdminShell> {
  final ProvincialAdminService _service = ProvincialAdminService();

  late Future<ProvincialAdminProfile> _profileFuture;
  bool _collapsed = false;

  @override
  void initState() {
    super.initState();
    _profileFuture = _service.loadCurrentAdminProfile();
  }

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WebPortalLoginScreen()),
      (_) => false,
    );
  }

  void _navigate(ProvincialAdminDestination destination) {
    if (destination == widget.current) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => _pageForDestination(destination)),
    );
  }

  Widget _pageForDestination(ProvincialAdminDestination destination) {
    switch (destination) {
      case ProvincialAdminDestination.dashboard:
        return const ProvincialAdminDashboardScreen();
      case ProvincialAdminDestination.cityTenants:
        return const CityTenantsScreen();
      case ProvincialAdminDestination.registrations:
        return const CityTenantsScreen();
      case ProvincialAdminDestination.packages:
        return const ProvincePackagesScreen();
      case ProvincialAdminDestination.tourismData:
        return const ProvincialSpotsScreen();
      case ProvincialAdminDestination.reports:
        return const ProvinceReportsScreen();
      case ProvincialAdminDestination.feedback:
        return const FeedbackTrendsScreen();
      case ProvincialAdminDestination.settings:
        return const ProvincialAdminSettingsScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProvincialAdminProfile>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: ProvincialAdminColors.background,
            body: AdminLoadingView(),
          );
        }

        if (snapshot.hasError) {
          return _UnauthorizedScaffold(
            message: snapshot.error.toString(),
            onLogout: _logout,
          );
        }

        final profile = snapshot.data!;

        if (Responsive.isMobile(context)) {
          return _MobileShell(
            current: widget.current,
            title: widget.title,
            profile: profile,
            actions: widget.actions,
            floatingActionButton: widget.floatingActionButton,
            onNavigate: _navigate,
            onLogout: _logout,
            child: widget.child,
          );
        }

        final desktop = Responsive.isDesktop(context);
        final compact = Responsive.isTablet(context) || _collapsed;

        return Scaffold(
          backgroundColor: ProvincialAdminColors.background,
          floatingActionButton: widget.floatingActionButton,
          body: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFEAF5FF),
                  Color(0xFFF6FAFF),
                  Color(0xFFEFFAF5),
                ],
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.all(desktop ? 12 : 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProvincialAdminSidebar(
                      current: widget.current,
                      compact: compact,
                      onToggleCompact: desktop
                          ? () => setState(() => _collapsed = !_collapsed)
                          : null,
                      onDestinationSelected: _navigate,
                      onLogout: _logout,
                    ),
                    SizedBox(width: desktop ? 22 : 14),
                    Expanded(
                      child: Column(
                        children: [
                          _DesktopHeader(
                            title: widget.title,
                            subtitle: widget.subtitle,
                            profile: profile,
                            actions: widget.actions,
                          ),
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(28),
                              child: SizedBox(
                                width: double.infinity,
                                child: widget.child,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.current,
    required this.title,
    required this.profile,
    required this.child,
    required this.onNavigate,
    required this.onLogout,
    this.actions = const [],
    this.floatingActionButton,
  });

  final ProvincialAdminDestination current;
  final String title;
  final ProvincialAdminProfile profile;
  final Widget child;
  final ValueChanged<ProvincialAdminDestination> onNavigate;
  final VoidCallback onLogout;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProvincialAdminColors.background,
      drawer: ProvincialAdminSidebar.drawer(
        current: current,
        onDestinationSelected: (destination) {
          Navigator.maybePop(context);
          onNavigate(destination);
        },
        onLogout: onLogout,
      ),
      appBar: AppBar(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        leading: Builder(
          builder: (context) => IconButton(
            onPressed: () => Scaffold.of(context).openDrawer(),
            icon: const Icon(
              Icons.menu_rounded,
              color: ProvincialAdminColors.text,
              size: 24,
            ),
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ProvincialAdminColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: actions,
      ),
      body: child,
      floatingActionButton: floatingActionButton,
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.title,
    required this.profile,
    required this.actions,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final ProvincialAdminProfile profile;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    return Container(
      height: 88,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white),
        boxShadow: [provincialAdminShadow()],
      ),
      child: Row(
        children: [
          Expanded(
            child: _HeaderTitle(title: title, subtitle: subtitle),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: 14),
            Flexible(
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 10,
                runSpacing: 8,
                children: actions,
              ),
            ),
          ],
          const SizedBox(width: 14),
          if (desktop) ...[const _HeaderSearch(), const SizedBox(width: 12)],
          Tooltip(
            message: 'Notifications',
            child: IconButton.filledTonal(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFEAF4FF),
                foregroundColor: ProvincialAdminColors.blue,
              ),
            ),
          ),
          if (desktop) ...[
            const SizedBox(width: 10),
            _ProfileChip(profile: profile),
          ],
        ],
      ),
    );
  }
}

class _HeaderTitle extends StatelessWidget {
  const _HeaderTitle({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final compact = !Responsive.isDesktop(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ProvincialAdminColors.text,
            fontSize: compact ? 20 : 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ProvincialAdminColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _HeaderSearch extends StatelessWidget {
  const _HeaderSearch();

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 330, minWidth: 220),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: ProvincialAdminColors.line),
        ),
        child: const Row(
          children: [
            Icon(Icons.search_rounded, color: ProvincialAdminColors.lightMuted),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Search province data...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: ProvincialAdminColors.lightMuted,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileChip extends StatelessWidget {
  const _ProfileChip({required this.profile});

  final ProvincialAdminProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: Color(0xFFEAF4FF),
            child: Icon(
              Icons.account_balance_rounded,
              color: ProvincialAdminColors.blue,
              size: 18,
            ),
          ),
          const SizedBox(width: 9),
          Text(
            profile.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ProvincialAdminColors.text,
              fontSize: 12.5,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnauthorizedScaffold extends StatelessWidget {
  const _UnauthorizedScaffold({required this.message, required this.onLogout});

  final String message;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ProvincialAdminColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AdminEmptyState(
            icon: Icons.lock_outline_rounded,
            title: 'Unauthorized',
            message: message,
            actionLabel: 'Back to Login',
            onAction: onLogout,
          ),
        ),
      ),
    );
  }
}
