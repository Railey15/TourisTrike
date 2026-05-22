import 'package:flutter/material.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_package_form_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_package_itinerary_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

enum _PackageViewMode { list, grid }

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
  _PackageViewMode _viewMode = _PackageViewMode.list;

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
    final nextFuture = _load();
    setState(() {
      _future = nextFuture;
    });
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

    return packages.where((item) {
      final matchesSearch =
          query.isEmpty ||
          item.title.toLowerCase().contains(query) ||
          item.subtitle.toLowerCase().contains(query) ||
          item.status.toLowerCase().contains(query) ||
          item.visibilityStatus.toLowerCase().contains(query) ||
          item.priceText.toLowerCase().contains(query) ||
          item.durationText.toLowerCase().contains(query);

      final matchesStatus = _status == 'all' || item.status == _status;
      final matchesVisibility =
          _visibility == 'all' || item.visibilityStatus == _visibility;

      return matchesSearch && matchesStatus && matchesVisibility;
    }).toList(growable: false);
  }

  int _countStatus(List<SubTenantPackage> packages, String status) {
    return packages.where((item) => item.status == status).length;
  }

  int _countVisibility(List<SubTenantPackage> packages, String visibility) {
    return packages.where((item) => item.visibilityStatus == visibility).length;
  }

  Future<void> _openFilters(List<SubTenantPackage> allPackages) async {
    final result = await showModalBottomSheet<_PackageFilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _PackageFilterSheet(
          status: _status,
          visibility: _visibility,
          total: allPackages.length,
          draft: _countStatus(allPackages, 'draft'),
          pending: _countStatus(allPackages, 'pending'),
          published: _countStatus(allPackages, 'published'),
          returned: _countStatus(allPackages, 'returned'),
          soldOut: _countStatus(allPackages, 'sold_out'),
          visible: _countVisibility(allPackages, 'visible'),
          hidden: _countVisibility(allPackages, 'hidden'),
        );
      },
    );

    if (result == null) return;

    setState(() {
      _status = result.status;
      _visibility = result.visibility;
    });
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
            style: FilledButton.styleFrom(
              backgroundColor: SubTenantColors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
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
            child: _PackagesBody(
              profile: load.profile,
              allPackages: load.packages,
              packages: packages,
              searchCtrl: _searchCtrl,
              status: _status,
              visibility: _visibility,
              viewMode: _viewMode,
              onOpenFilters: () => _openFilters(load.packages),
              onViewModeChanged: (mode) => setState(() => _viewMode = mode),
              onCreate: () => _openForm(),
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
          );
        },
      ),
    );
  }
}

class _PackagesBody extends StatelessWidget {
  const _PackagesBody({
    required this.profile,
    required this.allPackages,
    required this.packages,
    required this.searchCtrl,
    required this.status,
    required this.visibility,
    required this.viewMode,
    required this.onOpenFilters,
    required this.onViewModeChanged,
    required this.onCreate,
    required this.onEdit,
    required this.onItinerary,
    required this.onStatus,
    required this.onVisibilityChanged,
  });

  final SubTenantProfile profile;
  final List<SubTenantPackage> allPackages;
  final List<SubTenantPackage> packages;
  final TextEditingController searchCtrl;
  final String status;
  final String visibility;
  final _PackageViewMode viewMode;
  final VoidCallback onOpenFilters;
  final ValueChanged<_PackageViewMode> onViewModeChanged;
  final VoidCallback onCreate;
  final ValueChanged<SubTenantPackage> onEdit;
  final ValueChanged<SubTenantPackage> onItinerary;
  final void Function(SubTenantPackage package, String status) onStatus;
  final void Function(SubTenantPackage package, bool visible)
      onVisibilityChanged;

  String get _filterLabel {
    final hasStatus = status != 'all';
    final hasVisibility = visibility != 'all';

    if (!hasStatus && !hasVisibility) return 'Filters';

    final parts = <String>[
      if (hasStatus) _pretty(status),
      if (hasVisibility) _pretty(visibility),
    ];

    return parts.join(' • ');
  }

