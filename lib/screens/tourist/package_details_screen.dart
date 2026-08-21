import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/tourist/package_booking_screen.dart';

class PackageDetailsScreen extends StatefulWidget {
  const PackageDetailsScreen({
    super.key,
    this.packageId,
  });

  final dynamic packageId;

  @override
  State<PackageDetailsScreen> createState() => _PackageDetailsScreenState();
}

class _PackageDetailsScreenState extends State<PackageDetailsScreen> {
  static const Color _primary = Color(0xFF2A86FF);
  static const Color _ink = Color(0xFF0F172A);
  static const Color _muted = Color(0xFF64748B);
  static const Color _border = Color(0xFFE7EEF7);
  static const Color _surface = Color(0xFFF8FAFF);

  final TourisTrikeRepository _repo = TourisTrikeRepository();

  late Future<_PackageDetailsData> _future;

  bool _isSaved = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_PackageDetailsData> _load() async {
    if (widget.packageId == null) {
      throw StateError('No package was selected.');
    }

    await _repo.trackTourPackageView(widget.packageId);

    final package = await _repo.fetchTourPackage(widget.packageId);

    if (package == null) {
      throw StateError('Package not found.');
    }

    final spots = await _repo.fetchPackageSpots(widget.packageId);

    return _PackageDetailsData(
      package: package,
      originalSpots: spots,
    );
  }

  void _reload() {
    setState(() {
      _future = _load();
    });
  }

  Future<void> _sharePackage(TourPackage package) async {
    final province = dbString(
      package.row['province'],
      fallback: 'Bulacan',
    );

    final text = [
      package.title,
      '${package.city}, $province',
      package.priceText,
    ].join('\n');

    await Clipboard.setData(
      ClipboardData(text: text),
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Package details copied for sharing'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  Future<void> _book(_PackageDetailsData data) async {
    final messenger = ScaffoldMessenger.of(context);

    try {
      final hasActiveTour = await _repo.hasActiveTour();

      if (hasActiveTour) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              TourisTrikeRepository.activeTourErrorMessage,
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Color(0xFFDC2626),
          ),
        );
        return;
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to verify your current tour status right now. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFFDC2626),
        ),
      );
      return;
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PackageBookingScreen(
          packageId: data.package.id,
          initialPackage: data.package,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: FutureBuilder<_PackageDetailsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _LoadingView();
          }

          if (snapshot.hasError) {
            return _ErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final data = snapshot.data!;
          final package = data.package;

          return Stack(
            children: [
              CustomScrollView(
                physics: const BouncingScrollPhysics(),
                slivers: [
                  SliverToBoxAdapter(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _PackageHeroImage(
                          imageUrl: package.displayImageUrl,
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 355,
                          child: _PackageHeaderCard(
                            package: package,
                            spotCount: data.originalSpots.length,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        22,
                        32,
                        22,
                        150,
                      ),
                      child: _PackageDetailsBody(
                        data: data,
                      ),
                    ),
                  ),
                ],
              ),

              SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    18,
                    14,
                    18,
                    0,
                  ),
                  child: Row(
                    children: [
                      _FloatingActionButton(
                        icon: Icons.arrow_back_rounded,
                        onTap: () => Navigator.pop(context),
                      ),

                      const Spacer(),

                      _FloatingActionButton(
                        icon: _isSaved
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        iconColor: _isSaved
                            ? const Color(0xFFEF4444)
                            : _ink,
                        onTap: () {
                          setState(() {
                            _isSaved = !_isSaved;
                          });
                        },
                      ),

                      const SizedBox(width: 10),

                      _FloatingActionButton(
                        icon: Icons.ios_share_rounded,
                        onTap: () => _sharePackage(package),
                      ),
                    ],
                  ),
                ),
              ),

              Align(
                alignment: Alignment.bottomCenter,
                child: _BottomBookBar(
                  package: package,
                  spotCount: data.originalSpots.length,
                  onBook: () => _book(data),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// =============================================================================
// DATA
// =============================================================================

class _PackageDetailsData {
  const _PackageDetailsData({
    required this.package,
    required this.originalSpots,
  });

  final TourPackage package;
  final List<TouristSpot> originalSpots;
}

// =============================================================================
// HERO
// =============================================================================

class _PackageHeroImage extends StatelessWidget {
  const _PackageHeroImage({
    required this.imageUrl,
  });

  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 470,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, _, _) => const _ImageFallback(),
            )
          else
            const _ImageFallback(),

          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.36),
                    Colors.black.withValues(alpha: 0.02),
                    Colors.black.withValues(alpha: 0.05),
                  ],
                  stops: const [
                    0,
                    0.46,
                    1,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// HEADER
// =============================================================================

class _PackageHeaderCard extends StatelessWidget {
  const _PackageHeaderCard({
    required this.package,
    required this.spotCount,
  });

  final TourPackage package;
  final int spotCount;

  @override
  Widget build(BuildContext context) {
    final province = dbString(
      package.row['province'],
      fallback: 'Bulacan',
    );

    final duration = package.durationText.trim().isEmpty
        ? 'Flexible'
        : package.durationText;

    final price = package.numericPrice > 0
        ? NumberFormat.currency(
            symbol: '₱',
            decimalDigits: 0,
          ).format(package.numericPrice)
        : package.priceText.isNotEmpty
            ? package.priceText.replaceAll('PHP ', '₱')
            : 'Ask office';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        26,
        26,
        26,
        24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(32),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  package.title,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF182433),
                    fontSize: 24,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.6,
                  ),
                ),
              ),

              const SizedBox(width: 12),

              _HeaderStatusBadge(
                text: package.status,
              ),
            ],
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                color: Color(0xFF2A86FF),
                size: 19,
              ),

              const SizedBox(width: 8),

              Expanded(
                child: Text(
                  '${package.city}, $province',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF536B87),
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          _PackageStatsRow(
            priceText: price,
            durationText: duration,
            spotCount: spotCount,
          ),
        ],
      ),
    );
  }
}

