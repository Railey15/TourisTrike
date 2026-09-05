import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class AdminGlobalSearchButton extends StatelessWidget {
  const AdminGlobalSearchButton({
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
    final result = await showDialog<AdminSearchResult>(
      context: context,
      builder: (_) => const _AdminSearchDialog(),
    );
    if (result == null || !context.mounted) return;
    switch (result.type) {
      case AdminSearchResultType.tenant:
        onOpenTenant(result.id);
      case AdminSearchResultType.spot:
        onOpenSpots(result.title);
      case AdminSearchResultType.package:
        onOpenPackages(result.title);
      case AdminSearchResultType.driver:
      case AdminSearchResultType.booking:
        await _showRecord(context, result);
    }
  }

  Future<void> _showRecord(
    BuildContext context,
    AdminSearchResult result,
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
            border: Border.all(color: ProvincialAdminColors.line),
          ),
          child: const Row(
            children: [
              Icon(
                Icons.search_rounded,
                color: ProvincialAdminColors.lightMuted,
              ),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Search province data...',
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
  final _service = ProvincialAdminService();
  final _controller = TextEditingController();
  Timer? _debounce;
  Future<List<AdminSearchResult>>? _future;

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
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => setState(() => _future = _service.searchProvince(query)),
    );
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
    return FutureBuilder<List<AdminSearchResult>>(
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
              style: const TextStyle(color: ProvincialAdminColors.red),
            ),
          );
        }
        final results = snapshot.data ?? const <AdminSearchResult>[];
        if (results.isEmpty) {
          return const Center(child: Text('No matching province records.'));
        }
        final groups = <AdminSearchResultType, List<AdminSearchResult>>{};
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
                        color: ProvincialAdminColors.blue,
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

  String _groupLabel(AdminSearchResultType type) => switch (type) {
    AdminSearchResultType.tenant => 'Municipalities / Subtenants',
    AdminSearchResultType.spot => 'Tourist Spots',
    AdminSearchResultType.package => 'Tour Packages',
    AdminSearchResultType.driver => 'Drivers',
    AdminSearchResultType.booking => 'Bookings',
  };

  IconData _icon(AdminSearchResultType type) => switch (type) {
    AdminSearchResultType.tenant => Icons.location_city_rounded,
    AdminSearchResultType.spot => Icons.place_rounded,
    AdminSearchResultType.package => Icons.inventory_2_rounded,
    AdminSearchResultType.driver => Icons.badge_rounded,
    AdminSearchResultType.booking => Icons.receipt_long_rounded,
  };
}

class AdminNotificationButton extends StatefulWidget {
  const AdminNotificationButton({
    super.key,
    required this.userId,
    required this.onNavigate,
  });

  final String userId;
  final ValueChanged<ProvincialAdminDestination> onNavigate;

  @override
  State<AdminNotificationButton> createState() =>
      _AdminNotificationButtonState();
}

class _AdminNotificationButtonState extends State<AdminNotificationButton> {
  final _service = ProvincialAdminService();

  Stream<List<Map<String, dynamic>>> get _stream => Supabase.instance.client
      .from('notifications')
      .stream(primaryKey: const ['id'])
      .eq('user_id', widget.userId)
      .order('created_at', ascending: false);

  Future<void> _open() async {
    await showDialog<void>(
      context: context,
      builder: (_) => _AdminNotificationsDialog(
        service: _service,
        onNavigate: widget.onNavigate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        final unread = (snapshot.data ?? const [])
            .where((row) => row['is_read'] != true)
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
            foregroundColor: ProvincialAdminColors.blue,
          ),
        );
      },
    );
  }
}

class _AdminNotificationsDialog extends StatefulWidget {
  const _AdminNotificationsDialog({
    required this.service,
    required this.onNavigate,
  });

  final ProvincialAdminService service;
  final ValueChanged<ProvincialAdminDestination> onNavigate;

  @override
  State<_AdminNotificationsDialog> createState() =>
      _AdminNotificationsDialogState();
}

class _AdminNotificationsDialogState extends State<_AdminNotificationsDialog> {
  late Future<List<AdminNotification>> _future;
  bool _markingAll = false;

  @override
  void initState() {
    super.initState();
    _future = widget.service.fetchAdminNotifications();
  }

  void _reload() {
    setState(() => _future = widget.service.fetchAdminNotifications());
  }

  Future<void> _markAll() async {
    setState(() => _markingAll = true);
    try {
      await widget.service.markAllAdminNotificationsRead();
      _reload();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not update notifications: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  Future<void> _openNotification(AdminNotification item) async {
    try {
      if (!item.isRead) await widget.service.markAdminNotificationRead(item.id);
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

  ProvincialAdminDestination? _destination(String type) {
    final value = type.toLowerCase();
    if (value.contains('city_admin') || value.contains('registration')) {
      return ProvincialAdminDestination.cityTenants;
    }
    if (value.contains('spot')) return ProvincialAdminDestination.tourismData;
    if (value.contains('package')) return ProvincialAdminDestination.packages;
    if (value.contains('booking') || value.contains('payment')) {
      return ProvincialAdminDestination.reports;
    }
    if (value.contains('review') || value.contains('feedback')) {
      return ProvincialAdminDestination.feedback;
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
        child: FutureBuilder<List<AdminNotification>>(
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
            final items = snapshot.data ?? const <AdminNotification>[];
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
                        ? ProvincialAdminColors.lightMuted
                        : ProvincialAdminColors.blue,
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
