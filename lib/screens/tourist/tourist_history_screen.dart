import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/tourist/package_details_screen.dart';
import 'package:touristrike/widgets/app_bottom_nav_tourist.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final TourisTrikeRepository _repo = TourisTrikeRepository();
  late Future<List<PackageBooking>> _future;
  TimeFilter _time = TimeFilter.all;

  @override
  void initState() {
    super.initState();
    _future = _repo.fetchTouristPackageBookings();
  }

  void _reload() {
    setState(() => _future = _repo.fetchTouristPackageBookings());
  }

  List<PackageBooking> _filtered(List<PackageBooking> bookings) {
    final now = DateTime.now();
    return bookings
        .where((booking) {
          final travel = booking.travelDate;
          final status = booking.status.toLowerCase();
          return switch (_time) {
            TimeFilter.all => true,
            TimeFilter.upcoming =>
              status == 'pending' ||
                  status == 'confirmed' ||
                  (travel != null && travel.isAfter(now)),
            TimeFilter.previous =>
              status == 'completed' ||
                  status == 'cancelled' ||
                  (travel != null && travel.isBefore(now)),
          };
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      bottomNavigationBar: const SafeArea(
        top: false,
        child: SizedBox(height: 86, child: AppBottomNav(selectedIndex: 3)),
      ),
      body: SafeArea(
        child: FutureBuilder<List<PackageBooking>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: Color(0xFF2A86FF)),
              );
            }
            if (snapshot.hasError) {
              return _ErrorState(
                message: snapshot.error.toString(),
                onRetry: _reload,
              );
            }

            final bookings = snapshot.data ?? const [];
            final filtered = _filtered(bookings);
            final totalSpent = bookings
                .where((booking) => booking.status != 'cancelled')
                .fold<double>(0, (sum, booking) => sum + booking.totalAmount);

            return RefreshIndicator(
              onRefresh: () async => _reload(),
              color: const Color(0xFF2A86FF),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                    children: [
                  Row(
                    children: [
                      const SizedBox(width: 44),
                      const Expanded(
                        child: Center(
                          child: Text(
                            'History',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: _reload,
                        icon: const Icon(
                          Icons.refresh_rounded,
                          color: Color(0xFF2A86FF),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _StatCard(
                          title: 'Bookings',
                          value: '${bookings.length}',
                          icon: Icons.card_travel_rounded,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatCard(
                          title: 'Spent',
                          value: NumberFormat.currency(
                            symbol: 'PHP ',
                            decimalDigits: 0,
                          ).format(totalSpent),
                          icon: Icons.payments_outlined,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _FilterRow(
                    value: _time,
                    onChanged: (value) => setState(() => _time = value),
                  ),
                  const SizedBox(height: 14),
                  if (filtered.isEmpty)
                    const _EmptyState()
                  else
                    ...filtered.map(
                      (booking) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _BookingCard(booking: booking),
                      ),
                    ),
                ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

enum TimeFilter { all, upcoming, previous }

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.booking});

  final PackageBooking booking;

  @override
  Widget build(BuildContext context) {
    final package = booking.packageRow;
    final title = dbString(package?['title'], fallback: 'Tour Package');
    final city = dbString(package?['city']);
    final imageUrl = dbString(
      package?['cover_image_url'],
      fallback: dbString(package?['image_url']),
    );
    final date = booking.travelDate == null
        ? 'No date'
        : DateFormat('MMM d, yyyy').format(booking.travelDate!);
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 0);

    return InkWell(
      onTap: package == null
          ? null
          : () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      PackageDetailsScreen(packageId: booking.packageId),
                ),
              );
            },
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE7EEF7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 22,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 74,
                height: 74,
                child: imageUrl.isEmpty
                    ? const _ImageFallback()
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _ImageFallback(),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      _StatusChip(status: booking.status),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    city.isEmpty ? date : '$city - $date',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _MetaPill(
                        icon: Icons.groups_2_outlined,
                        text: '${booking.adults} pax',
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MetaPill(
                          icon: Icons.payments_outlined,
                          text: money.format(booking.totalAmount),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.value, required this.onChanged});

  final TimeFilter value;
  final ValueChanged<TimeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: TimeFilter.values.map((filter) {
        final selected = filter == value;
        final label = switch (filter) {
          TimeFilter.all => 'All',
          TimeFilter.upcoming => 'Upcoming',
          TimeFilter.previous => 'Previous',
        };
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              onTap: () => onChanged(filter),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: selected ? const Color(0xFF2A86FF) : Colors.white,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: const Color(0xFFE7EEF7)),
                ),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  final String title;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF2A86FF)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w900,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final lower = status.toLowerCase();
    final color = lower == 'completed'
        ? const Color(0xFF16A34A)
        : lower == 'cancelled'
        ? const Color(0xFFDC2626)
        : const Color(0xFF2A86FF);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  const _MetaPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF64748B)),
          const SizedBox(width: 5),
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

class _ImageFallback extends StatelessWidget {
  const _ImageFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFEAF2FF),
      child: const Icon(Icons.map_rounded, color: Color(0xFF2A86FF)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: const Text(
        'No package booking history found.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w900),
      ),
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
