import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_models.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_nav.dart';
import 'package:touristrike/screens/main_tenant/main_tenant_service.dart';
import 'package:touristrike/screens/main_tenant/widgets/main_tenant_style.dart';

class MainTenantGlobalSearchButton extends StatelessWidget {
  const MainTenantGlobalSearchButton({
    super.key,
    required this.onOpenTenant,
    required this.onOpenSpots,
    required this.onOpenPackages,
    this.compact = false,
  });

  final ValueChanged<String> onOpenTenant;
  final ValueChanged<String> onOpenSpots;
  final ValueChanged<String> onOpenPackages;
  final bool compact;

  Future<void> _open(BuildContext context) async {
    final result = await showDialog<MainTenantSearchResult>(
      context: context,
      builder: (_) => const _AdminSearchDialog(),
    );
    if (result == null || !context.mounted) return;
    switch (result.type) {
      case MainTenantSearchResultType.tenant:
        onOpenTenant(result.id);
      case MainTenantSearchResultType.spot:
        onOpenSpots(result.title);
      case MainTenantSearchResultType.package:
        onOpenPackages(result.title);
      case MainTenantSearchResultType.driver:
      case MainTenantSearchResultType.booking:
        await _showRecord(context, result);
    }
  }

  Future<void> _showRecord(
    BuildContext context,
    MainTenantSearchResult result,
  ) async {
    final rows = result.raw.entries
        .where((entry) => entry.value != null && entry.value is! Map)
        .take(10)
        .toList(growable: false);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(result.title),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: rows
                  .map(
                    (entry) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_label(entry.key)),
                      subtitle: Text(entry.value.toString()),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _label(String value) => value
      .split('_')
      .map(
        (part) => part.isEmpty
            ? ''
            : '${part.substring(0, 1).toUpperCase()}${part.substring(1)}',
      )
      .join(' ');

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return IconButton(
        tooltip: 'Search province data',
        onPressed: () => _open(context),
        icon: const Icon(Icons.search_rounded),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 310, minWidth: 210),
      child: InkWell(
        onTap: () => _open(context),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: MainTenantColors.line),
          ),
          child: const Row(
            children: [
              Icon(Icons.search_rounded, color: MainTenantColors.lightMuted),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Search province data...',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: MainTenantColors.lightMuted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminSearchDialog extends StatefulWidget {
  const _AdminSearchDialog();

  @override
  State<_AdminSearchDialog> createState() => _AdminSearchDialogState();
}

class _AdminSearchDialogState extends State<_AdminSearchDialog> {
  final _service = MainTenantService();
  final _controller = TextEditingController();
  Timer? _debounce;
  Future<List<MainTenantSearchResult>>? _future;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() => _future = null);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      final next = _service.searchProvince(query);
      setState(() {
        _future = next;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Search province data',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _controller,
                autofocus: true,
                onChanged: _search,
                decoration: InputDecoration(
                  hintText: 'Municipality, spot, package, driver, or booking…',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Flexible(child: _results()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _results() {
    final future = _future;
    if (future == null) {
      return const Center(child: Text('Enter at least 2 characters.'));
    }
    return FutureBuilder<List<MainTenantSearchResult>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Search failed: ${snapshot.error}',
              textAlign: TextAlign.center,
              style: const TextStyle(color: MainTenantColors.red),
            ),
          );
        }
        final results = snapshot.data ?? const <MainTenantSearchResult>[];
        if (results.isEmpty) {
          return const Center(child: Text('No matching province records.'));
        }
        final groups =
            <MainTenantSearchResultType, List<MainTenantSearchResult>>{};
        for (final result in results) {
          groups.putIfAbsent(result.type, () => []).add(result);
        }
        return ListView(
          shrinkWrap: true,
          children: groups.entries
              .expand(
                (group) => [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                    child: Text(
                      _groupLabel(group.key),
                      style: const TextStyle(
                        color: MainTenantColors.blue,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  ...group.value.map(
                    (result) => ListTile(
                      leading: Icon(_icon(result.type)),
                      title: Text(result.title),
                      subtitle: Text(result.subtitle),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.pop(context, result),
                    ),
                  ),
                ],
              )
              .toList(growable: false),
        );
      },
    );
  }

  String _groupLabel(MainTenantSearchResultType type) => switch (type) {
    MainTenantSearchResultType.tenant => 'Municipalities / Subtenants',
    MainTenantSearchResultType.spot => 'Tourist Spots',
    MainTenantSearchResultType.package => 'Tour Packages',
    MainTenantSearchResultType.driver => 'Drivers',
    MainTenantSearchResultType.booking => 'Bookings',
  };

  IconData _icon(MainTenantSearchResultType type) => switch (type) {
    MainTenantSearchResultType.tenant => Icons.location_city_rounded,
    MainTenantSearchResultType.spot => Icons.place_rounded,
    MainTenantSearchResultType.package => Icons.inventory_2_rounded,
    MainTenantSearchResultType.driver => Icons.badge_rounded,
    MainTenantSearchResultType.booking => Icons.receipt_long_rounded,
  };
}

class MainTenantNotificationButton extends StatefulWidget {
  const MainTenantNotificationButton({
    super.key,
    required this.userId,
    required this.onNavigate,
  });

  final String userId;
  final ValueChanged<MainTenantDestination> onNavigate;

  @override
  State<MainTenantNotificationButton> createState() =>
      _MainTenantNotificationButtonState();
}

class _MainTenantNotificationButtonState
    extends State<MainTenantNotificationButton> {
  final _service = MainTenantService();
  final Set<String> _locallyReadNotificationIds = <String>{};

  Stream<List<Map<String, dynamic>>> get _stream => Supabase.instance.client
      .from('notifications')
      .stream(primaryKey: const ['id'])
      .eq('user_id', widget.userId)
      .order('created_at', ascending: false);

  Future<void> _open() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _MainTenantNotificationsDialog(
        service: _service,
        onNavigate: widget.onNavigate,
        onNotificationsRead: _handleNotificationsRead,
      ),
    );
  }

