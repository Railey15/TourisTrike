import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/city_tenants_screen.dart';
import 'package:touristrike/screens/admin/city_tenant_details_screen.dart';
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
import 'package:touristrike/screens/admin/widgets/admin_header_tools.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_sidebar.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';
import 'package:touristrike/screens/auth/web_portal_login_screen.dart';

class ProvincialAdminPortalScreen extends StatefulWidget {
  const ProvincialAdminPortalScreen({
    super.key,
    this.initialDestination = ProvincialAdminDestination.dashboard,
    @visibleForTesting this.pageBuilder,
    @visibleForTesting this.profileOverride,
  });

  final ProvincialAdminDestination initialDestination;
  final Widget Function(ProvincialAdminDestination destination)? pageBuilder;
  final ProvincialAdminProfile? profileOverride;

  static const destinations = <ProvincialAdminDestination>[
    ProvincialAdminDestination.dashboard,
    ProvincialAdminDestination.cityTenants,
    ProvincialAdminDestination.packages,
    ProvincialAdminDestination.tourismData,
    ProvincialAdminDestination.reports,
    ProvincialAdminDestination.feedback,
    ProvincialAdminDestination.settings,
  ];

  static ProvincialAdminDestination normalize(
    ProvincialAdminDestination destination,
  ) {
    return destination == ProvincialAdminDestination.registrations
        ? ProvincialAdminDestination.cityTenants
        : destination;
  }

  static Widget pageForDestination(ProvincialAdminDestination destination) {
    return switch (normalize(destination)) {
      ProvincialAdminDestination.cityTenants => const CityTenantsScreen(),
      ProvincialAdminDestination.packages => const ProvincePackagesScreen(),
      ProvincialAdminDestination.tourismData => const ProvincialSpotsScreen(),
      ProvincialAdminDestination.reports => const ProvinceReportsScreen(),
      ProvincialAdminDestination.feedback => const FeedbackTrendsScreen(),
      ProvincialAdminDestination.settings =>
        const ProvincialAdminSettingsScreen(),
      _ => const ProvincialAdminDashboardScreen(),
    };
  }

  @override
  State<ProvincialAdminPortalScreen> createState() =>
      _ProvincialAdminPortalScreenState();
}

