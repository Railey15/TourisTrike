import 'package:flutter/material.dart';

import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_package_form_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_package_itinerary_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/subtenant_workspace_search.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Local design colors
// ─────────────────────────────────────────────────────────────────────────────

const _pageBackground = Color(0xFFF4F7FB);

const _softBlue = Color(0xFFF1F6FF);
const _softGreen = Color(0xFFF0FDF4);
const _softAmber = Color(0xFFFFFBEB);
const _softRed = Color(0xFFFEF2F2);
const _softPurple = Color(0xFFF7F3FF);

const _green = Color(0xFF16A34A);
const _amber = Color(0xFFF59E0B);
const _red = Color(0xFFDC2626);
const _purple = Color(0xFF7C3AED);

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class SubTenantPackagesScreen extends StatefulWidget {
  const SubTenantPackagesScreen({
    super.key,
  });

  @override
  State<SubTenantPackagesScreen> createState() =>
      _SubTenantPackagesScreenState();
}

class _SubTenantPackagesScreenState extends State<SubTenantPackagesScreen> {
  final SubTenantService _service = SubTenantService();

  final TextEditingController _searchCtrl = TextEditingController();

  final SubTenantWorkspaceSearchController _workspaceSearch =
      SubTenantWorkspaceSearchController.instance;

  late Future<_PackageListLoad> _future;

  String _status = 'all';

  // ───────────────────────────────────────────────────────────────────────────
  // Lifecycle
  // ───────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();

    _future = _load();

    _searchCtrl.addListener(
      _handleLocalSearchChanged,
    );

    _workspaceSearch.addListener(
      _handleWorkspaceSearchChanged,
    );
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(
      _handleLocalSearchChanged,
    );

    _workspaceSearch.removeListener(
      _handleWorkspaceSearchChanged,
    );

    _searchCtrl.dispose();