  void _handleNotificationsRead(Set<String> notificationIds) {
    if (!mounted || notificationIds.isEmpty) return;
    setState(() => _locallyReadNotificationIds.addAll(notificationIds));
  }

  @override
  void didUpdateWidget(covariant MainTenantNotificationButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _locallyReadNotificationIds.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        final unread = (snapshot.data ?? const [])
            .where(
              (row) =>
                  row['is_read'] != true &&
                  !_locallyReadNotificationIds.contains('${row['id']}'),
            )
            .length;
        return IconButton.filledTonal(
          tooltip: snapshot.hasError
              ? 'Notifications unavailable'
              : 'Notifications${unread > 0 ? ' ($unread unread)' : ''}',
          onPressed: _open,
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: Icon(
              unread > 0
                  ? Icons.notifications_active_rounded
                  : Icons.notifications_none_rounded,
            ),
          ),
          style: IconButton.styleFrom(
            backgroundColor: const Color(0xFFEAF4FF),
            foregroundColor: MainTenantColors.blue,
          ),
        );
      },
    );
  }
}

class _MainTenantNotificationsDialog extends StatefulWidget {
  const _MainTenantNotificationsDialog({
    required this.service,
    required this.onNavigate,
    required this.onNotificationsRead,
  });

  final MainTenantService service;
  final ValueChanged<MainTenantDestination> onNavigate;
  final ValueChanged<Set<String>> onNotificationsRead;

  @override
  State<_MainTenantNotificationsDialog> createState() =>
      _MainTenantNotificationsDialogState();
}

class _MainTenantNotificationsDialogState
    extends State<_MainTenantNotificationsDialog> {
  late Future<List<MainTenantNotification>> _future;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _future = widget.service.fetchMainTenantNotifications();
  }

  void _reload() {
    final next = widget.service.fetchMainTenantNotifications();
    if (!mounted) return;
    setState(() {
      _future = next;
    });
  }

  Future<void> _markAll() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      final updatedIds = await widget.service
          .markAllMainTenantNotificationsRead();
      if (!mounted) return;
      widget.onNotificationsRead(updatedIds);
      final next = _future.then(
        (items) => items
            .map(
              (item) => updatedIds.contains('${item.id}')
                  ? item.copyWith(isRead: true)
                  : item,
            )
            .toList(growable: false),
      );
      setState(() {
        _future = next;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to mark notifications as read. Try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _openNotification(MainTenantNotification item) async {
    try {
      if (!item.isRead)
        await widget.service.markMainTenantNotificationRead(item.id);
      final destination = _destination(item.type);
      if (!mounted) return;
      Navigator.pop(context);
      if (destination != null) widget.onNavigate(destination);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open notification: $error')),
        );
      }
    }
  }

  MainTenantDestination? _destination(String type) {
    final value = type.toLowerCase();
    if (value.contains('city_admin') || value.contains('registration')) {
      return MainTenantDestination.cityTenants;
    }
    if (value.contains('spot')) return MainTenantDestination.tourismData;
    if (value.contains('package')) return MainTenantDestination.packages;
    if (value.contains('booking') || value.contains('payment')) {
      return MainTenantDestination.reports;
    }
    if (value.contains('review') || value.contains('feedback')) {
      return MainTenantDestination.feedback;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final compact = viewport.width < 620;
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Notifications')),
          TextButton(
            onPressed: _markingAll ? null : _markAll,
            child: Text(_markingAll ? 'Updating…' : 'Mark all read'),
          ),
        ],
      ),
      content: SizedBox(
        width: compact ? math.max(220, viewport.width - 96) : 520,
        height: math.max(260, math.min(460, viewport.height - 190)),
        child: FutureBuilder<List<MainTenantNotification>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Unable to load notifications: ${snapshot.error}'),
                    const SizedBox(height: 10),
                    FilledButton(
                      onPressed: _reload,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            final items = snapshot.data ?? const <MainTenantNotification>[];
            if (items.isEmpty) {
              return const Center(child: Text('No notifications yet.'));
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = items[index];
                return ListTile(
                  leading: Icon(
                    item.isRead
                        ? Icons.notifications_none_rounded
                        : Icons.notifications_active_rounded,
                    color: item.isRead
                        ? MainTenantColors.lightMuted
                        : MainTenantColors.blue,
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(
                      fontWeight: item.isRead
                          ? FontWeight.w700
                          : FontWeight.w900,
                    ),
                  ),
                  subtitle: Text(
                    [
                      item.body,
                      if (item.createdAt != null)
                        DateFormat.yMMMd().add_jm().format(
                          item.createdAt!.toLocal(),
                        ),
                    ].where((value) => value.isNotEmpty).join('\n'),
                  ),
                  onTap: () => _openNotification(item),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}
