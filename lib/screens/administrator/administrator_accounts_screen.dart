import 'package:flutter/material.dart';
import 'package:touristrike/core/auth/app_role.dart';

import 'administrator_models.dart';
import 'widgets/system_admin_shared.dart';

typedef AdministratorSuspendAccountCallback =
    Future<void> Function(
      PlatformAccountSummary account,
      AdministratorSuspensionRequest request,
    );

typedef AdministratorReactivateAccountCallback =
    Future<void> Function(PlatformAccountSummary account);

class AdministratorAccountsScreen extends StatefulWidget {
  const AdministratorAccountsScreen({
    super.key,
    required this.accounts,
    this.currentAdministratorId,
    this.onSuspendAccount,
    this.onReactivateAccount,
    this.initialSuspensions = const <String, AdministratorSuspensionRecord>{},
  });

  final List<PlatformAccountSummary> accounts;

  /// Pass the authenticated administrator account ID when available.
  /// This prevents the UI from allowing self-suspension.
  final String? currentAdministratorId;

  /// Backend callback that must perform the secure suspension.
  ///
  /// The backend remains responsible for:
  /// - administrator authorization
  /// - Auth ban/session enforcement
  /// - last-administrator protection
  /// - persistence
  /// - audit logging
  final AdministratorSuspendAccountCallback? onSuspendAccount;

  /// Backend callback that must securely reactivate the account.
  final AdministratorReactivateAccountCallback? onReactivateAccount;

  /// Optional existing suspension data keyed by account/profile ID.
  final Map<String, AdministratorSuspensionRecord> initialSuspensions;

  @override
  State<AdministratorAccountsScreen> createState() =>
      _AdministratorAccountsScreenState();
}

