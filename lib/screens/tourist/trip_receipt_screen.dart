import 'package:flutter/material.dart';

/// Trip Details (Option A: Trip Receipt)
/// - Clean "receipt" layout
/// - Works for Ride + Tour
/// - Handles Ongoing / Completed / Cancelled
/// - Uses same visual language: blue, rounded cards, soft shadows
///
/// Usage:
/// Navigator.push(
///   context,
///   MaterialPageRoute(
///     builder: (_) => TripReceiptScreen(trip: yourTrip),
///   ),
/// );
class TripReceiptScreen extends StatelessWidget {
  const TripReceiptScreen({
    super.key,
    required this.trip,
  });

  final TripReceipt trip;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const textLight = Color(0xFF94A3B8);
    const line = Color(0xFFE7EEF7);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // =========================
            // TOP BAR
            // =========================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  _TopCircleButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Trip Details',
                      style: TextStyle(
                        fontSize: 20.5,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  _StatusChip(status: trip.status),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: [
                  // =========================
                  // ROUTE CARD
                  // =========================
                  _Card(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _TypeChip(type: trip.type),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _prettyDateTime(trip.scheduledAt),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: textMid,
                                ),
                              ),
                            ),
                            if (trip.status == TripStatus.cancelled &&
                                (trip.cancelReason?.isNotEmpty ?? false))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF1F2),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                      color: const Color(0xFFFCA5A5)),
                                ),
                                child: const Text(
                                  'View reason',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFFDC2626),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Route rows
                        _RouteRow(
                          topLabel: 'PICK-UP',
                          title: trip.pickup,
                          topIcon: Icons.my_location_rounded,
                          topColor: blue,
                        ),
                        const SizedBox(height: 12),
                        _RouteRow(
                          topLabel: 'DROP-OFF',
                          title: trip.dropoff,
                          topIcon: Icons.place_rounded,
                          topColor: const Color(0xFFEF4444),
                          isLast: true,
                        ),

                        const SizedBox(height: 12),
                        const Divider(height: 1, color: line),
                        const SizedBox(height: 12),

                        // small info line
                        Row(
                          children: [
                            const Icon(Icons.info_outline_rounded,
                                size: 18, color: textLight),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                trip.note ??
                                    (trip.type == TripType.ride
                                        ? 'Trip details are encrypted and secure.'
                                        : 'Tour details are encrypted and secure.'),
                                style: const TextStyle(
                                  color: textLight,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),

                        if (trip.status == TripStatus.cancelled &&
                            (trip.cancelReason?.isNotEmpty ?? false)) ...[
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF1F2),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: const Color(0xFFFCA5A5), width: 1.2),
                            ),
                            child: Text(
                              'Cancelled: ${trip.cancelReason}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // =========================
                  // DRIVER / VEHICLE CARD
                  // =========================
                  _Card(
                    child: Row(
                      children: [
                        // Avatar
                        Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF2FF),
                            shape: BoxShape.circle,
                            border: Border.all(color: line),
                          ),
                          child: const Icon(Icons.person_rounded,
                              color: blue, size: 28),
                        ),
                        const SizedBox(width: 12),

                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                trip.driverName,
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.w900,
                                  color: textDark,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Text(
                                    trip.vehicleName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: textMid,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    trip.plateNo,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: textDark,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        // Rating pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: line),
                          ),
                          child: Row(
                            children: [
                              Text(
                                trip.driverRating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: textDark,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Icon(Icons.star_rounded,
                                  size: 18, color: Color(0xFFF59E0B)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // =========================
                  // SUMMARY GRID (2x2)
                  // =========================
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          title: 'FARE',
                          value: trip.fareLabel,
                          icon: Icons.payments_outlined,
                          accent: blue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          title: 'DURATION',
                          value: _minToNice(trip.durationMin),
                          icon: Icons.schedule_rounded,
                          accent: blue,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _StatTile(
                          title: 'DISTANCE',
                          value: '${trip.distanceKm.toStringAsFixed(1)} km',
                          icon: Icons.place_outlined,
                          accent: blue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatTile(
                          title: 'PAYMENT',
                          value: trip.paymentMethod,
                          icon: Icons.credit_card_rounded,
                          accent: blue,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // =========================
                  // TIMELINE
                  // =========================
                  _Card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Timeline',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: textDark,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _Timeline(
                          items: trip.timeline,
                          highlightColor: blue,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // =========================
                  // BOTTOM CTA (page-level, not sticky)
                  // =========================
                  if (trip.status == TripStatus.ongoing) ...[
                    SizedBox(
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // TODO: Navigate back to navigation screen
                          Navigator.pop(context);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 0,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        icon: const Icon(Icons.navigation_rounded),
                        label: const Text('Back to Navigation'),
                      ),
                    ),
                  ] else if (trip.status == TripStatus.completed) ...[
                    SizedBox(
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // TODO: go to rating screen
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          elevation: 0,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        icon: const Icon(Icons.star_rounded),
                        label: const Text('Rate Trip'),
                      ),
                    ),
                  ] else ...[
                    SizedBox(
                      height: 54,
                      child: OutlinedButton.icon(
                        onPressed: () {
                          // TODO: book again flow
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: blue,
                          side: const BorderSide(color: blue, width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Book Again'),
                      ),
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

  static String _prettyDateTime(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    const dows = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dow = dows[d.weekday - 1];
    final mon = months[d.month - 1];
    final h = d.hour;
    final m = d.minute.toString().padLeft(2, '0');
    final ampm = h >= 12 ? 'PM' : 'AM';
    final hour12 = ((h + 11) % 12) + 1;
    return '$dow, $mon ${d.day} • $hour12:$m $ampm';
  }

  static String _minToNice(int minutes) {
    if (minutes <= 0) return '0 min';
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }
}

// ============================================================
// UI Pieces
// ============================================================

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE7EEF7);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF0F172A)),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final TripStatus status;

  @override
  Widget build(BuildContext context) {
    late final Color bg;
    late final Color fg;
    late final String label;

    switch (status) {
      case TripStatus.ongoing:
        bg = const Color(0xFFF0FDF4);
        fg = const Color(0xFF16A34A);
        label = 'ONGOING';
        break;
      case TripStatus.completed:
        bg = const Color(0xFFEAF2FF);
        fg = const Color(0xFF2A86FF);
        label = 'COMPLETED';
        break;
      case TripStatus.cancelled:
        bg = const Color(0xFFFFF1F2);
        fg = const Color(0xFFDC2626);
        label = 'CANCELLED';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
          color: fg,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  const _TypeChip({required this.type});
  final TripType type;

  @override
  Widget build(BuildContext context) {
    final isRide = type == TripType.ride;
    final bg = isRide ? const Color(0xFFEAF2FF) : const Color(0xFFF5F3FF);
    final fg = isRide ? const Color(0xFF2A86FF) : const Color(0xFF7C3AED);
    final label = isRide ? 'RIDE' : 'TOUR';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
          color: fg,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  const _RouteRow({
    required this.topLabel,
    required this.title,
    required this.topIcon,
    required this.topColor,
    this.isLast = false,
  });

  final String topLabel;
  final String title;
  final IconData topIcon;
  final Color topColor;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const line = Color(0xFFE7EEF7);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icon + dotted line
        Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: topColor.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(topIcon, color: topColor),
            ),
            if (!isLast) ...[
              const SizedBox(height: 6),
              Container(
                width: 2,
                height: 34,
                decoration: BoxDecoration(
                  color: line,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 6),
            ],
          ],
        ),
        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                topLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textMid,
                  fontSize: 12,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textDark,
                  fontSize: 17,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.title,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const line = Color(0xFFE7EEF7);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textMid,
                    fontSize: 12,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textDark,
                    fontSize: 16.5,
                    letterSpacing: -0.2,
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

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.items,
    required this.highlightColor,
  });

  final List<TimelineItem> items;
  final Color highlightColor;

  @override
  Widget build(BuildContext context) {
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const line = Color(0xFFE7EEF7);

    return Column(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // dot + line
              Column(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: items[i].done ? highlightColor : const Color(0xFFE2E8F0),
                      shape: BoxShape.circle,
                    ),
                  ),
                  if (i != items.length - 1) ...[
                    const SizedBox(height: 4),
                    Container(
                      width: 2,
                      height: 34,
                      decoration: BoxDecoration(
                        color: line,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(width: 12),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        items[i].title,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: items[i].done ? textDark : textMid,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        items[i].subtitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: textMid,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (i != items.length - 1) const SizedBox(height: 6),
        ],
      ],
    );
  }
}

// ============================================================
// Models (simple demo-ready)
// ============================================================

enum TripType { ride, tour }
enum TripStatus { ongoing, completed, cancelled }

class TripReceipt {
  final TripType type;
  final TripStatus status;

  final DateTime scheduledAt;

  final String pickup;
  final String dropoff;

  final String driverName;
  final String vehicleName;
  final String plateNo;
  final double driverRating;

  final double fare;
  final int durationMin;
  final double distanceKm;
  final String paymentMethod;

  final String? note; // small gray info line
  final String? cancelReason;

  final List<TimelineItem> timeline;

  const TripReceipt({
    required this.type,
    required this.status,
    required this.scheduledAt,
    required this.pickup,
    required this.dropoff,
    required this.driverName,
    required this.vehicleName,
    required this.plateNo,
    required this.driverRating,
    required this.fare,
    required this.durationMin,
    required this.distanceKm,
    required this.paymentMethod,
    required this.timeline,
    this.note,
    this.cancelReason,
  });

  String get fareLabel => '₱ ${fare.toStringAsFixed(0)}';
}

class TimelineItem {
  final String title;
  final String subtitle;
  final bool done;

  const TimelineItem({
    required this.title,
    required this.subtitle,
    required this.done,
  });
}