class _HeaderStatusBadge extends StatelessWidget {
  const _HeaderStatusBadge({
    required this.text,
  });

  final String text;

  @override
  Widget build(BuildContext context) {
    final display = text.trim().isEmpty
        ? 'AVAILABLE'
        : text.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        display,
        style: const TextStyle(
          color: Color(0xFF15803D),
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _PackageStatsRow extends StatelessWidget {
  const _PackageStatsRow({
    required this.priceText,
    required this.durationText,
    required this.spotCount,
  });

  final String priceText;
  final String durationText;
  final int spotCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: _DetailStat(
              icon: Icons.payments_outlined,
              value: priceText,
              label: 'Starting Price',
            ),
          ),

          const _StatDivider(),

          Expanded(
            child: _DetailStat(
              icon: Icons.schedule_outlined,
              value: durationText,
              label: 'Duration',
            ),
          ),

          const _StatDivider(),

          Expanded(
            child: _DetailStat(
              icon: Icons.place_outlined,
              value: '$spotCount',
              label: spotCount == 1 ? 'Included Spot' : 'Included Spots',
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailStat extends StatelessWidget {
  const _DetailStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          icon,
          color: const Color(0xFF2A86FF),
          size: 18,
        ),

        const SizedBox(height: 7),

        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
          ),
        ),

        const SizedBox(height: 3),

        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Color(0xFF8492A6),
            fontWeight: FontWeight.w700,
            fontSize: 9.5,
          ),
        ),
      ],
    );
  }
}

class _StatDivider extends StatelessWidget {
  const _StatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 48,
      color: const Color(0xFFE3E9F1),
    );
  }
}

// =============================================================================
// BODY
// =============================================================================

class _PackageDetailsBody extends StatelessWidget {
  const _PackageDetailsBody({
    required this.data,
  });

  final _PackageDetailsData data;

  @override
  Widget build(BuildContext context) {
    final package = data.package;

    final description = package.description.trim().isNotEmpty
        ? package.description
        : package.subtitle.trim().isNotEmpty
            ? package.subtitle
            : 'No description has been added for this package yet.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _DetailsSectionTitle(
          title: 'About this tour',
          subtitle: 'Know what to expect before booking.',
          icon: Icons.info_outline_rounded,
        ),

