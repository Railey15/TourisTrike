import 'package:flutter/material.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_driver_details_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/subtenant_workspace_search.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantDriversScreen extends StatefulWidget {
  const SubTenantDriversScreen({super.key});

  @override
  State<SubTenantDriversScreen> createState() => _SubTenantDriversScreenState();
}

class _SubTenantDriversScreenState extends State<SubTenantDriversScreen> {
  final SubTenantService _service = SubTenantService();
  final TextEditingController _searchCtrl = TextEditingController();
  final _workspaceSearch = SubTenantWorkspaceSearchController.instance;

  late Future<_DriverListLoad> _future;
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _future = _load();
    _searchCtrl.addListener(() => setState(() {}));
    _workspaceSearch.addListener(_handleWorkspaceSearchChanged);
  }

  @override
  void dispose() {
    _workspaceSearch.removeListener(_handleWorkspaceSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleWorkspaceSearchChanged() {
    if (!mounted || _workspaceSearch.activeScope != 4) return;
    setState(() {});
  }

  Future<_DriverListLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final drivers = await _service.fetchDrivers(profile);
    return _DriverListLoad(profile: profile, drivers: drivers);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _openDetails(SubTenantDriver driver) async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubTenantDriverDetailsScreen(driverId: driver.id),
      ),
    );

    if (!mounted) return;
    if (changed == true) _reload();
  }

  List<SubTenantDriver> _filteredDrivers(List<SubTenantDriver> drivers) {
    final query = [
      _searchCtrl.text.trim(),
      _workspaceSearch.queryFor(4),
    ].where((value) => value.isNotEmpty).join(' ').toLowerCase();

    return drivers.where((driver) {
      final searchable = [
        driver.fullName,
        driver.mobile,
        driver.plateNumber,
        driver.todaName,
        driver.status,
        driver.documentCompleteness,
        driver.isOnline ? 'online' : 'offline',
      ].join(' ').toLowerCase();

      final matchesSearch = query.isEmpty || searchable.contains(query);

      final matchesStatus = switch (_status) {
        'online' => driver.isOnline,
        'offline' => !driver.isOnline,
        'all' => true,
        _ => driver.status == _status,
      };

      return matchesSearch && matchesStatus;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return SubTenantAdminShell(
      currentIndex: 4,
      title: 'Drivers & Guides',
      subtitle: 'Review local driver profiles, TODA data, documents, and account status.',
      child: FutureBuilder<_DriverListLoad>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SubTenantLoadingView();
          }

          if (snapshot.hasError) {
            return SubTenantErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final load = snapshot.data!;
          final drivers = _filteredDrivers(load.drivers);

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ResponsivePageContainer(
              children: [
                _DriversToolbar(
                  controller: _searchCtrl,
                  selectedStatus: _status,
                  resultCount: drivers.length,
                  totalCount: load.drivers.length,
                  onStatusChanged: (value) {
                    setState(() => _status = value);
                  },
                ),
                const SizedBox(height: 16),
                if (drivers.isEmpty)
                  EmptyStateCard(
                    icon: Icons.badge_outlined,
                    title: 'No local drivers found',
                    message: _searchCtrl.text.trim().isNotEmpty || _status != 'all'
                        ? 'No drivers match your current search or filter.'
                        : 'Drivers must have profiles.role = driver and city = ${load.profile.assignedCity}.',
                  )
                else
                  _DriversGrid(
                    drivers: drivers,
                    onOpenDetails: _openDetails,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DriversToolbar extends StatelessWidget {
  const _DriversToolbar({
    required this.controller,
    required this.selectedStatus,
    required this.resultCount,
    required this.totalCount,
    required this.onStatusChanged,
  });

  final TextEditingController controller;
  final String selectedStatus;
  final int resultCount;
  final int totalCount;
  final ValueChanged<String> onStatusChanged;

  String get _countLabel {
    if (resultCount == totalCount) {
      return '$totalCount driver${totalCount == 1 ? '' : 's'}';
    }
    return '$resultCount of $totalCount drivers';
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    return DashboardSectionCard(
      child: desktop
          ? Row(
              children: [
                Expanded(
                  flex: 5,
                  child: SubTenantSearchBar(
                    controller: controller,
                    hintText: 'Search name, mobile, plate, TODA...',
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _StatusDropdown(
                    value: selectedStatus,
                    onChanged: onStatusChanged,
                  ),
                ),
                const SizedBox(width: 12),
                _ResultPill(label: _countLabel),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SubTenantSearchBar(
                  controller: controller,
                  hintText: 'Search drivers...',
                  onChanged: (_) {},
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _StatusDropdown(
                        value: selectedStatus,
                        onChanged: onStatusChanged,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ResultPill(label: _countLabel),
                  ],
                ),
              ],
            ),
    );
  }
}

class _DriversGrid extends StatelessWidget {
  const _DriversGrid({
    required this.drivers,
    required this.onOpenDetails,
  });

  final List<SubTenantDriver> drivers;
  final ValueChanged<SubTenantDriver> onOpenDetails;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = Responsive.isMobile(context);
        final isDesktop = Responsive.isDesktop(context);
        final cols = mobile ? 1 : (isDesktop ? 3 : 2);
        const spacing = 14.0;
        final cardWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: drivers
              .map(
                (driver) => SizedBox(
                  width: cardWidth,
                  child: _DriverCard(
                    driver: driver,
                    onTap: () => onOpenDetails(driver),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  String _pretty(String value) {
    if (value == 'all') return 'All Drivers';
    if (value == 'online') return 'Online';
    if (value == 'offline') return 'Offline';
    return value[0].toUpperCase() + value.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    const values = [
      'all',
      'pending',
      'approved',
      'suspended',
      'online',
      'offline',
    ];

    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.tune_rounded,
          color: SubTenantColors.blue,
          size: 20,
        ),
        filled: true,
        fillColor: const Color(0xFFF7FAFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SubTenantColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SubTenantColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SubTenantColors.blue, width: 1.3),
        ),
      ),
      items: values
          .map(
            (status) => DropdownMenuItem<String>(
              value: status,
              child: Text(
                _pretty(status),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SubTenantColors.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

class _ResultPill extends StatelessWidget {
  const _ResultPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: SubTenantColors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubTenantColors.blue.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.badge_rounded,
            size: 16,
            color: SubTenantColors.blue,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: SubTenantColors.blue,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverCard extends StatefulWidget {
  const _DriverCard({
    required this.driver,
    required this.onTap,
  });

  final SubTenantDriver driver;
  final VoidCallback onTap;

  @override
  State<_DriverCard> createState() => _DriverCardState();
}

class _DriverCardState extends State<_DriverCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final driver = widget.driver;

    final mobile = driver.mobile.isEmpty ? 'Mobile N/A' : driver.mobile;
    final plate = driver.plateNumber.isEmpty ? 'Plate N/A' : driver.plateNumber;
    final toda = driver.todaName.isEmpty ? 'No TODA assigned' : driver.todaName;
    final onlineStatus = driver.isOnline ? 'online' : 'offline';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..translate(0.0, _hovered ? -3.0 : 0.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _hovered
                ? SubTenantColors.blue.withValues(alpha: 0.35)
                : SubTenantColors.line,
          ),
          boxShadow: [
            BoxShadow(
              color: _hovered
                  ? SubTenantColors.blue.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.045),
              blurRadius: _hovered ? 24 : 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: driver.isOnline
                              ? const LinearGradient(
                                  colors: [
                                    Color(0xFF16A34A),
                                    Color(0xFF22C55E),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                )
                              : SubTenantColors.gradient,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: (driver.isOnline
                                      ? const Color(0xFF16A34A)
                                      : SubTenantColors.blue)
                                  .withValues(alpha: 0.22),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.person_rounded,
                          color: Colors.white,
                          size: 23,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driver.fullName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: SubTenantColors.text,
                                fontSize: 14.5,
                                fontWeight: FontWeight.w900,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.confirmation_number_rounded,
                                  size: 13,
                                  color: SubTenantColors.muted,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    plate,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: SubTenantColors.muted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SubTenantStatusPill(status: onlineStatus, icon: Icons.circle),
                    ],
                  ),

                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: SubTenantColors.line.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 14),

                  _DetailRow(
                    icon: Icons.phone_rounded,
                    label: 'Mobile',
                    value: mobile,
                  ),
                  const SizedBox(height: 9),
                  _DetailRow(
                    icon: Icons.groups_rounded,
                    label: 'TODA',
                    value: toda,
                  ),
                  const SizedBox(height: 9),
                  _DetailRow(
                    icon: Icons.verified_user_rounded,
                    label: 'Account Status',
                    value: _prettyStatus(driver.status),
                    valueColor: SubTenantColors.blue,
                    valueBold: true,
                  ),
                  const SizedBox(height: 9),
                  _DetailRow(
                    icon: Icons.description_rounded,
                    label: 'Documents',
                    value: driver.documentCompleteness,
                  ),

                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: widget.onTap,
                      icon: const Icon(Icons.visibility_rounded, size: 16),
                      label: const Text('View Details'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _hovered
                            ? SubTenantColors.blue
                            : SubTenantColors.blue.withValues(alpha: 0.09),
                        foregroundColor:
                            _hovered ? Colors.white : SubTenantColors.blue,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _prettyStatus(String value) {
    if (value.isEmpty) return 'N/A';
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueBold = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool valueBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: SubTenantColors.blue.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 15, color: SubTenantColors.blue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: SubTenantColors.lightMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueColor ?? SubTenantColors.text,
                  fontSize: 12.5,
                  fontWeight: valueBold ? FontWeight.w900 : FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DriverListLoad {
  const _DriverListLoad({
    required this.profile,
    required this.drivers,
  });

  final SubTenantProfile profile;
  final List<SubTenantDriver> drivers;
}