  String _pretty(String value) {
    if (value == 'all') return 'All';
    if (value == 'sold_out') return 'Sold Out';
    return value
        .split('_')
        .map((word) =>
            word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    if (!desktop) {
      return SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
        child: Column(
          children: [
            _PackageToolbar(
              controller: searchCtrl,
              filterLabel: _filterLabel,
              viewMode: viewMode,
              resultCount: packages.length,
              totalCount: allPackages.length,
              onOpenFilters: onOpenFilters,
              onViewModeChanged: onViewModeChanged,
            ),
            const SizedBox(height: 12),
            if (packages.isEmpty)
              EmptyStateCard(
                icon: Icons.inventory_2_outlined,
                title: 'No packages found',
                message:
                    'Only packages for ${profile.assignedCity} are shown here.',
                actionLabel: 'Create Package',
                onAction: onCreate,
              )
            else if (viewMode == _PackageViewMode.grid)
              _PackageGrid(
                packages: packages,
                onEdit: onEdit,
                onItinerary: onItinerary,
                onStatus: onStatus,
                onVisibilityChanged: onVisibilityChanged,
              )
            else
              _MobilePackageList(
                packages: packages,
                onEdit: onEdit,
                onItinerary: onItinerary,
                onStatus: onStatus,
                onVisibilityChanged: onVisibilityChanged,
              ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        children: [
          _PackageToolbar(
            controller: searchCtrl,
            filterLabel: _filterLabel,
            viewMode: viewMode,
            resultCount: packages.length,
            totalCount: allPackages.length,
            onOpenFilters: onOpenFilters,
            onViewModeChanged: onViewModeChanged,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: packages.isEmpty
                ? EmptyStateCard(
                    icon: Icons.inventory_2_outlined,
                    title: 'No packages found',
                    message:
                        'Only packages for ${profile.assignedCity} are shown here.',
                    actionLabel: 'Create Package',
                    onAction: onCreate,
                  )
                : viewMode == _PackageViewMode.grid
                    ? _PanelCard(
                        padding: const EdgeInsets.all(12),
                        child: Scrollbar(
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            child: _PackageGrid(
                              packages: packages,
                              onEdit: onEdit,
                              onItinerary: onItinerary,
                              onStatus: onStatus,
                              onVisibilityChanged: onVisibilityChanged,
                            ),
                          ),
                        ),
                      )
                    : _PackageTable(
                        packages: packages,
                        onEdit: onEdit,
                        onItinerary: onItinerary,
                        onStatus: onStatus,
                        onVisibilityChanged: onVisibilityChanged,
                      ),
          ),
        ],
      ),
    );
  }
}

class _PackageToolbar extends StatelessWidget {
  const _PackageToolbar({
    required this.controller,
    required this.filterLabel,
    required this.viewMode,
    required this.resultCount,
    required this.totalCount,
    required this.onOpenFilters,
    required this.onViewModeChanged,
  });

  final TextEditingController controller;
  final String filterLabel;
  final _PackageViewMode viewMode;
  final int resultCount;
  final int totalCount;
  final VoidCallback onOpenFilters;
  final ValueChanged<_PackageViewMode> onViewModeChanged;

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);
    final countLabel = resultCount == totalCount
        ? '$totalCount package${totalCount == 1 ? '' : 's'}'
        : '$resultCount of $totalCount packages';

    return _PanelCard(
      child: desktop
          ? Row(
              children: [
                Expanded(
                  child: SubTenantSearchBar(
                    controller: controller,
                    hintText: 'Search package title, subtitle, status...',
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(width: 12),
                _ToolbarButton(
                  icon: Icons.tune_rounded,
                  label: filterLabel,
                  onTap: onOpenFilters,
                ),
                const SizedBox(width: 10),
                _ViewModeToggle(
                  value: viewMode,
                  onChanged: onViewModeChanged,
                ),
                const SizedBox(width: 10),
                _ResultPill(label: countLabel),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SubTenantSearchBar(
                  controller: controller,
                  hintText: 'Search packages...',
                  onChanged: (_) {},
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _ToolbarButton(
                        icon: Icons.tune_rounded,
                        label: filterLabel,
                        onTap: onOpenFilters,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ViewModeToggle(
                      value: viewMode,
                      onChanged: onViewModeChanged,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _ResultPill(label: countLabel),
              ],
            ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF7FAFF),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SubTenantColors.line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: SubTenantColors.blue),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: SubTenantColors.muted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ViewModeToggle extends StatelessWidget {
  const _ViewModeToggle({
    required this.value,
    required this.onChanged,
  });

  final _PackageViewMode value;
  final ValueChanged<_PackageViewMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _ToggleIconButton(
            selected: value == _PackageViewMode.list,
            icon: Icons.view_list_rounded,
            tooltip: 'List view',
            onTap: () => onChanged(_PackageViewMode.list),
          ),
          _ToggleIconButton(
            selected: value == _PackageViewMode.grid,
            icon: Icons.grid_view_rounded,
            tooltip: 'Grid view',
            onTap: () => onChanged(_PackageViewMode.grid),
          ),
        ],
      ),
    );
  }
}

class _ToggleIconButton extends StatelessWidget {
  const _ToggleIconButton({
    required this.selected,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: selected ? SubTenantColors.blue : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 18,
            color: selected ? Colors.white : SubTenantColors.muted,
          ),
        ),
      ),
    );
  }
}