        const SizedBox(height: 12),

        _ContentCard(
          child: Text(
            description,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 14,
              height: 1.55,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        const SizedBox(height: 26),

        const _DetailsSectionTitle(
          title: 'Included destinations',
          subtitle:
              'These are the original tourist spots included by the tour operator.',
          icon: Icons.map_outlined,
        ),

        const SizedBox(height: 12),

        if (data.originalSpots.isEmpty)
          const _EmptyBlock(
            icon: Icons.place_outlined,
            title: 'No destinations yet',
            message:
                'The tour operator has not linked tourist destinations to this package yet.',
          )
        else
          _IncludedSpotsCard(
            spots: data.originalSpots,
          ),

        const SizedBox(height: 20),

        const _BookingCustomizationNotice(),

        const SizedBox(height: 26),

        const _DetailsSectionTitle(
          title: 'How booking works',
          subtitle: 'You can personalize the trip after tapping Book Now.',
          icon: Icons.auto_awesome_outlined,
        ),

        const SizedBox(height: 12),

        const _BookingProcessCard(),
      ],
    );
  }
}

class _DetailsSectionTitle extends StatelessWidget {
  const _DetailsSectionTitle({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3FF),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            icon,
            color: const Color(0xFF2A86FF),
            size: 19,
          ),
        ),

        const SizedBox(width: 11),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  letterSpacing: -0.25,
                ),
              ),

              const SizedBox(height: 3),

              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF8492A6),
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ContentCard extends StatelessWidget {
  const _ContentCard({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE7EEF7),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

// =============================================================================
// INCLUDED SPOTS
// =============================================================================

class _IncludedSpotsCard extends StatelessWidget {
  const _IncludedSpotsCard({
    required this.spots,
  });

  final List<TouristSpot> spots;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFE7EEF7),
        ),
      ),
      child: Column(
        children: spots.asMap().entries.map((entry) {
          final index = entry.key;
          final spot = entry.value;

          return Padding(
            padding: EdgeInsets.only(
              bottom: index == spots.length - 1 ? 0 : 8,
            ),
            child: _IncludedSpotTile(
              index: index + 1,
              spot: spot,
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _IncludedSpotTile extends StatelessWidget {
  const _IncludedSpotTile({
    required this.index,
    required this.spot,
  });

  final int index;
  final TouristSpot spot;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      spot.barangay,
      spot.municipality,
      if (spot.address.trim().isNotEmpty) spot.address,
    ].where((value) => value.trim().isNotEmpty).join(' • ');

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: SizedBox(
                  width: 62,
                  height: 62,
                  child: spot.imageUrl.trim().isEmpty
                      ? const _ImageFallback()
                      : Image.network(
                          spot.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const _ImageFallback(),
                        ),
                ),
              ),

              Positioned(
                top: 5,
                left: 5,
                child: Container(
                  width: 23,
                  height: 23,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$index',
                    style: const TextStyle(
                      color: Color(0xFF2A86FF),
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  spot.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                    height: 1.2,
                  ),
                ),

                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 5),

                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF718096),
                      fontWeight: FontWeight.w600,
                      fontSize: 10.5,
                      height: 1.35,
                    ),
                  ),
                ],

                const SizedBox(height: 7),

                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Included in package',
                    style: TextStyle(
                      color: Color(0xFF15803D),
                      fontWeight: FontWeight.w800,
                      fontSize: 9.5,
                    ),
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

// =============================================================================
// CUSTOMIZATION NOTICE
// =============================================================================

