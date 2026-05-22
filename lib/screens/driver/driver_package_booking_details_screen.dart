import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/driver/driver_package_tracking_screen.dart';

class DriverPackageBookingDetailsScreen extends StatefulWidget {
  const DriverPackageBookingDetailsScreen({
    super.key,
    required this.activityId,
    required this.initialJob,
    required this.initialItineraryCount,
    this.disabledReason,
  });

  final String activityId;
  final PackageActivity initialJob;
  final int initialItineraryCount;
  final String? disabledReason;

  @override
  State<DriverPackageBookingDetailsScreen> createState() =>
      _DriverPackageBookingDetailsScreenState();
}

class _DriverPackageBookingDetailsScreenState
    extends State<DriverPackageBookingDetailsScreen> {
  final _repo = TourisTrikeRepository();

  late PackageActivity _job;
  List<BookingItineraryItem> _spots = [];
  bool _loading = true;
  bool _accepting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _job = widget.initialJob;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final activity = await _repo.fetchPackageActivityById(widget.activityId);
      final bookingId = activity?.bookingId ?? widget.initialJob.bookingId;
      final booking = bookingId.isEmpty
          ? null
          : await _repo.fetchPackageBookingDetails(bookingId);
      var spots = bookingId.isEmpty
          ? const <BookingItineraryItem>[]
          : await _repo.fetchBookingItinerary(bookingId);
      if (bookingId.isNotEmpty && spots.isEmpty) {
        try {
          await _repo.ensureBookingItinerary(bookingId);
          spots = await _repo.fetchBookingItinerary(bookingId);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _job = PackageActivity({
          ...(activity ?? widget.initialJob).row,
          if (booking != null) 'package_bookings': booking.row,
        });
        _spots = spots;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _accept() async {
    if (_accepting || widget.disabledReason != null) return;
    setState(() => _accepting = true);
    try {
      final result = await _repo.acceptPackageBooking(
        bookingId: _job.bookingId,
      );
      if (!mounted) return;
      final accepted = (result['accepted_count'] as num?)?.toInt() ?? 1;
      final required = (result['required_count'] as num?)?.toInt() ?? 1;
      final allFilled = result['all_filled'] as bool? ?? true;
      final remaining = required - accepted;
      final msg = allFilled
          ? 'All drivers confirmed! Head to tracking.'
          : 'Slot accepted! Waiting for $remaining more driver${remaining == 1 ? '' : 's'}.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              DriverPackageTrackingScreen(activityId: _job.id.toString()),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_humanizeError(e.toString()))));
    } finally {
      if (mounted) setState(() => _accepting = false);
    }
  }

  String _humanizeError(String raw) {
    if (raw.contains('MUNICIPALITY_MISMATCH')) {
      final match = RegExp(r'Booking is for (.+?) only').firstMatch(raw);
      final area = match?.group(1) ?? 'your area';
      return 'This booking is only available to drivers in $area.';
    }
    if (raw.contains('PROVINCE_MISMATCH')) {
      return 'This booking is outside your assigned municipality.';
    }
    if (raw.contains('BOOKING_ALREADY_FULL')) {
      return 'This booking already has enough drivers.';
    }
    if (raw.contains('ALREADY_ACCEPTED')) {
      return 'You already accepted this booking.';
    }
    if (raw.contains('DRIVER_NOT_AVAILABLE')) {
      return 'You must be online/available to accept bookings.';
    }
    if (raw.contains('DRIVER_NOT_VERIFIED')) {
      return 'Only verified drivers can accept bookings.';
    }
    if (raw.contains('ACTIVE_TOUR_EXISTS')) {
      return 'Complete your current tour before accepting another.';
    }
    if (raw.contains('BOOKING_NOT_AVAILABLE')) {
      return 'This booking is no longer accepting drivers.';
    }
    return 'Failed to accept booking. Please try again.';
  }

  String _touristName(Json? tourist) {
    if (tourist == null) return 'Tourist';
    final full = dbString(tourist['full_name']);
    if (full.isNotEmpty) return full;
    final name = [
      dbString(tourist['first_name']),
      dbString(tourist['last_name']),
    ].where((part) => part.isNotEmpty).join(' ');
    return name.isNotEmpty ? name : 'Tourist';
  }

  @override
  Widget build(BuildContext context) {
    final bookingRow = _job.bookingRow;
    final booking = bookingRow != null ? PackageBooking(bookingRow) : null;
    final package = _job.packageRow;
    final tourist = _job.touristRow ?? booking?.touristRow;
    final packageTitle = dbString(package?['title'], fallback: 'Package Tour');
    final municipality = dbString(booking?.row['municipality']);
    final province = dbString(booking?.row['province'], fallback: 'Bulacan');
    final area = municipality.isNotEmpty
        ? '$municipality, $province'
        : province;
    final travelDate = booking?.travelDate;
    final rawTravelDate = dbString(booking?.row['travel_date']);
    final travelDateText = travelDate != null
        ? DateFormat('MMMM d, yyyy').format(travelDate)
        : rawTravelDate.isNotEmpty
        ? rawTravelDate
        : 'Date pending';
    final adults = booking?.adults ?? 1;
    final children = booking?.children ?? 0;
    final passengerText = dbString(booking?.row['total_passengers']);
    final totalAmount = booking?.totalAmount ?? _job.price;
    final pickupAddress = dbString(booking?.row['pickup_address']);
    final dropoffAddress = dbString(booking?.row['dropoff_address']);
    final touristPhone = dbString(tourist?['mobile']);
    final touristImage = dbString(tourist?['profile_image_url']);
    final notes = booking?.notes ?? '';
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 2);
    final itineraryCount = _spots.isNotEmpty
        ? _spots.length
        : widget.initialItineraryCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F8FF),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF4F8FF),
        elevation: 0,
        scrolledUnderElevation: 0,
        title: const Text(
          'Booking Details',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _ErrorState(message: _error!, onRetry: _load)
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _HeroCard(
                  packageTitle: packageTitle,
                  area: area,
                  tourDate: travelDateText,
                  participants: passengerText.isNotEmpty
                      ? passengerText
                      : '$adults adult${adults == 1 ? '' : 's'}${children > 0 ? ' • $children child${children == 1 ? '' : 'ren'}' : ''}',
                  totalAmount: money.format(totalAmount),
                  itineraryCount: itineraryCount,
                ),
                const SizedBox(height: 12),
                _DetailCard(
                  title: 'Tourist Info',
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: const Color(0xFFEAF2FF),
                        backgroundImage: touristImage.isNotEmpty
                            ? NetworkImage(touristImage)
                            : null,
                        child: touristImage.isEmpty
                            ? const Icon(
                                Icons.person_rounded,
                                color: Color(0xFF2F6FFF),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _touristName(tourist),
                              style: const TextStyle(
                                color: Color(0xFF0F172A),
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            if (touristPhone.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                touristPhone,
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _DetailCard(
                  title: 'Booking Info',
                  child: Column(
                    children: [
                      _InfoLine(
                        icon: Icons.location_city_rounded,
                        label: 'Area',
                        value: area,
                      ),
                      _InfoLine(
                        icon: Icons.trip_origin_rounded,
                        label: 'Pickup',
                        value: pickupAddress.isEmpty
                            ? 'Pickup pending'
                            : pickupAddress,
                      ),
                      _InfoLine(
                        icon: Icons.flag_rounded,
                        label: 'Drop-off',
                        value: dropoffAddress.isEmpty
                            ? 'Drop-off pending'
                            : dropoffAddress,
                      ),
                      _InfoLine(
                        icon: Icons.payments_rounded,
                        label: 'Total Amount',
                        value: money.format(totalAmount),
                      ),
                      _InfoLine(
                        icon: Icons.map_rounded,
                        label: 'Itinerary',
                        value:
                            '$itineraryCount spot${itineraryCount == 1 ? '' : 's'}',
                      ),
                    ],
                  ),
                ),
                if (notes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _DetailCard(
                    title: 'Tourist Note',
                    child: Text(
                      notes,
                      style: const TextStyle(
                        color: Color(0xFF334155),
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _DetailCard(
                  title: 'Selected Spots',
                  child: itineraryCount == 0
                      ? const Text(
                          'No itinerary items found yet.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        )
                      : Column(
                          children: _spots.isEmpty
                              ? List.generate(
                                  itineraryCount,
                                  (index) => _ItineraryRowPlaceholder(
                                    index: index + 1,
                                  ),
                                )
                              : _spots
                                    .asMap()
                                    .entries
                                    .map(
                                      (entry) => _ItineraryRow(
                                        index: entry.key + 1,
                                        item: entry.value,
                                        isLast: entry.key == _spots.length - 1,
                                      ),
                                    )
                                    .toList(growable: false),
                        ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: _accepting || widget.disabledReason != null
                      ? null
                      : _accept,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2F6FFF),
                    disabledBackgroundColor: const Color(0xFF94A3B8),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: _accepting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.check_circle_outline_rounded),
                  label: Text(
                    _accepting ? 'Accepting...' : 'Accept This Booking',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15.5,
                    ),
                  ),
                ),
                if (widget.disabledReason != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    widget.disabledReason!,
                    style: const TextStyle(
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.w800,
                      height: 1.4,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.packageTitle,
    required this.area,
    required this.tourDate,
    required this.participants,
    required this.totalAmount,
    required this.itineraryCount,
  });

  final String packageTitle;
  final String area;
  final String tourDate;
  final String participants;
  final String totalAmount;
  final int itineraryCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2F6FFF), Color(0xFF42B8FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            packageTitle,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroPill(icon: Icons.location_city_rounded, text: area),
              _HeroPill(icon: Icons.calendar_today_rounded, text: tourDate),
              _HeroPill(icon: Icons.groups_rounded, text: participants),
              _HeroPill(
                icon: Icons.map_rounded,
                text: '$itineraryCount stop${itineraryCount == 1 ? '' : 's'}',
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            totalAmount,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 24,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 17, color: const Color(0xFF2F6FFF)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w800,
                    height: 1.35,
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

class _ItineraryRow extends StatelessWidget {
  const _ItineraryRow({
    required this.index,
    required this.item,
    required this.isLast,
  });

  final int index;
  final BookingItineraryItem item;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final timeLabel = [
      item.formattedArrivalTime,
      item.formattedDepartureTime,
    ].where((part) => part.isNotEmpty).join(' - ');
    final stopOrder = item.orderNumber > 0
        ? item.orderNumber
        : item.destinationOrder;
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: item.spotStatus == 'completed'
                  ? const Color(0xFFECFDF5)
                  : const Color(0xFFEAF2FF),
              shape: BoxShape.circle,
              border: Border.all(
                color: item.spotStatus == 'completed'
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF2F6FFF),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: TextStyle(
                color: item.spotStatus == 'completed'
                    ? const Color(0xFF16A34A)
                    : const Color(0xFF2F6FFF),
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.destinationName,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _MetaChip(
                      label: 'Stop ${stopOrder > 0 ? stopOrder : index}',
                      color: const Color(0xFF2F6FFF),
                    ),
                    _MetaChip(
                      label: item.sourceType.replaceAll('_', ' '),
                      color: const Color(0xFF16A34A),
                    ),
                  ],
                ),
                if (item.destinationAddress.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    item.destinationAddress,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                ],
                if (timeLabel.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    timeLabel,
                    style: const TextStyle(
                      color: Color(0xFF2F6FFF),
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 10.5,
        ),
      ),
    );
  }
}

class _ItineraryRowPlaceholder extends StatelessWidget {
  const _ItineraryRowPlaceholder({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 15,
            backgroundColor: const Color(0xFFEAF2FF),
            child: Text(
              '$index',
              style: const TextStyle(
                color: Color(0xFF2F6FFF),
                fontWeight: FontWeight.w900,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Loading itinerary item...',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
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
            const Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: Color(0xFFEF4444),
            ),
            const SizedBox(height: 12),
            const Text(
              'Failed to load booking details',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