class _ResultPill extends StatelessWidget {
  const _ResultPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
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
            Icons.inventory_2_rounded,
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
    return _PanelCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: ResponsiveTableWrapper(
          minWidth: 1120,
          child: DataTable(
            showCheckboxColumn: false,
            headingRowHeight: 46,
            dataRowMinHeight: 64,
            dataRowMaxHeight: 70,
            horizontalMargin: 18,
            columnSpacing: 24,
            headingTextStyle: const TextStyle(
              color: SubTenantColors.muted,
              fontWeight: FontWeight.w900,
              fontSize: 11.5,
            ),
            dataTextStyle: const TextStyle(
              color: SubTenantColors.text,
              fontWeight: FontWeight.w700,
              fontSize: 12.2,
            ),
            columns: const [
              DataColumn(label: Text('Package')),
              DataColumn(label: Text('Price')),
              DataColumn(label: Text('Duration')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Visibility')),
              DataColumn(label: Text('Actions')),
            ],
            rows: packages.map((package) {
              final isVisible = package.visibilityStatus != 'hidden';

              return DataRow(
                onSelectChanged: (_) => onEdit(package),
                cells: [
                  DataCell(_PackageIdentity(package: package)),
                  DataCell(Text(package.priceText.isEmpty ? 'N/A' : package.priceText)),
                  DataCell(Text(package.durationText.isEmpty ? 'N/A' : package.durationText)),
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
                    _PackageActionsButton(
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
                    ),
                  ),
                ],
              );
            }).toList(growable: false),
          ),
        ),
      ),
    );
  }
}

class _PackageGrid extends StatelessWidget {
  const _PackageGrid({
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
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1150
            ? 3
            : width >= 760
                ? 2
                : 1;

        const spacing = 12.0;
        final cardWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: packages.map((package) {
            return SizedBox(
              width: cardWidth,
              child: _PackageGridCard(
                package: package,
                onEdit: () => onEdit(package),
                onItinerary: () => onItinerary(package),
                onPublish: () => onStatus(package, 'published'),
                onDraft: () => onStatus(package, 'draft'),
                onSoldOut: () => onStatus(package, 'sold_out'),
                onVisibilityChanged: (visible) =>
                    onVisibilityChanged(package, visible),
              ),
            );
          }).toList(growable: false),
        );
      },
    );
  }
}