class _AdministratorAccountsScreenState
    extends State<AdministratorAccountsScreen> {
  final TextEditingController _search = TextEditingController();

  AppRole? _role;
  PlatformAccountStatus? _status;

  final Map<String, PlatformAccountStatus> _localStatusOverrides =
      <String, PlatformAccountStatus>{};

  late final Map<String, AdministratorSuspensionRecord> _suspensions =
      Map<String, AdministratorSuspensionRecord>.from(
        widget.initialSuspensions,
      );

  bool _busy = false;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  PlatformAccountStatus _effectiveStatus(PlatformAccountSummary account) {
    return _localStatusOverrides[account.id] ?? account.status;
  }

  List<PlatformAccountSummary> get _filtered {
    final query = _search.text.trim();

    final accounts = widget.accounts
        .where(
          (account) =>
              account.matches(query) &&
              (_role == null || account.role == _role) &&
              (_status == null || _effectiveStatus(account) == _status),
        )
        .toList(growable: true);

    accounts.sort((a, b) {
      final roleComparison =
          _roleSortOrder(a.role).compareTo(_roleSortOrder(b.role));

      if (roleComparison != 0) {
        return roleComparison;
      }

      return _displayName(
        a,
      ).toLowerCase().compareTo(
        _displayName(b).toLowerCase(),
      );
    });

    return List<PlatformAccountSummary>.unmodifiable(accounts);
  }

  int _roleSortOrder(AppRole role) {
    return switch (role) {
      AppRole.administrator => 0,
      AppRole.mainTenant => 1,
      AppRole.subtenant => 2,
      AppRole.driver => 3,
      AppRole.tourist => 4,
    };
  }

  bool get _hasFilters =>
      _search.text.trim().isNotEmpty || _role != null || _status != null;

  int _countStatus(PlatformAccountStatus status) {
    return widget.accounts
        .where((account) => _effectiveStatus(account) == status)
        .length;
  }

  int _countRole(AppRole role) {
    return widget.accounts.where((account) => account.role == role).length;
  }

  int get _activeAdministratorCount {
    return widget.accounts
        .where(
          (account) =>
              account.role == AppRole.administrator &&
              _effectiveStatus(account) == PlatformAccountStatus.active,
        )
        .length;
  }

  bool _isCurrentAdministrator(PlatformAccountSummary account) {
    final currentId = widget.currentAdministratorId?.trim();

    return currentId != null && currentId.isNotEmpty && currentId == account.id;
  }

  bool _isLastUsableAdministrator(PlatformAccountSummary account) {
    return account.role == AppRole.administrator &&
        _effectiveStatus(account) == PlatformAccountStatus.active &&
        _activeAdministratorCount <= 1;
  }

  void _clearFilters() {
    setState(() {
      _search.clear();
      _role = null;
      _status = null;
    });
  }

  Future<void> _showAccountDetails(PlatformAccountSummary account) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return _AccountDetailsDialog(
          account: account,
          status: _effectiveStatus(account),
          suspension: _suspensions[account.id],
          isCurrentAdministrator: _isCurrentAdministrator(account),
          isLastUsableAdministrator: _isLastUsableAdministrator(account),
          suspensionAvailable: widget.onSuspendAccount != null,
          reactivationAvailable: widget.onReactivateAccount != null,
          busy: _busy,
          onSuspend: () {
            Navigator.of(dialogContext).pop();
            _beginSuspension(account);
          },
          onReactivate: () {
            Navigator.of(dialogContext).pop();
            _confirmReactivation(account);
          },
        );
      },
    );
  }

  Future<void> _beginSuspension(PlatformAccountSummary account) async {
    if (_isCurrentAdministrator(account)) {
      _showError(
        'You cannot suspend the administrator account currently signed in.',
      );
      return;
    }

    if (_isLastUsableAdministrator(account)) {
      _showError(
        'This account cannot be suspended because it is the last active '
        'System Administrator.',
      );
      return;
    }

    if (widget.onSuspendAccount == null) {
      _showError(
        'Account suspension is not connected to the administrator backend yet.',
      );
      return;
    }

    final request = await showDialog<AdministratorSuspensionRequest>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SuspendAccountDialog(account: account),
    );

    if (request == null || !mounted) {
      return;
    }

    final confirmed = await _showFinalSuspensionConfirmation(account, request);

    if (!confirmed || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await widget.onSuspendAccount!(account, request);

      if (!mounted) {
        return;
      }

      setState(() {
        _localStatusOverrides[account.id] = PlatformAccountStatus.suspended;

        _suspensions[account.id] = AdministratorSuspensionRecord(
          id: '',
          reason: request.reason,
          details: request.details,
          suspendedAt: request.startedAt,
          suspendedUntil: request.suspendedUntil,
          isPermanent: request.isPermanent,
          suspendedByName: 'System Administrator',
        );
      });

      _showSuccess(
        request.isPermanent
            ? '${_displayName(account)} has been suspended permanently.'
            : '${_displayName(account)} has been suspended until '
                  '${administratorDateTime(request.suspendedUntil)}.',
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showError('Unable to suspend the account.\n$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<bool> _showFinalSuspensionConfirmation(
    PlatformAccountSummary account,
    AdministratorSuspensionRequest request,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
          contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
          actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AdministratorColors.red),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Confirm account suspension',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'You are about to suspend ${_displayName(account)}.',
                  style: const TextStyle(
                    color: AdministratorColors.ink,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                _ConfirmationValue(label: 'Reason', value: request.reasonLabel),
                if (request.details.trim().isNotEmpty)
                  _ConfirmationValue(
                    label: 'Details',
                    value: request.details.trim(),
                  ),
                _ConfirmationValue(
                  label: 'Start',
                  value: administratorDateTime(request.startedAt),
                ),
                _ConfirmationValue(
                  label: 'Duration',
                  value: request.isPermanent
                      ? 'Permanent'
                      : '${request.totalDays ?? 0} day'
                            '${request.totalDays == 1 ? '' : 's'}',
                ),
                _ConfirmationValue(
                  label: 'Suspended until',
                  value: request.isPermanent
                      ? 'Until manually reactivated'
                      : administratorDateTime(request.suspendedUntil),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AdministratorColors.red.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AdministratorColors.red.withValues(alpha: 0.14),
                    ),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.block_rounded,
                        size: 18,
                        color: AdministratorColors.red,
                      ),
                      SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          'The account should be prevented from using '
                          'TourisTrike while this suspension is active.',
                          style: TextStyle(
                            color: AdministratorColors.red,
                            fontSize: 12,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AdministratorColors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.block_rounded, size: 18),
              label: const Text('Suspend Account'),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  Future<void> _confirmReactivation(PlatformAccountSummary account) async {
    if (widget.onReactivateAccount == null) {
      _showError(
        'Account reactivation is not connected to the administrator backend yet.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Reactivate account?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(
              'Reactivate ${_displayName(account)} and restore access '
              'to TourisTrike?',
              style: const TextStyle(
                color: AdministratorColors.muted,
                height: 1.45,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context, true),
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: const Text('Reactivate Account'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _busy = true;
    });

    try {
      await widget.onReactivateAccount!(account);

      if (!mounted) {
        return;
      }

      setState(() {
        _localStatusOverrides[account.id] = PlatformAccountStatus.active;
        _suspensions.remove(account.id);
      });

      _showSuccess('${_displayName(account)} has been reactivated.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showError('Unable to reactivate the account.\n$error');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.check_circle_outline_rounded,
                color: Colors.white,
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AdministratorColors.green,
        ),
      );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(message)),
            ],
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AdministratorColors.red,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _filtered;

    final totalAccounts = widget.accounts.length;

    final activeAccounts = _countStatus(PlatformAccountStatus.active);

    final pendingAccounts = _countStatus(
      PlatformAccountStatus.pendingVerification,
    );

    final suspendedAccounts = _countStatus(PlatformAccountStatus.suspended);

    return ColoredBox(
      color: AdministratorColors.background,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final horizontalPadding = constraints.maxWidth >= 1200
              ? 32.0
              : constraints.maxWidth >= 700
              ? 24.0
              : 16.0;

          return Stack(
            children: [
              ListView(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  24,
                  horizontalPadding,
                  48,
                ),
                children: [
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1440),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _AccountsHeader(
                            totalAccounts: totalAccounts,
                            activeAccounts: activeAccounts,
                          ),
                          const SizedBox(height: 22),

                          _AccountMetrics(
                            totalAccounts: totalAccounts,
                            activeAccounts: activeAccounts,
                            pendingAccounts: pendingAccounts,
                            suspendedAccounts: suspendedAccounts,
                          ),
                          const SizedBox(height: 22),

                          AdministratorPanel(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _DirectoryHeader(
                                  resultCount: accounts.length,
                                  totalCount: totalAccounts,
                                ),
                                const SizedBox(height: 18),

                                _FilterSection(
                                  search: _search,
                                  selectedRole: _role,
                                  selectedStatus: _status,
                                  hasFilters: _hasFilters,
                                  onSearchChanged: (_) {
                                    setState(() {});
                                  },
                                  onRoleChanged: (value) {
                                    setState(() {
                                      _role = value;
                                    });
                                  },
                                  onStatusChanged: (value) {
                                    setState(() {
                                      _status = value;
                                    });
                                  },
                                  onClear: _clearFilters,
                                ),

                                if (_hasFilters) ...[
                                  const SizedBox(height: 12),
                                  _ActiveFilters(
                                    searchText: _search.text,
                                    role: _role,
                                    status: _status,
                                    onClearSearch: () {
                                      setState(() {
                                        _search.clear();
                                      });
                                    },
                                    onClearRole: () {
                                      setState(() {
                                        _role = null;
                                      });
                                    },
                                    onClearStatus: () {
                                      setState(() {
                                        _status = null;
                                      });
                                    },
                                  ),
                                ],

                                const SizedBox(height: 18),

                                _ResultSummary(
                                  visible: accounts.length,
                                  total: totalAccounts,
                                  filtered: _hasFilters,
                                ),

                                const SizedBox(height: 14),

                                if (accounts.isEmpty)
                                  AdministratorEmptyState(
                                    icon: _hasFilters
                                        ? Icons.manage_search_rounded
                                        : Icons.people_outline_rounded,
                                    title: _hasFilters
                                        ? 'No matching accounts'
                                        : 'No accounts available',
                                    message: _hasFilters
                                        ? 'Try adjusting or clearing the current search and filters.'
                                        : 'Platform accounts will appear here once they are available.',
                                  )
                                else
                                  LayoutBuilder(
                                    builder: (context, innerConstraints) {
                                      if (innerConstraints.maxWidth >= 900) {
                                        return _AccountTable(
                                          accounts: accounts,
                                          statusFor: _effectiveStatus,
                                          onAccountTap: _showAccountDetails,
                                        );
                                      }

                                      return Column(
                                        children: [
                                          for (
                                            var index = 0;
                                            index < accounts.length;
                                            index++
                                          )
                                            Padding(
                                              padding: EdgeInsets.only(
                                                bottom:
                                                    index == accounts.length - 1
                                                    ? 0
                                                    : 12,
                                              ),
                                              child: _AccountCard(
                                                account: accounts[index],
                                                status: _effectiveStatus(
                                                  accounts[index],
                                                ),
                                                onTap: _showAccountDetails,
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 22),

                          _RoleOverview(
                            accounts: widget.accounts,
                            countRole: _countRole,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              if (_busy)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.10),
                    child: const Center(
                      child: Card(
                        elevation: 4,
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 18,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              ),
                              SizedBox(width: 13),
                              Text(
                                'Updating account...',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _AccountsHeader extends StatelessWidget {
  const _AccountsHeader({
    required this.totalAccounts,
    required this.activeAccounts,
  });

  final int totalAccounts;
  final int activeAccounts;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF102E61), Color(0xFF155EEF)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF155EEF).withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.manage_accounts_outlined,
                      color: Color(0xFFD8E6FF),
                      size: 15,
                    ),
                    SizedBox(width: 6),
                    Text(
                      'USERS & ROLES',
                      style: TextStyle(
                        color: Color(0xFFD8E6FF),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Platform account directory',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  height: 1.15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 7),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 650),
                child: Text(
                  'Review identities, role assignments, verification states, '
                  'locations, account status, and recent sign-in visibility '
                  'across TourisTrike.',
                  style: TextStyle(
                    color: Color(0xFFDDE8FF),
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          );

          final summary = Container(
            constraints: const BoxConstraints(minWidth: 210),
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 43,
                  height: 43,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.13),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.people_alt_outlined,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$totalAccounts',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$activeAccounts active accounts',
                      style: const TextStyle(
                        color: Color(0xFFDDE8FF),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [content, const SizedBox(height: 20), summary],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: content),
              const SizedBox(width: 24),
              summary,
            ],
          );
        },
      ),
    );
  }
}

class _AccountMetrics extends StatelessWidget {
  const _AccountMetrics({
    required this.totalAccounts,
    required this.activeAccounts,
    required this.pendingAccounts,
    required this.suspendedAccounts,
  });

  final int totalAccounts;
  final int activeAccounts;
  final int pendingAccounts;
  final int suspendedAccounts;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;

        final columns = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 680
            ? 2
            : 1;

        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        final metrics = <Widget>[
          _AccountMetricCard(
            label: 'Total accounts',
            value: '$totalAccounts',
            helper: 'All registered platform accounts',
            icon: Icons.groups_2_outlined,
            color: AdministratorColors.blue,
          ),
          _AccountMetricCard(
            label: 'Active',
            value: '$activeAccounts',
            helper: 'Verified and active accounts',
            icon: Icons.verified_user_outlined,
            color: AdministratorColors.green,
          ),
          _AccountMetricCard(
            label: 'Pending verification',
            value: '$pendingAccounts',
            helper: 'Accounts awaiting verification',
            icon: Icons.mark_email_unread_outlined,
            color: AdministratorColors.amber,
          ),
          _AccountMetricCard(
            label: 'Suspended',
            value: '$suspendedAccounts',
            helper: 'Restricted platform accounts',
            icon: Icons.block_outlined,
            color: AdministratorColors.red,
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final metric in metrics)
              SizedBox(width: itemWidth, child: metric),
          ],
        );
      },
    );
  }
}

class _AccountMetricCard extends StatelessWidget {
  const _AccountMetricCard({
    required this.label,
    required this.value,
    required this.helper,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String helper;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 125),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdministratorColors.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    color: AdministratorColors.ink,
                    fontSize: 24,
                    height: 1,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  label,
                  style: const TextStyle(
                    color: AdministratorColors.ink,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  helper,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AdministratorColors.muted,
                    fontSize: 10.8,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DirectoryHeader extends StatelessWidget {
  const _DirectoryHeader({required this.resultCount, required this.totalCount});

  final int resultCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 10,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Users & roles directory',
              style: TextStyle(
                color: AdministratorColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 3),
            Text(
              'Select an account to review details and account controls',
              style: TextStyle(
                color: AdministratorColors.muted,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AdministratorColors.blue.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.people_outline_rounded,
                size: 15,
                color: AdministratorColors.blue,
              ),
              const SizedBox(width: 6),
              Text(
                '$resultCount / $totalCount',
                style: const TextStyle(
                  color: AdministratorColors.blue,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterSection extends StatelessWidget {
  const _FilterSection({
    required this.search,
    required this.selectedRole,
    required this.selectedStatus,
    required this.hasFilters,
    required this.onSearchChanged,
    required this.onRoleChanged,
    required this.onStatusChanged,
    required this.onClear,
  });

  final TextEditingController search;
  final AppRole? selectedRole;
  final PlatformAccountStatus? selectedStatus;
  final bool hasFilters;

  final ValueChanged<String> onSearchChanged;
  final ValueChanged<AppRole?> onRoleChanged;
  final ValueChanged<PlatformAccountStatus?> onStatusChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AdministratorColors.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < 720) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SearchField(controller: search, onChanged: onSearchChanged),
                const SizedBox(height: 10),
                AdministratorDropdownFilter<AppRole>(
                  value: selectedRole,
                  hint: 'All roles',
                  values: AppRole.values,
                  label: (value) => value.displayName,
                  onChanged: onRoleChanged,
                ),
                const SizedBox(height: 10),
                AdministratorDropdownFilter<PlatformAccountStatus>(
                  value: selectedStatus,
                  hint: 'All statuses',
                  values: PlatformAccountStatus.values,
                  label: administratorAccountStatusLabel,
                  onChanged: onStatusChanged,
                ),
                if (hasFilters) ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
                    label: const Text('Clear filters'),
                  ),
                ],
              ],
            );
          }

          return Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: constraints.maxWidth >= 1000 ? 420 : 320,
                child: _SearchField(
                  controller: search,
                  onChanged: onSearchChanged,
                ),
              ),
              AdministratorDropdownFilter<AppRole>(
                value: selectedRole,
                hint: 'All roles',
                values: AppRole.values,
                label: (value) => value.displayName,
                onChanged: onRoleChanged,
              ),
              AdministratorDropdownFilter<PlatformAccountStatus>(
                value: selectedStatus,
                hint: 'All statuses',
                values: PlatformAccountStatus.values,
                label: administratorAccountStatusLabel,
                onChanged: onStatusChanged,
              ),
              if (hasFilters)
                TextButton.icon(
                  onPressed: onClear,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
                  label: const Text('Clear'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search name, email, role, city, or account ID',
        hintStyle: const TextStyle(
          color: AdministratorColors.muted,
          fontSize: 12.5,
        ),
        prefixIcon: const Icon(Icons.search_rounded, size: 20),
        suffixIcon: controller.text.trim().isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 15,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdministratorColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AdministratorColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: AdministratorColors.blue,
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class _ActiveFilters extends StatelessWidget {
  const _ActiveFilters({
    required this.searchText,
    required this.role,
    required this.status,
    required this.onClearSearch,
    required this.onClearRole,
    required this.onClearStatus,
  });

  final String searchText;
  final AppRole? role;
  final PlatformAccountStatus? status;

  final VoidCallback onClearSearch;
  final VoidCallback onClearRole;
  final VoidCallback onClearStatus;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 2),
          child: Text(
            'Active filters:',
            style: TextStyle(
              color: AdministratorColors.muted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (searchText.trim().isNotEmpty)
          _FilterChip(
            icon: Icons.search_rounded,
            label: '"${searchText.trim()}"',
            onDeleted: onClearSearch,
          ),
        if (role != null)
          _FilterChip(
            icon: administratorRoleIcon(role!),
            label: role!.displayName,
            onDeleted: onClearRole,
          ),
        if (status != null)
          _FilterChip(
            icon: Icons.circle_outlined,
            label: administratorAccountStatusLabel(status!),
            onDeleted: onClearStatus,
          ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.icon,
    required this.label,
    required this.onDeleted,
  });

  final IconData icon;
  final String label;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 9, right: 3, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AdministratorColors.blue.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AdministratorColors.blue.withValues(alpha: 0.12),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AdministratorColors.blue),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AdministratorColors.blue,
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onDeleted,
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                size: 13,
                color: AdministratorColors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultSummary extends StatelessWidget {
  const _ResultSummary({
    required this.visible,
    required this.total,
    required this.filtered,
  });

  final int visible;
  final int total;
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          filtered ? Icons.filter_alt_outlined : Icons.touch_app_outlined,
          size: 16,
          color: AdministratorColors.muted,
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            filtered
                ? 'Showing $visible matching account'
                      '${visible == 1 ? '' : 's'} out of $total'
                : '$total account${total == 1 ? '' : 's'} available • '
                      'Select a row to view account details',
            style: const TextStyle(
              color: AdministratorColors.muted,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountTable extends StatelessWidget {
  const _AccountTable({
    required this.accounts,
    required this.statusFor,
    required this.onAccountTap,
  });

  final List<PlatformAccountSummary> accounts;

  final PlatformAccountStatus Function(PlatformAccountSummary account)
  statusFor;

  final ValueChanged<PlatformAccountSummary> onAccountTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AdministratorColors.line),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const _AccountTableHeader(),
          for (var index = 0; index < accounts.length; index++) ...[
            _AccountTableRow(
              account: accounts[index],
              status: statusFor(accounts[index]),
              onTap: () => onAccountTap(accounts[index]),
            ),
            if (index < accounts.length - 1)
              const Divider(
                height: 1,
                thickness: 1,
                color: AdministratorColors.line,
              ),
          ],
        ],
      ),
    );
  }
}

class _AccountTableHeader extends StatelessWidget {
  const _AccountTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 50),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: AdministratorColors.line)),
      ),
      child: const Row(
        children: [
          Expanded(flex: 28, child: _TableHeaderText('ACCOUNT')),
          SizedBox(width: 18),
          Expanded(flex: 16, child: _TableHeaderText('ROLE')),
          SizedBox(width: 18),
          Expanded(flex: 13, child: _TableHeaderText('STATUS')),
          SizedBox(width: 18),
          Expanded(flex: 17, child: _TableHeaderText('LOCATION')),
          SizedBox(width: 18),
          Expanded(flex: 17, child: _TableHeaderText('LAST SIGN-IN')),
          SizedBox(width: 18),
          Expanded(flex: 13, child: _TableHeaderText('CREATED')),
        ],
      ),
    );
  }
}

