import 'package:flutter/material.dart';
import 'package:touristrike/core/maintenance/maintenance_settings.dart';
import 'package:touristrike/screens/auth/web_portal_login_screen.dart';

import 'administrator_models.dart';
import 'administrator_service.dart';
import 'administrator_accounts_screen.dart';
import 'administrator_audit_logs_screen.dart';
import 'administrator_configuration_screen.dart';
import 'administrator_dashboard_screen.dart';
import 'administrator_developer_tools_screen.dart';
import 'administrator_integrations_screen.dart';
import 'administrator_security_screen.dart';
import 'administrator_tenants_screen.dart';
import 'widgets/system_admin_shared.dart';
import 'widgets/system_admin_shell.dart';

export 'widgets/system_admin_shared.dart' show AdministratorSection;

class AdministratorPortalScreen extends StatefulWidget {
  const AdministratorPortalScreen({
    super.key,
    this.initialSection = AdministratorSection.overview,
    @visibleForTesting this.dataLoader,
    @visibleForTesting this.signOut,
    @visibleForTesting this.signedOutDestinationBuilder,
    @visibleForTesting this.suspendAccount,
    @visibleForTesting this.reactivateAccount,
    @visibleForTesting this.updateMaintenance,
  });

  final AdministratorSection initialSection;
  final Future<AdministratorPortalData> Function()? dataLoader;
  final Future<void> Function()? signOut;
  final WidgetBuilder? signedOutDestinationBuilder;
  final AdministratorSuspendAccountCallback? suspendAccount;
  final AdministratorReactivateAccountCallback? reactivateAccount;
  final AdministratorMaintenanceUpdateCallback? updateMaintenance;

  @override
  State<AdministratorPortalScreen> createState() =>
      _AdministratorPortalScreenState();
}

class _AdministratorPortalScreenState extends State<AdministratorPortalScreen> {
  AdministratorService? _service;
  late AdministratorSection _section = widget.initialSection;
  late Future<AdministratorPortalData> _future = _load();

  AdministratorService get _activeService =>
      _service ??= AdministratorService();

  Future<AdministratorPortalData> _load() {
    return widget.dataLoader?.call() ?? _activeService.loadPortalData();
  }

  void _reload() {
    final next = _load();
    if (!mounted) return;
    setState(() {
      _future = next;
    });
  }

  void _reloadAfterMutation() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  Future<void> _suspendAccount(
    PlatformAccountSummary account,
    AdministratorSuspensionRequest request,
  ) async {
    await (widget.suspendAccount?.call(account, request) ??
        _activeService.suspendAccount(account, request));
    _reloadAfterMutation();
  }

  Future<void> _reactivateAccount(PlatformAccountSummary account) async {
    await (widget.reactivateAccount?.call(account) ??
        _activeService.reactivateAccount(account));
    _reloadAfterMutation();
  }

  Future<MaintenanceSettings> _updateMaintenance(
    MaintenanceUpdate update,
  ) async {
    final result =
        await (widget.updateMaintenance?.call(update) ??
            _activeService.updateMaintenance(update));
    _reloadAfterMutation();
    return result;
  }

  Future<void> _signOut() async {
    await (widget.signOut?.call() ?? _activeService.signOut());
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder:
            widget.signedOutDestinationBuilder ??
            (_) => const WebPortalLoginScreen(),
      ),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdministratorPortalData>(
      future: _future,
      builder: (context, snapshot) {
        final data = snapshot.data;
        final body = switch (snapshot.connectionState) {
          ConnectionState.none ||
          ConnectionState.waiting ||
          ConnectionState.active => const AdministratorLoadingState(),
          ConnectionState.done when snapshot.hasError =>
            AdministratorErrorState(
              message: snapshot.error.toString(),
              onRetry: _reload,
            ),
          ConnectionState.done => switch (_section) {
            AdministratorSection.overview => AdministratorDashboardScreen(
              data: data!,
            ),
            AdministratorSection.accounts => AdministratorAccountsScreen(
              accounts: data!.accounts,
              currentAdministratorId: data.profile.id,
              onSuspendAccount: _suspendAccount,
              onReactivateAccount: _reactivateAccount,
              initialSuspensions: data.activeSuspensionsByAccountId,
            ),
            AdministratorSection.tenants => AdministratorTenantsScreen(
              tenants: data!.tenants,
            ),
            AdministratorSection.configuration =>
              AdministratorConfigurationScreen(
                data: data!,
                onUpdateMaintenance: _updateMaintenance,
              ),
            AdministratorSection.integrations =>
              AdministratorIntegrationsScreen(checks: data!.healthChecks),
            AdministratorSection.security => AdministratorSecurityScreen(
              data: data!,
            ),
            AdministratorSection.developerTools =>
              const AdministratorDeveloperToolsScreen(),
            AdministratorSection.audit => AdministratorAuditLogsScreen(
              entries: data!.auditEntries,
              actorNames: data.accountNamesById,
            ),
          },
        };

        return SystemAdminShell(
          section: _section,
          profile: data?.profile,
          onSelected: (value) => setState(() => _section = value),
          onRefresh: _reload,
          onSignOut: _signOut,
          body: body,
        );
      },
    );
  }
}
