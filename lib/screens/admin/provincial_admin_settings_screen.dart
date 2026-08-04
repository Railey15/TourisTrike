import 'package:flutter/material.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class ProvincialAdminSettingsScreen extends StatefulWidget {
  const ProvincialAdminSettingsScreen({super.key});

  @override
  State<ProvincialAdminSettingsScreen> createState() =>
      _ProvincialAdminSettingsScreenState();
}

class _ProvincialAdminSettingsScreenState
    extends State<ProvincialAdminSettingsScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();

  late Future<AdminSettingsData> _future;
  late AdminSettingsData _settings;

  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _service.loadSettings();
  }

  void _reload() {
    setState(() {
      _loaded = false;
      _future = _service.loadSettings();
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);

    try {
      await _service.saveSettings(_settings);

      if (!mounted) return;
      showAdminSnack(
        context,
        'Settings saved successfully.',
        error: false,
      );
    } catch (error) {
      if (!mounted) return;
      showAdminSnack(
        context,
        'Failed to save settings: $error',
        error: true,
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _update(AdminSettingsData value) {
    setState(() => _settings = value);
  }

  @override
  Widget build(BuildContext context) {
    return ProvincialAdminShell(
      current: ProvincialAdminDestination.settings,
      title: 'Settings',
      subtitle: 'Configure provincial admin notifications and dashboard preferences.',
      child: FutureBuilder<AdminSettingsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting && !_loaded) {
            return const AdminLoadingView();
          }

          if (snapshot.hasError && !_loaded) {
            return AdminErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          if (!_loaded) {
            _settings =
                snapshot.data ?? AdminSettingsData.defaults(available: false);
            _loaded = true;
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1150;

              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
                child: wide
                    ? _DesktopSettingsLayout(
                        height: (constraints.maxHeight - 28).clamp(
                          0.0,
                          double.infinity,
                        ),
                        settings: _settings,
                        saving: _saving,
                        onChanged: _update,
                        onSave: _save,
                      )
                    : SingleChildScrollView(
                        child: _MobileSettingsLayout(
                          settings: _settings,
                          saving: _saving,
                          onChanged: _update,
                          onSave: _save,
                        ),
                      ),
              );
            },
          );
        },
      ),
    );
  }
}

