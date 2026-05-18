import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/auth/web_portal_login_screen.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_sidebar.dart';
import 'package:touristrike/widgets/app_bottom_nav_subtenant.dart';

class SubTenantAdminShell extends StatelessWidget {
  const SubTenantAdminShell({
    super.key,
    required this.currentIndex,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const [],
    this.floatingActionButton,
  });

  final int currentIndex;
  final String title;
  final String? subtitle;
  final Widget child;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  void _navigate(BuildContext context, int index) {
    AppBottomNavSubTenant.navigateToIndex(
      context,
      index,
      currentIndex: currentIndex,
    );
  }

  Future<void> _logout(BuildContext context) async {
    await Supabase.instance.client.auth.signOut();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const WebPortalLoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (Responsive.isMobile(context)) {
      return _MobileShell(
        currentIndex: currentIndex,
        title: title,
        actions: actions,
        floatingActionButton: floatingActionButton,
        onNavigate: (index) => _navigate(context, index),
        onLogout: () => _logout(context),
        child: child,
      );
    }

    final compactSidebar = Responsive.isTablet(context);

    return Scaffold(
      backgroundColor: SubTenantColors.background,
      floatingActionButton: floatingActionButton,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFEAF5FF), Color(0xFFF6FAFF), Color(0xFFEFFAF5)],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            children: [
              SubTenantSidebar(
                currentIndex: currentIndex,
                compact: compactSidebar,
                onDestinationSelected: (index) => _navigate(context, index),
                onLogout: () => _logout(context),
              ),
              Expanded(
                child: Column(
                  children: [
                    _DesktopHeader(
                      title: title,
                      subtitle: subtitle,
                      actions: actions,
                    ),
                    Expanded(child: child),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileShell extends StatelessWidget {
  const _MobileShell({
    required this.currentIndex,
    required this.title,
    required this.child,
    required this.onNavigate,
    required this.onLogout,
    this.actions = const [],
    this.floatingActionButton,
  });

  final int currentIndex;
  final String title;
  final Widget child;
  final ValueChanged<int> onNavigate;
  final VoidCallback onLogout;
  final List<Widget> actions;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SubTenantColors.background,
      drawer: SubTenantSidebar.drawer(
        currentIndex: currentIndex,
        onDestinationSelected: (index) {
          Navigator.maybePop(context);
          onNavigate(index);
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
              color: SubTenantColors.text,
              size: 24,
            ),
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: SubTenantColors.text,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
        actions: actions,
      ),
      body: child,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: AppBottomNavSubTenant(currentIndex: currentIndex),
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.title,
    required this.actions,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    return Container(
      height: 88,
      margin: const EdgeInsets.fromLTRB(0, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: PageTitleBar(
              title: title,
              subtitle: subtitle,
              actions: actions,
            ),
          ),
          const SizedBox(width: 14),
          if (desktop) ...[_HeaderSearch(), const SizedBox(width: 12)],
          Tooltip(
            message: 'Notifications',
            child: IconButton.filledTonal(
              onPressed: () {},
              icon: const Icon(Icons.notifications_none_rounded),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFEAF4FF),
                foregroundColor: SubTenantColors.blue,
              ),
            ),
          ),
          if (desktop) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 12, 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: SubTenantColors.line),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Color(0xFFEAF4FF),
                    child: Icon(
                      Icons.admin_panel_settings_rounded,
                      color: SubTenantColors.blue,
                      size: 18,
                    ),
                  ),
                  SizedBox(width: 9),
                  Text(
                    'City Admin',
                    style: TextStyle(
                      color: SubTenantColors.text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeaderSearch extends StatelessWidget {
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
          border: Border.all(color: SubTenantColors.line),
        ),
        child: const Row(
          children: [
            Icon(Icons.search_rounded, color: SubTenantColors.lightMuted),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Search workspace...',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: SubTenantColors.lightMuted,
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
