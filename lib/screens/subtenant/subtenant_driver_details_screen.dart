import 'package:flutter/material.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantDriverDetailsScreen extends StatefulWidget {
  const SubTenantDriverDetailsScreen({super.key, required this.driverId});

  final String driverId;

  @override
  State<SubTenantDriverDetailsScreen> createState() =>
      _SubTenantDriverDetailsScreenState();
}

class _SubTenantDriverDetailsScreenState
    extends State<SubTenantDriverDetailsScreen> {
  final SubTenantService _service = SubTenantService();
  late Future<_DriverDetailsLoad> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DriverDetailsLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final driver = await _service.fetchDriverById(profile, widget.driverId);
    if (driver == null) {
      throw StateError('Driver not found in your assigned city.');
    }
    return _DriverDetailsLoad(profile: profile, driver: driver);
  }

  void _reload() {
    setState(() => _future = _load());
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

  void _contact(SubTenantDriver driver) {
    final mobile = driver.mobile.isEmpty
        ? 'No mobile number saved'
        : driver.mobile;
    showSubTenantSnack(context, mobile, error: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SubTenantColors.background,
      appBar: subTenantAppBar(context, title: 'Driver Details', showBack: true),
      body: FutureBuilder<_DriverDetailsLoad>(
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
          final driver = load.driver;
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              SubTenantDashboardCard(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: SubTenantColors.blue.withValues(
                        alpha: 0.1,
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: SubTenantColors.blue,
                        size: 38,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      driver.fullName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: SubTenantColors.text,
                        fontSize: 21,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SubTenantStatusPill(
                      status: driver.isOnline ? 'online' : 'offline',
                      icon: Icons.circle,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _setStatus(load.profile, driver, 'approved'),
                            icon: const Icon(Icons.verified_rounded),
                            label: const Text('Approve'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _setStatus(load.profile, driver, 'suspended'),
                            icon: const Icon(Icons.block_rounded),
                            label: const Text('Suspend'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton.filled(
                          onPressed: () => _contact(driver),
                          icon: const Icon(Icons.call_rounded),
                          style: IconButton.styleFrom(
                            backgroundColor: SubTenantColors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SubTenantDashboardCard(
                child: Column(
                  children: [
                    const SubTenantSectionHeader(title: 'Profile'),
                    const SizedBox(height: 8),
                    SubTenantInfoTile(
                      icon: Icons.phone_rounded,
                      title: 'Mobile',
                      subtitle: driver.mobile.isEmpty
                          ? 'Not provided'
                          : driver.mobile,
                    ),
                    SubTenantInfoTile(
                      icon: Icons.home_rounded,
                      title: 'Address',
                      subtitle: driver.address.isEmpty
                          ? 'Not provided'
                          : driver.address,
                    ),
                    SubTenantInfoTile(
                      icon: Icons.location_city_rounded,
                      title: 'Assigned City',
                      subtitle: driver.city,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SubTenantDashboardCard(
                child: Column(
                  children: [
                    const SubTenantSectionHeader(title: 'Driver Details'),
                    const SizedBox(height: 8),
                    SubTenantInfoTile(
                      icon: Icons.badge_rounded,
                      title: 'License Number',
                      subtitle: driver.licenseNumber.isEmpty
                          ? 'Not provided'
                          : driver.licenseNumber,
                    ),
                    SubTenantInfoTile(
                      icon: Icons.confirmation_number_rounded,
                      title: 'Plate Number',
                      subtitle: driver.plateNumber.isEmpty
                          ? 'Not provided'
                          : driver.plateNumber,
                    ),
                    SubTenantInfoTile(
                      icon: Icons.groups_rounded,
                      title: 'TODA Name',
                      subtitle: driver.todaName.isEmpty
                          ? 'Not provided'
                          : driver.todaName,
                    ),
                    SubTenantInfoTile(
                      icon: Icons.qr_code_rounded,
                      title: 'Operator Code',
                      subtitle: driver.operatorCode.isEmpty
                          ? 'Not provided'
                          : driver.operatorCode,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SubTenantDashboardCard(
                child: Column(
                  children: [
                    const SubTenantSectionHeader(
                      title: 'Documents',
                      subtitle: 'Uploaded document image URLs.',
                    ),
                    const SizedBox(height: 8),
                    if (driver.documentLinks.isEmpty)
                      const SubTenantEmptyState(
                        icon: Icons.description_outlined,
                        title: 'No documents uploaded',
                        message:
                            'Driver documents from driver_documents will appear here.',
                      )
                    else
                      ...driver.documentLinks.map(
                        (doc) => SubTenantInfoTile(
                          icon: Icons.image_rounded,
                          title: doc.label,
                          subtitle: doc.url,
                          onTap: () {
                            showSubTenantSnack(context, doc.url, error: false);
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DriverDetailsLoad {
  const _DriverDetailsLoad({required this.profile, required this.driver});

  final SubTenantProfile profile;
  final SubTenantDriver driver;
}
