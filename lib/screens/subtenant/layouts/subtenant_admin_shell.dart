import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/auth/web_portal_login_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_workspace_search.dart';
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
      return _SubTenantScopeActivation(
        scope: currentIndex,
        child: _MobileShell(
          currentIndex: currentIndex,
          title: title,
          actions: actions,
          floatingActionButton: floatingActionButton,
          onNavigate: (index) => _navigate(context, index),
          onLogout: () => _logout(context),
          child: child,
        ),
      );
    }

    final compactSidebar = Responsive.isTablet(context);

    return _SubTenantScopeActivation(
      scope: currentIndex,
      child: Scaffold(
        backgroundColor: SubTenantColors.background,
        floatingActionButton: floatingActionButton,
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFE8F4FF), Color(0xFFF7FBFF), Color(0xFFEFFAF4)],
            ),
          ),
          child: Stack(
            children: [
              const Positioned(
                top: -90,
                right: -70,
                child: _ShellGlow(size: 260, color: Color(0xFFBFE3FF)),
              ),
              const Positioned(
                bottom: -120,
                left: 260,
                child: _ShellGlow(size: 300, color: Color(0xFFCFF5DC)),
              ),
              SafeArea(
                bottom: false,
                child: Row(
                  children: [
                    SubTenantSidebar(
                      currentIndex: currentIndex,
                      compact: compactSidebar,
                      onDestinationSelected: (index) =>
                          _navigate(context, index),
                      onLogout: () => _logout(context),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(
                          compactSidebar ? 12 : 16,
                          12,
                          16,
                          0,
                        ),
                        child: Column(
                          children: [
                            _DesktopHeader(
                              currentIndex: currentIndex,
                              title: title,
                              subtitle: subtitle,
                              actions: actions,
                            ),
                            const SizedBox(height: 14),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(28),
                                ),
                                child: child,
                              ),
                            ),
                          ],
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
    );
  }
}

class _SubTenantScopeActivation extends StatefulWidget {
  const _SubTenantScopeActivation({required this.scope, required this.child});

  final int scope;
  final Widget child;

  @override
  State<_SubTenantScopeActivation> createState() =>
      _SubTenantScopeActivationState();
}

class _SubTenantScopeActivationState extends State<_SubTenantScopeActivation> {
  @override
  void initState() {
    super.initState();
    SubTenantWorkspaceSearchController.instance.setActiveScope(widget.scope);
  }

  @override
  void didUpdateWidget(covariant _SubTenantScopeActivation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      SubTenantWorkspaceSearchController.instance.setActiveScope(widget.scope);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
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
        centerTitle: false,
        toolbarHeight: 72,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        leadingWidth: 58,
        leading: Builder(
          builder: (context) => Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Center(
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Scaffold.of(context).openDrawer(),
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F8FF),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: SubTenantColors.line),
                  ),
                  child: const Icon(
                    Icons.menu_rounded,
                    color: SubTenantColors.text,
                    size: 23,
                  ),
                ),
              ),
            ),
          ),
        ),
        titleSpacing: 8,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'TourisTrike Admin',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: SubTenantColors.lightMuted,
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SubTenantColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        actions: [
          const _NotificationButton(),
          ...actions,
          const SizedBox(width: 6),
        ],
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white, Color(0xFFF6FAFF), Color(0xFFEFFAF5)],
          ),
        ),
        child: child,
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

class _DesktopHeader extends StatelessWidget {
  const _DesktopHeader({
    required this.currentIndex,
    required this.title,
    required this.actions,
    this.subtitle,
  });

  final int currentIndex;
  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    return Container(
      height: 92,
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: 0.95)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 14),
          Expanded(
            child: PageTitleBar(
              title: title,
              subtitle: subtitle,
              actions: const [],
            ),
          ),
          const SizedBox(width: 14),
          if (desktop) ...[
            _HeaderSearch(scope: currentIndex),
            const SizedBox(width: 12),
          ],
          const _NotificationButton(),
          const SizedBox(width: 10),
          if (actions.isNotEmpty) ...[
            Container(
              height: 46,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: SubTenantColors.line),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
            const SizedBox(width: 10),
          ],
          if (desktop) const _AdminBadge(),
        ],
      ),
    );
  }
}

class _HeaderSearch extends StatefulWidget {
  const _HeaderSearch({required this.scope});

  final int scope;

  @override
  State<_HeaderSearch> createState() => _HeaderSearchState();
}

class _HeaderSearchState extends State<_HeaderSearch> {
  final _controller = TextEditingController();
  final _debouncer = SubTenantSearchDebouncer();

  SubTenantWorkspaceSearchController get _search =>
      SubTenantWorkspaceSearchController.instance;

  @override
  void initState() {
    super.initState();
    _controller.text = _search.queryFor(widget.scope);
  }