class _AccountTableRow extends StatelessWidget {
  const _AccountTableRow({
    required this.account,
    required this.status,
    required this.onTap,
  });

  final PlatformAccountSummary account;
  final PlatformAccountStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        hoverColor: const Color(0xFFF6F9FE),
        splashColor: AdministratorColors.blue.withValues(alpha: 0.05),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(flex: 28, child: _AccountIdentity(account: account)),
              const SizedBox(width: 18),

              Expanded(
                flex: 16,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _RoleBadge(role: account.role),
                ),
              ),
              const SizedBox(width: 18),

              Expanded(
                flex: 13,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: AdministratorAccountStatusBadge(status: status),
                ),
              ),
              const SizedBox(width: 18),

              Expanded(
                flex: 17,
                child: _TableValueWithIcon(
                  icon: Icons.location_on_outlined,
                  value: administratorAccountLocation(account),
                ),
              ),
              const SizedBox(width: 18),

              Expanded(
                flex: 17,
                child: _TableValueWithIcon(
                  icon: Icons.login_rounded,
                  value: administratorDateTime(account.lastSignInAt),
                ),
              ),
              const SizedBox(width: 18),

              Expanded(
                flex: 13,
                child: _TableValueWithIcon(
                  icon: Icons.calendar_today_outlined,
                  value: administratorDate(account.createdAt),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableHeaderText extends StatelessWidget {
  const _TableHeaderText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: AdministratorColors.muted,
        fontSize: 10.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    );
  }
}

