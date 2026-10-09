import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_models.dart';
import 'package:touristrike/screens/main_tenant/city_tenants_screen.dart';
import 'package:touristrike/screens/main_tenant/city_tenant_details_screen.dart';
import 'package:touristrike/screens/main_tenant/feedback_trends_screen.dart';
import 'package:touristrike/screens/main_tenant/province_packages_screen.dart';
import 'package:touristrike/screens/main_tenant/province_reports_screen.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_dashboard_screen.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_nav.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_service.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_settings_screen.dart';
import 'package:touristrike/screens/main_tenant/provincial_spots_screen.dart';
import 'package:touristrike/screens/main_tenant/widgets/main_tenant_common.dart';
import 'package:touristrike/screens/main_tenant/widgets/main_tenant_empty_state.dart';
import 'package:touristrike/screens/main_tenant/widgets/main_tenant_header_tools.dart';
import 'package:touristrike/screens/main_tenant/widgets/main_tenant_sidebar.dart';
import 'package:touristrike/screens/main_tenant/widgets/main_tenant_style.dart';
import 'package:touristrike/screens/auth/web_portal_login_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_payment_disputes_screen.dart';

class MainTenantPortalScreen extends StatefulWidget {
  const MainTenantPortalScreen({
    super.key,
    this.initialDestination = MainTenantDestination.dashboard,
    @visibleForTesting this.pageBuilder,
    @visibleForTesting this.profileOverride,
    this.initialCaseId,
  });

  final MainTenantDestination initialDestination;
  final Widget Function(MainTenantDestination destination)? pageBuilder;
  final MainTenantProfile? profileOverride;
  final String? initialCaseId;

  static const destinations = <MainTenantDestination>[
    MainTenantDestination.dashboard,
    MainTenantDestination.cityTenants,
    MainTenantDestination.packages,
    MainTenantDestination.tourismData,
    MainTenantDestination.reports,
    MainTenantDestination.disputes,
    MainTenantDestination.feedback,
    MainTenantDestination.settings,
  ];

  static MainTenantDestination normalize(MainTenantDestination destination) {
    return destination == MainTenantDestination.registrations
        ? MainTenantDestination.cityTenants
        : destination;
  }

  static Widget pageForDestination(
    MainTenantDestination destination, {
    String? initialCaseId,
  }) {
    return switch (normalize(destination)) {
      MainTenantDestination.cityTenants => const CityTenantsScreen(),
      MainTenantDestination.packages => const ProvincePackagesScreen(),
      MainTenantDestination.tourismData => const ProvincialSpotsScreen(),
      MainTenantDestination.reports => const ProvinceReportsScreen(),
      MainTenantDestination.disputes => SubTenantPaymentDisputesScreen(
        initialCaseId: initialCaseId,
        suspensionCasesOnly: true,
        shellBuilder: (context, child) => MainTenantShell(
          current: MainTenantDestination.disputes,
          title: 'Disputes & Cases',
          subtitle:
              'Review province-wide booking suspension cases and appeals.',
          child: child,
        ),
      ),
      MainTenantDestination.feedback => const FeedbackTrendsScreen(),
      MainTenantDestination.settings => const MainTenantSettingsScreen(),
      _ => const MainTenantDashboardScreen(),
    };
  }

  @override
  State<MainTenantPortalScreen> createState() => _MainTenantPortalScreenState();
}

class _MainTenantPortalScreenState extends State<MainTenantPortalScreen> {
  late MainTenantDestination _current;
  final Map<MainTenantDestination, Widget> _pages = {};
  final Map<MainTenantDestination, _MainTenantTabChrome> _chrome = {};

  @override
  void initState() {
    super.initState();
    _current = MainTenantPortalScreen.normalize(widget.initialDestination);
    _pages[_current] = _buildPage(_current);
  }

  Widget _buildPage(MainTenantDestination destination) {
    return widget.pageBuilder?.call(destination) ??
        MainTenantPortalScreen.pageForDestination(
          destination,
          initialCaseId: destination == MainTenantDestination.disputes
              ? widget.initialCaseId
              : null,
        );
  }

  void _selectDestination(MainTenantDestination destination) {
    final normalized = MainTenantPortalScreen.normalize(destination);
    if (normalized == _current) return;

    setState(() {
      _current = normalized;
      _pages[normalized] ??= _buildPage(normalized);
    });
  }

