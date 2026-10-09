import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/auth/app_role.dart';

import 'administrator_models.dart';
import 'widgets/system_admin_shared.dart';

class AdministratorSecurityScreen extends StatelessWidget {
  const AdministratorSecurityScreen({super.key, required this.data});

  final AdministratorPortalData data;

  @override
  Widget build(BuildContext context) {
    final authMetadataAccounts = data.accounts
        .where((account) => account.authMetadataAvailable)
        .length;
    final guardOperational = data.healthChecks.any(
      (check) =>
          check.name == 'Authentication and role guard' && check.isOperational,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 40),
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            AdministratorMetric(
              label: 'Auth metadata available',
              value: '$authMetadataAccounts/${data.accounts.length}',
              icon: Icons.key_outlined,
              color: AdministratorColors.blue,
            ),
            AdministratorMetric(
              label: 'Pending verification',
              value: data.statusCount(
                PlatformAccountStatus.pendingVerification,
              ),
              icon: Icons.mark_email_unread_outlined,
              color: AdministratorColors.amber,
            ),
            AdministratorMetric(
              label: 'Suspended accounts',
              value: data.statusCount(PlatformAccountStatus.suspended),
              icon: Icons.block_outlined,
              color: AdministratorColors.red,
            ),
          ],
        ),
        const SizedBox(height: 18),
        AdministratorPanel(
          title: 'Current administrator session',
          subtitle: 'Authenticated identity and enforced access boundary',
          child: Column(
            children: [
              AdministratorLabelValueRow(
                label: data.profile.name,
                value: data.profile.role.displayName,
                icon: Icons.person_outline_rounded,
              ),
              AdministratorLabelValueRow(
                label: data.profile.email.isEmpty
                    ? 'Authenticated account'
                    : data.profile.email,
                value: guardOperational ? 'Verified' : 'Degraded',
                icon: Icons.shield_outlined,
                color: guardOperational
                    ? AdministratorColors.green
                    : AdministratorColors.amber,
              ),
              AdministratorLabelValueRow(
                label: 'Technical role',
                value: data.profile.role.databaseValue,
                icon: Icons.admin_panel_settings_outlined,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AdministratorPanel(
          title: 'Security controls',
          subtitle: 'Observed controls for this portal session',
          child: Column(
            children: [
              AdministratorLabelValueRow(
                label: 'Administrator role guard',
                value: guardOperational ? 'Operational' : 'Degraded',
                icon: Icons.verified_user_outlined,
                color: guardOperational
                    ? AdministratorColors.green
                    : AdministratorColors.amber,
              ),
              AdministratorLabelValueRow(
                label: 'Canonical role boundaries',
                value: '${AppRole.values.length} roles',
                icon: Icons.account_tree_outlined,
              ),
              const AdministratorLabelValueRow(
                label: 'Portal operations',
                value: 'Role guarded',
                icon: Icons.verified_user_outlined,
                color: AdministratorColors.green,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _BookingRestrictionAppeals(accounts: data.accounts),
      ],
    );
  }
}

class _BookingRestrictionAppeals extends StatefulWidget {
  const _BookingRestrictionAppeals({required this.accounts});

  final List<PlatformAccountSummary> accounts;

  @override
  State<_BookingRestrictionAppeals> createState() =>
      _BookingRestrictionAppealsState();
}

class _BookingRestrictionAppealsState
    extends State<_BookingRestrictionAppeals> {
  late Future<List<Map<String, dynamic>>> _appeals = _load();
  String? _reviewingId;

  Future<List<Map<String, dynamic>>> _load() async {
    final rows = await Supabase.instance.client
        .from('tourist_booking_restriction_appeals')
        .select('id,tourist_id,reason,created_at')
        .eq('status', 'pending')
        .order('created_at', ascending: true);
    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  void _refresh() {
    final next = _load();
    if (!mounted) return;
    setState(() {
      _appeals = next;
    });
  }

  Future<void> _review(String appealId, bool approve) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Lift booking restriction?' : 'Decline appeal?'),
        content: Text(
          approve
              ? 'The tourist will be able to create new bookings again.'
              : 'The temporary restriction will expire at its scheduled time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Back'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(approve ? 'Approve' : 'Decline'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _reviewingId = appealId);
    try {
      await Supabase.instance.client.rpc(
        'administrator_review_booking_restriction_appeal',
        params: {'p_appeal_id': appealId, 'p_approve': approve},
      );
      if (!mounted) return;
      _refresh();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(approve ? 'Restriction lifted.' : 'Appeal declined.'),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unable to review appeal: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _reviewingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdministratorPanel(
      title: 'Booking restriction appeals',
      subtitle: 'Review temporary new-booking restrictions',
      child: FutureBuilder<List<Map<String, dynamic>>>(
        future: _appeals,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TextButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Unable to load appeals. Retry'),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final appeals = snapshot.data!;
          if (appeals.isEmpty) {
            return const Text('No appeals awaiting review.');
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: IconButton(
                  tooltip: 'Refresh appeals',
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh),
                ),
              ),
              for (final appeal in appeals) ...[
                Builder(
                  builder: (context) {
                    final id = appeal['id']?.toString() ?? '';
                    final touristId = appeal['tourist_id']?.toString() ?? '';
                    final account = widget.accounts
                        .where((item) => item.id == touristId)
                        .firstOrNull;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          account?.name ?? touristId,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(appeal['reason']?.toString() ?? ''),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            TextButton(
                              onPressed: _reviewingId == null
                                  ? () => _review(id, false)
                                  : null,
                              child: const Text('Decline'),
                            ),
                            FilledButton(
                              onPressed: _reviewingId == null
                                  ? () => _review(id, true)
                                  : null,
                              child: const Text('Approve'),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                const Divider(height: 20),
              ],
            ],
          );
        },
      ),
    );
  }
}