  @override
  void didUpdateWidget(covariant _HeaderSearch oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scope != widget.scope) {
      _controller.text = _search.queryFor(widget.scope);
    }
  }

  @override
  void dispose() {
    _debouncer.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 340, minWidth: 230),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: SubTenantColors.line),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.search_rounded,
              color: SubTenantColors.lightMuted,
              size: 21,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: _controller,
                onChanged: (value) {
                  setState(() {});
                  _debouncer.run(() => _search.setQuery(widget.scope, value));
                },
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  hintText: 'Search this page...',
                  border: InputBorder.none,
                  isCollapsed: true,
                  hintStyle: TextStyle(
                    color: SubTenantColors.lightMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                style: const TextStyle(
                  color: SubTenantColors.text,
                  fontSize: 12.8,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_controller.text.trim().isNotEmpty)
              IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  _controller.clear();
                  _search.clear(widget.scope);
                  setState(() {});
                },
                icon: const Icon(
                  Icons.close_rounded,
                  color: SubTenantColors.lightMuted,
                  size: 18,
                ),
              )
            else
              const Icon(
                Icons.tune_rounded,
                color: SubTenantColors.lightMuted,
                size: 18,
              ),
          ],
        ),
      ),
    );
  }
}

class _NotificationButton extends StatefulWidget {
  const _NotificationButton();

  @override
  State<_NotificationButton> createState() => _NotificationButtonState();
}

class _NotificationButtonState extends State<_NotificationButton> {
  SupabaseClient get _client => Supabase.instance.client;
  String? get _userId => _client.auth.currentUser?.id;

  Stream<List<Map<String, dynamic>>> _stream(String userId) {
    return _client
        .from('notifications')
        .stream(primaryKey: const ['id'])
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .map(
          (rows) => rows.map((row) => Map<String, dynamic>.from(row)).toList(),
        );
  }

  Future<List<Map<String, dynamic>>> _latest() async {
    final userId = _userId;
    if (userId == null) return const [];
    final rows = await _client
        .from('notifications')
        .select('*')
        .eq('user_id', userId)
        .order('created_at', ascending: false)
        .limit(20);
    return (rows as List)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(growable: false);
  }

  Future<void> _markRead(dynamic id) async {
    final userId = _userId;
    if (userId == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('id', id)
        .eq('user_id', userId);
  }

  Future<void> _markAllRead() async {
    final userId = _userId;
    if (userId == null) return;
    await _client
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  Future<void> _openPanel() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              const Expanded(child: Text('Notifications')),
              TextButton(
                onPressed: () async {
                  await _markAllRead();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text('Mark all read'),
              ),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _latest(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const SizedBox(
                    height: 160,
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final rows = snapshot.data ?? const [];
                if (rows.isEmpty) {
                  return const SizedBox(
                    height: 140,
                    child: Center(child: Text('No notifications yet.')),
                  );
                }
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 420),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final row = rows[index];
                      final unread = row['is_read'] != true;
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          unread
                              ? Icons.notifications_active_rounded
                              : Icons.notifications_none_rounded,
                          color: unread
                              ? SubTenantColors.blue
                              : SubTenantColors.lightMuted,
                        ),
                        title: Text(
                          (row['title'] ?? 'Notification').toString(),
                          style: TextStyle(
                            fontWeight: unread
                                ? FontWeight.w900
                                : FontWeight.w700,
                          ),
                        ),
                        subtitle: Text((row['body'] ?? '').toString()),
                        onTap: () async {
                          await _markRead(row['id']);
                          if (context.mounted) Navigator.pop(context);
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final userId = _userId;
    if (userId == null) {
      return _HeaderIconButton(
        tooltip: 'Notifications',
        icon: Icons.notifications_none_rounded,
        onPressed: () {},
      );
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream(userId),
      builder: (context, snapshot) {
        final rows = snapshot.data ?? const [];
        final unread = rows.where((row) => row['is_read'] != true).length;
        return Tooltip(
          message: 'Notifications',
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: _openPanel,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF4FF),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: SubTenantColors.blue.withValues(alpha: 0.08),
                    ),
                  ),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: SubTenantColors.blue,
                    size: 22,
                  ),
                ),
                if (unread > 0)
                  Positioned(
                    right: -2,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(99),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        unread > 9 ? '9+' : '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onPressed,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF4FF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: SubTenantColors.blue.withValues(alpha: 0.08),
            ),
          ),
          child: Icon(icon, color: SubTenantColors.blue, size: 22),
        ),
      ),
    );
  }
}

class _AdminBadge extends StatelessWidget {
  const _AdminBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.fromLTRB(10, 7, 12, 7),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: Color(0xFFEAF4FF),
            child: Icon(
              Icons.admin_panel_settings_rounded,
              color: SubTenantColors.blue,
              size: 18,
            ),
          ),
          SizedBox(width: 9),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'City Admin',
                style: TextStyle(
                  color: SubTenantColors.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(height: 1),
            ],
          ),
        ],
      ),
    );
  }
}

class _ShellGlow extends StatelessWidget {
  const _ShellGlow({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.36),
        ),
      ),
    );
  }
}