class _TableValueWithIcon extends StatelessWidget {
  const _TableValueWithIcon({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 14, color: AdministratorColors.muted),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AdministratorColors.ink,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.3,
            ),
          ),
        ),
      ],
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.status,
    required this.onTap,
  });

  final PlatformAccountSummary account;
  final PlatformAccountStatus status;

  final ValueChanged<PlatformAccountSummary> onTap;

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(account.role);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => onTap(account),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AdministratorColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _AccountIdentity(account: account)),
                  const SizedBox(width: 10),
                  AdministratorAccountStatusBadge(status: status),
                ],
              ),
              const SizedBox(height: 14),
              const Divider(height: 1, color: AdministratorColors.line),
              const SizedBox(height: 13),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MobileDetailChip(
                    icon: administratorRoleIcon(account.role),
                    label: account.role.displayName,
                    color: roleColor,
                  ),
                  _MobileDetailChip(
                    icon: Icons.location_on_outlined,
                    label: administratorAccountLocation(account),
                    color: AdministratorColors.blue,
                  ),
                ],
              ),
              const SizedBox(height: 13),
              _MobileInformationRow(
                icon: Icons.login_rounded,
                label: 'Last sign-in',
                value: administratorDateTime(account.lastSignInAt),
              ),
              const SizedBox(height: 9),
              _MobileInformationRow(
                icon: Icons.calendar_today_outlined,
                label: 'Created',
                value: administratorDate(account.createdAt),
              ),
              const SizedBox(height: 12),
              const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'View account',
                    style: TextStyle(
                      color: AdministratorColors.blue,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: AdministratorColors.blue,
                    size: 18,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileDetailChip extends StatelessWidget {
  const _MobileDetailChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileInformationRow extends StatelessWidget {
  const _MobileInformationRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFFF4F7FB),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: AdministratorColors.muted),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AdministratorColors.muted,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  color: AdministratorColors.ink,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccountIdentity extends StatelessWidget {
  const _AccountIdentity({required this.account});

  final PlatformAccountSummary account;

  @override
  Widget build(BuildContext context) {
    final displayName = _displayName(account);

    final secondaryText = account.email.trim().isEmpty
        ? account.id
        : account.email.trim();

    final initial = displayName == 'Unnamed account'
        ? '?'
        : displayName[0].toUpperCase();

    final color = _roleColor(account.role);

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            shape: BoxShape.circle,
            border: Border.all(color: color.withValues(alpha: 0.10)),
          ),
          child: Text(
            initial,
            style: TextStyle(
              color: color,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AdministratorColors.ink,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(
                    account.email.trim().isEmpty
                        ? Icons.fingerprint_rounded
                        : Icons.alternate_email_rounded,
                    size: 12,
                    color: AdministratorColors.muted,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      secondaryText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AdministratorColors.muted,
                        fontSize: 10.8,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final color = _roleColor(role);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(administratorRoleIcon(role), size: 14, color: color),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              role.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountDetailsDialog extends StatelessWidget {
  const _AccountDetailsDialog({
    required this.account,
    required this.status,
    required this.suspension,
    required this.isCurrentAdministrator,
    required this.isLastUsableAdministrator,
    required this.suspensionAvailable,
    required this.reactivationAvailable,
    required this.busy,
    required this.onSuspend,
    required this.onReactivate,
  });

  final PlatformAccountSummary account;
  final PlatformAccountStatus status;
  final AdministratorSuspensionRecord? suspension;

  final bool isCurrentAdministrator;
  final bool isLastUsableAdministrator;
  final bool suspensionAvailable;
  final bool reactivationAvailable;
  final bool busy;

  final VoidCallback onSuspend;
  final VoidCallback onReactivate;

  @override
  Widget build(BuildContext context) {
    final roleColor = _roleColor(account.role);

    final isSuspended = status == PlatformAccountStatus.suspended;

    final canSuspend =
        status == PlatformAccountStatus.active &&
        !isCurrentAdministrator &&
        !isLastUsableAdministrator &&
        suspensionAvailable &&
        !busy;

    final canReactivate = isSuspended && reactivationAvailable && !busy;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 660, maxHeight: 760),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 20, 18, 18),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(
                  bottom: BorderSide(color: AdministratorColors.line),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: roleColor.withValues(alpha: 0.09),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      _accountInitial(account),
                      style: TextStyle(
                        color: roleColor,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName(account),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AdministratorColors.ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          account.email.trim().isEmpty
                              ? account.id
                              : account.email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AdministratorColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  AdministratorAccountStatusBadge(status: status),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _DialogSectionTitle(
                      title: 'Account information',
                      subtitle:
                          'Identity and access information for this platform account',
                    ),
                    const SizedBox(height: 12),

                    _AccountDetailGrid(
                      children: [
                        _AccountDetailTile(
                          icon: administratorRoleIcon(account.role),
                          label: 'Role',
                          value: account.role.displayName,
                          color: roleColor,
                        ),
                        _AccountDetailTile(
                          icon: Icons.shield_outlined,
                          label: 'Status',
                          value: administratorAccountStatusLabel(status),
                          color: _statusColor(status),
                        ),
                        _AccountDetailTile(
                          icon: Icons.location_on_outlined,
                          label: 'Location',
                          value: administratorAccountLocation(account),
                        ),
                        _AccountDetailTile(
                          icon: Icons.login_rounded,
                          label: 'Last sign-in',
                          value: administratorDateTime(account.lastSignInAt),
                        ),
                        _AccountDetailTile(
                          icon: Icons.calendar_today_outlined,
                          label: 'Account created',
                          value: administratorDate(account.createdAt),
                        ),
                        _AccountDetailTile(
                          icon: Icons.fingerprint_rounded,
                          label: 'Account ID',
                          value: account.id,
                        ),
                      ],
                    ),

                    if (isSuspended) ...[
                      const SizedBox(height: 22),

                      const _DialogSectionTitle(
                        title: 'Suspension details',
                        subtitle: 'Current restriction applied to this account',
                      ),

                      const SizedBox(height: 12),

                      _SuspensionInformationCard(suspension: suspension),
                    ],

                    if (isCurrentAdministrator ||
                        isLastUsableAdministrator) ...[
                      const SizedBox(height: 20),
                      _ProtectionNotice(
                        message: isCurrentAdministrator
                            ? 'You cannot suspend the System Administrator account currently signed in.'
                            : 'This is the last active System Administrator and cannot be suspended.',
                      ),
                    ],

                    if (!isSuspended && !suspensionAvailable) ...[
                      const SizedBox(height: 20),
                      const _ProtectionNotice(
                        message:
                            'Suspension controls are visible, but the secure backend suspension callback has not been connected yet.',
                        neutral: true,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  top: BorderSide(color: AdministratorColors.line),
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 460) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Close'),
                        ),
                        const SizedBox(height: 9),
                        if (isSuspended)
                          FilledButton.icon(
                            onPressed: canReactivate ? onReactivate : null,
                            icon: const Icon(
                              Icons.check_circle_outline_rounded,
                            ),
                            label: const Text('Reactivate Account'),
                          )
                        else if (status == PlatformAccountStatus.active)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AdministratorColors.red,
                              foregroundColor: Colors.white,
                            ),
                            onPressed: canSuspend ? onSuspend : null,
                            icon: const Icon(Icons.block_rounded),
                            label: const Text('Suspend Account'),
                          ),
                      ],
                    );
                  }

                  return Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close'),
                      ),
                      const SizedBox(width: 10),
                      if (isSuspended)
                        FilledButton.icon(
                          onPressed: canReactivate ? onReactivate : null,
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          label: const Text('Reactivate Account'),
                        )
                      else if (status == PlatformAccountStatus.active)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: AdministratorColors.red,
                            foregroundColor: Colors.white,
                          ),
                          onPressed: canSuspend ? onSuspend : null,
                          icon: const Icon(Icons.block_rounded),
                          label: const Text('Suspend Account'),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountDetailGrid extends StatelessWidget {
  const _AccountDetailGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 10.0;

        final columns = constraints.maxWidth >= 520 ? 2 : 1;

        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _AccountDetailTile extends StatelessWidget {
  const _AccountDetailTile({
    required this.icon,
    required this.label,
    required this.value,
    this.color = AdministratorColors.blue,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 78),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: AdministratorColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AdministratorColors.muted,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AdministratorColors.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DialogSectionTitle extends StatelessWidget {
  const _DialogSectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AdministratorColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: AdministratorColors.muted,
            fontSize: 11,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _SuspensionInformationCard extends StatelessWidget {
  const _SuspensionInformationCard({required this.suspension});

  final AdministratorSuspensionRecord? suspension;

  @override
  Widget build(BuildContext context) {
    if (suspension == null) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AdministratorColors.red.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AdministratorColors.red.withValues(alpha: 0.14),
          ),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.block_outlined, color: AdministratorColors.red),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'This account is currently marked as suspended. '
                'Detailed suspension metadata is not available in the '
                'current account payload.',
                style: TextStyle(
                  color: AdministratorColors.red,
                  fontSize: 11.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final duration = suspension!.isPermanent
        ? 'Permanent'
        : '${suspension!.totalDays ?? 0} day'
              '${suspension!.totalDays == 1 ? '' : 's'}';

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AdministratorColors.red.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AdministratorColors.red.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        children: [
          _SuspensionInfoRow(label: 'Reason', value: suspension!.reasonLabel),
          if (suspension!.details.trim().isNotEmpty)
            _SuspensionInfoRow(
              label: 'Details',
              value: suspension!.details.trim(),
            ),
          _SuspensionInfoRow(
            label: 'Suspended at',
            value: administratorDateTime(suspension!.suspendedAt),
          ),
          _SuspensionInfoRow(label: 'Duration', value: duration),
          _SuspensionInfoRow(
            label: 'Suspended until',
            value: suspension!.isPermanent
                ? 'Until manually reactivated'
                : administratorDateTime(suspension!.suspendedUntil),
          ),
          if (suspension!.suspendedByName.trim().isNotEmpty)
            _SuspensionInfoRow(
              label: 'Suspended by',
              value: suspension!.suspendedByName.trim(),
              last: true,
            ),
        ],
      ),
    );
  }
}

class _SuspensionInfoRow extends StatelessWidget {
  const _SuspensionInfoRow({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                color: AdministratorColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AdministratorColors.ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProtectionNotice extends StatelessWidget {
  const _ProtectionNotice({required this.message, this.neutral = false});

  final String message;
  final bool neutral;

  @override
  Widget build(BuildContext context) {
    final color = neutral
        ? AdministratorColors.blue
        : AdministratorColors.amber;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            neutral ? Icons.info_outline_rounded : Icons.shield_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 11.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SuspendAccountDialog extends StatefulWidget {
  const _SuspendAccountDialog({required this.account});

  final PlatformAccountSummary account;

  @override
  State<_SuspendAccountDialog> createState() => _SuspendAccountDialogState();
}

class _SuspendAccountDialogState extends State<_SuspendAccountDialog> {
  final TextEditingController _details = TextEditingController();

  final TextEditingController _customDays = TextEditingController();

  AdministratorSuspensionReason? _reason;

  AdministratorSuspensionDuration _duration =
      AdministratorSuspensionDuration.sevenDays;

  String? _reasonError;
  String? _detailsError;
  String? _customDaysError;

  @override
  void dispose() {
    _details.dispose();
    _customDays.dispose();
    super.dispose();
  }

  int? get _durationDays {
    return switch (_duration) {
      AdministratorSuspensionDuration.oneDay => 1,
      AdministratorSuspensionDuration.threeDays => 3,
      AdministratorSuspensionDuration.sevenDays => 7,
      AdministratorSuspensionDuration.fourteenDays => 14,
      AdministratorSuspensionDuration.thirtyDays => 30,
      AdministratorSuspensionDuration.custom => int.tryParse(
        _customDays.text.trim(),
      ),
      AdministratorSuspensionDuration.permanent => null,
    };
  }

  DateTime? get _previewEnd {
    if (_duration == AdministratorSuspensionDuration.permanent) {
      return null;
    }

    final days = _durationDays;

    if (days == null || days <= 0) {
      return null;
    }

    return DateTime.now().add(Duration(days: days));
  }

  bool _validate() {
    final reason = _reason;

    String? reasonError;
    String? detailsError;
    String? customDaysError;

    if (reason == null) {
      reasonError = 'Select a suspension reason.';
    }

    if (reason == AdministratorSuspensionReason.other &&
        _details.text.trim().isEmpty) {
      detailsError = 'Enter the custom suspension reason.';
    }

    if (_duration == AdministratorSuspensionDuration.custom) {
      final value = int.tryParse(_customDays.text.trim());

      if (value == null || value <= 0) {
        customDaysError = 'Enter a valid number of days.';
      } else if (value > 3650) {
        customDaysError = 'Custom suspension cannot exceed 3650 days.';
      }
    }

    setState(() {
      _reasonError = reasonError;
      _detailsError = detailsError;
      _customDaysError = customDaysError;
    });

    return reasonError == null &&
        detailsError == null &&
        customDaysError == null;
  }

  void _submit() {
    if (!_validate()) {
      return;
    }

    final startedAt = DateTime.now();

    final permanent = _duration == AdministratorSuspensionDuration.permanent;

    final days = _durationDays;

    final suspendedUntil = permanent
        ? null
        : startedAt.add(Duration(days: days!));

    Navigator.pop(
      context,
      AdministratorSuspensionRequest(
        reason: _reason!,
        details: _details.text.trim(),
        startedAt: startedAt,
        suspendedUntil: suspendedUntil,
        isPermanent: permanent,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final permanent = _duration == AdministratorSuspensionDuration.permanent;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 820),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(22, 20, 18, 18),
              decoration: BoxDecoration(
                color: AdministratorColors.red.withValues(alpha: 0.045),
                border: const Border(
                  bottom: BorderSide(color: AdministratorColors.line),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AdministratorColors.red.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Icon(
                      Icons.block_rounded,
                      color: AdministratorColors.red,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Suspend Account',
                          style: TextStyle(
                            color: AdministratorColors.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _displayName(widget.account),
                          style: const TextStyle(
                            color: AdministratorColors.muted,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),

            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _FieldLabel(
                      label: 'Suspension reason',
                      requiredField: true,
                    ),
                    const SizedBox(height: 7),

                    DropdownButtonFormField<AdministratorSuspensionReason>(
                      initialValue: _reason,
                      isExpanded: true,
                      decoration: InputDecoration(
                        hintText: 'Select a reason',
                        errorText: _reasonError,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      items: AdministratorSuspensionReason.values
                          .map(
                            (reason) => DropdownMenuItem(
                              value: reason,
                              child: Text(
                                administratorSuspensionReasonLabel(reason),
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setState(() {
                          _reason = value;
                          _reasonError = null;

                          if (value != AdministratorSuspensionReason.other) {
                            _detailsError = null;
                          }
                        });
                      },
                    ),

                    const SizedBox(height: 18),

                    _FieldLabel(
                      label: _reason == AdministratorSuspensionReason.other
                          ? 'Custom reason'
                          : 'Additional notes',
                      requiredField:
                          _reason == AdministratorSuspensionReason.other,
                    ),

                    const SizedBox(height: 7),

                    TextField(
                      controller: _details,
                      minLines: 3,
                      maxLines: 5,
                      maxLength: 500,
                      decoration: InputDecoration(
                        hintText: _reason == AdministratorSuspensionReason.other
                            ? 'Explain why this account is being suspended...'
                            : 'Optional details about the suspension...',
                        errorText: _detailsError,
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onChanged: (_) {
                        if (_detailsError != null) {
                          setState(() {
                            _detailsError = null;
                          });
                        }
                      },
                    ),

                    const SizedBox(height: 12),

                    const _FieldLabel(
                      label: 'Suspension duration',
                      requiredField: true,
                    ),

                    const SizedBox(height: 9),

                    _DurationSelector(
                      selected: _duration,
                      onChanged: (value) {
                        setState(() {
                          _duration = value;

                          if (value != AdministratorSuspensionDuration.custom) {
                            _customDaysError = null;
                          }
                        });
                      },
                    ),

                    if (_duration ==
                        AdministratorSuspensionDuration.custom) ...[
                      const SizedBox(height: 14),

                      const _FieldLabel(
                        label: 'Number of suspension days',
                        requiredField: true,
                      ),

                      const SizedBox(height: 7),

                      TextField(
                        controller: _customDays,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Enter number of days',
                          suffixText: 'days',
                          errorText: _customDaysError,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onChanged: (_) {
                          setState(() {
                            _customDaysError = null;
                          });
                        },
                      ),
                    ],

                    const SizedBox(height: 18),

                    _SuspensionPreview(
                      duration: _duration,
                      days: _durationDays,
                      end: _previewEnd,
                    ),

                    if (permanent) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AdministratorColors.red.withValues(
                            alpha: 0.06,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AdministratorColors.red.withValues(
                              alpha: 0.14,
                            ),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: AdministratorColors.red,
                              size: 18,
                            ),
                            SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                'Permanent suspension will remain active until a System Administrator manually reactivates the account.',
                                style: TextStyle(
                                  color: AdministratorColors.red,
                                  fontSize: 11.5,
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            Container(
              padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
              decoration: const BoxDecoration(
                border: Border(
                  top: BorderSide(color: AdministratorColors.line),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 9),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AdministratorColors.red,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: _submit,
                    icon: const Icon(Icons.block_rounded, size: 18),
                    label: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DurationSelector extends StatelessWidget {
  const _DurationSelector({required this.selected, required this.onChanged});

  final AdministratorSuspensionDuration selected;

  final ValueChanged<AdministratorSuspensionDuration> onChanged;

  @override
  Widget build(BuildContext context) {
    return RadioGroup<AdministratorSuspensionDuration>(
      groupValue: selected,
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
      child: Column(
        children: [
          for (
            var index = 0;
            index < AdministratorSuspensionDuration.values.length;
            index++
          )
            Padding(
              padding: EdgeInsets.only(
                bottom:
                    index == AdministratorSuspensionDuration.values.length - 1
                    ? 0
                    : 7,
              ),
              child: _DurationOption(
                duration: AdministratorSuspensionDuration.values[index],
                selected:
                    selected == AdministratorSuspensionDuration.values[index],
                onTap: () =>
                    onChanged(AdministratorSuspensionDuration.values[index]),
              ),
            ),
        ],
      ),
    );
  }
}

class _DurationOption extends StatelessWidget {
  const _DurationOption({
    required this.duration,
    required this.selected,
    required this.onTap,
  });

  final AdministratorSuspensionDuration duration;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final permanent = duration == AdministratorSuspensionDuration.permanent;

    final color = permanent
        ? AdministratorColors.red
        : AdministratorColors.blue;

    return Material(
      color: selected ? color.withValues(alpha: 0.06) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? color : AdministratorColors.line,
            ),
          ),
          child: Row(
            children: [
              Radio<AdministratorSuspensionDuration>(
                value: duration,
                activeColor: color,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  administratorSuspensionDurationLabel(duration),
                  style: TextStyle(
                    color: permanent
                        ? AdministratorColors.red
                        : AdministratorColors.ink,
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (permanent)
                const Icon(
                  Icons.lock_outline_rounded,
                  size: 17,
                  color: AdministratorColors.red,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuspensionPreview extends StatelessWidget {
  const _SuspensionPreview({
    required this.duration,
    required this.days,
    required this.end,
  });

  final AdministratorSuspensionDuration duration;
  final int? days;
  final DateTime? end;

  @override
  Widget build(BuildContext context) {
    final permanent = duration == AdministratorSuspensionDuration.permanent;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdministratorColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Suspension summary',
            style: TextStyle(
              color: AdministratorColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 11),

          _ConfirmationValue(
            label: 'Starts',
            value: administratorDateTime(DateTime.now()),
          ),

          _ConfirmationValue(
            label: 'Duration',
            value: permanent
                ? 'Permanent'
                : days == null || days! <= 0
                ? 'Enter a valid duration'
                : '$days day${days == 1 ? '' : 's'}',
          ),

          _ConfirmationValue(
            label: 'Ends',
            value: permanent
                ? 'Until manually reactivated'
                : end == null
                ? 'Pending duration'
                : administratorDateTime(end),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.label, this.requiredField = false});

  final String label;
  final bool requiredField;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AdministratorColors.ink,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (requiredField) ...[
          const SizedBox(width: 3),
          const Text(
            '*',
            style: TextStyle(
              color: AdministratorColors.red,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ],
    );
  }
}

class _ConfirmationValue extends StatelessWidget {
  const _ConfirmationValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 118,
            child: Text(
              label,
              style: const TextStyle(
                color: AdministratorColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AdministratorColors.ink,
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleOverview extends StatelessWidget {
  const _RoleOverview({required this.accounts, required this.countRole});

  final List<PlatformAccountSummary> accounts;

  final int Function(AppRole role) countRole;

  @override
  Widget build(BuildContext context) {
    return AdministratorPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Role distribution',
            style: TextStyle(
              color: AdministratorColors.ink,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Current account distribution across TourisTrike access levels',
            style: TextStyle(
              color: AdministratorColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 10.0;

              final columns = constraints.maxWidth >= 1000
                  ? AppRole.values.length
                  : constraints.maxWidth >= 650
                  ? 2
                  : 1;

              final width =
                  (constraints.maxWidth - (spacing * (columns - 1))) / columns;

              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final role in AppRole.values)
                    SizedBox(
                      width: width,
                      child: _RoleSummaryCard(
                        role: role,
                        count: countRole(role),
                        total: accounts.length,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RoleSummaryCard extends StatelessWidget {
  const _RoleSummaryCard({
    required this.role,
    required this.count,
    required this.total,
  });

  final AppRole role;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final color = _roleColor(role);

    final percentage = total == 0 ? 0.0 : count / total;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdministratorColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 35,
                height: 35,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  administratorRoleIcon(role),
                  size: 18,
                  color: color,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  role.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AdministratorColors.ink,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: percentage.clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFE9EEF5),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            total == 0
                ? '0% of accounts'
                : '${(percentage * 100).toStringAsFixed(0)}% of accounts',
            style: const TextStyle(
              color: AdministratorColors.muted,
              fontSize: 9.8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

String _displayName(PlatformAccountSummary account) {
  final name = account.name.trim();

  return name.isEmpty ? 'Unnamed account' : name;
}

String _accountInitial(PlatformAccountSummary account) {
  final name = _displayName(account);

  return name == 'Unnamed account' ? '?' : name[0].toUpperCase();
}

Color _statusColor(PlatformAccountStatus status) {
  return switch (status) {
    PlatformAccountStatus.active => AdministratorColors.green,
    PlatformAccountStatus.pendingVerification => AdministratorColors.amber,
    PlatformAccountStatus.suspended => AdministratorColors.red,
    PlatformAccountStatus.unknown => AdministratorColors.muted,
  };
}

Color _roleColor(AppRole role) {
  return switch (role) {
    AppRole.administrator => const Color(0xFF155EEF),
    AppRole.mainTenant => const Color(0xFF7A5AF8),
    AppRole.subtenant => const Color(0xFF0BA5EC),
    AppRole.driver => const Color(0xFF079455),
    AppRole.tourist => const Color(0xFFF79009),
  };
}
