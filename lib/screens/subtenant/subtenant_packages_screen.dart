import 'package:flutter/material.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_package_form_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_package_itinerary_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantPackagesScreen extends StatefulWidget {
  const SubTenantPackagesScreen({super.key});

  @override
  State<SubTenantPackagesScreen> createState() =>
      _SubTenantPackagesScreenState();
}

class _SubTenantPackagesScreenState extends State<SubTenantPackagesScreen> {
  final SubTenantService _service = SubTenantService();
  final TextEditingController _searchCtrl = TextEditingController();

  late Future<_PackageListLoad> _future;
  String _status = 'all';
  String _visibility = 'all';

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

  Future<_PackageListLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final packages = await _service.fetchPackages(profile);
    return _PackageListLoad(profile: profile, packages: packages);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _openForm([SubTenantPackage? package]) async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubTenantPackageFormScreen(package: package),
      ),
    );
    if (!mounted) return;
    if (changed == true) _reload();
  }

  Future<void> _openItinerary(SubTenantPackage package) async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubTenantPackageItineraryScreen(package: package),
      ),
    );
    if (!mounted) return;
    if (changed == true) _reload();
  }

  Future<void> _setStatus(
    SubTenantProfile profile,
    SubTenantPackage package,
    String status,
  ) async {
    try {
      await _service.updatePackageStatus(profile, package, status);
      if (!mounted) return;
      showSubTenantSnack(context, 'Package status updated.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to update package: $e');
    }
  }

  Future<void> _setVisibility(
    SubTenantProfile profile,
    SubTenantPackage package,
    String visibility,
  ) async {
    try {
      await _service.updatePackageVisibility(profile, package, visibility);
      if (!mounted) return;
      showSubTenantSnack(context, 'Package visibility updated.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to update visibility: $e');
    }
  }

  List<SubTenantPackage> _filtered(List<SubTenantPackage> packages) {
    final query = _searchCtrl.text.trim().toLowerCase();
    return packages
        .where((item) {
          final matchesSearch =
              query.isEmpty ||
              item.title.toLowerCase().contains(query) ||
              item.subtitle.toLowerCase().contains(query) ||
              item.status.toLowerCase().contains(query);
          final matchesStatus = _status == 'all' || item.status == _status;
          final matchesVisibility =
              _visibility == 'all' || item.visibilityStatus == _visibility;
          return matchesSearch && matchesStatus && matchesVisibility;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return SubTenantAdminShell(
      currentIndex: 2,
      title: 'Packages',
      subtitle: 'Create, publish, hide, and maintain city tour packages.',
      actions: [
        if (!mobile)
          FilledButton.icon(
            onPressed: () => _openForm(),
            icon: const Icon(Icons.add_box_rounded),
            label: const Text('Create Package'),
          ),
      ],
      floatingActionButton: mobile
          ? FloatingActionButton(
              heroTag: 'subtenant_package_add_fab',
              backgroundColor: SubTenantColors.blue,
              foregroundColor: Colors.white,
              onPressed: () => _openForm(),
              child: const Icon(Icons.add_rounded),
            )
          : null,
      child: FutureBuilder<_PackageListLoad>(
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
          final packages = _filtered(load.packages);
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ResponsivePageContainer(
              children: [
                _PackageToolbar(
                  controller: _searchCtrl,
                  status: _status,
                  visibility: _visibility,
                  onStatusChanged: (value) => setState(() => _status = value),
                  onVisibilityChanged: (value) =>
                      setState(() => _visibility = value),
                ),
                const SizedBox(height: 16),
                if (packages.isEmpty)
                  EmptyStateCard(
                    icon: Icons.inventory_2_outlined,
                    title: 'No packages found',
                    message:
                        'Only packages for ${load.profile.assignedCity} are shown here.',
                    actionLabel: 'Create Package',
                    onAction: () => _openForm(),
                  )
                else if (mobile)
                  ...packages.map(
                    (package) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _PackageCard(
                        package: package,
                        onEdit: () => _openForm(package),
                        onItinerary: () => _openItinerary(package),
                        onPublish: () =>
                            _setStatus(load.profile, package, 'published'),
                        onDraft: () =>
                            _setStatus(load.profile, package, 'draft'),
                        onSoldOut: () =>
                            _setStatus(load.profile, package, 'sold_out'),
                        onVisibilityChanged: (visible) => _setVisibility(
                          load.profile,
                          package,
                          visible ? 'visible' : 'hidden',
                        ),
                      ),
                    ),
                  )
                else
                  _PackageTable(
                    packages: packages,
                    onEdit: _openForm,
                    onItinerary: _openItinerary,
                    onStatus: (package, status) =>
                        _setStatus(load.profile, package, status),
                    onVisibilityChanged: (package, visible) => _setVisibility(
                      load.profile,
                      package,
                      visible ? 'visible' : 'hidden',
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PackageToolbar extends StatelessWidget {
  const _PackageToolbar({
    required this.controller,
    required this.status,
    required this.visibility,
    required this.onStatusChanged,
    required this.onVisibilityChanged,
  });

  final TextEditingController controller;
  final String status;
  final String visibility;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SubTenantSearchBar(
            controller: controller,
            hintText: 'Search packages...',
            onChanged: (_) {},
          ),
          const SizedBox(height: 12),
          SubTenantFilterChips(
            values: const [
              'all',
              'draft',
              'pending',
              'published',
              'returned',
              'sold_out',
            ],
            selected: status,
            onSelected: onStatusChanged,
          ),
          const SizedBox(height: 10),
          SubTenantFilterChips(
            values: const ['all', 'visible', 'hidden'],
            selected: visibility,
            onSelected: onVisibilityChanged,
          ),
        ],
      ),
    );
  }
}

class _PackageTable extends StatelessWidget {
  const _PackageTable({
    required this.packages,
    required this.onEdit,
    required this.onItinerary,
    required this.onStatus,
    required this.onVisibilityChanged,
  });

  final List<SubTenantPackage> packages;
  final ValueChanged<SubTenantPackage> onEdit;
  final ValueChanged<SubTenantPackage> onItinerary;
  final void Function(SubTenantPackage package, String status) onStatus;
  final void Function(SubTenantPackage package, bool visible)
  onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    return ResponsiveTableWrapper(
      minWidth: 1120,
      child: DataTable(
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
          DataColumn(label: Text('Package')),
          DataColumn(label: Text('Price')),
          DataColumn(label: Text('Duration')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Visibility')),
          DataColumn(label: Text('Actions')),
        ],
        rows: packages
            .map((package) {
              final isVisible = package.visibilityStatus != 'hidden';
              return DataRow(
                cells: [
                  DataCell(_PackageIdentity(package: package)),
                  DataCell(Text(package.priceText)),
                  DataCell(Text(package.durationText)),
                  DataCell(SubTenantStatusPill(status: package.status)),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SubTenantStatusPill(
                          status: package.visibilityStatus,
                          icon: isVisible
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                        const SizedBox(width: 8),
                        Switch(
                          value: isVisible,
                          activeThumbColor: Colors.white,
                          activeTrackColor: SubTenantColors.blue,
                          inactiveThumbColor: Colors.white,
                          inactiveTrackColor: const Color(0xFFD7E2F0),
                          onChanged: (visible) =>
                              onVisibilityChanged(package, visible),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    PopupMenuButton<String>(
                      tooltip: 'Package actions',
                      onSelected: (value) {
                        switch (value) {
                          case 'edit':
                            onEdit(package);
                            break;
                          case 'itinerary':
                            onItinerary(package);
                            break;
                          case 'publish':
                          case 'draft':
                          case 'sold_out':
                            onStatus(package, value);
                            break;
                        }
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(value: 'edit', child: Text('Edit')),
                        PopupMenuItem(
                          value: 'itinerary',
                          child: Text('Manage Itinerary'),
                        ),
                        PopupMenuItem(value: 'publish', child: Text('Publish')),
                        PopupMenuItem(
                          value: 'draft',
                          child: Text('Move to Draft'),
                        ),
                        PopupMenuItem(
                          value: 'sold_out',
                          child: Text('Mark Sold Out'),
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

class _PackageIdentity extends StatelessWidget {
  const _PackageIdentity({required this.package});

  final SubTenantPackage package;

  @override
  Widget build(BuildContext context) {
    final imageUrl = package.coverImageUrl.isNotEmpty
        ? package.coverImageUrl
        : package.imageUrl;

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFE8EEF7),
            borderRadius: BorderRadius.circular(14),
            image: imageUrl.isEmpty
                ? null
                : DecorationImage(
                    image: NetworkImage(imageUrl),
                    fit: BoxFit.cover,
                  ),
          ),
          child: imageUrl.isEmpty
              ? const Icon(
                  Icons.image_outlined,
                  color: SubTenantColors.lightMuted,
                  size: 20,
                )
              : null,
        ),
        const SizedBox(width: 10),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 290),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                package.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                package.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SubTenantColors.muted,
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

class _PackageCard extends StatelessWidget {
  const _PackageCard({
    required this.package,
    required this.onEdit,
    required this.onItinerary,
    required this.onPublish,
    required this.onDraft,
    required this.onSoldOut,
    required this.onVisibilityChanged,
  });

  final SubTenantPackage package;
  final VoidCallback onEdit;
  final VoidCallback onItinerary;
  final VoidCallback onPublish;
  final VoidCallback onDraft;
  final VoidCallback onSoldOut;
  final ValueChanged<bool> onVisibilityChanged;

  @override
  Widget build(BuildContext context) {
    final isVisible = package.visibilityStatus != 'hidden';
    final imageUrl = package.coverImageUrl.isNotEmpty
        ? package.coverImageUrl
        : package.imageUrl;

    return SubTenantDashboardCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8EEF7),
                  borderRadius: BorderRadius.circular(18),
                  image: imageUrl.isEmpty
                      ? null
                      : DecorationImage(
                          image: NetworkImage(imageUrl),
                          fit: BoxFit.cover,
                        ),
                ),
                child: imageUrl.isEmpty
                    ? const Icon(
                        Icons.image_outlined,
                        color: SubTenantColors.lightMuted,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            package.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SubTenantColors.text,
                              fontSize: 15.5,
                              fontWeight: FontWeight.w900,
                              height: 1.15,
                            ),
                          ),
                        ),
                        PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'edit':
                                onEdit();
                                break;
                              case 'itinerary':
                                onItinerary();
                                break;
                              case 'publish':
                                onPublish();
                                break;
                              case 'draft':
                                onDraft();
                                break;
                              case 'sold_out':
                                onSoldOut();
                                break;
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'edit',
                              child: Text('Edit Package'),
                            ),
                            PopupMenuItem(
                              value: 'itinerary',
                              child: Text('Manage Itinerary'),
                            ),
                            PopupMenuItem(
                              value: 'publish',
                              child: Text('Publish'),
                            ),
                            PopupMenuItem(
                              value: 'draft',
                              child: Text('Move to Draft'),
                            ),
                            PopupMenuItem(
                              value: 'sold_out',
                              child: Text('Mark Sold Out'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    Text(
                      package.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SubTenantStatusPill(status: package.status),
                        SubTenantStatusPill(
                          status: package.visibilityStatus,
                          icon: isVisible
                              ? Icons.visibility_rounded
                              : Icons.visibility_off_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${package.priceText} - ${package.durationText}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                isVisible ? 'Visible' : 'Hidden',
                style: const TextStyle(
                  color: SubTenantColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              Switch(
                value: isVisible,
                activeThumbColor: Colors.white,
                activeTrackColor: SubTenantColors.blue,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFD7E2F0),
                onChanged: onVisibilityChanged,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PackageListLoad {
  const _PackageListLoad({required this.profile, required this.packages});

  final SubTenantProfile profile;
  final List<SubTenantPackage> packages;
}
