import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/city_tenant_details_screen.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/admin_data_table.dart';
import 'package:touristrike/screens/admin/widgets/admin_empty_state.dart';
import 'package:touristrike/screens/admin/widgets/admin_section_card.dart';
import 'package:touristrike/screens/admin/widgets/admin_status_pill.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Local colors
// ─────────────────────────────────────────────────────────────────────────────

const _pageBackground = Color(0xFFF4F7FB);

const _softBlue = Color(0xFFF2F7FF);
const _softGreen = Color(0xFFF0FDF4);
const _softAmber = Color(0xFFFFFBEB);
const _softRed = Color(0xFFFEF2F2);
const _softPurple = Color(0xFFF7F3FF);

const _green = Color(0xFF16A34A);
const _amber = Color(0xFFF59E0B);
const _red = Color(0xFFDC2626);
const _purple = Color(0xFF7C3AED);
const _cyan = Color(0xFF0EA5E9);

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class CityTenantsScreen extends StatefulWidget {
  const CityTenantsScreen({
    super.key,
  });

  @override
  State<CityTenantsScreen> createState() => _CityTenantsScreenState();
}

class _CityTenantsScreenState extends State<CityTenantsScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();
  final TextEditingController _searchCtrl = TextEditingController();

  late Future<_CityTenantWorkbenchData> _future;

  String _status = 'all';

  @override
  void initState() {
    super.initState();

    _future = _loadData();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<_CityTenantWorkbenchData> _loadData() async {
    final results = await Future.wait<dynamic>([
      _service.fetchCityTenants(),
      _service.fetchRegistrations(),
    ]);

    return _CityTenantWorkbenchData(
      tenants: results[0] as List<CityTenant>,
      registrations: results[1] as TableResult<CityRegistration>,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _future = _loadData();
    });

    await _future;
  }

  void _clearSearch() {
    _searchCtrl.clear();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Filtering
  // ───────────────────────────────────────────────────────────────────────────

  List<CityTenant> _filtered(
    List<CityTenant> tenants,
  ) {
    final query = _searchCtrl.text.trim().toLowerCase();

    return tenants.where((tenant) {
      final status = tenant.status.trim().toLowerCase();

      final matchesStatus =
          _status == 'all' ||
          (_status == 'active' &&
              [
                'active',
                'approved',
                'verified',
              ].contains(status)) ||
          (_status == 'inactive' &&
              [
                'inactive',
                'disabled',
                'deactivated',
                'suspended',
              ].contains(status)) ||
          (_status == 'pending' && status == 'pending') ||
          (_status == 'verified' && tenant.verified) ||
          (_status == 'classification' &&
              !tenant.localGovernmentTypeReviewed);

      if (!matchesStatus) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final searchable = [
        tenant.city,
        tenant.province,
        tenant.adminName,
        tenant.email,
        tenant.mobile,
        tenant.address,
        tenant.status,
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList(growable: false);
  }

  int _countByStatus(
    List<CityTenant> tenants,
    String filter,
  ) {
    if (filter == 'all') {
      return tenants.length;
    }

    return tenants.where((tenant) {
      final status = tenant.status.trim().toLowerCase();

      switch (filter) {
        case 'active':
          return [
            'active',
            'approved',
            'verified',
          ].contains(status);

        case 'inactive':
          return [
            'inactive',
            'disabled',
            'deactivated',
            'suspended',
          ].contains(status);

        case 'pending':
          return status == 'pending';

        case 'verified':
          return tenant.verified;

        case 'classification':
          return !tenant.localGovernmentTypeReviewed;

        default:
          return false;
      }
    }).length;
  }

  List<CityRegistration> _filteredPendingRegistrations(
    List<CityRegistration> registrations,
  ) {
    final query = _searchCtrl.text.trim().toLowerCase();

    return registrations.where((registration) {
      if (registration.status.trim().toLowerCase() != 'pending') {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final searchable = [
        registration.city,
        registration.officeName,
        registration.contactPerson,
        registration.contactNumber,
        registration.email,
        registration.address,
      ].join(' ').toLowerCase();

      return searchable.contains(query);
    }).toList(growable: false);
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Tenant actions
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _setStatus(
    CityTenant tenant,
    String status,
  ) async {
    try {
      await _service.updateTenantStatus(
        tenant,
        status,
      );

      if (!mounted) return;

      showAdminSnack(
        context,
        'City tenant updated.',
        error: false,
      );

      await _reload();
    } catch (error) {
      if (!mounted) return;

      showAdminSnack(
        context,
        'Failed to update tenant: $error',
      );
    }
  }

  Future<void> _editCity(
    CityTenant tenant,
  ) async {
    final controller = TextEditingController(
      text: tenant.city,
    );

    final city = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Edit Assigned City',
            style: TextStyle(
              fontWeight: FontWeight.w900,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'City / Municipality',
                prefixIcon: const Icon(
                  Icons.location_city_outlined,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  controller.text.trim(),
                );
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (city == null ||
        city.trim().isEmpty ||
        city.trim() == tenant.city.trim()) {
      return;
    }

    try {
      await _service.updateTenantCity(
        tenant,
        city.trim(),
      );

      if (!mounted) return;

      showAdminSnack(
        context,
        'Assigned city updated.',
        error: false,
      );

      await _reload();
    } catch (error) {
      if (!mounted) return;

      showAdminSnack(
        context,
        'Failed to update city: $error',
      );
    }
  }

  void _openDetails(
    CityTenant tenant,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) {
          return CityTenantDetailsScreen(
            tenantId: tenant.id,
          );
        },
      ),
    ).then((_) {
      _reload();
    });
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Registration actions
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _approveRegistration(
    CityRegistration registration,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Approve Registration?',
            style: TextStyle(
              fontWeight: FontWeight.w900,
            ),
          ),
          content: Text(
            'Approve the tourism office registration for '
            '${registration.city}?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              icon: const Icon(
                Icons.check_rounded,
                size: 17,
              ),
              label: const Text('Approve'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    try {
      await _service.reviewRegistration(
        registration,
        'approved',
      );

      if (!mounted) return;

      showAdminSnack(
        context,
        'Registration approved.',
        error: false,
      );

      await Future<void>.delayed(
        const Duration(milliseconds: 300),
      );

      if (mounted) {
        await _reload();
      }
    } catch (error) {
      if (!mounted) return;

      showAdminSnack(
        context,
        'Failed to approve registration: $error',
      );
    }
  }

  Future<void> _rejectRegistration(
    CityRegistration registration,
  ) async {
    final controller = TextEditingController();

    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Text(
            'Reject Registration',
            style: TextStyle(
              fontWeight: FontWeight.w900,
            ),
          ),
          content: SizedBox(
            width: 440,
            child: TextField(
              controller: controller,
              minLines: 3,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: 'Rejection reason',
                hintText:
                    'Explain why this registration cannot be approved...',
                alignLabelWithHint: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: ProvincialAdminColors.red,
              ),
              onPressed: () {
                Navigator.pop(
                  context,
                  controller.text.trim(),
                );
              },
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (reason == null) {
      return;
    }

    try {
      await _service.reviewRegistration(
        registration,
        'rejected',
        rejectionReason: reason,
      );

      if (!mounted) return;

      showAdminSnack(
        context,
        'Registration rejected.',
        error: false,
      );

      await Future<void>.delayed(
        const Duration(milliseconds: 300),
      );

      if (mounted) {
        await _reload();
      }
    } catch (error) {
      if (!mounted) return;

      showAdminSnack(
        context,
        'Failed to reject registration: $error',
      );
    }
  }

  void _viewRegistration(
    CityRegistration registration,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _RegistrationDetailsSheet(
          registration: registration,
        );
      },
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return ProvincialAdminShell(
      current: ProvincialAdminDestination.cityTenants,
      title: 'City Tenants',
      subtitle:
          'Manage tourism office accounts and review registration requests.',
      child: FutureBuilder<_CityTenantWorkbenchData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const AdminLoadingView();
          }

          if (snapshot.hasError) {
            return AdminErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final data = snapshot.data!;

          final allTenants = data.tenants;
          final tenants = _filtered(allTenants);

          final registrationResult =
              data.registrations;

          final registrations =
              registrationResult.items;

          final pendingRegistrationCount =
              registrationResult.available
                  ? registrations.where((registration) {
                      return registration.status
                              .trim()
                              .toLowerCase() ==
                          'pending';
                    }).length
                  : 0;

          final counts = <String, int>{
            'all':
                _countByStatus(
              allTenants,
              'all',
            ),
            'active':
                _countByStatus(
              allTenants,
              'active',
            ),
            'inactive':
                _countByStatus(
              allTenants,
              'inactive',
            ),
            'pending':
                _countByStatus(
                      allTenants,
                      'pending',
                    ) +
                    pendingRegistrationCount,
            'verified':
                _countByStatus(
              allTenants,
              'verified',
            ),
            'classification':
                _countByStatus(
              allTenants,
              'classification',
            ),
          };

          final showingPending =
              _status == 'pending';

          final pendingRegistrations =
              showingPending &&
                      registrationResult.available
                  ? _filteredPendingRegistrations(
                      registrations,
                    )
                  : <CityRegistration>[];

          return ColoredBox(
            color: _pageBackground,
            child: RefreshIndicator(
              onRefresh: _reload,
              child: SingleChildScrollView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  mobile ? 14 : 22,
                  mobile ? 14 : 18,
                  mobile ? 14 : 22,
                  32,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    // One search/filter block.
                    _TenantToolbar(
                      controller: _searchCtrl,
                      status: _status,
                      counts: counts,
                      onStatusChanged: (value) {
                        setState(() {
                          _status = value;
                        });
                      },
                      onClearSearch:
                          _clearSearch,
                    ),

                    const SizedBox(height: 18),

                    if (!showingPending) ...[
                      _SectionHeader(
                        title: 'Tenant Accounts',
                        count: tenants.length,
                        subtitle:
                            'Approved city and municipal tourism office accounts.',
                      ),

                      const SizedBox(height: 10),

                      if (tenants.isEmpty)
                        _TenantEmptyState(
                          searched:
                              _searchCtrl.text.trim().isNotEmpty,
                          onClearSearch:
                              _clearSearch,
                        )
                      else
                        _TenantGrid(
                          tenants: tenants,
                          onOpen:
                              _openDetails,
                          onEditCity:
                              _editCity,
                          onStatus:
                              _setStatus,
                        ),
                    ],

                    if (showingPending) ...[
                      _SectionHeader(
                        title: 'Pending Registrations',
                        count:
                            pendingRegistrations.length,
                        subtitle:
                            'New tourism office applications awaiting provincial review.',
                      ),

                      const SizedBox(height: 10),

                      if (!registrationResult.available)
                        const AdminEmptyState(
                          icon:
                              Icons.info_outline_rounded,
                          title:
                              'Registrations table unavailable',
                          message:
                              'Create or connect the registrations table to review city applications.',
                        )
                      else if (pendingRegistrations.isEmpty)
                        const AdminEmptyState(
                          icon:
                              Icons.how_to_reg_outlined,
                          title:
                              'No pending registrations',
                          message:
                              'All registration requests have been processed.',
                        )
                      else if (mobile)
                        ...pendingRegistrations.map(
                          (registration) {
                            return Padding(
                              padding:
                                  const EdgeInsets.only(
                                bottom: 12,
                              ),
                              child:
                                  _RegistrationCard(
                                registration:
                                    registration,
                                onView: () {
                                  _viewRegistration(
                                    registration,
                                  );
                                },
                                onApprove: () {
                                  _approveRegistration(
                                    registration,
                                  );
                                },
                                onReject: () {
                                  _rejectRegistration(
                                    registration,
                                  );
                                },
                              ),
                            );
                          },
                        )
                      else
                        _RegistrationsTable(
                          registrations:
                              pendingRegistrations,
                          onView:
                              _viewRegistration,
                          onApprove:
                              _approveRegistration,
                          onReject:
                              _rejectRegistration,
                        ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _CityTenantWorkbenchData {
  const _CityTenantWorkbenchData({
    required this.tenants,
    required this.registrations,
  });

  final List<CityTenant> tenants;
  final TableResult<CityRegistration> registrations;
}

// ─────────────────────────────────────────────────────────────────────────────
// Search and filters
// ─────────────────────────────────────────────────────────────────────────────

class _TenantToolbar extends StatelessWidget {
  const _TenantToolbar({
    required this.controller,
    required this.status,
    required this.counts,
    required this.onStatusChanged,
    required this.onClearSearch,
  });

  final TextEditingController controller;

  final String status;

  final Map<String, int> counts;

  final ValueChanged<String>
      onStatusChanged;

  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(14),
        border: Border.all(
          color:
              ProvincialAdminColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 42,
            child: TextField(
              controller: controller,
              textInputAction:
                  TextInputAction.search,
              decoration: InputDecoration(
                hintText:
                    'Search city, admin, email, contact or address...',
                hintStyle:
                    const TextStyle(
                  color:
                      ProvincialAdminColors
                          .lightMuted,
                  fontSize: 10.5,
                  fontWeight:
                      FontWeight.w600,
                ),
                prefixIcon:
                    const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color:
                      ProvincialAdminColors
                          .lightMuted,
                ),
                suffixIcon:
                    controller.text.isNotEmpty
                        ? IconButton(
                            tooltip:
                                'Clear search',
                            onPressed:
                                onClearSearch,
                            icon:
                                const Icon(
                              Icons
                                  .close_rounded,
                              size: 16,
                            ),
                          )
                        : null,
                filled: true,
                fillColor:
                    const Color(
                  0xFFF8FAFC,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(
                  horizontal: 12,
                ),
                enabledBorder:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    9,
                  ),
                  borderSide:
                      const BorderSide(
                    color:
                        ProvincialAdminColors
                            .line,
                  ),
                ),
                focusedBorder:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    9,
                  ),
                  borderSide:
                      const BorderSide(
                    color:
                        ProvincialAdminColors
                            .blue,
                    width: 1.2,
                  ),
                ),
                border:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(
                    9,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),

          _FilterChips(
            selected: status,
            counts: counts,
            onSelected:
                onStatusChanged,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Filter chips
// ─────────────────────────────────────────────────────────────────────────────

class _FilterChips extends StatelessWidget {
  const _FilterChips({
    required this.selected,
    required this.counts,
    required this.onSelected,
  });

  final String selected;
  final Map<String, int> counts;
  final ValueChanged<String>
      onSelected;

  @override
  Widget build(BuildContext context) {
    const filters = [
      (
        'all',
        'All',
        Icons.people_alt_outlined,
      ),
      (
        'active',
        'Active',
        Icons.check_circle_outline_rounded,
      ),
      (
        'inactive',
        'Inactive',
        Icons.pause_circle_outline_rounded,
      ),
      (
        'pending',
        'Pending',
        Icons.pending_actions_outlined,
      ),
      (
        'verified',
        'Verified',
        Icons.verified_outlined,
      ),
      (
        'classification',
        'Needs Classification',
        Icons.rule_outlined,
      ),
    ];

    return SingleChildScrollView(
      scrollDirection:
          Axis.horizontal,
      child: Row(
        children:
            filters.map((item) {
          final key = item.$1;
          final label = item.$2;
          final icon = item.$3;

          final active =
              selected == key;

          return Padding(
            padding:
                const EdgeInsets.only(
              right: 7,
            ),
            child: InkWell(
              borderRadius:
                  BorderRadius.circular(
                9,
              ),
              onTap: () {
                onSelected(key);
              },
              child:
                  AnimatedContainer(
                duration:
                    const Duration(
                  milliseconds: 150,
                ),
                height: 36,
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 10,
                ),
                decoration:
                    BoxDecoration(
                  color: active
                      ? ProvincialAdminColors
                          .blue
                      : const Color(
                          0xFFF8FAFC,
                        ),
                  borderRadius:
                      BorderRadius.circular(
                    9,
                  ),
                  border: Border.all(
                    color: active
                        ? ProvincialAdminColors
                            .blue
                        : ProvincialAdminColors
                            .line,
                  ),
                ),
                child: Row(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 13,
                      color: active
                          ? Colors.white
                          : ProvincialAdminColors
                              .muted,
                    ),
                    const SizedBox(
                      width: 5,
                    ),
                    Text(
                      label,
                      style:
                          TextStyle(
                        color: active
                            ? Colors.white
                            : ProvincialAdminColors
                                .muted,
                        fontSize: 10,
                        fontWeight:
                            FontWeight
                                .w800,
                      ),
                    ),
                    const SizedBox(
                      width: 6,
                    ),
                    Container(
                      constraints:
                          const BoxConstraints(
                        minWidth: 20,
                      ),
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      alignment:
                          Alignment.center,
                      decoration:
                          BoxDecoration(
                        color: active
                            ? Colors.white
                                .withValues(
                                  alpha: .18,
                                )
                            : ProvincialAdminColors
                                .blue
                                .withValues(
                                  alpha: .07,
                                ),
                        borderRadius:
                            BorderRadius.circular(
                          999,
                        ),
                      ),
                      child: Text(
                        '${counts[key] ?? 0}',
                        style:
                            TextStyle(
                          color: active
                              ? Colors.white
                              : ProvincialAdminColors
                                  .blue,
                          fontSize: 9,
                          fontWeight:
                              FontWeight
                                  .w900,
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

// ─────────────────────────────────────────────────────────────────────────────
// Section title
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.subtitle,
  });

  final String title;
  final int count;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    title,
                    style:
                        const TextStyle(
                      color:
                          ProvincialAdminColors
                              .text,
                      fontSize: 15,
                      fontWeight:
                          FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          ProvincialAdminColors
                              .blue
                              .withValues(
                        alpha: .07,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        999,
                      ),
                    ),
                    child: Text(
                      '$count',
                      style:
                          const TextStyle(
                        color:
                            ProvincialAdminColors
                                .blue,
                        fontSize: 9,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style:
                    const TextStyle(
                  color:
                      ProvincialAdminColors
                          .muted,
                  fontSize: 10,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tenant grid
// ─────────────────────────────────────────────────────────────────────────────

class _TenantGrid extends StatelessWidget {
  const _TenantGrid({
    required this.tenants,
    required this.onOpen,
    required this.onEditCity,
    required this.onStatus,
  });

  final List<CityTenant> tenants;

  final ValueChanged<CityTenant> onOpen;
  final ValueChanged<CityTenant> onEditCity;

  final void Function(
    CityTenant tenant,
    String status,
  ) onStatus;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;

        final columns = width >= 1150
            ? 3
            : width >= 680
                ? 2
                : 1;

        // Slightly taller on narrow layouts so text has room.
        final cardHeight =
            columns == 1 ? 260.0 : 248.0;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: tenants.length,
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            mainAxisExtent: cardHeight,
          ),
          itemBuilder: (context, index) {
            final tenant = tenants[index];

            return _TenantCard(
              tenant: tenant,
              onTap: () {
                onOpen(tenant);
              },
              onEditCity: () {
                onEditCity(tenant);
              },
              onActivate: () {
                onStatus(
                  tenant,
                  'active',
                );
              },
              onDeactivate: () {
                onStatus(
                  tenant,
                  'inactive',
                );
              },
            );
          },
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tenant card
// ─────────────────────────────────────────────────────────────────────────────

class _TenantCard extends StatelessWidget {
  const _TenantCard({
    required this.tenant,
    required this.onTap,
    required this.onEditCity,
    required this.onActivate,
    required this.onDeactivate,
  });

  final CityTenant tenant;

  final VoidCallback onTap;
  final VoidCallback onEditCity;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;

  @override
  Widget build(BuildContext context) {
    final status =
        tenant.status
            .trim()
            .toLowerCase();

    final active = [
      'active',
      'approved',
      'verified',
    ].contains(status);

    return Material(
      color: Colors.white,
      borderRadius:
          BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(16),
        child: Container(
          height: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(16),
            border: Border.all(
              color:
                  ProvincialAdminColors
                      .line,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black
                        .withValues(
                  alpha: .018,
                ),
                blurRadius: 9,
                offset:
                    const Offset(
                  0,
                  3,
                ),
              ),
            ],
          ),
          clipBehavior:
              Clip.antiAlias,
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              // ─────────────────────────────
              // Header
              // ─────────────────────────────

              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  13,
                  13,
                  7,
                  11,
                ),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 45,
                      height: 45,
                      decoration:
                          BoxDecoration(
                        color: active
                            ? ProvincialAdminColors
                                .blue
                            : _softBlue,
                        borderRadius:
                            BorderRadius.circular(
                          11,
                        ),
                      ),
                      child: Icon(
                        Icons
                            .location_city_rounded,
                        color: active
                            ? Colors.white
                            : ProvincialAdminColors
                                .blue,
                        size: 22,
                      ),
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                        children: [
                          Text(
                            tenant.city
                                    .trim()
                                    .isEmpty
                                ? 'Unassigned LGU'
                                : tenant.city,
                            maxLines: 1,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                const TextStyle(
                              color:
                                  ProvincialAdminColors
                                      .text,
                              fontSize:
                                  14,
                              fontWeight:
                                  FontWeight
                                      .w900,
                            ),
                          ),

                          const SizedBox(
                            height: 3,
                          ),

                          Text(
                            tenant.adminName
                                    .trim()
                                    .isEmpty
                                ? 'No administrator assigned'
                                : tenant
                                    .adminName,
                            maxLines: 1,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                const TextStyle(
                              color:
                                  ProvincialAdminColors
                                      .muted,
                              fontSize:
                                  10,
                              fontWeight:
                                  FontWeight
                                      .w700,
                            ),
                          ),

                          const SizedBox(
                            height: 6,
                          ),

                          Row(
                            children: [
                              AdminStatusPill(
                                status:
                                    tenant.status,
                              ),

                              if (tenant.verified) ...[
                                const SizedBox(
                                  width: 5,
                                ),
                                const _VerificationBadge(),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    PopupMenuButton<String>(
                      tooltip:
                          'Tenant actions',
                      padding:
                          EdgeInsets.zero,
                      icon:
                          const Icon(
                        Icons
                            .more_horiz_rounded,
                        color:
                            ProvincialAdminColors
                                .muted,
                        size: 20,
                      ),
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(
                          12,
                        ),
                      ),
                      onSelected:
                          (value) {
                        switch (value) {
                          case 'view':
                            onTap();
                            break;

                          case 'edit':
                            onEditCity();
                            break;

                          case 'activate':
                            onActivate();
                            break;

                          case 'deactivate':
                            onDeactivate();
                            break;
                        }
                      },
                      itemBuilder:
                          (_) {
                        return [
                          const PopupMenuItem(
                            value: 'view',
                            child: _MenuItem(
                              icon: Icons
                                  .visibility_outlined,
                              label:
                                  'View details',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'edit',
                            child: _MenuItem(
                              icon: Icons
                                  .edit_location_alt_outlined,
                              label:
                                  'Edit assigned city',
                            ),
                          ),
                          if (!active)
                            const PopupMenuItem(
                              value:
                                  'activate',
                              child:
                                  _MenuItem(
                                icon: Icons
                                    .check_circle_outline_rounded,
                                label:
                                    'Activate account',
                                color:
                                    _green,
                              ),
                            ),
                          if (active)
                            const PopupMenuItem(
                              value:
                                  'deactivate',
                              child:
                                  _MenuItem(
                                icon: Icons
                                    .block_outlined,
                                label:
                                    'Deactivate account',
                                color:
                                    _red,
                              ),
                            ),
                        ];
                      },
                    ),
                  ],
                ),
              ),

              const Divider(
                height: 1,
                color:
                    ProvincialAdminColors
                        .line,
              ),

              // ─────────────────────────────
              // Contact details
              // ─────────────────────────────

              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  13,
                  10,
                  13,
                  8,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _TenantInfo(
                        icon:
                            Icons.email_outlined,
                        label: 'Email',
                        value:
                            tenant.email.trim().isEmpty
                                ? 'No email'
                                : tenant.email,
                      ),
                    ),

                    Container(
                      width: 1,
                      height: 31,
                      color:
                          ProvincialAdminColors
                              .line,
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Expanded(
                      child: _TenantInfo(
                        icon:
                            Icons.phone_outlined,
                        label: 'Contact',
                        value:
                            tenant.mobile.trim().isEmpty
                                ? 'No contact'
                                : tenant.mobile,
                      ),
                    ),
                  ],
                ),
              ),

              // ─────────────────────────────
              // Reserved classification area
              //
              // Always consumes same height so every
              // tenant card remains equal.
              // ─────────────────────────────

              Padding(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 13,
                ),
                child: SizedBox(
                  height: 34,
                  child:
                      tenant.localGovernmentTypeReviewed
                          ? const _ReviewedClassification()
                          : const _ClassificationNotice(),
                ),
              ),

              const Spacer(),

              // ─────────────────────────────
              // Metrics
              // ─────────────────────────────

              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  13,
                  8,
                  13,
                  12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child:
                          _TenantMetric(
                        label: 'Spots',
                        value:
                            tenant.spotsCount,
                        icon:
                            Icons.place_outlined,
                        color: _cyan,
                      ),
                    ),
                    const SizedBox(
                      width: 7,
                    ),
                    Expanded(
                      child:
                          _TenantMetric(
                        label: 'Packages',
                        value:
                            tenant.packagesCount,
                        icon:
                            Icons.inventory_2_outlined,
                        color: _green,
                      ),
                    ),
                    const SizedBox(
                      width: 7,
                    ),
                    Expanded(
                      child:
                          _TenantMetric(
                        label: 'Bookings',
                        value:
                            tenant.bookingsCount,
                        icon:
                            Icons.receipt_long_outlined,
                        color: _purple,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Verification badge
// ─────────────────────────────────────────────────────────────────────────────

class _VerificationBadge extends StatelessWidget {
  const _VerificationBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: _softGreen,
        borderRadius:
            BorderRadius.circular(999),
        border: Border.all(
          color:
              _green.withValues(
            alpha: .16,
          ),
        ),
      ),
      child: const Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_rounded,
            color: _green,
            size: 11,
          ),
          SizedBox(width: 4),
          Text(
            'Verified',
            style: TextStyle(
              color: _green,
              fontSize: 8.5,
              fontWeight:
                  FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Classification
// ─────────────────────────────────────────────────────────────────────────────

class _ClassificationNotice extends StatelessWidget {
  const _ClassificationNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 30,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 9,
      ),
      decoration: BoxDecoration(
        color: _softAmber,
        borderRadius:
            BorderRadius.circular(7),
        border: Border.all(
          color:
              _amber.withValues(
            alpha: .18,
          ),
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.rule_outlined,
            color: _amber,
            size: 13,
          ),
          SizedBox(width: 5),
          Expanded(
            child: Text(
              'City / municipality classification requires review',
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style: TextStyle(
                color: _amber,
                fontSize: 8,
                fontWeight:
                    FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewedClassification extends StatelessWidget {
  const _ReviewedClassification();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 30,
      alignment:
          Alignment.centerLeft,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 9,
      ),
      decoration: BoxDecoration(
        color:
            const Color(0xFFF8FAFC),
        borderRadius:
            BorderRadius.circular(7),
        border: Border.all(
          color:
              ProvincialAdminColors.line,
        ),
      ),
      child: const Row(
        children: [
          Icon(
            Icons
                .check_circle_outline_rounded,
            size: 13,
            color:
                ProvincialAdminColors
                    .lightMuted,
          ),
          SizedBox(width: 5),
          Text(
            'LGU classification reviewed',
            style: TextStyle(
              color:
                  ProvincialAdminColors
                      .lightMuted,
              fontSize: 8,
              fontWeight:
                  FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tenant information
// ─────────────────────────────────────────────────────────────────────────────

class _TenantInfo extends StatelessWidget {
  const _TenantInfo({
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
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 13,
          color:
              ProvincialAdminColors
                  .lightMuted,
        ),

        const SizedBox(width: 6),

        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style:
                    const TextStyle(
                  color:
                      ProvincialAdminColors
                          .lightMuted,
                  fontSize: 8,
                  fontWeight:
                      FontWeight.w700,
                ),
              ),

              const SizedBox(height: 2),

              Text(
                value,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  color:
                      ProvincialAdminColors
                          .text,
                  fontSize: 9,
                  fontWeight:
                      FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tenant metrics
// ─────────────────────────────────────────────────────────────────────────────

class _TenantMetric extends StatelessWidget {
  const _TenantMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final int value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color:
            color.withValues(
          alpha: .07,
        ),
        borderRadius:
            BorderRadius.circular(8),
        border: Border.all(
          color:
              color.withValues(
            alpha: .12,
          ),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 13,
            color: color,
          ),

          const SizedBox(width: 5),

          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  '$value',
                  style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight:
                        FontWeight.w900,
                    height: 1,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                    color:
                        ProvincialAdminColors
                            .muted,
                    fontSize: 7.5,
                    fontWeight:
                        FontWeight.w700,
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

// ─────────────────────────────────────────────────────────────────────────────
// Card menu
// ─────────────────────────────────────────────────────────────────────────────

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final actualColor =
        color ??
            ProvincialAdminColors
                .muted;

    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: actualColor,
        ),
        const SizedBox(width: 9),
        Text(
          label,
          style: TextStyle(
            color:
                color ??
                    ProvincialAdminColors
                        .text,
            fontSize: 11,
            fontWeight:
                FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty tenant state
// ─────────────────────────────────────────────────────────────────────────────

class _TenantEmptyState extends StatelessWidget {
  const _TenantEmptyState({
    required this.searched,
    required this.onClearSearch,
  });

  final bool searched;
  final VoidCallback onClearSearch;

  @override
  Widget build(BuildContext context) {
    if (!searched) {
      return const AdminEmptyState(
        icon:
            Icons.location_city_outlined,
        title: 'No city tenants found',
        message:
            'Approved tourism office accounts will appear here.',
      );
    }

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 38,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(15),
        border: Border.all(
          color:
              ProvincialAdminColors.line,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color:
                  ProvincialAdminColors.blue
                      .withValues(
                alpha: .08,
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.search_off_rounded,
              color:
                  ProvincialAdminColors
                      .blue,
              size: 23,
            ),
          ),

          const SizedBox(height: 11),

          const Text(
            'No matching tenant accounts',
            style: TextStyle(
              color:
                  ProvincialAdminColors
                      .text,
              fontSize: 14,
              fontWeight:
                  FontWeight.w900,
            ),
          ),

          const SizedBox(height: 5),

          const Text(
            'Try another city, administrator, email, contact number, or address.',
            textAlign:
                TextAlign.center,
            style: TextStyle(
              color:
                  ProvincialAdminColors
                      .muted,
              fontSize: 10,
              height: 1.4,
            ),
          ),

          const SizedBox(height: 12),

          OutlinedButton.icon(
            onPressed:
                onClearSearch,
            icon: const Icon(
              Icons.close_rounded,
              size: 15,
            ),
            label: const Text(
              'Clear Search',
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Registration table
// ─────────────────────────────────────────────────────────────────────────────

class _RegistrationsTable extends StatelessWidget {
  const _RegistrationsTable({
    required this.registrations,
    required this.onView,
    required this.onApprove,
    required this.onReject,
  });

  final List<CityRegistration> registrations;

  final ValueChanged<CityRegistration>
      onView;

  final ValueChanged<CityRegistration>
      onApprove;

  final ValueChanged<CityRegistration>
      onReject;

  @override
  Widget build(BuildContext context) {
    return AdminDataTable(
      minWidth: 1040,
      child: Column(
        children: [
          const _RegistrationTableHeader(),

          const Divider(
            height: 1,
            color:
                ProvincialAdminColors.line,
          ),

          ...registrations
              .asMap()
              .entries
              .map((entry) {
            final index = entry.key;
            final registration =
                entry.value;

            return Column(
              children: [
                _RegistrationTableRow(
                  registration:
                      registration,
                  shaded:
                      index.isOdd,
                  onView: () {
                    onView(
                      registration,
                    );
                  },
                  onApprove: () {
                    onApprove(
                      registration,
                    );
                  },
                  onReject: () {
                    onReject(
                      registration,
                    );
                  },
                ),

                if (index <
                    registrations.length -
                        1)
                  const Divider(
                    height: 1,
                    color:
                        ProvincialAdminColors
                            .line,
                    indent: 14,
                    endIndent: 14,
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _RegistrationTableHeader
    extends StatelessWidget {
  const _RegistrationTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      color:
          const Color(0xFFF8FAFC),
      padding:
          const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 11,
      ),
      child: const Row(
        children: [
          SizedBox(
            width: 130,
            child:
                _HeadCell('LGU'),
          ),
          SizedBox(
            width: 160,
            child:
                _HeadCell(
              'Tourism Office',
            ),
          ),
          SizedBox(
            width: 150,
            child:
                _HeadCell(
              'Contact',
            ),
          ),
          SizedBox(
            width: 200,
            child:
                _HeadCell(
              'Email',
            ),
          ),
          SizedBox(
            width: 120,
            child:
                _HeadCell(
              'Submitted',
            ),
          ),
          SizedBox(
            width: 100,
            child:
                _HeadCell(
              'Status',
            ),
          ),
          SizedBox(
            width: 132,
            child:
                _HeadCell(
              'Actions',
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadCell extends StatelessWidget {
  const _HeadCell(
    this.label,
  );

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style:
          const TextStyle(
        color:
            ProvincialAdminColors
                .muted,
        fontSize: 9.5,
        fontWeight:
            FontWeight.w900,
        letterSpacing: .2,
      ),
    );
  }
}

class _RegistrationTableRow
    extends StatelessWidget {
  const _RegistrationTableRow({
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
    final pending =
        registration.status
                .trim()
                .toLowerCase() ==
            'pending';

    final submitted =
        registration.submittedAt == null
            ? '-'
            : DateFormat(
                'MMM d, yyyy',
              ).format(
                registration.submittedAt!,
              );

    return InkWell(
      onTap: onView,
      child: Container(
        color: shaded
            ? const Color(
                0xFFFCFDFE,
              )
            : Colors.white,
        padding:
            const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 13,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 130,
              child: Text(
                registration.city,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  color:
                      ProvincialAdminColors
                          .text,
                  fontWeight:
                      FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),

            SizedBox(
              width: 160,
              child: Text(
                registration
                        .officeName
                        .trim()
                        .isEmpty
                    ? 'Tourism Office'
                    : registration
                        .officeName,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  color:
                      ProvincialAdminColors
                          .muted,
                  fontWeight:
                      FontWeight.w700,
                  fontSize: 10.5,
                ),
              ),
            ),

            SizedBox(
              width: 150,
              child: Text(
                registration
                        .contactPerson
                        .trim()
                        .isEmpty
                    ? 'No contact person'
                    : registration
                        .contactPerson,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  color:
                      ProvincialAdminColors
                          .text,
                  fontWeight:
                      FontWeight.w700,
                  fontSize: 10.5,
                ),
              ),
            ),

            SizedBox(
              width: 200,
              child: Text(
                registration.email.trim().isEmpty
                    ? 'No email'
                    : registration.email,
                maxLines: 1,
                overflow:
                    TextOverflow.ellipsis,
                style:
                    const TextStyle(
                  color:
                      ProvincialAdminColors
                          .muted,
                  fontWeight:
                      FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),

            SizedBox(
              width: 120,
              child: Text(
                submitted,
                style:
                    const TextStyle(
                  color:
                      ProvincialAdminColors
                          .muted,
                  fontWeight:
                      FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),

            SizedBox(
              width: 100,
              child:
                  AdminStatusPill(
                status:
                    registration.status,
              ),
            ),

            SizedBox(
              width: 132,
              child: Row(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  _IconAction(
                    icon: Icons
                        .visibility_outlined,
                    tooltip:
                        'View application',
                    color:
                        ProvincialAdminColors
                            .blue,
                    onPressed:
                        onView,
                  ),

                  if (pending) ...[
                    const SizedBox(
                      width: 4,
                    ),
                    _IconAction(
                      icon: Icons
                          .check_rounded,
                      tooltip:
                          'Approve',
                      color: _green,
                      onPressed:
                          onApprove,
                    ),
                    const SizedBox(
                      width: 4,
                    ),
                    _IconAction(
                      icon: Icons
                          .close_rounded,
                      tooltip:
                          'Reject',
                      color: _red,
                      onPressed:
                          onReject,
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

// ─────────────────────────────────────────────────────────────────────────────
// Registration mobile card
// ─────────────────────────────────────────────────────────────────────────────

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
    final pending =
        registration.status
                .trim()
                .toLowerCase() ==
            'pending';

    final submitted =
        registration.submittedAt == null
            ? '-'
            : DateFormat(
                'MMM d, yyyy',
              ).format(
                registration.submittedAt!,
              );

    return AdminSectionCard(
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration:
                    BoxDecoration(
                  color:
                      ProvincialAdminColors
                          .blue
                          .withValues(
                    alpha: .08,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),
                ),
                child: const Icon(
                  Icons
                      .location_city_outlined,
                  color:
                      ProvincialAdminColors
                          .blue,
                  size: 20,
                ),
              ),

              const SizedBox(
                width: 10,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      registration.city,
                      style:
                          const TextStyle(
                        color:
                            ProvincialAdminColors
                                .text,
                        fontSize: 14,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),

                    const SizedBox(
                      height: 2,
                    ),

                    Text(
                      registration
                              .officeName
                              .trim()
                              .isEmpty
                          ? 'Tourism Office'
                          : registration
                              .officeName,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style:
                          const TextStyle(
                        color:
                            ProvincialAdminColors
                                .muted,
                        fontSize: 10.5,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(
                width: 10,
              ),

              AdminStatusPill(
                status:
                    registration.status,
              ),
            ],
          ),

          const SizedBox(
            height: 13,
          ),

          const Divider(
            height: 1,
            color:
                ProvincialAdminColors.line,
          ),

          const SizedBox(
            height: 12,
          ),

          _CardInfoRow(
            icon:
                Icons.person_outline_rounded,
            text:
                registration.contactPerson.trim().isEmpty
                    ? 'No contact person'
                    : registration
                        .contactPerson,
          ),

          const SizedBox(
            height: 7,
          ),

          _CardInfoRow(
            icon:
                Icons.email_outlined,
            text:
                registration.email.trim().isEmpty
                    ? 'No email'
                    : registration.email,
          ),

          const SizedBox(
            height: 7,
          ),

          _CardInfoRow(
            icon: Icons
                .calendar_today_outlined,
            text:
                'Submitted $submitted',
          ),

          const SizedBox(
            height: 14,
          ),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed:
                    onView,
                icon:
                    const Icon(
                  Icons
                      .visibility_outlined,
                  size: 15,
                ),
                label:
                    const Text(
                  'View',
                ),
              ),

              if (pending)
                FilledButton.icon(
                  onPressed:
                      onApprove,
                  icon:
                      const Icon(
                    Icons.check_rounded,
                    size: 15,
                  ),
                  label:
                      const Text(
                    'Approve',
                  ),
                  style:
                      FilledButton.styleFrom(
                    backgroundColor:
                        _green,
                  ),
                ),

              if (pending)
                OutlinedButton.icon(
                  onPressed:
                      onReject,
                  icon:
                      const Icon(
                    Icons.close_rounded,
                    size: 15,
                  ),
                  label:
                      const Text(
                    'Reject',
                  ),
                  style:
                      OutlinedButton.styleFrom(
                    foregroundColor:
                        _red,
                    side:
                        const BorderSide(
                      color: _red,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small action widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CardInfoRow extends StatelessWidget {
  const _CardInfoRow({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 14,
          color:
              ProvincialAdminColors
                  .lightMuted,
        ),

        const SizedBox(
          width: 8,
        ),

        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style:
                const TextStyle(
              color:
                  ProvincialAdminColors
                      .muted,
              fontSize: 10.5,
              fontWeight:
                  FontWeight.w700,
            ),
          ),
        ),
      ],
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
        borderRadius:
            BorderRadius.circular(8),
        child: Container(
          padding:
              const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color:
                color.withValues(
              alpha: .08,
            ),
            borderRadius:
                BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: color,
            size: 16,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Registration details bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _RegistrationDetailsSheet extends StatelessWidget {
  const _RegistrationDetailsSheet({
    required this.registration,
  });

  final CityRegistration registration;

  @override
  Widget build(BuildContext context) {
    final submitted =
        registration.submittedAt == null
            ? '-'
            : DateFormat(
                'MMM d, yyyy - h:mm a',
              ).format(
                registration.submittedAt!,
              );

    final height =
        MediaQuery.sizeOf(context)
            .height;

    return Container(
      constraints: BoxConstraints(
        maxHeight:
            height * .88,
      ),
      decoration:
          const BoxDecoration(
        color:
            Color(0xFFF8FAFC),
        borderRadius:
            BorderRadius.vertical(
          top: Radius.circular(
            24,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Padding(
              padding:
                  const EdgeInsets.fromLTRB(
                20,
                12,
                12,
                12,
              ),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration:
                        BoxDecoration(
                      color:
                          ProvincialAdminColors
                              .blue
                              .withValues(
                        alpha: .08,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        10,
                      ),
                    ),
                    child:
                        const Icon(
                      Icons
                          .how_to_reg_outlined,
                      color:
                          ProvincialAdminColors
                              .blue,
                      size: 19,
                    ),
                  ),

                  const SizedBox(
                    width: 10,
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          registration.city,
                          style:
                              const TextStyle(
                            color:
                                ProvincialAdminColors
                                    .text,
                            fontSize: 16,
                            fontWeight:
                                FontWeight.w900,
                          ),
                        ),
                        const SizedBox(
                          height: 2,
                        ),
                        Text(
                          registration
                                  .officeName
                                  .trim()
                                  .isEmpty
                              ? 'Tourism Office Registration'
                              : registration
                                  .officeName,
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style:
                              const TextStyle(
                            color:
                                ProvincialAdminColors
                                    .muted,
                            fontSize: 10.5,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  AdminStatusPill(
                    status:
                        registration.status,
                  ),

                  const SizedBox(
                    width: 6,
                  ),

                  IconButton(
                    tooltip: 'Close',
                    onPressed: () {
                      Navigator.pop(
                        context,
                      );
                    },
                    icon:
                        const Icon(
                      Icons.close_rounded,
                    ),
                  ),
                ],
              ),
            ),

            const Divider(
              height: 1,
              color:
                  ProvincialAdminColors
                      .line,
            ),

            Flexible(
              child:
                  SingleChildScrollView(
                padding:
                    const EdgeInsets.all(
                  20,
                ),
                child:
                    AdminSectionCard(
                  child: Column(
                    children: [
                      _DetailTile(
                        icon: Icons
                            .person_outline_rounded,
                        label:
                            'Contact Person',
                        value:
                            registration.contactPerson.trim().isEmpty
                                ? 'No contact person'
                                : registration
                                    .contactPerson,
                      ),

                      _DetailTile(
                        icon:
                            Icons.phone_outlined,
                        label:
                            'Contact Number',
                        value:
                            registration.contactNumber.trim().isEmpty
                                ? 'No contact number'
                                : registration
                                    .contactNumber,
                      ),

                      _DetailTile(
                        icon:
                            Icons.email_outlined,
                        label:
                            'Email',
                        value:
                            registration.email.trim().isEmpty
                                ? 'No email'
                                : registration.email,
                      ),

                      _DetailTile(
                        icon:
                            Icons.home_outlined,
                        label:
                            'Office Address',
                        value:
                            registration.address.trim().isEmpty
                                ? 'No address submitted'
                                : registration.address,
                      ),

                      _DetailTile(
                        icon: Icons
                            .calendar_today_outlined,
                        label:
                            'Submitted',
                        value:
                            submitted,
                        isLast:
                            registration.rejectionReason.trim().isEmpty,
                      ),

                      if (registration
                          .rejectionReason
                          .trim()
                          .isNotEmpty)
                        _DetailTile(
                          icon: Icons
                              .info_outline_rounded,
                          label:
                              'Rejection Reason',
                          value:
                              registration.rejectionReason,
                          valueColor:
                              _red,
                          isLast:
                              true,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Detail tile
// ─────────────────────────────────────────────────────────────────────────────

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
          padding:
              const EdgeInsets.symmetric(
            vertical: 10,
          ),
          child: Row(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration:
                    BoxDecoration(
                  color:
                      ProvincialAdminColors
                          .blue
                          .withValues(
                    alpha: .07,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    8,
                  ),
                ),
                child: Icon(
                  icon,
                  color:
                      ProvincialAdminColors
                          .blue,
                  size: 15,
                ),
              ),

              const SizedBox(
                width: 10,
              ),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style:
                          const TextStyle(
                        color:
                            ProvincialAdminColors
                                .muted,
                        fontSize: 9.5,
                        fontWeight:
                            FontWeight.w700,
                      ),
                    ),

                    const SizedBox(
                      height: 2,
                    ),

                    Text(
                      value,
                      style:
                          TextStyle(
                        color:
                            valueColor ??
                                ProvincialAdminColors
                                    .text,
                        fontSize: 11.5,
                        fontWeight:
                            FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        if (!isLast)
          const Divider(
            height: 1,
            color:
                ProvincialAdminColors
                    .line,
          ),
      ],
    );
  }
}