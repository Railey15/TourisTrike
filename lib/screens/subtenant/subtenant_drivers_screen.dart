import 'package:flutter/material.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_driver_details_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
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

  late Future<_DriverListLoad> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<_DriverListLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final drivers = await _service.fetchDrivers(profile);
    return _DriverListLoad(profile: profile, drivers: drivers);
  }

  void _reload() {
  final nextFuture = _load();

  setState(() {
    _future = nextFuture;
  });
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

  Future<void> _setStatus(
    SubTenantProfile profile,
    SubTenantDriver driver,
    String status,
  ) async {
    try {
      await _service.updateDriverStatus(profile, driver, status);
      if (!mounted) return;
      showSubTenantSnack(context, 'Driver status updated.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(
        context,
        'Driver status update needs a profiles.status column: $e',
      );
    }
  }

  List<SubTenantDriver> _filtered(List<SubTenantDriver> drivers) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return drivers;
    return drivers
        .where((driver) {
          return driver.fullName.toLowerCase().contains(query) ||
              driver.mobile.toLowerCase().contains(query) ||
              driver.plateNumber.toLowerCase().contains(query) ||
              driver.todaName.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return SubTenantAdminShell(
      currentIndex: 4,
      title: 'Drivers & Guides',
      subtitle: 'Review local driver profiles, TODA data, and account status.',
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
          final drivers = _filtered(load.drivers);
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ResponsivePageContainer(
              children: [
                DashboardSectionCard(
                  child: SubTenantSearchBar(
                    controller: _searchCtrl,
                    hintText: 'Search name, mobile, plate, TODA...',
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 16),
                if (drivers.isEmpty)
                  EmptyStateCard(
                    icon: Icons.badge_outlined,
                    title: 'No local drivers found',
                    message:
                        'Drivers must have profiles.role = driver and city = ${load.profile.assignedCity}.',
                  )
                else if (mobile)
                  ...drivers.map(
                    (driver) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _DriverCard(
                        driver: driver,
                        onTap: () => _openDetails(driver),
                        onApprove: () =>
                            _setStatus(load.profile, driver, 'approved'),
                        onSuspend: () =>
                            _setStatus(load.profile, driver, 'suspended'),
                      ),
                    ),
                  )
                else
                  _DriversTable(
                    drivers: drivers,
                    onOpenDetails: _openDetails,
                    onStatus: (driver, status) =>
                        _setStatus(load.profile, driver, status),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DriversTable extends StatelessWidget {
  const _DriversTable({
    required this.drivers,
    required this.onOpenDetails,
    required this.onStatus,
  });

  final List<SubTenantDriver> drivers;
  final ValueChanged<SubTenantDriver> onOpenDetails;
  final void Function(SubTenantDriver driver, String status) onStatus;

  @override
  Widget build(BuildContext context) {
    return ResponsiveTableWrapper(
      minWidth: 1050,
      child: DataTable(
        showCheckboxColumn: false,
        headingTextStyle: const TextStyle(
          color: SubTenantColors.muted,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
        dataTextStyle: const TextStyle(
          color: SubTenantColors.text,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        columns: const [
          DataColumn(label: Text('Driver')),
          DataColumn(label: Text('Mobile')),
          DataColumn(label: Text('Plate')),
          DataColumn(label: Text('TODA')),
          DataColumn(label: Text('Online')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: drivers
            .map((driver) {
              return DataRow(
                onSelectChanged: (_) => onOpenDetails(driver),
                cells: [
                  DataCell(_DriverIdentity(driver: driver)),
                  DataCell(Text(driver.mobile.isEmpty ? 'N/A' : driver.mobile)),
                  DataCell(
                    Text(
                      driver.plateNumber.isEmpty ? 'N/A' : driver.plateNumber,
                    ),
                  ),
                  DataCell(
                    Text(driver.todaName.isEmpty ? 'N/A' : driver.todaName),
                  ),
                  DataCell(
                    SubTenantStatusPill(
                      status: driver.isOnline ? 'online' : 'offline',
                      icon: Icons.circle,
                    ),
                  ),
                  DataCell(SubTenantStatusPill(status: driver.status)),
                  DataCell(
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => onStatus(driver, 'approved'),
                          child: const Text('Approve'),
                        ),
                        TextButton(
                          onPressed: () => onStatus(driver, 'suspended'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                          ),
                          child: const Text('Suspend'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _DriverIdentity extends StatelessWidget {
  const _DriverIdentity({required this.driver});

  final SubTenantDriver driver;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: driver.isOnline
              ? const Color(0xFFEAFBF2)
              : const Color(0xFFE8EEF7),
          child: Icon(
            Icons.person_rounded,
            color: driver.isOnline
                ? const Color(0xFF16A34A)
                : SubTenantColors.blue,
          ),
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 240),
          child: Text(
            driver.fullName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

class _DriverCard extends StatelessWidget {
  const _DriverCard({
    required this.driver,
    required this.onTap,
    required this.onApprove,
    required this.onSuspend,
  });

  final SubTenantDriver driver;
  final VoidCallback onTap;
  final VoidCallback onApprove;
  final VoidCallback onSuspend;

  @override
  Widget build(BuildContext context) {
    return SubTenantDashboardCard(
      padding: const EdgeInsets.all(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: driver.isOnline
                      ? const Color(0xFFEAFBF2)
                      : const Color(0xFFE8EEF7),
                  child: Icon(
                    Icons.person_rounded,
                    color: driver.isOnline
                        ? const Color(0xFF16A34A)
                        : SubTenantColors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver.fullName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SubTenantColors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 15.5,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (driver.mobile.isNotEmpty) driver.mobile,
                          if (driver.plateNumber.isNotEmpty) driver.plateNumber,
                        ].join(' - '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SubTenantColors.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                SubTenantStatusPill(
                  status: driver.isOnline ? 'online' : 'offline',
                  icon: Icons.circle,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    driver.todaName.isEmpty
                        ? 'No TODA assigned'
                        : driver.todaName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SubTenantColors.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: onApprove,
                      child: const Text('Approve'),
                    ),
                    TextButton(
                      onPressed: onSuspend,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                      ),
                      child: const Text('Suspend'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverListLoad {
  const _DriverListLoad({required this.profile, required this.drivers});

  final SubTenantProfile profile;
  final List<SubTenantDriver> drivers;
}