class _ProvincialAdminPortalScreenState
    extends State<ProvincialAdminPortalScreen> {
  late ProvincialAdminDestination _current;
  final Map<ProvincialAdminDestination, Widget> _pages = {};
  final Map<ProvincialAdminDestination, _ProvincialAdminTabChrome> _chrome = {};

  @override
  void initState() {
    super.initState();
    _current = ProvincialAdminPortalScreen.normalize(widget.initialDestination);
    _pages[_current] = _buildPage(_current);
  }

  Widget _buildPage(ProvincialAdminDestination destination) {
    return widget.pageBuilder?.call(destination) ??
        ProvincialAdminPortalScreen.pageForDestination(destination);
  }

  void _selectDestination(ProvincialAdminDestination destination) {
    final normalized = ProvincialAdminPortalScreen.normalize(destination);
    if (normalized == _current) return;

    setState(() {
      _current = normalized;
      _pages[normalized] ??= _buildPage(normalized);
    });
  }

  void _registerChrome(_ProvincialAdminTabChrome chrome) {
    if (!mounted) return;

    final destination = ProvincialAdminPortalScreen.normalize(
      chrome.destination,
    );
    final previous = _chrome[destination];
    _chrome[destination] = chrome;

    if (destination == _current && previous?.signature != chrome.signature) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome =
        _chrome[_current] ?? _ProvincialAdminTabChrome.fallbackFor(_current);
    final currentIndex = ProvincialAdminPortalScreen.destinations.indexOf(
      _current,
    );

    return _ProvincialAdminPortalScope(
      current: _current,
      onSelectDestination: _selectDestination,
      onRegisterChrome: _registerChrome,
      child: ProvincialAdminShell._portal(
        current: _current,
        title: chrome.title,
        subtitle: chrome.subtitle,
        actions: chrome.actions,
        floatingActionButton: chrome.floatingActionButton,
        profileOverride: widget.profileOverride,
        child: IndexedStack(
          index: currentIndex,
          sizing: StackFit.expand,
          children: ProvincialAdminPortalScreen.destinations
              .map(
                (destination) => KeyedSubtree(
                  key: PageStorageKey<String>(
                    'provincial-admin-${destination.name}',
                  ),
                  child: _pages[destination] ?? const SizedBox.shrink(),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _ProvincialAdminTabChrome {
  const _ProvincialAdminTabChrome({
    required this.destination,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.floatingActionButton,
  });

  final ProvincialAdminDestination destination;
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  Object get signature => Object.hash(
    title,
    subtitle,
    actions.length,
    Object.hashAll(actions.map((action) => action.runtimeType)),
    floatingActionButton?.runtimeType,
  );

  static _ProvincialAdminTabChrome fallbackFor(
    ProvincialAdminDestination destination,
  ) {
    return switch (ProvincialAdminPortalScreen.normalize(destination)) {
      ProvincialAdminDestination.cityTenants => const _ProvincialAdminTabChrome(
        destination: ProvincialAdminDestination.cityTenants,
        title: 'City Tenants',
        subtitle:
            'Manage tourism office accounts and review registration requests.',
      ),
      ProvincialAdminDestination.packages => const _ProvincialAdminTabChrome(
        destination: ProvincialAdminDestination.packages,
        title: 'Packages',
        subtitle: 'Monitor packages from every city and municipality.',
      ),
      ProvincialAdminDestination.tourismData => const _ProvincialAdminTabChrome(
        destination: ProvincialAdminDestination.tourismData,
        title: 'Tourism Data',
        subtitle:
            'Review, verify, and manage tourist spots submitted by city tenants.',
      ),
      ProvincialAdminDestination.reports => const _ProvincialAdminTabChrome(
        destination: ProvincialAdminDestination.reports,
        title: 'Provincial Reports',
        subtitle:
            'Official province-wide tourism reports and performance records.',
      ),
      ProvincialAdminDestination.feedback => const _ProvincialAdminTabChrome(
        destination: ProvincialAdminDestination.feedback,
        title: 'Feedback',
        subtitle: 'Review tourist feedback trends and low-rated experiences.',
      ),
      ProvincialAdminDestination.settings => const _ProvincialAdminTabChrome(
        destination: ProvincialAdminDestination.settings,
        title: 'Settings',
        subtitle:
            'Manage provincial office information, policies, notifications, and account security.',
      ),
      _ => const _ProvincialAdminTabChrome(
        destination: ProvincialAdminDestination.dashboard,
        title: 'Dashboard',
        subtitle: 'Province-wide tourism overview for Bulacan.',
      ),
    };
  }
}

class _ProvincialAdminPortalScope extends InheritedWidget {
  const _ProvincialAdminPortalScope({
    required this.current,
    required this.onSelectDestination,
    required this.onRegisterChrome,
    required super.child,
  });

  final ProvincialAdminDestination current;
  final ValueChanged<ProvincialAdminDestination> onSelectDestination;
  final ValueChanged<_ProvincialAdminTabChrome> onRegisterChrome;

  static _ProvincialAdminPortalScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_ProvincialAdminPortalScope>();
  }

  @override
  bool updateShouldNotify(_ProvincialAdminPortalScope oldWidget) {
    return current != oldWidget.current;
  }
}

class ProvincialAdminShell extends StatefulWidget {
  const ProvincialAdminShell({
    super.key,
    required this.current,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.floatingActionButton,
  }) : _isPortalRoot = false,
       _profileOverride = null;

  const ProvincialAdminShell._portal({
    required this.current,
    required this.title,
    required this.child,
    required ProvincialAdminProfile? profileOverride,
    this.subtitle,
    this.actions = const [],
    this.floatingActionButton,
  }) : _isPortalRoot = true,
       _profileOverride = profileOverride;

  final ProvincialAdminDestination current;
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final bool _isPortalRoot;
  final ProvincialAdminProfile? _profileOverride;

  static void navigateTo(
    BuildContext context,
    ProvincialAdminDestination destination, {
    ProvincialAdminDestination? current,
  }) {
    final normalized = ProvincialAdminPortalScreen.normalize(destination);
    final portal = _ProvincialAdminPortalScope.maybeOf(context);
    if (portal != null) {
      portal.onSelectDestination(normalized);
      return;
    }

    if (current != null &&
        ProvincialAdminPortalScreen.normalize(current) == normalized) {
      return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) =>
            ProvincialAdminPortalScreen(initialDestination: normalized),
        transitionsBuilder: (_, _, _, child) => child,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  State<ProvincialAdminShell> createState() => _ProvincialAdminShellState();
}

class _ProvincialAdminShellState extends State<ProvincialAdminShell> {
  final ProvincialAdminService _service = ProvincialAdminService();

  Future<ProvincialAdminProfile>? _profileFuture;
  bool _collapsed = false;

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WebPortalLoginScreen()),
      (_) => false,
    );
  }

  void _navigate(ProvincialAdminDestination destination) {
    ProvincialAdminShell.navigateTo(
      context,
      destination,
      current: widget.current,
    );
  }

  void _openTenant(String tenantId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CityTenantDetailsScreen(tenantId: tenantId),
      ),
    );
  }

  void _openSpots(String query) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProvincialSpotsScreen(initialSearch: query),
      ),
    );
  }

  void _openPackages(String query) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProvincePackagesScreen(initialSearch: query),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final portal = _ProvincialAdminPortalScope.maybeOf(context);
    if (!widget._isPortalRoot && portal != null) {
      final chrome = _ProvincialAdminTabChrome(
        destination: widget.current,
        title: widget.title,
        subtitle: widget.subtitle,
        actions: widget.actions,
        floatingActionButton: widget.floatingActionButton,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        portal.onRegisterChrome(chrome);
      });
      return widget.child;
    }

    _profileFuture ??= widget._profileOverride == null
        ? _service.loadCurrentAdminProfile()
        : Future<ProvincialAdminProfile>.value(widget._profileOverride);

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
            actions: [
              AdminGlobalSearchButton(
                compact: true,
                onOpenTenant: _openTenant,
                onOpenSpots: _openSpots,
                onOpenPackages: _openPackages,
              ),
              AdminNotificationButton(
                userId: profile.id,
                onNavigate: _navigate,
              ),
              ...widget.actions,
            ],
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
                            search: AdminGlobalSearchButton(
                              onOpenTenant: _openTenant,
                              onOpenSpots: _openSpots,
                              onOpenPackages: _openPackages,
                            ),
                            notifications: AdminNotificationButton(
                              userId: profile.id,
                              onNavigate: _navigate,
                            ),
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
    required this.search,
    required this.notifications,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final ProvincialAdminProfile profile;
  final List<Widget> actions;
  final Widget search;
  final Widget notifications;

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
          if (desktop) ...[search, const SizedBox(width: 12)],
          notifications,
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