class _BookingCustomizationNotice extends StatelessWidget {
  const _BookingCustomizationNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFF0F7FF),
            Color(0xFFF7FBFF),
          ],
        ),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: const Color(0xFFCFE3FF),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFE0EEFF),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Color(0xFF2A86FF),
              size: 19,
            ),
          ),

          const SizedBox(width: 11),

          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Customize during booking',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),

                SizedBox(height: 4),

                Text(
                  'After tapping Book Now, you can choose which destinations to keep, reorder them, and add nearby Google Places suggestions before planning your final schedule.',
                  style: TextStyle(
                    color: Color(0xFF58708E),
                    fontWeight: FontWeight.w600,
                    fontSize: 10.8,
                    height: 1.45,
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

// =============================================================================
// BOOKING PROCESS
// =============================================================================

class _BookingProcessCard extends StatelessWidget {
  const _BookingProcessCard();

  static const _steps = [
    (
      Icons.calendar_month_outlined,
      'Trip Details',
      'Choose your date and participants.',
    ),
    (
      Icons.route_outlined,
      'Pickup & Drop-off',
      'Choose where the driver meets and leaves you.',
    ),
    (
      Icons.place_outlined,
      'Choose Spots',
      'Keep package spots or add nearby places.',
    ),
    (
      Icons.schedule_outlined,
      'Plan Schedule',
      'Organize the final order and timing.',
    ),
    (
      Icons.payments_outlined,
      'Payment',
      'Choose the available payment method.',
    ),
    (
      Icons.task_alt_rounded,
      'Review',
      'Confirm your final booking request.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFE7EEF7),
        ),
      ),
      child: Column(
        children: List.generate(
          _steps.length,
          (index) {
            final step = _steps[index];

            return Padding(
              padding: EdgeInsets.only(
                bottom: index == _steps.length - 1 ? 0 : 14,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF3FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      step.$1,
                      color: const Color(0xFF2A86FF),
                      size: 17,
                    ),
                  ),

                  const SizedBox(width: 10),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${index + 1}. ${step.$2}',
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w800,
                            fontSize: 12.5,
                          ),
                        ),

                        const SizedBox(height: 3),

                        Text(
                          step.$3,
                          style: const TextStyle(
                            color: Color(0xFF7D8A9D),
                            fontWeight: FontWeight.w600,
                            fontSize: 10.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// =============================================================================
// BOTTOM BAR
// =============================================================================

class _BottomBookBar extends StatelessWidget {
  const _BottomBookBar({
    required this.package,
    required this.spotCount,
    required this.onBook,
  });

  final TourPackage package;
  final int spotCount;
  final VoidCallback onBook;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    final price = package.numericPrice > 0
        ? NumberFormat.currency(
            symbol: '₱',
            decimalDigits: 0,
          ).format(package.numericPrice)
        : package.priceText.isNotEmpty
            ? package.priceText
            : 'Ask office';

    final canBook = package.status == 'published';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(
            color: Color(0xFFE8EDF4),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 22,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        bottom + 12,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Starts at',
                  style: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  price,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),

                const SizedBox(height: 2),

                Text(
                  '$spotCount included ${spotCount == 1 ? 'spot' : 'spots'}',
                  style: const TextStyle(
                    color: Color(0xFF718096),
                    fontWeight: FontWeight.w600,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 14),

          SizedBox(
            height: 52,
            width: 165,
            child: ElevatedButton(
              onPressed: canBook ? onBook : null,
              style: ElevatedButton.styleFrom(
                elevation: 0,
                backgroundColor: const Color(0xFF2A86FF),
                disabledBackgroundColor: const Color(0xFFBBD7FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Book Now',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 13.5,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// SMALL UI
// =============================================================================

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFF),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: const Color(0xFFE7EEF7),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF3FF),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              icon,
              color: const Color(0xFF2A86FF),
              size: 19,
            ),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),

                const SizedBox(height: 4),

                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFF718096),
                    fontWeight: FontWeight.w600,
                    fontSize: 10.5,
                    height: 1.4,
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

class _FloatingActionButton extends StatelessWidget {
  const _FloatingActionButton({
    required this.icon,
    required this.onTap,
    this.iconColor = const Color(0xFF0F172A),
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: iconColor,
            size: 23,
          ),
        ),
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
      alignment: Alignment.center,
      child: const Icon(
        Icons.map_rounded,
        color: Color(0xFF2A86FF),
        size: 36,
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(
        color: Color(0xFF2A86FF),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFFE7EEF7),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Color(0xFFDC2626),
                  size: 36,
                ),

                const SizedBox(height: 12),

                const Text(
                  'Unable to load package',
                  style: TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),

                const SizedBox(height: 7),

                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                  ),
                ),

                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Try Again'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}