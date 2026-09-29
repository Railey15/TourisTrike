import 'package:supabase_flutter/supabase_flutter.dart';

import 'maintenance_settings.dart';

abstract interface class MaintenanceStatusService {
  Future<MaintenanceSettings> fetchStatus();
}

class MaintenanceService implements MaintenanceStatusService {
  MaintenanceService({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<MaintenanceSettings> fetchStatus() async {
    final value = await _client.rpc('get_maintenance_status');
    if (value is Map) {
      return MaintenanceSettings.fromJson(Map<String, dynamic>.from(value));
    }
    throw const FormatException('Maintenance status response is invalid.');
  }

  Future<MaintenanceSettings> update(MaintenanceUpdate update) async {
    final value = await _client.rpc(
      'administrator_set_maintenance',
      params: {
        'p_enabled': update.enabled,
        'p_title': update.title.trim(),
        'p_message': update.message.trim(),
        'p_starts_at': update.startsAt?.toUtc().toIso8601String(),
        'p_ends_at': update.endsAt?.toUtc().toIso8601String(),
        'p_indefinite': update.indefinite,
        'p_allow_main_tenant': update.allowMainTenant,
      },
    );
    if (value is Map) {
      return MaintenanceSettings.fromJson(Map<String, dynamic>.from(value));
    }
    return fetchStatus();
  }
}