class _DesktopSettingsLayout extends StatelessWidget {
  const _DesktopSettingsLayout({
    required this.height,
    required this.settings,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  final double height;
  final AdminSettingsData settings;
  final bool saving;
  final ValueChanged<AdminSettingsData> onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    const gap = 14.0;

    return SizedBox(
      height: height,
      child: Column(
        children: [
          const _SettingsHero(),
          const SizedBox(height: gap),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _SettingsPanel(
                    title: 'Notifications',
                    subtitle: 'Alert preferences for provincial workflows.',
                    icon: Icons.notifications_active_rounded,
                    color: ProvincialAdminColors.blue,
                    child: Column(
                      children: [
                        _SwitchTile(
                          icon: Icons.notifications_rounded,
                          title: 'General Notifications',
                          subtitle: 'Enable general admin notifications.',
                          value: settings.notifications,
                          onChanged: (value) => onChanged(
                            settings.copyWith(notifications: value),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SwitchTile(
                          icon: Icons.inventory_2_rounded,
                          title: 'Package Alerts',
                          subtitle: 'Notify when package submissions need review.',
                          value: settings.packageAlerts,
                          onChanged: (value) => onChanged(
                            settings.copyWith(packageAlerts: value),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SwitchTile(
                          icon: Icons.travel_explore_rounded,
                          title: 'Tourist Spot Alerts',
                          subtitle: 'Notify when tourism data needs verification.',
                          value: settings.touristSpotAlerts,
                          onChanged: (value) => onChanged(
                            settings.copyWith(touristSpotAlerts: value),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  child: _SettingsPanel(
                    title: 'Reports & Notices',
                    subtitle: 'Operational summaries and platform notices.',
                    icon: Icons.campaign_rounded,
                    color: ProvincialAdminColors.purple,
                    child: Column(
                      children: [
                        _SwitchTile(
                          icon: Icons.analytics_rounded,
                          title: 'Performance Reports',
                          subtitle: 'Show recurring performance reminders.',
                          value: settings.performanceReports,
                          onChanged: (value) => onChanged(
                            settings.copyWith(performanceReports: value),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SwitchTile(
                          icon: Icons.campaign_rounded,
                          title: 'System Notices',
                          subtitle: 'Show platform-level notices in dashboard.',
                          value: settings.systemNotices,
                          onChanged: (value) => onChanged(
                            settings.copyWith(systemNotices: value),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: gap),
                Expanded(
                  child: _SettingsPanel(
                    title: 'Dashboard Widgets',
                    subtitle: 'Choose the widgets shown on the overview page.',
                    icon: Icons.dashboard_customize_rounded,
                    color: ProvincialAdminColors.green,
                    child: _DashboardWidgetToggles(
                      settings: settings,
                      onChanged: onChanged,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: gap),
          _SaveFooter(
            available: settings.available,
            saving: saving,
            onSave: onSave,
          ),
        ],
      ),
    );
  }
}

class _MobileSettingsLayout extends StatelessWidget {
  const _MobileSettingsLayout({
    required this.settings,
    required this.saving,
    required this.onChanged,
    required this.onSave,
  });

  final AdminSettingsData settings;
  final bool saving;
  final ValueChanged<AdminSettingsData> onChanged;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _SettingsHero(compact: true),
        const SizedBox(height: 14),
        _SettingsPanel(
          expand: false,
          title: 'Notifications',
          subtitle: 'Alert preferences for provincial workflows.',
          icon: Icons.notifications_active_rounded,
          color: ProvincialAdminColors.blue,
          child: Column(
            children: [
              _SwitchTile(
                icon: Icons.notifications_rounded,
                title: 'General Notifications',
                subtitle: 'Enable admin notifications.',
                value: settings.notifications,
                onChanged: (value) => onChanged(
                  settings.copyWith(notifications: value),
                ),
              ),
              const SizedBox(height: 12),
              _SwitchTile(
                icon: Icons.inventory_2_rounded,
                title: 'Package Alerts',
                subtitle: 'Package submissions needing review.',
                value: settings.packageAlerts,
                onChanged: (value) => onChanged(
                  settings.copyWith(packageAlerts: value),
                ),
              ),
              const SizedBox(height: 12),
              _SwitchTile(
                icon: Icons.travel_explore_rounded,
                title: 'Tourist Spot Alerts',
                subtitle: 'Tourism data needing verification.',
                value: settings.touristSpotAlerts,
                onChanged: (value) => onChanged(
                  settings.copyWith(touristSpotAlerts: value),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsPanel(
          expand: false,
          title: 'Reports & Notices',
          subtitle: 'Operational summaries and notices.',
          icon: Icons.campaign_rounded,
          color: ProvincialAdminColors.purple,
          child: Column(
            children: [
              _SwitchTile(
                icon: Icons.analytics_rounded,
                title: 'Performance Reports',
                subtitle: 'Recurring report reminders.',
                value: settings.performanceReports,
                onChanged: (value) => onChanged(
                  settings.copyWith(performanceReports: value),
                ),
              ),
              const SizedBox(height: 12),
              _SwitchTile(
                icon: Icons.campaign_rounded,
                title: 'System Notices',
                subtitle: 'Platform notices in dashboard.',
                value: settings.systemNotices,
                onChanged: (value) => onChanged(
                  settings.copyWith(systemNotices: value),
                ),
              ),
              const SizedBox(height: 16),
              _LanguageBox(
                value: settings.language,
                onChanged: (value) => onChanged(
                  settings.copyWith(language: value),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SettingsPanel(
          expand: false,
          title: 'Dashboard Widgets',
          subtitle: 'Choose the widgets shown on overview.',
          icon: Icons.dashboard_customize_rounded,
          color: ProvincialAdminColors.green,
          child: _DashboardWidgetToggles(
            settings: settings,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 14),
        _SaveFooter(
          available: settings.available,
          saving: saving,
          onSave: onSave,
        ),
      ],
    );
  }
}

class _SettingsHero extends StatelessWidget {
  const _SettingsHero({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final iconBadge = Container(
      width: compact ? 46 : 58,
      height: compact ? 46 : 58,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .18),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
      ),
      child: Icon(
        Icons.settings_rounded,
        color: Colors.white,
        size: compact ? 24 : 30,
      ),
    );

    final titleBlock = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ADMIN PREFERENCES',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .86),
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: .4,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Provincial Admin Settings',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: compact ? 19 : 27,
            fontWeight: FontWeight.w900,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'Configure alerts, system notices, language, and dashboard widget preferences.',
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: .92),
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
      ],
    );

    final chips = Wrap(
      spacing: 10,
      runSpacing: 10,
      children: const [
        _HeroChip(
          icon: Icons.notifications_active_rounded,
          value: 'Alerts',
          label: 'enabled',
        ),
        _HeroChip(
          icon: Icons.dashboard_customize_rounded,
          value: 'Widgets',
          label: 'customizable',
        ),
      ],
    );

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 18 : 22,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4AA3FF), Color(0xFF1D63E9)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: compact
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    iconBadge,
                    const SizedBox(width: 14),
                    Expanded(child: titleBlock),
                  ],
                ),
                const SizedBox(height: 14),
                chips,
              ],
            )
          : Row(
              children: [
                iconBadge,
                const SizedBox(width: 16),
                Expanded(child: titleBlock),
                const SizedBox(width: 14),
                chips,
              ],
            ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 138,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .15),
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: Colors.white.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 17),
          const SizedBox(width: 7),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$value\n',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: label,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .86),
                      fontSize: 11,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.child,
    this.expand = true,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Widget child;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ProvincialAdminColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .022),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 21),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$title\n',
                        style: const TextStyle(
                          color: ProvincialAdminColors.text,
                          fontSize: 17.5,
                          height: 1.15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      TextSpan(
                        text: subtitle,
                        style: const TextStyle(
                          color: ProvincialAdminColors.muted,
                          fontSize: 12.2,
                          height: 1.25,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          expand ? Expanded(child: child) : child,
        ],
      ),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: ProvincialAdminColors.blue.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: ProvincialAdminColors.blue, size: 20),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$title\n',
                    style: const TextStyle(
                      color: ProvincialAdminColors.text,
                      fontSize: 13.5,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  TextSpan(
                    text: subtitle,
                    style: const TextStyle(
                      color: ProvincialAdminColors.muted,
                      fontSize: 11.7,
                      height: 1.25,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Switch.adaptive(
            value: value,
            activeColor: ProvincialAdminColors.blue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _LanguageBox extends StatelessWidget {
  const _LanguageBox({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = ['English', 'Filipino'];

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: DropdownButtonFormField<String>(
        value: options.contains(value) ? value : 'English',
        decoration: const InputDecoration(
          labelText: 'Language',
          border: InputBorder.none,
          isDense: true,
          labelStyle: TextStyle(
            color: ProvincialAdminColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
        style: const TextStyle(
          color: ProvincialAdminColors.text,
          fontSize: 14,
          fontWeight: FontWeight.w900,
        ),
        items: const [
          DropdownMenuItem(value: 'English', child: Text('English')),
          DropdownMenuItem(value: 'Filipino', child: Text('Filipino')),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _DashboardWidgetToggles extends StatelessWidget {
  const _DashboardWidgetToggles({
    required this.settings,
    required this.onChanged,
  });

  final AdminSettingsData settings;
  final ValueChanged<AdminSettingsData> onChanged;

  @override
  Widget build(BuildContext context) {
    final widgets = settings.dashboardWidgets.entries.toList();

    return ListView.separated(
      padding: EdgeInsets.zero,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widgets.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final entry = widgets[index];

        return _SwitchTile(
          icon: Icons.widgets_rounded,
          title: entry.key,
          subtitle: 'Show ${entry.key.toLowerCase()} widget.',
          value: entry.value,
          onChanged: (value) {
            final updated = Map<String, bool>.from(settings.dashboardWidgets);
            updated[entry.key] = value;
            onChanged(settings.copyWith(dashboardWidgets: updated));
          },
        );
      },
    );
  }
}

class _SaveFooter extends StatelessWidget {
  const _SaveFooter({
    required this.available,
    required this.saving,
    required this.onSave,
  });

  final bool available;
  final bool saving;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final message = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          available ? Icons.check_circle_rounded : Icons.info_rounded,
          color: available
              ? ProvincialAdminColors.green
              : ProvincialAdminColors.amber,
          size: 22,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            available
                ? 'Settings are connected and ready to save.'
                : 'Settings table is not available. Defaults are shown.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ProvincialAdminColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 460;

        final button = SizedBox(
          width: stacked ? double.infinity : 220,
          height: 44,
          child: ElevatedButton.icon(
            onPressed: saving ? null : onSave,
            style: ElevatedButton.styleFrom(
              backgroundColor: ProvincialAdminColors.blue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            icon: saving
                ? const SizedBox(
                    width: 17,
                    height: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: Text(
              saving ? 'Saving...' : 'Save Settings',
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: ProvincialAdminColors.line),
          ),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    message,
                    const SizedBox(height: 10),
                    button,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: message),
                    const SizedBox(width: 12),
                    button,
                  ],
                ),
        );
      },
    );
  }
}