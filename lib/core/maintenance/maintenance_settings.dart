import 'package:touristrike/core/auth/app_role.dart';

enum MaintenanceSystemStatus { operational, scheduled, active }

class MaintenanceSettings {
  const MaintenanceSettings({
    required this.enabled,
    required this.title,
    required this.message,
    required this.startsAt,
    required this.endsAt,
    required this.indefinite,
    required this.allowMainTenant,
    required this.updatedBy,
    required this.updatedByName,
    required this.updatedAt,
    required this.viewerRole,
    required this.viewerAllowed,
    required this.serverActive,
  });

  const MaintenanceSettings.operational()
    : enabled = false,
      title = 'We\'ll be right back!',
      message =
          'TourisTrike is temporarily unavailable while we perform system maintenance. Your account and booking information remain safe.',
      startsAt = null,
      endsAt = null,
      indefinite = false,
      allowMainTenant = false,
      updatedBy = '',
      updatedByName = '',
      updatedAt = null,
      viewerRole = null,
      viewerAllowed = true,
      serverActive = false;

  final bool enabled;
  final String title;
  final String message;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool indefinite;
  final bool allowMainTenant;
  final String updatedBy;
  final String updatedByName;
  final DateTime? updatedAt;
  final AppRole? viewerRole;
  final bool viewerAllowed;
  final bool serverActive;

  factory MaintenanceSettings.fromJson(Map<String, dynamic> json) {
    return MaintenanceSettings(
      enabled: json['maintenance_enabled'] == true,
      title: _text(
        json['maintenance_title'],
        fallback: 'We\'ll be right back!',
      ),
      message: _text(
        json['maintenance_message'],
        fallback:
            'TourisTrike is temporarily unavailable while we perform system maintenance. Your account and booking information remain safe.',
      ),
      startsAt: _date(json['maintenance_starts_at']),
      endsAt: _date(json['maintenance_ends_at']),
      indefinite: json['maintenance_indefinite'] == true,
      allowMainTenant: json['maintenance_allow_main_tenant'] == true,
      updatedBy: _text(json['maintenance_updated_by']),
      updatedByName: _text(json['maintenance_updated_by_name']),
      updatedAt: _date(json['maintenance_updated_at']),
      viewerRole: AppRole.tryParse(json['viewer_role']?.toString()),
      viewerAllowed: json['viewer_allowed'] != false,
      serverActive: json['maintenance_active'] == true,
    );
  }

  MaintenanceSystemStatus statusAt(DateTime now) {
    if (!enabled || startsAt == null) {
      return MaintenanceSystemStatus.operational;
    }
    final utcNow = now.toUtc();
    if (utcNow.isBefore(startsAt!)) {
      return MaintenanceSystemStatus.scheduled;
    }
    if (!indefinite && (endsAt == null || !utcNow.isBefore(endsAt!))) {
      return MaintenanceSystemStatus.operational;
    }
    return MaintenanceSystemStatus.active;
  }

  MaintenanceSystemStatus get status => statusAt(DateTime.now());
  bool get isActive => status == MaintenanceSystemStatus.active;
  bool get isScheduled => status == MaintenanceSystemStatus.scheduled;
  bool get blocksViewer => serverActive && !viewerAllowed;

  bool allowsRole(AppRole role) {
    if (role == AppRole.administrator) return true;
    return role == AppRole.mainTenant && allowMainTenant;
  }

  static String _text(Object? value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  static DateTime? _date(Object? value) {
    final parsed = DateTime.tryParse(value?.toString() ?? '');
    return parsed?.toUtc();
  }
}

class MaintenanceUpdate {
  const MaintenanceUpdate({
    required this.enabled,
    required this.title,
    required this.message,
    required this.startsAt,
    required this.endsAt,
    required this.indefinite,
    required this.allowMainTenant,
  });

  final bool enabled;
  final String title;
  final String message;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool indefinite;
  final bool allowMainTenant;
}