class _MobilePackageList extends StatelessWidget {
  const _MobilePackageList({
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
    return Column(
      children: packages.map((package) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _PackageListCard(
            package: package,
            onEdit: () => onEdit(package),
            onItinerary: () => onItinerary(package),
            onPublish: () => onStatus(package, 'published'),
            onDraft: () => onStatus(package, 'draft'),
            onSoldOut: () => onStatus(package, 'sold_out'),
            onVisibilityChanged: (visible) =>
                onVisibilityChanged(package, visible),
          ),
        );
      }).toList(growable: false),
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
        _PackageThumb(imageUrl: imageUrl, size: 46),
        const SizedBox(width: 11),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 310),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                package.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SubTenantColors.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                package.subtitle.isEmpty ? 'No subtitle' : package.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SubTenantColors.muted,
                  fontSize: 11.2,
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

class _PackageThumb extends StatelessWidget {
  const _PackageThumb({
    required this.imageUrl,
    required this.size,
  });

  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEF7),
        borderRadius: BorderRadius.circular(size >= 70 ? 18 : 15),
        image: imageUrl.isEmpty
            ? null
            : DecorationImage(
                image: NetworkImage(imageUrl),
                fit: BoxFit.cover,
              ),
      ),
      child: imageUrl.isEmpty
          ? Icon(
              Icons.image_outlined,
              color: SubTenantColors.lightMuted,
              size: size >= 70 ? 26 : 20,
            )
          : null,
    );
  }
}

class _PackageGridCard extends StatelessWidget {
  const _PackageGridCard({
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

    return _PanelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PackageThumb(imageUrl: imageUrl, size: 64),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${package.title}\n',
                        style: const TextStyle(
                          color: SubTenantColors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          height: 1.12,
                        ),
                      ),
                      TextSpan(
                        text: package.subtitle.isEmpty
                            ? 'No subtitle'
                            : package.subtitle,
                        style: const TextStyle(
                          color: SubTenantColors.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 11.5,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _PackageActionsButton(
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
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              SubTenantStatusPill(status: package.status),
              SubTenantStatusPill(
                status: package.visibilityStatus,
                icon:
                    isVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFFF7FAFF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: SubTenantColors.line),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${package.priceText.isEmpty ? 'N/A' : package.priceText} • ${package.durationText.isEmpty ? 'N/A' : package.durationText}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SubTenantColors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
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
          ),
        ],
      ),
    );
  }
}

