import 'package:flutter/material.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/tourist/package_details_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_tourist.dart';

class TouristPackagesScreen extends StatefulWidget {
  const TouristPackagesScreen({super.key});

  @override
  State<TouristPackagesScreen> createState() => _TouristPackagesScreenState();
}

class _TouristPackagesScreenState extends State<TouristPackagesScreen> {
  final TourisTrikeRepository _repo = TourisTrikeRepository();
  final _searchCtrl = TextEditingController();
  late Future<List<TourPackage>> _future;

  int _navIndex = 1;
  int _selectedChip = 0;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchTourPackages(limit: 100);
    _searchCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _reload() {
    setState(() => _future = _repo.fetchTourPackages(limit: 100));
  }

  List<String> _chipsFor(List<TourPackage> packages) {
    final cities =
        packages
            .map((item) => item.city)
            .where((city) => city.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return ['All', ...cities];
  }

  List<TourPackage> _filtered(List<TourPackage> packages, List<String> chips) {
    final query = _searchCtrl.text.trim().toLowerCase();
    final selected = chips[_selectedChip < chips.length ? _selectedChip : 0];
    return packages
        .where((package) {
          final cityOk = selected == 'All' || package.city == selected;
          final searchOk =
              query.isEmpty ||
              package.title.toLowerCase().contains(query) ||
              package.description.toLowerCase().contains(query) ||
              package.city.toLowerCase().contains(query);
          return cityOk && searchOk;
        })
        .toList(growable: false);
  }

  void _open(TourPackage package) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PackageDetailsScreen(packageId: package.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    const navBodyH = 92.0;
    final navTotalH = navBodyH + bottomInset;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: FutureBuilder<List<TourPackage>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const _LoadingState();
                  }
                  if (snapshot.hasError) {
                    return _ErrorState(
                      message: snapshot.error.toString(),
                      onRetry: _reload,
                    );
                  }

                  final packages = snapshot.data ?? const [];
                  final chips = _chipsFor(packages);
                  if (_selectedChip >= chips.length) _selectedChip = 0;
                  final filtered = _filtered(packages, chips);

                  return RefreshIndicator(
                    onRefresh: () async => _reload(),
                    color: const Color(0xFF2A86FF),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 680),
                        child: SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(16, 12, 16, navTotalH + 18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(
                            children: [
                              _BackButtonCircle(
                                onTap: () => Navigator.pop(context),
                              ),
                              const Spacer(),
                              const Text(
                                'Tour Packages',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: _reload,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                  color: Color(0xFF2A86FF),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _SearchBar(controller: _searchCtrl),
                          const SizedBox(height: 14),
                          SizedBox(
                            height: 44,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              itemCount: chips.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (_, i) {
                                return _CategoryChip(
                                  label: chips[i],
                                  selected: i == _selectedChip,
                                  onTap: () =>
                                      setState(() => _selectedChip = i),
                                );
                              },
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (filtered.isEmpty)
                            const _EmptyState(
                              message: 'No published tour packages found.',
                            )
                          else
                            ...filtered.map(
                              (package) => Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: _PackageCard(
                                  package: package,
                                  onTap: () => _open(package),
                                ),
                              ),
                            ),
                        ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AppBottomNav(
                selectedIndex: _navIndex,
                onSelect: (i) => setState(() => _navIndex = i),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.package, required this.onTap});

  final TourPackage package;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE8EEF6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 190,
                width: double.infinity,
                child: package.displayImageUrl.isEmpty
                    ? const _ImageFallback()
                    : Image.network(
                        package.displayImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _ImageFallback(),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            package.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.verified_rounded,
                          size: 18,
                          color: Color(0xFF2A86FF),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      package.description.isEmpty
                          ? package.subtitle
                          : package.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14.2,
                        height: 1.45,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _MiniInfoPill(
                          icon: Icons.location_on_outlined,
                          text: package.city,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _MiniInfoPill(
                            icon: Icons.schedule_rounded,
                            text: package.durationText.isEmpty
                                ? 'Flexible'
                                : package.durationText,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Color(0xFFE7EEF7)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            package.priceText.isEmpty
                                ? 'PHP ${package.numericPrice.toStringAsFixed(0)}'
                                : package.priceText,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF2A86FF),
                            ),
                          ),
                        ),
                        const Text(
                          'View details',
                          style: TextStyle(
                            color: Color(0xFF2A86FF),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Color(0xFF2A86FF),
                        ),
                      ],
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

class _SearchBar extends StatelessWidget {
  const _SearchBar({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          const Icon(Icons.search_rounded, color: Color(0xFF94A3B8)),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Search packages or cities...',
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF2A86FF) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? Colors.transparent : const Color(0xFFE2E8F0),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF334155),
            fontWeight: FontWeight.w900,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }
}

class _MiniInfoPill extends StatelessWidget {
  const _MiniInfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackButtonCircle extends StatelessWidget {
  const _BackButtonCircle({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Icon(Icons.arrow_back_rounded, color: Color(0xFF0F172A)),
      ),
    );
  }
}

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF2FF),
      child: const Center(
        child: Icon(Icons.map_rounded, color: Color(0xFF2A86FF), size: 34),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontWeight: FontWeight.w800,
          height: 1.4,
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Color(0xFF2A86FF)),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
