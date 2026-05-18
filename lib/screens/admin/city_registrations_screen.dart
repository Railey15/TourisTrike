import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/admin_empty_state.dart';
import 'package:touristrike/screens/admin/widgets/admin_section_card.dart';
import 'package:touristrike/screens/admin/widgets/admin_status_pill.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class CityRegistrationsScreen extends StatefulWidget {
  const CityRegistrationsScreen({super.key});

  @override
  State<CityRegistrationsScreen> createState() =>
      _CityRegistrationsScreenState();
}

class _CityRegistrationsScreenState extends State<CityRegistrationsScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();
  late Future<TableResult<CityRegistration>> _future;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _future = _service.fetchRegistrations();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _future = _service.fetchRegistrations();
    });
  }

  List<CityRegistration> _applyFilter(List<CityRegistration> items) {
    if (_filter == 'all') return items;
    return items.where((r) => r.status.toLowerCase() == _filter).toList();
  }

  Future<void> _approve(CityRegistration registration) async {
    try {
      await _service.reviewRegistration(registration, 'approved');
      if (!mounted) return;
      
      showAdminSnack(context, 'Registration approved.', error: false);
      
      // Reload after a brief delay to ensure backend has updated
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (!mounted) return;
      showAdminSnack(context, 'Failed to approve: $e');
    }
  }

  Future<void> _reject(CityRegistration registration) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Reject Registration',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: TextField(
          controller: controller,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            labelText: 'Rejection reason (optional)',
            alignLabelWithHint: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: ProvincialAdminColors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return;

    try {
      await _service.reviewRegistration(
        registration,
        'rejected',
        rejectionReason: reason,
      );
      if (!mounted) return;
      
      showAdminSnack(context, 'Registration rejected.', error: false);
      
      // Reload after a brief delay to ensure backend has updated
      if (!mounted) return;
      await Future.delayed(const Duration(milliseconds: 500));
      
      if (!mounted) return;
      _reload();
    } catch (e) {
      if (!mounted) return;
      showAdminSnack(context, 'Failed to reject: $e');
    }
  }

  void _view(CityRegistration registration) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _RegistrationDetailsSheet(registration: registration),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return ProvincialAdminShell(
      current: ProvincialAdminDestination.registrations,
      title: 'City Registrations',
      subtitle: 'Review and approve city tourism office applications.',
      child: FutureBuilder<TableResult<CityRegistration>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AdminLoadingView();
          }
          if (snapshot.hasError) {
            return AdminErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final result = snapshot.data!;

          if (!result.available) {
            return const AdminEmptyState(
              icon: Icons.how_to_reg_outlined,
              title: 'Registration migration needed',
              message:
                  'Run the latest Supabase migration to enable city admin applications.',
            );
          }

          final all = result.items;
          final pending = all.where((r) => r.status.toLowerCase() == 'pending').length;
          final approved = all.where((r) => r.status.toLowerCase() == 'approved').length;
          final rejected = all.where((r) => r.status.toLowerCase() == 'rejected').length;
          final filtered = _applyFilter(all);

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: AdminPageContainer(
              children: [
                _FilterTabs(
                  selected: _filter,
                  counts: {
                    'all': all.length,
                    'pending': pending,
                    'approved': approved,
                    'rejected': rejected,
                  },
                  onSelect: (f) => setState(() => _filter = f),
                ),
                const SizedBox(height: 16),
                if (filtered.isEmpty)
                  AdminEmptyState(
                    icon: Icons.how_to_reg_outlined,
                    title: _filter == 'all'
                        ? 'No registrations yet'
                        : 'No $_filter registrations',
                    message: _filter == 'all'
                        ? 'City and municipal registration requests will appear here.'
                        : 'No registrations with status "$_filter" found.',
                  )
                else if (mobile)
                  ...filtered.map(
                    (r) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _RegistrationCard(
                        registration: r,
                        onView: () => _view(r),
                        onApprove: () => _approve(r),
                        onReject: () => _reject(r),
                      ),
                    ),
                  )
                else
                  _RegistrationsTable(
                    registrations: filtered,
                    onView: _view,
                    onApprove: _approve,
                    onReject: _reject,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Summary bar ──────────────────────────────────────────────────────────────

// ── Filter tabs ───────────────────────────────────────────────────────────────

class _FilterTabs extends StatelessWidget {
  const _FilterTabs({
    required this.selected,
    required this.counts,
    required this.onSelect,
  });

  final String selected;
  final Map<String, int> counts;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    const tabs = [
      ('all', 'All'),
      ('pending', 'Pending'),
      ('approved', 'Approved'),
      ('rejected', 'Rejected'),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: tabs.map((tab) {
          final key = tab.$1;
          final label = tab.$2;
          final active = selected == key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: active
                      ? ProvincialAdminColors.blue
                      : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: active
                        ? ProvincialAdminColors.blue
                        : ProvincialAdminColors.line,
                  ),
                  boxShadow: active
                      ? [provincialAdminShadow(alpha: 0.10)]
                      : null,
                ),
                child: Row(
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: active
                            ? Colors.white
                            : ProvincialAdminColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white.withValues(alpha: 0.25)
                            : ProvincialAdminColors.backgroundAlt,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${counts[key] ?? 0}',
                        style: TextStyle(
                          color: active
                              ? Colors.white
                              : ProvincialAdminColors.blue,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Desktop table ─────────────────────────────────────────────────────────────

class _RegistrationsTable extends StatelessWidget {
  const _RegistrationsTable({
    required this.registrations,
    required this.onView,
    required this.onApprove,
    required this.onReject,
  });

  final List<CityRegistration> registrations;
  final ValueChanged<CityRegistration> onView;
  final ValueChanged<CityRegistration> onApprove;
  final ValueChanged<CityRegistration> onReject;

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            _TableHeader(),
            const Divider(height: 1, color: ProvincialAdminColors.line),
            ...registrations.asMap().entries.map((entry) {
              final i = entry.key;
              final r = entry.value;
              return Column(
                children: [
                  _TableRow(
                    registration: r,
                    shaded: i.isOdd,
                    onView: () => onView(r),
                    onApprove: () => onApprove(r),
                    onReject: () => onReject(r),
                  ),
                  if (i < registrations.length - 1)
                    const Divider(
                      height: 1,
                      color: ProvincialAdminColors.line,
                      indent: 16,
                      endIndent: 16,
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _TableHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      color: ProvincialAdminColors.backgroundAlt,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: const Row(
        children: [
          Expanded(flex: 3, child: _HeadCell('City / Municipality')),
          Expanded(flex: 4, child: _HeadCell('Office')),
          Expanded(flex: 4, child: _HeadCell('Contact Person')),
          Expanded(flex: 5, child: _HeadCell('Email')),
          Expanded(flex: 3, child: _HeadCell('Submitted')),
          SizedBox(width: 100, child: _HeadCell('Status')),
          SizedBox(width: 130, child: _HeadCell('Actions')),
        ],
      ),
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        color: ProvincialAdminColors.muted,
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 0.5,
      ),
    );
  }
}

class _TableRow extends StatelessWidget {
  const _TableRow({
    required this.registration,
    required this.shaded,
    required this.onView,
    required this.onApprove,
    required this.onReject,
  });

  final CityRegistration registration;
  final bool shaded;
  final VoidCallback onView;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final pending = registration.status.toLowerCase() == 'pending';
    final submitted = registration.submittedAt == null
        ? '—'
        : DateFormat('MMM d, yyyy').format(registration.submittedAt!);

    return InkWell(
      onTap: onView,
      child: Container(
        color: shaded
            ? ProvincialAdminColors.background.withValues(alpha: 0.6)
            : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Text(
                registration.city,
                style: const TextStyle(
                  color: ProvincialAdminColors.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                registration.officeName,
                style: const TextStyle(
                  color: ProvincialAdminColors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                registration.contactPerson,
                style: const TextStyle(
                  color: ProvincialAdminColors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Text(
                registration.email,
                style: const TextStyle(
                  color: ProvincialAdminColors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                submitted,
                style: const TextStyle(
                  color: ProvincialAdminColors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
            SizedBox(
              width: 100,
              child: AdminStatusPill(status: registration.status),
            ),
            SizedBox(
              width: 130,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _IconAction(
                    icon: Icons.visibility_rounded,
                    tooltip: 'View details',
                    color: ProvincialAdminColors.blue,
                    onPressed: onView,
                  ),
                  if (pending) ...[
                    const SizedBox(width: 4),
                    _IconAction(
                      icon: Icons.check_circle_rounded,
                      tooltip: 'Approve',
                      color: ProvincialAdminColors.green,
                      onPressed: onApprove,
                    ),
                    const SizedBox(width: 4),
                    _IconAction(
                      icon: Icons.cancel_rounded,
                      tooltip: 'Reject',
                      color: ProvincialAdminColors.red,
                      onPressed: onReject,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 17),
        ),
      ),
    );
  }
}

// ── Mobile card ───────────────────────────────────────────────────────────────

class _RegistrationCard extends StatelessWidget {
  const _RegistrationCard({
    required this.registration,
    required this.onView,
    required this.onApprove,
    required this.onReject,
  });

  final CityRegistration registration;
  final VoidCallback onView;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final pending = registration.status.toLowerCase() == 'pending';
    final submitted = registration.submittedAt == null
        ? '—'
        : DateFormat('MMM d, yyyy').format(registration.submittedAt!);

    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      registration.city,
                      style: const TextStyle(
                        color: ProvincialAdminColors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      registration.officeName,
                      style: const TextStyle(
                        color: ProvincialAdminColors.muted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              AdminStatusPill(status: registration.status),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: ProvincialAdminColors.line, height: 1),
          const SizedBox(height: 12),
          _CardInfoRow(
            icon: Icons.person_rounded,
            text: registration.contactPerson,
          ),
          const SizedBox(height: 6),
          _CardInfoRow(
            icon: Icons.email_rounded,
            text: registration.email,
          ),
          const SizedBox(height: 6),
          _CardInfoRow(
            icon: Icons.calendar_today_rounded,
            text: 'Submitted $submitted',
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: onView,
                icon: const Icon(Icons.visibility_rounded, size: 16),
                label: const Text('View'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ProvincialAdminColors.blue,
                  side: const BorderSide(color: ProvincialAdminColors.blue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (pending) ...[
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onApprove,
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: ProvincialAdminColors.green,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onReject,
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('Reject'),
                  style: FilledButton.styleFrom(
                    backgroundColor: ProvincialAdminColors.red,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CardInfoRow extends StatelessWidget {
  const _CardInfoRow({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: ProvincialAdminColors.lightMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: ProvincialAdminColors.muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Detail sheet ──────────────────────────────────────────────────────────────

class _RegistrationDetailsSheet extends StatelessWidget {
  const _RegistrationDetailsSheet({required this.registration});

  final CityRegistration registration;

  @override
  Widget build(BuildContext context) {
    final submitted = registration.submittedAt == null
        ? '—'
        : DateFormat('MMM d, yyyy – h:mm a').format(registration.submittedAt!);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(
        color: ProvincialAdminColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: ProvincialAdminColors.line,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        registration.city,
                        style: const TextStyle(
                          color: ProvincialAdminColors.text,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        registration.officeName,
                        style: const TextStyle(
                          color: ProvincialAdminColors.muted,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                AdminStatusPill(status: registration.status),
              ],
            ),
            const SizedBox(height: 18),
            AdminSectionCard(
              child: Column(
                children: [
                  _DetailTile(
                    icon: Icons.person_rounded,
                    label: 'Contact Person',
                    value: registration.contactPerson,
                  ),
                  _DetailTile(
                    icon: Icons.phone_rounded,
                    label: 'Contact Number',
                    value: registration.contactNumber.isEmpty
                        ? '—'
                        : registration.contactNumber,
                  ),
                  _DetailTile(
                    icon: Icons.email_rounded,
                    label: 'Email',
                    value: registration.email.isEmpty ? '—' : registration.email,
                  ),
                  _DetailTile(
                    icon: Icons.home_rounded,
                    label: 'Office Address',
                    value: registration.address.isEmpty
                        ? 'No address submitted'
                        : registration.address,
                  ),
                  _DetailTile(
                    icon: Icons.calendar_today_rounded,
                    label: 'Submitted',
                    value: submitted,
                    isLast: registration.rejectionReason.isEmpty,
                  ),
                  if (registration.rejectionReason.isNotEmpty)
                    _DetailTile(
                      icon: Icons.info_outline_rounded,
                      label: 'Rejection Reason',
                      value: registration.rejectionReason,
                      valueColor: ProvincialAdminColors.red,
                      isLast: true,
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

class _DetailTile extends StatelessWidget {
  const _DetailTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 17, color: ProvincialAdminColors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        color: ProvincialAdminColors.muted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: TextStyle(
                        color: valueColor ?? ProvincialAdminColors.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          const Divider(height: 1, color: ProvincialAdminColors.line),
      ],
    );
  }
}