class _PackageListCard extends StatelessWidget {
  const _PackageListCard({
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

    return _PanelCard(
      child: Row(
        children: [
          _PackageThumb(imageUrl: imageUrl, size: 72),
          const SizedBox(width: 12),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '${package.title}\n',
                    style: const TextStyle(
                      color: SubTenantColors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                  TextSpan(
                    text:
                        '${package.subtitle.isEmpty ? 'No subtitle' : package.subtitle}\n',
                    style: const TextStyle(
                      color: SubTenantColors.muted,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text:
                        '${package.priceText.isEmpty ? 'N/A' : package.priceText} • ${package.durationText.isEmpty ? 'N/A' : package.durationText}',
                    style: const TextStyle(
                      color: SubTenantColors.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PackageActionsButton(
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

class _PackageActionsButton extends StatelessWidget {
  const _PackageActionsButton({required this.onSelected});

  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Package actions',
      onSelected: onSelected,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit Package')),
        PopupMenuItem(value: 'itinerary', child: Text('Manage Itinerary')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'publish', child: Text('Publish')),
        PopupMenuItem(value: 'draft', child: Text('Move to Draft')),
        PopupMenuItem(value: 'sold_out', child: Text('Mark Sold Out')),
      ],
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFF),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: SubTenantColors.line),
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          color: SubTenantColors.text,
          size: 20,
        ),
      ),
    );
  }
}

class _PackageFilterSheet extends StatefulWidget {
  const _PackageFilterSheet({
    required this.status,
    required this.visibility,
    required this.total,
    required this.draft,
    required this.pending,
    required this.published,
    required this.returned,
    required this.soldOut,
    required this.visible,
    required this.hidden,
  });

  final String status;
  final String visibility;
  final int total;
  final int draft;
  final int pending;
  final int published;
  final int returned;
  final int soldOut;
  final int visible;
  final int hidden;

  @override
  State<_PackageFilterSheet> createState() => _PackageFilterSheetState();
}

class _PackageFilterSheetState extends State<_PackageFilterSheet> {
  late String _status = widget.status;
  late String _visibility = widget.visibility;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 560),
          margin: const EdgeInsets.all(18),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(26),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 30,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD7E2F0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: SubTenantColors.blue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: SubTenantColors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Package Filters\n',
                            style: TextStyle(
                              color: SubTenantColors.text,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                          TextSpan(
                            text: 'Choose status and visibility filters',
                            style: TextStyle(
                              color: SubTenantColors.muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _status = 'all';
                        _visibility = 'all';
                      });
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _FilterGroup(
                title: 'Package Status',
                children: [
                  _FilterChipButton(
                    label: 'All',
                    count: widget.total,
                    selected: _status == 'all',
                    onTap: () => setState(() => _status = 'all'),
                  ),
                  _FilterChipButton(
                    label: 'Draft',
                    count: widget.draft,
                    selected: _status == 'draft',
                    onTap: () => setState(() => _status = 'draft'),
                  ),
                  _FilterChipButton(
                    label: 'Pending',
                    count: widget.pending,
                    selected: _status == 'pending',
                    onTap: () => setState(() => _status = 'pending'),
                  ),
                  _FilterChipButton(
                    label: 'Published',
                    count: widget.published,
                    selected: _status == 'published',
                    onTap: () => setState(() => _status = 'published'),
                  ),
                  _FilterChipButton(
                    label: 'Returned',
                    count: widget.returned,
                    selected: _status == 'returned',
                    onTap: () => setState(() => _status = 'returned'),
                  ),
                  _FilterChipButton(
                    label: 'Sold Out',
                    count: widget.soldOut,
                    selected: _status == 'sold_out',
                    onTap: () => setState(() => _status = 'sold_out'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FilterGroup(
                title: 'Visibility',
                children: [
                  _FilterChipButton(
                    label: 'All Visibility',
                    count: widget.total,
                    selected: _visibility == 'all',
                    onTap: () => setState(() => _visibility = 'all'),
                  ),
                  _FilterChipButton(
                    label: 'Visible',
                    count: widget.visible,
                    selected: _visibility == 'visible',
                    onTap: () => setState(() => _visibility = 'visible'),
                  ),
                  _FilterChipButton(
                    label: 'Hidden',
                    count: widget.hidden,
                    selected: _visibility == 'hidden',
                    onTap: () => setState(() => _visibility = 'hidden'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(
                          context,
                          _PackageFilterResult(
                            status: _status,
                            visibility: _visibility,
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Apply Filters'),
                      style: FilledButton.styleFrom(
                        backgroundColor: SubTenantColors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
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

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: SubTenantColors.text,
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: children,
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : SubTenantColors.text;
    final background =
        selected ? SubTenantColors.blue : Colors.white.withValues(alpha: 0.95);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? SubTenantColors.blue : SubTenantColors.line,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: foreground,
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: selected
                    ? Colors.white.withValues(alpha: 0.20)
                    : SubTenantColors.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  color: selected ? Colors.white : SubTenantColors.blue,
                  fontWeight: FontWeight.w900,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageFilterResult {
  const _PackageFilterResult({
    required this.status,
    required this.visibility,
  });

  final String status;
  final String visibility;
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.child,
    this.padding = const EdgeInsets.all(14),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SubTenantColors.line.withValues(alpha: 0.9)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PackageListLoad {
  const _PackageListLoad({required this.profile, required this.packages});

  final SubTenantProfile profile;
  final List<SubTenantPackage> packages;
}