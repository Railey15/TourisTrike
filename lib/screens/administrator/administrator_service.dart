import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/auth/app_role.dart';
import 'package:touristrike/core/maintenance/maintenance_service.dart';
import 'package:touristrike/core/maintenance/maintenance_settings.dart';

import 'administrator_models.dart';

class AdministratorService {
  AdministratorService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<AdministratorPortalData> loadPortalData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) throw StateError('No active session.');

    final guardTimer = Stopwatch()..start();
    final profileRow = await _supabase
        .from('profiles')
        .select('id,role,full_name,first_name,last_name')
        .eq('id', user.id)
        .maybeSingle();
    guardTimer.stop();

    if (profileRow == null ||
        AppRole.tryParse(profileRow['role'] as String?) !=
            AppRole.administrator) {
      throw StateError('System Administrator access is required.');
    }

    final healthChecks = <PlatformHealthCheck>[
      PlatformHealthCheck(
        name: 'Authentication and role guard',
        description: 'Authenticated administrator session and profile role',
        state: PlatformHealthState.operational,
        latency: guardTimer.elapsed,
        checkedAt: DateTime.now().toUtc(),
        detail: user.email ?? user.id,
      ),
    ];

    final accountDirectory = await _measure(_loadAccountDirectory);
    List<PlatformAccountSummary> accounts;
    if (accountDirectory.value != null) {
      accounts = accountDirectory.value!;
      healthChecks.add(
        _healthFrom(
          name: 'Account directory',
          description: 'Profiles joined with Supabase Auth account metadata',
          result: accountDirectory,
        ),
      );
    } else {
      final fallback = await _measure(_loadProfileDirectoryFallback);
      accounts = fallback.value ?? const [];
      healthChecks.add(
        PlatformHealthCheck(
          name: 'Account directory',
          description: 'Profiles joined with Supabase Auth account metadata',
          state: PlatformHealthState.degraded,
          latency: accountDirectory.elapsed + fallback.elapsed,
          checkedAt: DateTime.now().toUtc(),
          detail: fallback.value == null
              ? _errorText(fallback.error ?? accountDirectory.error)
              : 'Auth metadata RPC unavailable; showing profile metadata only.',
        ),
      );
    }

    final auditResult = await _measure(_loadAuditEntries);
    healthChecks.add(
      _healthFrom(
        name: 'Audit log',
        description: 'Recent platform audit events are readable',
        result: auditResult,
      ),
    );

    final maintenanceResult = await _measure(_loadMaintenance);
    healthChecks.add(
      _healthFrom(
        name: 'Maintenance controls',
        description: 'Platform-wide maintenance status and access guard',
        result: maintenanceResult,
      ),
    );

    final provincialResult = await _measure(_loadProvincialOffices);
    final localResult = await _measure(_loadLocalOffices);
    healthChecks.add(
      _combinedHealth(
        name: 'Tenant directory',
        description: 'Provincial and city/municipal office metadata',
        first: provincialResult,
        second: localResult,
      ),
    );

    final profile = Map<String, dynamic>.from(profileRow);
    return AdministratorPortalData(
      profile: AdministratorProfile(
        id: user.id,
        name: _name(profile),
        role: AppRole.administrator,
        email: user.email ?? '',
      ),
      accounts: accounts,
      tenants: [...?provincialResult.value, ...?localResult.value],
      auditEntries: auditResult.value ?? const [],
      healthChecks: healthChecks,
      maintenance:
          maintenanceResult.value ?? const MaintenanceSettings.operational(),
    );
  }

  Future<void> signOut() => _supabase.auth.signOut();

  Future<MaintenanceSettings> updateMaintenance(MaintenanceUpdate update) {
    return MaintenanceService(client: _supabase).update(update);
  }

  Future<void> suspendAccount(
    PlatformAccountSummary account,
    AdministratorSuspensionRequest request,
  ) {
    return _invokeAccountAccess({
      'action': 'suspend',
      'account_id': account.id,
      'reason': request.reason.databaseValue,
      'notes': request.details.trim(),
      'is_permanent': request.isPermanent,
      'suspended_until': request.suspendedUntil?.toUtc().toIso8601String(),
    });
  }

  Future<void> reactivateAccount(PlatformAccountSummary account) {
    return _invokeAccountAccess({
      'action': 'reactivate',
      'account_id': account.id,
    });
  }

  Future<void> _invokeAccountAccess(Map<String, dynamic> body) async {
    try {
      final response = await _supabase.functions.invoke(
        'administrator-account-access',
        body: body,
      );
      final data = response.data;
      if (data is! Map || data['ok'] != true) {
        throw StateError(_functionErrorMessage(data));
      }
    } on FunctionException catch (error) {
      throw StateError(_functionErrorMessage(error.details));
    }
  }

  Future<List<PlatformAccountSummary>> _loadAccountDirectory() async {
    final rows = await _supabase.rpc('administrator_list_accounts');
    return _rows(rows)
        .map((row) => _accountFromMap(row, authMetadataAvailable: true))
        .whereType<PlatformAccountSummary>()
        .toList(growable: false);
  }

  Future<List<PlatformAccountSummary>> _loadProfileDirectoryFallback() async {
    final rows = await _supabase
        .from('profiles')
        .select(
          'id,role,full_name,first_name,last_name,city,province,created_at',
        )
        .order('created_at', ascending: false);
    return _rows(rows)
        .map((row) => _accountFromMap(row, authMetadataAvailable: false))
        .whereType<PlatformAccountSummary>()
        .toList(growable: false);
  }

  Future<List<PlatformAuditEntry>> _loadAuditEntries() async {
    final rows = await _supabase
        .from('audit_logs')
        .select(
          'id,actor_id,action,table_name,record_id,description,created_at',
        )
        .order('created_at', ascending: false)
        .limit(250);
    return _rows(rows).map(_auditFromMap).toList(growable: false);
  }

  Future<MaintenanceSettings> _loadMaintenance() {
    return MaintenanceService(client: _supabase).fetchStatus();
  }

  Future<List<TenantOfficeSummary>> _loadProvincialOffices() async {
    final rows = await _supabase
        .from('provincial_office_details')
        .select(
          'user_id,office_name,province,contact_person,official_email,updated_at',
        )
        .order('province');
    return _rows(rows)
        .map(
          (row) => TenantOfficeSummary(
            accountId: _string(row['user_id']),
            officeName: _string(
              row['office_name'],
              fallback: 'Provincial Tourism Office',
            ),
            kind: TenantOfficeKind.provincial,
            city: '',
            province: _string(row['province'], fallback: 'Bulacan'),
            contactPerson: _string(row['contact_person']),
            email: _string(row['official_email']),
            verificationStatus: 'active',
            isActive: true,
            updatedAt: _date(row['updated_at']),
          ),
        )
        .toList(growable: false);
  }

  Future<List<TenantOfficeSummary>> _loadLocalOffices() async {
    final rows = await _supabase
        .from('subtenant_details')
        .select(
          'id,office_name,city,province,contact_person,email,verification_status,is_active,updated_at',
        )
        .order('city');
    return _rows(rows)
        .map(
          (row) => TenantOfficeSummary(
            accountId: _string(row['id']),
            officeName: _string(
              row['office_name'],
              fallback: '${_string(row['city'])} Tourism Office',
            ),
            kind: TenantOfficeKind.cityMunicipal,
            city: _string(row['city']),
            province: _string(row['province'], fallback: 'Bulacan'),
            contactPerson: _string(row['contact_person']),
            email: _string(row['email']),
            verificationStatus: _string(
              row['verification_status'],
              fallback: 'pending',
            ),
            isActive: row['is_active'] == true,
            updatedAt: _date(row['updated_at']),
          ),
        )
        .toList(growable: false);
  }

  PlatformAccountSummary? _accountFromMap(
    Map<String, dynamic> map, {
    required bool authMetadataAvailable,
  }) {
    final role = AppRole.tryParse(map['role']?.toString());
    if (role == null) return null;
    final suspensionId = _string(map['suspension_id']);
    final suspensionReason = AdministratorSuspensionReason.tryParse(
      map['suspension_reason']?.toString(),
    );
    final suspendedAt = _date(map['suspended_at']);
    final suspension =
        suspensionId.isNotEmpty &&
            suspensionReason != null &&
            suspendedAt != null
        ? AdministratorSuspensionRecord(
            id: suspensionId,
            reason: suspensionReason,
            details: _string(map['suspension_notes']),
            suspendedAt: suspendedAt,
            suspendedUntil: _date(map['suspended_until']),
            isPermanent: map['suspension_is_permanent'] == true,
            suspendedById: _string(map['suspended_by']),
            suspendedByName: _string(map['suspended_by_name']),
          )
        : null;
    return PlatformAccountSummary(
      id: _string(map['id']),
      name: _name(map),
      email: _string(map['email']),
      role: role,
      city: _string(map['city']),
      province: _string(map['province']),
      profileCreatedAt: _date(map['profile_created_at'] ?? map['created_at']),
      authCreatedAt: _date(map['auth_created_at']),
      emailConfirmedAt: _date(map['email_confirmed_at']),
      lastSignInAt: _date(map['last_sign_in_at']),
      bannedUntil: _date(map['banned_until']),
      authMetadataAvailable: authMetadataAvailable,
      suspension: suspension,
    );
  }

  PlatformAuditEntry _auditFromMap(Map<String, dynamic> map) {
    return PlatformAuditEntry(
      id: _string(map['id']),
      actorId: _string(map['actor_id']),
      action: _string(map['action']),
      tableName: _string(map['table_name']),
      recordId: _string(map['record_id']),
      description: _string(map['description']),
      createdAt: _date(map['created_at']),
    );
  }

  PlatformHealthCheck _healthFrom<T>({
    required String name,
    required String description,
    required _Measured<T> result,
  }) {
    return PlatformHealthCheck(
      name: name,
      description: description,
      state: result.value == null
          ? PlatformHealthState.degraded
          : PlatformHealthState.operational,
      latency: result.elapsed,
      checkedAt: DateTime.now().toUtc(),
      detail: result.value == null ? _errorText(result.error) : 'Available',
    );
  }

  PlatformHealthCheck _combinedHealth<A, B>({
    required String name,
    required String description,
    required _Measured<A> first,
    required _Measured<B> second,
  }) {
    final operational = first.value != null && second.value != null;
    return PlatformHealthCheck(
      name: name,
      description: description,
      state: operational
          ? PlatformHealthState.operational
          : PlatformHealthState.degraded,
      latency: first.elapsed + second.elapsed,
      checkedAt: DateTime.now().toUtc(),
      detail: operational
          ? 'Available'
          : _errorText(first.error ?? second.error),
    );
  }

  Future<_Measured<T>> _measure<T>(Future<T> Function() operation) async {
    final timer = Stopwatch()..start();
    try {
      final value = await operation();
      timer.stop();
      return _Measured(value: value, elapsed: timer.elapsed);
    } catch (error) {
      timer.stop();
      return _Measured(error: error, elapsed: timer.elapsed);
    }
  }

  List<Map<String, dynamic>> _rows(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  String _name(Map<String, dynamic> map) {
    final fullName = _string(map['full_name']);
    if (fullName.isNotEmpty) return fullName;
    final parts = [
      map['first_name'],
      map['last_name'],
    ].map(_string).where((value) => value.isNotEmpty);
    final name = parts.join(' ');
    return name.isEmpty ? 'Unnamed account' : name;
  }

  String _string(dynamic value, {String fallback = ''}) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }

  DateTime? _date(dynamic value) {
    return DateTime.tryParse(value?.toString() ?? '')?.toUtc();
  }

  String _errorText(Object? error) {
    if (error is PostgrestException) return error.message;
    final text = error?.toString().trim() ?? '';
    return text.isEmpty ? 'Unavailable' : text;
  }

  String _functionErrorMessage(dynamic value) {
    if (value is Map) {
      final message = value['message']?.toString().trim() ?? '';
      if (message.isNotEmpty) return message;
      final code = value['error']?.toString().trim() ?? '';
      if (code.isNotEmpty) return code;
    }
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? 'Account access update failed.' : text;
  }
}

class _Measured<T> {
  const _Measured({this.value, this.error, required this.elapsed});

  final T? value;
  final Object? error;
  final Duration elapsed;
}