    super.dispose();
  }

  void _handleLocalSearchChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _handleWorkspaceSearchChanged() {
    if (!mounted ||
        _workspaceSearch.activeScope != 2) {
      return;
    }

    setState(() {});
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Loading
  // ───────────────────────────────────────────────────────────────────────────

  Future<_PackageListLoad> _load() async {
    final profile =
        await _service.loadCurrentProfile();

    final packages =
        await _service.fetchPackages(
      profile,
    );

    return _PackageListLoad(
      profile: profile,
      packages: packages,
    );
  }

  Future<void> _reload() async {
    late Future<_PackageListLoad> nextFuture;

    setState(() {
      nextFuture = _load();
      _future = nextFuture;
    });

    await nextFuture;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Navigation
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _openForm([
    SubTenantPackage? package,
  ]) async {
    final changed =
        await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) {
          return SubTenantPackageFormScreen(
            package: package,
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }

    if (changed == true) {
      await _reload();
    }
  }

  Future<void> _openItinerary(
    SubTenantPackage package,
  ) async {
    final changed =
        await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) {
          return SubTenantPackageItineraryScreen(
            package: package,
          );
        },
      ),
    );

    if (!mounted) {
      return;
    }

    if (changed == true) {
      await _reload();
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Publication
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _setPublished(
    SubTenantProfile profile,
    SubTenantPackage package,
    bool published,
  ) async {
    try {
      await _service.setPackagePublicationState(
        profile,
        package,
        published,
      );

      if (!mounted) {
        return;
      }

      showSubTenantSnack(
        context,
        published
            ? 'Package published.'
            : 'Package unpublished.',
        error: false,
      );

      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }

      showSubTenantSnack(
        context,
        'Failed to update package: $error',
      );
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Filtering
  // ───────────────────────────────────────────────────────────────────────────

  String _publicationState(
    SubTenantPackage package,
  ) {
    return package.status
                    .trim()
                    .toLowerCase() ==
                'published' &&
            package.visibilityStatus
                    .trim()
                    .toLowerCase() ==
                'visible'
        ? 'published'
        : 'unpublished';
  }

  List<SubTenantPackage> _filtered(
    List<SubTenantPackage> packages,
  ) {
    final query = [
      _searchCtrl.text.trim(),
      _workspaceSearch.queryFor(2),
    ].where(
      (value) => value.isNotEmpty,
    ).join(' ').toLowerCase();

    return packages.where(
      (item) {
        final publication =
            _publicationState(
          item,
        );

        final matchesSearch =
            query.isEmpty ||
            item.title
                .toLowerCase()
                .contains(query) ||
            item.subtitle
                .toLowerCase()
                .contains(query) ||
            item.city
                .toLowerCase()
                .contains(query) ||
            publication.contains(
              query,
            ) ||
            item.priceText
                .toLowerCase()
                .contains(query) ||
            item.durationText
                .toLowerCase()
                .contains(query);

        final matchesStatus =
            _status == 'all' ||
            publication == _status;

        return matchesSearch &&
            matchesStatus;
      },
    ).toList(
      growable: false,
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Filter dialog
  // ───────────────────────────────────────────────────────────────────────────

  Future<void> _openFilters(
    List<SubTenantPackage> allPackages,
  ) async {
    final result =
        await showModalBottomSheet<_PackageFilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor:
          Colors.transparent,
      builder: (_) {
        return _PackageFilterSheet(
          status: _status,
          total:
              allPackages.length,
          published:
              allPackages.where(
            (item) {
              return _publicationState(
                    item,
                  ) ==
                  'published';
            },
          ).length,
          unpublished:
              allPackages.where(
            (item) {
              return _publicationState(
                    item,
                  ) ==
                  'unpublished';
            },
          ).length,
        );
      },
    );

    if (result == null) {
      return;
    }

    setState(() {
      _status = result.status;
    });
  }

  void _clearSearch() {
    _searchCtrl.clear();
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Build
  // ───────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mobile =
        Responsive.isMobile(context);

    return SubTenantAdminShell(
      currentIndex: 2,
      title: 'Packages',
      subtitle:
          'Create, publish, hide, and maintain city tour packages.',
      actions: [
        if (!mobile)
          FilledButton.icon(
            onPressed: () {
              _openForm();
            },
            icon: const Icon(
              Icons.add_box_rounded,
              size: 18,
            ),
            label:
                const Text(
              'Create Package',
            ),
            style:
                FilledButton.styleFrom(
              backgroundColor:
                  SubTenantColors.blue,
              foregroundColor:
                  Colors.white,
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 14,
              ),
              shape:
                  RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(
                  13,
                ),
              ),
            ),
          ),
      ],
      floatingActionButton:
          mobile
              ? FloatingActionButton(
                  heroTag:
                      'subtenant_package_add_fab',
                  backgroundColor:
                      SubTenantColors.blue,
                  foregroundColor:
                      Colors.white,
                  onPressed: () {
                    _openForm();
                  },
                  child:
                      const Icon(
                    Icons.add_rounded,
                  ),
                )
              : null,
      child:
          FutureBuilder<_PackageListLoad>(
        future: _future,
        builder: (
          context,
          snapshot,
        ) {
          if (snapshot.connectionState ==
              ConnectionState.waiting) {
            return const SubTenantLoadingView();
          }

          if (snapshot.hasError) {
            return SubTenantErrorView(
              message:
                  snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final load =
              snapshot.data!;

          final packages =
              _filtered(
            load.packages,
          );

          return ColoredBox(
            color: _pageBackground,
            child:
                RefreshIndicator(
              onRefresh: _reload,
              child:
                  SingleChildScrollView(
                physics:
                    const AlwaysScrollableScrollPhysics(),
                padding:
                    EdgeInsets.fromLTRB(
                  mobile ? 14 : 18,
                  mobile ? 12 : 16,
                  mobile ? 14 : 18,
                  32,
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    _PackageToolbar(
                      controller:
                          _searchCtrl,
                      filterStatus:
                          _status,
                      onOpenFilters: () {
                        _openFilters(
                          load.packages,
                        );
                      },
                      onClearSearch:
                          _clearSearch,
                    ),

                    const SizedBox(
                      height: 20,
                    ),

                    _PackageSectionHeader(
                      city:
                          load.profile.assignedCity,
                      resultCount:
                          packages.length,
                      totalCount:
                          load.packages.length,
                      filterStatus:
                          _status,
                    ),

                    const SizedBox(
                      height: 12,
                    ),

                    if (packages.isEmpty)
                      _PackageEmptyState(
                        city:
                            load.profile.assignedCity,
                        filtered:
                            _status != 'all' ||
                                _searchCtrl.text
                                    .trim()
                                    .isNotEmpty,
                        onCreate:
                            () {
                          _openForm();
                        },
                        onReset:
                            () {
                          setState(() {
                            _status =
                                'all';
                            _searchCtrl
                                .clear();
                          });
                        },
                      )
                    else
                      _PackageGrid(
                        packages:
                            packages,
                        onEdit:
                            _openForm,
                        onItinerary:
                            _openItinerary,
                        onPublishedChanged:
                            (
                          package,
                          published,
                        ) {
                          _setPublished(
                            load.profile,
                            package,
                            published,
                          );
                        },
                      ),
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
// Search / filters
// ─────────────────────────────────────────────────────────────────────────────

class _PackageToolbar extends StatelessWidget {
  const _PackageToolbar({
    required this.controller,
    required this.filterStatus,
    required this.onOpenFilters,
    required this.onClearSearch,
  });

  final TextEditingController controller;

  final String filterStatus;

  final VoidCallback onOpenFilters;
  final VoidCallback onClearSearch;

  String get _filterLabel {
    switch (filterStatus) {
      case 'published':
        return 'Published';

      case 'unpublished':
        return 'Unpublished';

      default:
        return 'Filters';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(16),
        border: Border.all(
          color:
              SubTenantColors.line,
        ),
      ),
      child: LayoutBuilder(
        builder: (
          context,
          constraints,
        ) {
          final horizontal =
              constraints.maxWidth >=
                  720;

          final search =
              SizedBox(
            height: 46,
            child: TextField(
              controller:
                  controller,
              textInputAction:
                  TextInputAction.search,
              decoration:
                  InputDecoration(
                hintText:
                    'Search package title, subtitle, price or duration...',
                hintStyle:
                    const TextStyle(
                  color:
                      SubTenantColors
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
                      SubTenantColors
                          .lightMuted,
                ),
                suffixIcon:
                    controller.text
                            .trim()
                            .isNotEmpty
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
                    const EdgeInsets
                        .symmetric(
                  horizontal: 12,
                ),
                enabledBorder:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius
                          .circular(
                    11,
                  ),
                  borderSide:
                      const BorderSide(
                    color:
                        SubTenantColors
                            .line,
                  ),
                ),
                focusedBorder:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius
                          .circular(
                    11,
                  ),
                  borderSide:
                      const BorderSide(
                    color:
                        SubTenantColors
                            .blue,
                    width: 1.2,
                  ),
                ),
                border:
                    OutlineInputBorder(
                  borderRadius:
                      BorderRadius
                          .circular(
                    11,
                  ),
                ),
              ),
            ),
          );

          final filter =
              SizedBox(
            height: 46,
            child: Material(
              color:
                  Colors.transparent,
              child: InkWell(
                borderRadius:
                    BorderRadius.circular(
                  11,
                ),
                onTap:
                    onOpenFilters,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 14,
                  ),
                  decoration:
                      BoxDecoration(
                    color: filterStatus ==
                            'all'
                        ? const Color(
                            0xFFF8FAFC,
                          )
                        : _softBlue,
                    borderRadius:
                        BorderRadius.circular(
                      11,
                    ),
                    border:
                        Border.all(
                      color: filterStatus ==
                              'all'
                          ? SubTenantColors
                              .line
                          : SubTenantColors
                              .blue
                              .withValues(
                                alpha:
                                    .20,
                              ),
                    ),
                  ),
                  child: Row(
                    mainAxisSize:
                        MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        size: 16,
                        color: filterStatus ==
                                'all'
                            ? SubTenantColors
                                .muted
                            : SubTenantColors
                                .blue,
                      ),

                      const SizedBox(
                        width: 7,
                      ),

                      Text(
                        _filterLabel,
                        style:
                            TextStyle(
                          color: filterStatus ==
                                  'all'
                              ? SubTenantColors
                                  .text
                              : SubTenantColors
                                  .blue,
                          fontSize: 10.5,
                          fontWeight:
                              FontWeight
                                  .w800,
                        ),
                      ),

                      const SizedBox(
                        width: 7,
                      ),

                      const Icon(
                        Icons
                            .keyboard_arrow_down_rounded,
                        size: 17,
                        color:
                            SubTenantColors
                                .muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );

          if (!horizontal) {
            return Column(
              crossAxisAlignment:
                  CrossAxisAlignment
                      .stretch,
              children: [
                search,

                const SizedBox(
                  height: 9,
                ),

                filter,
              ],
            );
          }

          return Row(
            children: [
              Expanded(
                child: search,
              ),

              const SizedBox(
                width: 10,
              ),

              filter,
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _PackageSectionHeader extends StatelessWidget {
  const _PackageSectionHeader({
    required this.city,
    required this.resultCount,
    required this.totalCount,
    required this.filterStatus,
  });

  final String city;

  final int resultCount;
  final int totalCount;

  final String filterStatus;

  @override
  Widget build(BuildContext context) {
    final filterText =
        filterStatus == 'all'
            ? ''
            : filterStatus == 'published'
                ? ' • Published'
                : ' • Unpublished';

    final countText =
        resultCount == totalCount
            ? '$totalCount package${totalCount == 1 ? '' : 's'}'
            : '$resultCount of $totalCount packages';

    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const Text(
                'Tour Package Library',
                style: TextStyle(
                  color:
                      SubTenantColors.text,
                  fontSize: 16,
                  fontWeight:
                      FontWeight.w900,
                ),
              ),

              const SizedBox(
                height: 4,
              ),

              Text(
                '$countText • $city$filterText',
                style:
                    const TextStyle(
                  color:
                      SubTenantColors
                          .muted,
                  fontSize: 10.5,
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
// Package grid
// ─────────────────────────────────────────────────────────────────────────────

class _PackageGrid extends StatelessWidget {
  const _PackageGrid({
    required this.packages,
    required this.onEdit,
    required this.onItinerary,
    required this.onPublishedChanged,
  });

  final List<SubTenantPackage>
      packages;

  final ValueChanged<SubTenantPackage>
      onEdit;

  final ValueChanged<SubTenantPackage>
      onItinerary;

  final void Function(
    SubTenantPackage package,
    bool published,
  ) onPublishedChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (
        context,
        constraints,
      ) {
        final width =
            constraints.maxWidth;

        final columns =
            width >= 1150
                ? 3
                : width >= 720
                    ? 2
                    : 1;

        final cardHeight =
            columns == 1
                ? 282.0
                : 276.0;

        return GridView.builder(
          shrinkWrap: true,
          physics:
              const NeverScrollableScrollPhysics(),
          itemCount:
              packages.length,
          gridDelegate:
              SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:
                columns,
            crossAxisSpacing:
                14,
            mainAxisSpacing:
                14,
            mainAxisExtent:
                cardHeight,
          ),
          itemBuilder:
              (
            context,
            index,
          ) {
            final package =
                packages[index];

            return _PackageGridCard(
              package:
                  package,
              onEdit: () {
                onEdit(
                  package,
                );
              },
              onItinerary: () {
                onItinerary(
                  package,
                );
              },
              onPublish: () {
                onPublishedChanged(
                  package,
                  true,
                );
              },
              onUnpublish: () {
                onPublishedChanged(
                  package,
                  false,
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
// Package card
// ─────────────────────────────────────────────────────────────────────────────

class _PackageGridCard extends StatelessWidget {
  const _PackageGridCard({
    required this.package,
    required this.onEdit,
    required this.onItinerary,
    required this.onPublish,
    required this.onUnpublish,
  });

  final SubTenantPackage package;

  final VoidCallback onEdit;
  final VoidCallback onItinerary;
  final VoidCallback onPublish;
  final VoidCallback onUnpublish;

  bool get _published {
    return package.status
                    .trim()
                    .toLowerCase() ==
                'published' &&
            package.visibilityStatus
                    .trim()
                    .toLowerCase() ==
                'visible';
  }

  bool get _visible {
    return package.visibilityStatus
            .trim()
            .toLowerCase() ==
        'visible';
  }

  String get _imageUrl {
    if (package.coverImageUrl
        .trim()
        .isNotEmpty) {
      return package.coverImageUrl;
    }

    return package.imageUrl;
  }

  @override
  Widget build(BuildContext context) {
    final published =
        _published;

    final price =
        package.priceText
                .trim()
                .isEmpty
            ? 'Not set'
            : package.priceText;

    final duration =
        package.durationText
                .trim()
                .isEmpty
            ? 'Not set'
            : package.durationText;

    final subtitle =
        package.subtitle
                .trim()
                .isEmpty
            ? 'No subtitle provided'
            : package.subtitle;

    return Material(
      color:
          Colors.transparent,
      child: InkWell(
        onTap:
            onEdit,
        borderRadius:
            BorderRadius.circular(
          18,
        ),
        child: Container(
          height:
              double.infinity,
          padding:
              const EdgeInsets.all(
            14,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(
              18,
            ),
            border: Border.all(
              color:
                  SubTenantColors.line,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black
                        .withValues(
                  alpha: .025,
                ),
                blurRadius: 14,
                offset:
                    const Offset(
                  0,
                  6,
                ),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              // ─────────────────────────
              // Header
              // ─────────────────────────

              Row(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  _PackageThumb(
                    imageUrl:
                        _imageUrl,
                    size: 68,
                  ),

                  const SizedBox(
                    width: 12,
                  ),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          package.title,
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style:
                              const TextStyle(
                            color:
                                SubTenantColors
                                    .text,
                            fontSize: 14,
                            fontWeight:
                                FontWeight.w900,
                            height: 1.2,
                          ),
                        ),

                        const SizedBox(
                          height: 4,
                        ),

                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow:
                              TextOverflow.ellipsis,
                          style:
                              const TextStyle(
                            color:
                                SubTenantColors
                                    .muted,
                            fontSize: 10,
                            fontWeight:
                                FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(
                    width: 6,
                  ),

                  _PackageActionsButton(
                    published:
                        published,
                    onSelected:
                        (value) {
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

                        case 'unpublish':
                          onUnpublish();
                          break;
                      }
                    },
                  ),
                ],
              ),

              const SizedBox(
                height: 12,
              ),

              // ─────────────────────────
              // Status
              // ─────────────────────────

              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _PackageStatusBadge(
                    published:
                        published,
                  ),
                  _VisibilityBadge(
                    visible:
                        _visible,
                  ),
                ],
              ),

              const SizedBox(
                height: 12,
              ),

              // ─────────────────────────
              // Information
              // ─────────────────────────

              Container(
                height: 64,
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xFFF8FAFC,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    13,
                  ),
                  border:
                      Border.all(
                    color:
                        SubTenantColors
                            .line,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child:
                          _PackageInfoBlock(
                        icon: Icons
                            .payments_outlined,
                        label:
                            'Price',
                        value:
                            price,
                        accent:
                            SubTenantColors
                                .blue,
                      ),
                    ),

                    Container(
                      width: 1,
                      height: 36,
                      color:
                          SubTenantColors
                              .line,
                    ),

                    Expanded(
                      child:
                          _PackageInfoBlock(
                        icon: Icons
                            .schedule_outlined,
                        label:
                            'Duration',
                        value:
                            duration,
                        accent:
                            _purple,
                      ),
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ─────────────────────────
              // Footer
              // ─────────────────────────

              Row(
                children: [
                  Expanded(
                    child:
                        OutlinedButton.icon(
                      onPressed:
                          onItinerary,
                      icon:
                          const Icon(
                        Icons
                            .route_outlined,
                        size: 15,
                      ),
                      label:
                          const Text(
                        'Itinerary',
                      ),
                      style:
                          OutlinedButton
                              .styleFrom(
                        minimumSize:
                            const Size(
                          0,
                          40,
                        ),
                        foregroundColor:
                            SubTenantColors
                                .blue,
                        side:
                            const BorderSide(
                          color:
                              SubTenantColors
                                  .line,
                        ),
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius
                                  .circular(
                            10,
                          ),
                        ),
                        textStyle:
                            const TextStyle(
                          fontSize:
                              10.5,
                          fontWeight:
                              FontWeight
                                  .w800,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                    width: 8,
                  ),

                  Tooltip(
                    message:
                        'Edit package',
                    child: InkWell(
                      onTap:
                          onEdit,
                      borderRadius:
                          BorderRadius.circular(
                        10,
                      ),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration:
                            BoxDecoration(
                          color:
                              _softBlue,
                          borderRadius:
                              BorderRadius
                                  .circular(
                            10,
                          ),
                          border:
                              Border.all(
                            color:
                                SubTenantColors
                                    .line,
                          ),
                        ),
                        child:
                            const Icon(
                          Icons
                              .edit_outlined,
                          color:
                              SubTenantColors
                                  .blue,
                          size: 16,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(
                    width: 10,
                  ),

                  _PublicationSwitch(
                    value:
                        published,
                    onChanged:
                        (value) {
                      if (value) {
                        onPublish();
                      } else {
                        onUnpublish();
                      }
                    },
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

// ─────────────────────────────────────────────────────────────────────────────
// Thumbnail
// ─────────────────────────────────────────────────────────────────────────────

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
      clipBehavior:
          Clip.antiAlias,
      decoration: BoxDecoration(
        color:
            const Color(
          0xFFEFF4FB,
        ),
        borderRadius:
            BorderRadius.circular(
          14,
        ),
        border: Border.all(
          color:
              SubTenantColors.line,
        ),
      ),
      child: imageUrl
              .trim()
              .isEmpty
          ? const _PackageImageFallback()
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder:
                  (
                _,
                __,
                ___,
              ) {
                return const _PackageImageFallback();
              },
              loadingBuilder:
                  (
                context,
                child,
                progress,
              ) {
                if (progress ==
                    null) {
                  return child;
                }

                return Container(
                  color:
                      _softBlue,
                  alignment:
                      Alignment.center,
                  child:
                      const SizedBox(
                    width: 18,
                    height: 18,
                    child:
                        CircularProgressIndicator(
                      strokeWidth:
                          2,
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _PackageImageFallback extends StatelessWidget {
  const _PackageImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color:
          const Color(
        0xFFF1F5F9,
      ),
      alignment:
          Alignment.center,
      child: Container(
        width: 34,
        height: 34,
        decoration:
            BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(
            9,
          ),
        ),
        child: const Icon(
          Icons
              .inventory_2_outlined,
          color:
              SubTenantColors
                  .lightMuted,
          size: 18,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status badges
// ─────────────────────────────────────────────────────────────────────────────

class _PackageStatusBadge extends StatelessWidget {
  const _PackageStatusBadge({
    required this.published,
  });

  final bool published;

  @override
  Widget build(BuildContext context) {
    return _SmallBadge(
      icon: published
          ? Icons
              .check_circle_rounded
          : Icons
              .radio_button_unchecked_rounded,
      label: published
          ? 'Published'
          : 'Unpublished',
      foreground: published
          ? _green
          : SubTenantColors.muted,
      background: published
          ? _softGreen
          : const Color(
              0xFFF3F6FA,
            ),
    );
  }
}

class _VisibilityBadge extends StatelessWidget {
  const _VisibilityBadge({
    required this.visible,
  });

  final bool visible;

  @override
  Widget build(BuildContext context) {
    return _SmallBadge(
      icon: visible
          ? Icons
              .visibility_outlined
          : Icons
              .visibility_off_outlined,
      label: visible
          ? 'Visible'
          : 'Hidden',
      foreground: visible
          ? _green
          : _red,
      background: visible
          ? _softGreen
          : _softRed,
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  final IconData icon;

  final String label;

  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius:
            BorderRadius.circular(
          999,
        ),
        border: Border.all(
          color:
              foreground.withValues(
            alpha: .12,
          ),
        ),
      ),
      child: Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 11,
            color: foreground,
          ),

          const SizedBox(
            width: 4,
          ),

          Text(
            label,
            style: TextStyle(
              color: foreground,
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
// Package information block
// ─────────────────────────────────────────────────────────────────────────────

class _PackageInfoBlock extends StatelessWidget {
  const _PackageInfoBlock({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;

  final String label;
  final String value;

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 11,
      ),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration:
                BoxDecoration(
              color:
                  accent.withValues(
                alpha: .08,
              ),
              borderRadius:
                  BorderRadius.circular(
                8,
              ),
            ),
            child: Icon(
              icon,
              size: 14,
              color: accent,
            ),
          ),

          const SizedBox(
            width: 8,
          ),

          Expanded(
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style:
                      const TextStyle(
                    color:
                        SubTenantColors
                            .lightMuted,
                    fontSize: 8,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),

                const SizedBox(
                  height: 2,
                ),

                Text(
                  value,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                    color:
                        SubTenantColors
                            .text,
                    fontSize: 10.5,
                    fontWeight:
                        FontWeight.w900,
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
// Publication switch
// ─────────────────────────────────────────────────────────────────────────────

class _PublicationSwitch extends StatelessWidget {
  const _PublicationSwitch({
    required this.value,
    required this.onChanged,
  });

  final bool value;

  final ValueChanged<bool>
      onChanged;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: value
          ? 'Unpublish package'
          : 'Publish package',
      child: Container(
        height: 40,
        padding:
            const EdgeInsets.only(
          left: 9,
          right: 2,
        ),
        decoration: BoxDecoration(
          color: value
              ? _softGreen
              : const Color(
                  0xFFF5F7FA,
                ),
          borderRadius:
              BorderRadius.circular(
            10,
          ),
          border: Border.all(
            color: value
                ? _green.withValues(
                    alpha: .15,
                  )
                : SubTenantColors
                    .line,
          ),
        ),
        child: Row(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Text(
              value
                  ? 'Published'
                  : 'Draft',
              style: TextStyle(
                color: value
                    ? _green
                    : SubTenantColors
                        .muted,
                fontSize: 8.5,
                fontWeight:
                    FontWeight.w800,
              ),
            ),

            Transform.scale(
              scale: .80,
              child: Switch(
                value: value,
                onChanged:
                    onChanged,
                activeThumbColor:
                    Colors.white,
                activeTrackColor:
                    SubTenantColors
                        .blue,
                inactiveThumbColor:
                    Colors.white,
                inactiveTrackColor:
                    const Color(
                  0xFFD5DFEC,
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
// Actions menu
// ─────────────────────────────────────────────────────────────────────────────

class _PackageActionsButton extends StatelessWidget {
  const _PackageActionsButton({
    required this.onSelected,
    required this.published,
  });

  final ValueChanged<String>
      onSelected;

  final bool published;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip:
          'Package actions',
      padding:
          EdgeInsets.zero,
      onSelected:
          onSelected,
      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(
          13,
        ),
      ),
      itemBuilder:
          (context) {
        return [
          const PopupMenuItem(
            value: 'edit',
            child:
                _PackageMenuItem(
              icon:
                  Icons.edit_outlined,
              label:
                  'Edit Package',
            ),
          ),

          const PopupMenuItem(
            value:
                'itinerary',
            child:
                _PackageMenuItem(
              icon:
                  Icons.route_outlined,
              label:
                  'Manage Itinerary',
            ),
          ),

          const PopupMenuDivider(),

          if (published)
            const PopupMenuItem(
              value:
                  'unpublish',
              child:
                  _PackageMenuItem(
                icon: Icons
                    .visibility_off_outlined,
                label:
                    'Unpublish Package',
                color:
                    _amber,
              ),
            )
          else
            const PopupMenuItem(
              value:
                  'publish',
              child:
                  _PackageMenuItem(
                icon: Icons
                    .publish_rounded,
                label:
                    'Publish Package',
                color:
                    _green,
              ),
            ),
        ];
      },
      child: Container(
        width: 36,
        height: 36,
        decoration:
            BoxDecoration(
          color:
              const Color(
            0xFFF8FAFC,
          ),
          borderRadius:
              BorderRadius.circular(
            10,
          ),
          border: Border.all(
            color:
                SubTenantColors.line,
          ),
        ),
        child: const Icon(
          Icons.more_horiz_rounded,
          color:
              SubTenantColors.muted,
          size: 19,
        ),
      ),
    );
  }
}

class _PackageMenuItem extends StatelessWidget {
  const _PackageMenuItem({
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
            SubTenantColors
                .muted;

    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: actualColor,
        ),

        const SizedBox(
          width: 9,
        ),

        Text(
          label,
          style: TextStyle(
            color:
                color ??
                    SubTenantColors
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
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _PackageEmptyState extends StatelessWidget {
  const _PackageEmptyState({
    required this.city,
    required this.filtered,
    required this.onCreate,
    required this.onReset,
  });

  final String city;

  final bool filtered;

  final VoidCallback onCreate;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 44,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(
          17,
        ),
        border: Border.all(
          color:
              SubTenantColors.line,
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration:
                BoxDecoration(
              color: _softBlue,
              borderRadius:
                  BorderRadius.circular(
                16,
              ),
            ),
            child: const Icon(
              Icons
                  .inventory_2_outlined,
              color:
                  SubTenantColors.blue,
              size: 25,
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          Text(
            filtered
                ? 'No matching packages'
                : 'No packages yet',
            style:
                const TextStyle(
              color:
                  SubTenantColors.text,
              fontSize: 15,
              fontWeight:
                  FontWeight.w900,
            ),
          ),

          const SizedBox(
            height: 5,
          ),

          Text(
            filtered
                ? 'No packages match your current search or filter.'
                : 'Tour packages created for $city will appear here.',
            textAlign:
                TextAlign.center,
            style:
                const TextStyle(
              color:
                  SubTenantColors.muted,
              fontSize: 10.5,
              fontWeight:
                  FontWeight.w600,
              height: 1.4,
            ),
          ),

          const SizedBox(
            height: 14,
          ),

          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment:
                WrapAlignment.center,
            children: [
              if (filtered)
                OutlinedButton.icon(
                  onPressed:
                      onReset,
                  icon:
                      const Icon(
                    Icons
                        .filter_alt_off_rounded,
                    size: 15,
                  ),
                  label:
                      const Text(
                    'Clear Filters',
                  ),
                ),

              FilledButton.icon(
                onPressed:
                    onCreate,
                icon:
                    const Icon(
                  Icons.add_rounded,
                  size: 16,
                ),
                label:
                    const Text(
                  'Create Package',
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
// Filter sheet
// ─────────────────────────────────────────────────────────────────────────────

class _PackageFilterSheet extends StatefulWidget {
  const _PackageFilterSheet({
    required this.status,
    required this.total,
    required this.published,
    required this.unpublished,
  });

  final String status;

  final int total;
  final int published;
  final int unpublished;

  @override
  State<_PackageFilterSheet> createState() =>
      _PackageFilterSheetState();
}

class _PackageFilterSheetState extends State<_PackageFilterSheet> {
  late String _status;

  @override
  void initState() {
    super.initState();

    _status =
        widget.status;
  }

  void _reset() {
    setState(() {
      _status = 'all';
    });
  }

  void _apply() {
    Navigator.pop(
      context,
      _PackageFilterResult(
        status: _status,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment:
            Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          constraints:
              const BoxConstraints(
            maxWidth: 560,
          ),
          margin:
              const EdgeInsets.all(
            16,
          ),
          padding:
              const EdgeInsets.fromLTRB(
            18,
            12,
            18,
            18,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(
              22,
            ),
            border: Border.all(
              color:
                  SubTenantColors.line,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black
                        .withValues(
                  alpha: .14,
                ),
                blurRadius: 30,
                offset:
                    const Offset(
                  0,
                  14,
                ),
              ),
            ],
          ),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.stretch,
            children: [
              Align(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xFFD5DFEC,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      999,
                    ),
                  ),
                ),
              ),

              const SizedBox(
                height: 15,
              ),

              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration:
                        BoxDecoration(
                      color:
                          _softBlue,
                      borderRadius:
                          BorderRadius.circular(
                        11,
                      ),
                    ),
                    child:
                        const Icon(
                      Icons.tune_rounded,
                      color:
                          SubTenantColors
                              .blue,
                      size: 19,
                    ),
                  ),

                  const SizedBox(
                    width: 11,
                  ),

                  const Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Package Filters',
                          style:
                              TextStyle(
                            color:
                                SubTenantColors
                                    .text,
                            fontSize:
                                15,
                            fontWeight:
                                FontWeight
                                    .w900,
                          ),
                        ),

                        SizedBox(
                          height: 2,
                        ),

                        Text(
                          'Filter your tour package library by publication state.',
                          style:
                              TextStyle(
                            color:
                                SubTenantColors
                                    .muted,
                            fontSize:
                                10,
                            fontWeight:
                                FontWeight
                                    .w600,
                          ),
                        ),
                      ],
                    ),
                  ),

                  TextButton(
                    onPressed:
                        _reset,
                    child:
                        const Text(
                      'Reset',
                    ),
                  ),
                ],
              ),

              const SizedBox(
                height: 16,
              ),

              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.all(
                  13,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xFFF8FAFC,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    13,
                  ),
                  border:
                      Border.all(
                    color:
                        SubTenantColors
                            .line,
                  ),
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Publication State',
                      style:
                          TextStyle(
                        color:
                            SubTenantColors
                                .text,
                        fontSize: 11,
                        fontWeight:
                            FontWeight.w900,
                      ),
                    ),

                    const SizedBox(
                      height: 10,
                    ),

                    Wrap(
                      spacing: 7,
                      runSpacing: 7,
                      children: [
                        _FilterChipButton(
                          label:
                              'All',
                          count:
                              widget.total,
                          selected:
                              _status ==
                                  'all',
                          onTap:
                              () {
                            setState(() {
                              _status =
                                  'all';
                            });
                          },
                        ),

                        _FilterChipButton(
                          label:
                              'Published',
                          count:
                              widget.published,
                          selected:
                              _status ==
                                  'published',
                          onTap:
                              () {
                            setState(() {
                              _status =
                                  'published';
                            });
                          },
                        ),

                        _FilterChipButton(
                          label:
                              'Unpublished',
                          count:
                              widget.unpublished,
                          selected:
                              _status ==
                                  'unpublished',
                          onTap:
                              () {
                            setState(() {
                              _status =
                                  'unpublished';
                            });
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(
                height: 17,
              ),

              Row(
                children: [
                  Expanded(
                    child:
                        OutlinedButton(
                      onPressed: () {
                        Navigator.pop(
                          context,
                        );
                      },
                      style:
                          OutlinedButton
                              .styleFrom(
                        minimumSize:
                            const Size
                                .fromHeight(
                          43,
                        ),
                      ),
                      child:
                          const Text(
                        'Cancel',
                      ),
                    ),
                  ),

                  const SizedBox(
                    width: 10,
                  ),

                  Expanded(
                    child:
                        FilledButton.icon(
                      onPressed:
                          _apply,
                      icon:
                          const Icon(
                        Icons
                            .check_rounded,
                        size: 16,
                      ),
                      label:
                          const Text(
                        'Apply Filters',
                      ),
                      style:
                          FilledButton
                              .styleFrom(
                        minimumSize:
                            const Size
                                .fromHeight(
                          43,
                        ),
                        backgroundColor:
                            SubTenantColors
                                .blue,
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

// ─────────────────────────────────────────────────────────────────────────────
// Filter chips
// ─────────────────────────────────────────────────────────────────────────────

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
    return Material(
      color:
          Colors.transparent,
      child: InkWell(
        onTap:
            onTap,
        borderRadius:
            BorderRadius.circular(
          999,
        ),
        child:
            AnimatedContainer(
          duration:
              const Duration(
            milliseconds: 140,
          ),
          height: 36,
          padding:
              const EdgeInsets.symmetric(
            horizontal: 11,
          ),
          decoration: BoxDecoration(
            color: selected
                ? SubTenantColors.blue
                : Colors.white,
            borderRadius:
                BorderRadius.circular(
              999,
            ),
            border: Border.all(
              color: selected
                  ? SubTenantColors.blue
                  : SubTenantColors.line,
            ),
          ),
          child: Row(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              Text(
                label,
                style:
                    TextStyle(
                  color: selected
                      ? Colors.white
                      : SubTenantColors
                          .muted,
                  fontSize: 9.5,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),

              const SizedBox(
                width: 6,
              ),

              Container(
                constraints:
                    const BoxConstraints(
                  minWidth: 19,
                ),
                alignment:
                    Alignment.center,
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 1,
                ),
                decoration:
                    BoxDecoration(
                  color: selected
                      ? Colors.white
                          .withValues(
                            alpha:
                                .18,
                          )
                      : _softBlue,
                  borderRadius:
                      BorderRadius.circular(
                    999,
                  ),
                ),
                child: Text(
                  '$count',
                  style:
                      TextStyle(
                    color: selected
                        ? Colors.white
                        : SubTenantColors
                            .blue,
                    fontSize: 8,
                    fontWeight:
                        FontWeight.w900,
                  ),
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
// Filter result
// ─────────────────────────────────────────────────────────────────────────────

class _PackageFilterResult {
  const _PackageFilterResult({
    required this.status,
  });

  final String status;
}

// ─────────────────────────────────────────────────────────────────────────────
// Load wrapper
// ─────────────────────────────────────────────────────────────────────────────

class _PackageListLoad {
  const _PackageListLoad({
    required this.profile,
    required this.packages,
  });

  final SubTenantProfile profile;

  final List<SubTenantPackage> packages;
}