  void _registerChrome(_MainTenantTabChrome chrome) {
    if (!mounted) return;

    final destination = MainTenantPortalScreen.normalize(chrome.destination);
    final previous = _chrome[destination];
    _chrome[destination] = chrome;

    if (destination == _current && previous?.signature != chrome.signature) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final chrome =
        _chrome[_current] ?? _MainTenantTabChrome.fallbackFor(_current);
    final currentIndex = MainTenantPortalScreen.destinations.indexOf(_current);

    return _MainTenantPortalScope(
      current: _current,
      onSelectDestination: _selectDestination,
      onRegisterChrome: _registerChrome,
      child: MainTenantShell._portal(
        current: _current,
        title: chrome.title,
        subtitle: chrome.subtitle,
        actions: chrome.actions,
        floatingActionButton: chrome.floatingActionButton,
        profileOverride: widget.profileOverride,
        child: IndexedStack(
          index: currentIndex,
          sizing: StackFit.expand,
          children: MainTenantPortalScreen.destinations
              .map(
                (destination) => KeyedSubtree(
                  key: PageStorageKey<String>(
                    'main-tenant-${destination.name}',
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

class _MainTenantTabChrome {
  const _MainTenantTabChrome({
    required this.destination,
    required this.title,
    required this.subtitle,
    this.actions = const [],
    this.floatingActionButton,
  });

  final MainTenantDestination destination;
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

  static _MainTenantTabChrome fallbackFor(MainTenantDestination destination) {
    return switch (MainTenantPortalScreen.normalize(destination)) {
      MainTenantDestination.cityTenants => const _MainTenantTabChrome(
        destination: MainTenantDestination.cityTenants,
        title: 'City/Municipal Administrators',
        subtitle:
            'Manage tourism office accounts and review registration requests.',
      ),
      MainTenantDestination.packages => const _MainTenantTabChrome(
        destination: MainTenantDestination.packages,
        title: 'Packages',
        subtitle: 'Monitor packages from every city and municipality.',
      ),
      MainTenantDestination.tourismData => const _MainTenantTabChrome(
        destination: MainTenantDestination.tourismData,
        title: 'Tourism Data',
        subtitle:
            'Review, verify, and manage tourist spots submitted by city tenants.',
      ),
      MainTenantDestination.reports => const _MainTenantTabChrome(
        destination: MainTenantDestination.reports,
        title: 'Provincial Reports',
        subtitle:
            'Official province-wide tourism reports and performance records.',
      ),
      MainTenantDestination.feedback => const _MainTenantTabChrome(
        destination: MainTenantDestination.feedback,
        title: 'Feedback',
        subtitle: 'Review tourist feedback trends and low-rated experiences.',
      ),
      MainTenantDestination.disputes => const _MainTenantTabChrome(
        destination: MainTenantDestination.disputes,
        title: 'Disputes & Cases',
        subtitle: 'Review province-wide booking suspension cases and appeals.',
      ),
      MainTenantDestination.settings => const _MainTenantTabChrome(
        destination: MainTenantDestination.settings,
        title: 'Settings',
        subtitle:
            'Manage provincial office information, policies, notifications, and account security.',
      ),
      _ => const _MainTenantTabChrome(
        destination: MainTenantDestination.dashboard,
        title: 'Dashboard',
        subtitle: 'Province-wide tourism overview for Bulacan.',
      ),
    };
  }
}

class _MainTenantPortalScope extends InheritedWidget {
  const _MainTenantPortalScope({
    required this.current,
    required this.onSelectDestination,
    required this.onRegisterChrome,
    required super.child,
  });

  final MainTenantDestination current;
  final ValueChanged<MainTenantDestination> onSelectDestination;
  final ValueChanged<_MainTenantTabChrome> onRegisterChrome;

  static _MainTenantPortalScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<_MainTenantPortalScope>();
  }

  @override
  bool updateShouldNotify(_MainTenantPortalScope oldWidget) {
    return current != oldWidget.current;
  }
}

class MainTenantShell extends StatefulWidget {
  const MainTenantShell({
    super.key,
    required this.current,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.floatingActionButton,
  }) : _isPortalRoot = false,
       _profileOverride = null;

  const MainTenantShell._portal({
    required this.current,
    required this.title,
    required this.child,
    required MainTenantProfile? profileOverride,
    this.subtitle,
    this.actions = const [],
    this.floatingActionButton,
  }) : _isPortalRoot = true,
       _profileOverride = profileOverride;

  final MainTenantDestination current;
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final bool _isPortalRoot;
  final MainTenantProfile? _profileOverride;

  static void navigateTo(
    BuildContext context,
    MainTenantDestination destination, {
    MainTenantDestination? current,
  }) {
    final normalized = MainTenantPortalScreen.normalize(destination);
    final portal = _MainTenantPortalScope.maybeOf(context);
    if (portal != null) {
      portal.onSelectDestination(normalized);
      return;
    }

    if (current != null &&
        MainTenantPortalScreen.normalize(current) == normalized) {
      return;
    }

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        pageBuilder: (_, _, _) =>
            MainTenantPortalScreen(initialDestination: normalized),
        transitionsBuilder: (_, _, _, child) => child,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: Duration.zero,
      ),
    );
  }

  @override
  State<MainTenantShell> createState() => _MainTenantShellState();
}

class _MainTenantShellState extends State<MainTenantShell> {
  final MainTenantService _service = MainTenantService();

  Future<MainTenantProfile>? _profileFuture;
  bool _collapsed = false;

  Future<void> _logout() async {
    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WebPortalLoginScreen()),
      (_) => false,
    );
  }

  void _navigate(MainTenantDestination destination) {
    MainTenantShell.navigateTo(context, destination, current: widget.current);
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

  void _openSuspensionCase(String caseId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MainTenantPortalScreen(
          initialDestination: MainTenantDestination.disputes,
          initialCaseId: caseId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final portal = _MainTenantPortalScope.maybeOf(context);
    if (!widget._isPortalRoot && portal != null) {
      final chrome = _MainTenantTabChrome(
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
        ? _service.loadCurrentMainTenantProfile()
        : Future<MainTenantProfile>.value(widget._profileOverride);

    return FutureBuilder<MainTenantProfile>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: MainTenantColors.background,
            body: MainTenantLoadingView(),
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
              MainTenantGlobalSearchButton(
                compact: true,
                onOpenTenant: _openTenant,
                onOpenSpots: _openSpots,
                onOpenPackages: _openPackages,
              ),
              MainTenantNotificationButton(
                userId: profile.id,
                onNavigate: _navigate,
                onOpenCase: _openSuspensionCase,
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
          backgroundColor: MainTenantColors.background,
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
                    MainTenantSidebar(
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
                            search: MainTenantGlobalSearchButton(
                              onOpenTenant: _openTenant,
                              onOpenSpots: _openSpots,
                              onOpenPackages: _openPackages,
                            ),
                            notifications: MainTenantNotificationButton(
                              userId: profile.id,
                              onNavigate: _navigate,
                              onOpenCase: _openSuspensionCase,
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

  final MainTenantDestination current;
  final String title;
  final MainTenantProfile profile;
  final Widget child;
  final ValueChanged<MainTenantDestination> onNavigate;
  final VoidCallback onLogout;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MainTenantColors.background,
      drawer: MainTenantSidebar.drawer(
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
              color: MainTenantColors.text,
              size: 24,
            ),
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: MainTenantColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: [ResponsiveAppBarActions(children: actions)],
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
  final MainTenantProfile profile;
  final List<Widget> actions;
  final Widget search;
  final Widget notifications;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use the space left after the sidebar, not the global viewport width.
        // At 1024px the expanded sidebar leaves too little room for the full
        // search/profile cluster even though the viewport is "desktop" sized.
        final showSearch = constraints.maxWidth >= 760;
        final showProfile = constraints.maxWidth >= 980;

        return Container(
          height: 88,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            borderRadius: BorderRadius.circular(26),
            border: Border.all(color: Colors.white),
            boxShadow: [mainTenantShadow()],
          ),
          child: Row(
            children: [
              Expanded(
                child: _HeaderTitle(title: title, subtitle: subtitle),
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(width: 14),
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: actions,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 14),
              if (showSearch) ...[search, const SizedBox(width: 12)],
              notifications,
              if (showProfile) ...[
                const SizedBox(width: 10),
                _ProfileChip(profile: profile),
              ],
            ],
          ),
        );
      },
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
            color: MainTenantColors.text,
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
              color: MainTenantColors.muted,
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

  final MainTenantProfile profile;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: MainTenantColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFFEAF4FF),
              child: Icon(
                Icons.account_balance_rounded,
                color: MainTenantColors.blue,
                size: 18,
              ),
            ),
            const SizedBox(width: 9),
            Flexible(
              child: Text(
                profile.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: MainTenantColors.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
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
      backgroundColor: MainTenantColors.background,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: MainTenantEmptyState(
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
