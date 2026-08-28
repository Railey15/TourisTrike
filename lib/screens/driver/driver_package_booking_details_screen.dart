import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/driver/driver_package_tracking_screen.dart';

// ============================================================================
// UI CONSTANTS
// ============================================================================

const Color _primary = Color(0xFF2563EB);
const Color _primaryLight = Color(0xFF3BA9F5);

const Color _background = Color(0xFFF5F7FB);
const Color _surface = Colors.white;

const Color _ink = Color(0xFF0F172A);
const Color _muted = Color(0xFF64748B);
const Color _subtle = Color(0xFF94A3B8);

const Color _border = Color(0xFFE5EBF3);
const Color _softBlue = Color(0xFFEAF3FF);

const Color _success = Color(0xFF16A34A);
const Color _successSoft = Color(0xFFECFDF5);

const Color _warning = Color(0xFFD97706);
const Color _warningSoft = Color(0xFFFFFBEB);

const Color _danger = Color(0xFFDC2626);
const Color _dangerSoft = Color(0xFFFEF2F2);

// ============================================================================
// SCREEN
// ============================================================================

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
  final TourisTrikeRepository _repo = TourisTrikeRepository();

  late PackageActivity _job;

  List<BookingItineraryItem> _spots = [];

  bool _loading = true;
  bool _accepting = false;

  String? _error;

  // =========================================================================
  // LIFECYCLE
  // =========================================================================

  @override
  void initState() {
    super.initState();

    _job = widget.initialJob;

    _load();
  }

  // =========================================================================
  // DATA
  // =========================================================================

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final activity = await _repo.fetchPackageActivityById(
        widget.activityId,
      );

      final bookingId = activity?.bookingId ?? widget.initialJob.bookingId;

      final booking = bookingId.isEmpty
          ? null
          : await _repo.fetchPackageBookingDetails(
              bookingId,
            );

      var spots = bookingId.isEmpty
          ? const <BookingItineraryItem>[]
          : await _repo.fetchBookingItinerary(
              bookingId,
            );

      if (bookingId.isNotEmpty && spots.isEmpty) {
        try {
          await _repo.ensureBookingItinerary(
            bookingId,
          );

          spots = await _repo.fetchBookingItinerary(
            bookingId,
          );
        } catch (_) {
          // Non-fatal. The placeholder itinerary UI will still work.
        }
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _job = PackageActivity({
          ...(activity ?? widget.initialJob).row,
          if (booking != null) 'package_bookings': booking.row,
        });

        _spots = spots;

        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // =========================================================================
  // ACCEPT BOOKING
  // =========================================================================

  Future<void> _accept() async {
    if (_accepting || widget.disabledReason != null) {
      return;
    }

    setState(() {
      _accepting = true;
    });

    try {
      final result = await _repo.acceptPackageBooking(
        bookingId: _job.bookingId,
      );

      if (!mounted) {
        return;
      }

      final accepted = (result['accepted_count'] as num?)?.toInt() ?? 1;

      final required = (result['required_count'] as num?)?.toInt() ?? 1;

      final allFilled = result['all_filled'] as bool? ?? true;

      final remaining = required - accepted;

      final message = allFilled
          ? 'All drivers confirmed! Head to tracking.'
          : 'Slot accepted! Waiting for $remaining more driver${remaining == 1 ? '' : 's'}.';

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              message,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
            behavior: SnackBarBehavior.floating,
            backgroundColor: const Color(0xFF1E293B),
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => DriverPackageTrackingScreen(
            activityId: _job.id.toString(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              _humanizeError(e.toString()),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
              ),
            ),
            backgroundColor: _danger,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _accepting = false;
        });
      }
    }
  }

  // =========================================================================
  // ERROR MESSAGES
  // =========================================================================

  String _humanizeError(String raw) {
    if (raw.contains('MUNICIPALITY_MISMATCH')) {
      final match = RegExp(
        r'Booking is for (.+?) only',
      ).firstMatch(raw);

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

    if (raw.contains('DRIVER_SCHEDULE_CONFLICT')) {
      return 'This tour overlaps another booking in your schedule.';
    }

    if (raw.contains('DRIVER_NOT_AVAILABLE')) {
      return 'You must be online/available to accept bookings.';
    }

    if (raw.contains('DRIVER_NOT_VERIFIED') ||
        raw.contains('DRIVER_NOT_APPROVED')) {
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

  // =========================================================================
  // TOURIST
  // =========================================================================

  String _touristName(Json? tourist) {
    if (tourist == null) {
      return 'Tourist';
    }

    final full = dbString(
      tourist['full_name'],
    );

    if (full.isNotEmpty) {
      return full;
    }

    final name = [
      dbString(tourist['first_name']),
      dbString(tourist['last_name']),
    ].where((part) => part.isNotEmpty).join(' ');

    return name.isNotEmpty ? name : 'Tourist';
  }

  // =========================================================================
  // BUILD
  // =========================================================================

  @override
  Widget build(BuildContext context) {
    final bookingRow = _job.bookingRow;

    final booking = bookingRow != null ? PackageBooking(bookingRow) : null;

    final package = _job.packageRow;

    final tourist = _job.touristRow ?? booking?.touristRow;

    final packageTitle = dbString(
      package?['title'],
      fallback: 'Package Tour',
    );

    final municipality = dbString(
      booking?.row['municipality'],
    );

    final province = dbString(
      booking?.row['province'],
      fallback: 'Bulacan',
    );

    final area = municipality.isNotEmpty ? '$municipality, $province' : province;

    final travelDate = booking?.travelDate;

    final rawTravelDate = dbString(
      booking?.row['travel_date'],
    );

    final travelDateText = travelDate != null
        ? DateFormat('MMMM d, yyyy').format(travelDate)
        : rawTravelDate.isNotEmpty
            ? rawTravelDate
            : 'Date pending';

    final adults = booking?.adults ?? 1;

    final children = booking?.children ?? 0;

    final passengerText = dbString(
      booking?.row['total_passengers'],
    );

    final passengers = passengerText.isNotEmpty
        ? passengerText
        : '$adults adult${adults == 1 ? '' : 's'}'
            '${children > 0 ? ' • $children child${children == 1 ? '' : 'ren'}' : ''}';

    final totalAmount = booking?.totalAmount ?? _job.price;

    final pickupAddress = dbString(
      booking?.row['pickup_address'],
    );

    final dropoffAddress = dbString(
      booking?.row['dropoff_address'],
    );

    final touristPhone = dbString(
      tourist?['mobile'],
    );

    final touristImage = dbString(
      tourist?['profile_image_url'],
    );

    final notes = booking?.notes ?? '';

    final money = NumberFormat.currency(
      symbol: '₱',
      decimalDigits: 2,
    );

    final itineraryCount =
        _spots.isNotEmpty ? _spots.length : widget.initialItineraryCount;

    final requiredDrivers = booking?.requiredDrivers ?? 1;

    return Scaffold(
      backgroundColor: _background,
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const _LoadingState()
            : _error != null
                ? Column(
                    children: [
                      _BookingDetailsTopBar(
                        onBack: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: _ErrorState(
                          message: _error!,
                          onRetry: _load,
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      // =====================================================
                      // CONSISTENT TOP BAR
                      // =====================================================

                      _BookingDetailsTopBar(
                        onBack: () => Navigator.of(context).pop(),
                      ),

                      // =====================================================
                      // CONTENT
                      // =====================================================

                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _load,
                          color: _primary,
                          child: ListView(
                            physics: const AlwaysScrollableScrollPhysics(
                              parent: BouncingScrollPhysics(),
                            ),
                            padding: const EdgeInsets.fromLTRB(
                              16,
                              8,
                              16,
                              22,
                            ),
                            children: [
                              // =============================================
                              // HERO
                              // =============================================

                              _BookingHeroCard(
                                packageTitle: packageTitle,
                                area: area,
                                tourDate: travelDateText,
                                participants: passengers,
                                totalAmount: money.format(totalAmount),
                                itineraryCount: itineraryCount,
                                requiredDrivers: requiredDrivers,
                              ),

                              const SizedBox(height: 14),

                              // =============================================
                              // TOURIST
                              // =============================================

                              _TouristSummaryCard(
                                name: _touristName(tourist),
                                phone: touristPhone,
                                imageUrl: touristImage,
                              ),

                              const SizedBox(height: 14),

                              // =============================================
                              // ROUTE
                              // =============================================

                              _RouteDetailsCard(
                                pickupAddress: pickupAddress,
                                dropoffAddress: dropoffAddress,
                                area: area,
                              ),

                              const SizedBox(height: 14),

                              // =============================================
                              // BOOKING SUMMARY
                              // =============================================

                              _BookingSummaryCard(
                                travelDate: travelDateText,
                                participants: passengers,
                                totalAmount: money.format(totalAmount),
                                itineraryCount: itineraryCount,
                                requiredDrivers: requiredDrivers,
                              ),

                              // =============================================
                              // NOTE
                              // =============================================

                              if (notes.trim().isNotEmpty) ...[
                                const SizedBox(height: 14),
                                _TouristNoteCard(
                                  notes: notes,
                                ),
                              ],

                              const SizedBox(height: 14),

                              // =============================================
                              // ITINERARY
                              // =============================================

                              _ItineraryCard(
                                spots: _spots,
                                itineraryCount: itineraryCount,
                              ),

                              // Space above sticky button
                              const SizedBox(height: 8),
                            ],
                          ),
                        ),
                      ),

                      // =====================================================
                      // PERSISTENT ACCEPT BUTTON
                      // =====================================================

                      _AcceptBookingBar(
                        accepting: _accepting,
                        disabledReason: widget.disabledReason,
                        onAccept: _accept,
                      ),
                    ],
                  ),
      ),
    );
  }
}

// ============================================================================
// TOP BAR
// ============================================================================

class _BookingDetailsTopBar extends StatelessWidget {
  const _BookingDetailsTopBar({
    required this.onBack,
  });

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
      ),
      color: _background,
      child: Row(
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(13),
            child: InkWell(
              onTap: onBack,
              borderRadius: BorderRadius.circular(13),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _border,
                  ),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: _ink,
                  size: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 11),
          const Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Booking Details',
                  style: TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 17.5,
                    letterSpacing: -0.2,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Review tour before accepting',
                  style: TextStyle(
                    color: _subtle,
                    fontWeight: FontWeight.w600,
                    fontSize: 9.5,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: _softBlue,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'DRIVER',
              style: TextStyle(
                color: _primary,
                fontWeight: FontWeight.w900,
                fontSize: 8.5,
                letterSpacing: 0.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// HERO CARD
// ============================================================================

class _BookingHeroCard extends StatelessWidget {
  const _BookingHeroCard({
    required this.packageTitle,
    required this.area,
    required this.tourDate,
    required this.participants,
    required this.totalAmount,
    required this.itineraryCount,
    required this.requiredDrivers,
  });

  final String packageTitle;
  final String area;
  final String tourDate;
  final String participants;
  final String totalAmount;

  final int itineraryCount;
  final int requiredDrivers;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _primary,
            _primaryLight,
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _primary.withValues(alpha: 0.19),
            blurRadius: 21,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.map_outlined,
                  color: Colors.white,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      packageTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        height: 1.15,
                        letterSpacing: -0.25,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          color: Colors.white70,
                          size: 13,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            area,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.80),
                              fontWeight: FontWeight.w700,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 17),

          // Price
          Text(
            'BOOKING VALUE',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.68),
              fontWeight: FontWeight.w900,
              fontSize: 8,
              letterSpacing: 0.55,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            totalAmount,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 25,
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 15),

          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _HeroStat(
                    icon: Icons.calendar_today_outlined,
                    label: 'DATE',
                    value: tourDate,
                  ),
                ),
                Container(
                  width: 1,
                  height: 32,
                  color: Colors.white.withValues(alpha: 0.16),
                ),
                Expanded(
                  child: _HeroStat(
                    icon: Icons.groups_outlined,
                    label: 'GROUP',
                    value: participants,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Row(
            children: [
              _HeroMiniPill(
                icon: Icons.route_outlined,
                text:
                    '$itineraryCount stop${itineraryCount == 1 ? '' : 's'}',
              ),
              const SizedBox(width: 7),
              _HeroMiniPill(
                icon: Icons.electric_rickshaw_outlined,
                text:
                    '$requiredDrivers tricycle${requiredDrivers == 1 ? '' : 's'}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
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
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: Colors.white70,
                size: 12,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w900,
                  fontSize: 7.5,
                  letterSpacing: 0.45,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroMiniPill extends StatelessWidget {
  const _HeroMiniPill({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: Colors.white,
            size: 12,
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// TOURIST
// ============================================================================

class _TouristSummaryCard extends StatelessWidget {
  const _TouristSummaryCard({
    required this.name,
    required this.phone,
    required this.imageUrl,
  });

  final String name;
  final String phone;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _softBlue,
              border: Border.all(
                color: const Color(0xFFD3E4FF),
              ),
            ),
            child: ClipOval(
              child: imageUrl.isNotEmpty
                  ? Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const _AvatarFallback(),
                    )
                  : const _AvatarFallback(),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOURIST',
                  style: TextStyle(
                    color: _subtle,
                    fontWeight: FontWeight.w900,
                    fontSize: 8,
                    letterSpacing: 0.55,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Icon(
                      Icons.phone_outlined,
                      color: _muted,
                      size: 13,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        phone.isNotEmpty ? phone : 'Phone number unavailable',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _muted,
                          fontWeight: FontWeight.w600,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 9,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: _successSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'BOOKED',
              style: TextStyle(
                color: _success,
                fontWeight: FontWeight.w900,
                fontSize: 8,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AvatarFallback extends StatelessWidget {
  const _AvatarFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _softBlue,
      alignment: Alignment.center,
      child: const Icon(
        Icons.person_rounded,
        color: _primary,
        size: 26,
      ),
    );
  }
}

// ============================================================================
// ROUTE DETAILS
// ============================================================================

class _RouteDetailsCard extends StatelessWidget {
  const _RouteDetailsCard({
    required this.pickupAddress,
    required this.dropoffAddress,
    required this.area,
  });

  final String pickupAddress;
  final String dropoffAddress;
  final String area;

  @override
  Widget build(BuildContext context) {
    final pickup = pickupAddress.trim().isEmpty
        ? 'Pickup location pending'
        : pickupAddress;

    final dropoff = dropoffAddress.trim().isEmpty
        ? 'Drop-off location pending'
        : dropoffAddress;

    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.route_rounded,
            title: 'Trip Route',
            subtitle: 'Pickup and final drop-off',
          ),
          const SizedBox(height: 14),

          _RoutePoint(
            icon: Icons.trip_origin_rounded,
            color: _success,
            label: 'PICKUP',
            value: pickup,
            hasLine: true,
          ),

          _RoutePoint(
            icon: Icons.location_on_rounded,
            color: _danger,
            label: 'DROP-OFF',
            value: dropoff,
            hasLine: false,
          ),

          const SizedBox(height: 10),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: 11,
              vertical: 9,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_city_outlined,
                  color: _primary,
                  size: 15,
                ),
                const SizedBox(width: 7),
                const Text(
                  'Service Area',
                  style: TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 9.5,
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    area,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _ink,
                      fontWeight: FontWeight.w900,
                      fontSize: 10,
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

class _RoutePoint extends StatelessWidget {
  const _RoutePoint({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    required this.hasLine,
  });

  final IconData icon;
  final Color color;

  final String label;
  final String value;

  final bool hasLine;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Column(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  color: color,
                  size: 15,
                ),
              ),
              if (hasLine)
                Container(
                  width: 2,
                  height: 39,
                  color: const Color(0xFFDCE5F0),
                ),
            ],
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              bottom: hasLine ? 13 : 0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _subtle,
                    fontWeight: FontWeight.w900,
                    fontSize: 8,
                    letterSpacing: 0.55,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// BOOKING SUMMARY
// ============================================================================

class _BookingSummaryCard extends StatelessWidget {
  const _BookingSummaryCard({
    required this.travelDate,
    required this.participants,
    required this.totalAmount,
    required this.itineraryCount,
    required this.requiredDrivers,
  });

  final String travelDate;
  final String participants;
  final String totalAmount;

  final int itineraryCount;
  final int requiredDrivers;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Icons.receipt_long_outlined,
            title: 'Booking Summary',
            subtitle: 'Important information before accepting',
          ),

          const SizedBox(height: 14),

          Row(
            children: [
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.groups_outlined,
                  value: participants,
                  label: 'PASSENGERS',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.route_outlined,
                  value: '$itineraryCount',
                  label: 'STOPS',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _SummaryMetric(
                  icon: Icons.electric_rickshaw_outlined,
                  value: '$requiredDrivers',
                  label: 'TRICYCLES',
                ),
              ),
            ],
          ),

          const SizedBox(height: 13),

          const Divider(
            height: 1,
            color: Color(0xFFEDF1F6),
          ),

          const SizedBox(height: 12),

          _BookingInfoLine(
            icon: Icons.calendar_today_outlined,
            label: 'Travel Date',
            value: travelDate,
          ),

          const SizedBox(height: 9),

          _BookingInfoLine(
            icon: Icons.payments_outlined,
            label: 'Booking Value',
            value: totalAmount,
            valueColor: _success,
          ),
        ],
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(
        minHeight: 78,
      ),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: _primary,
            size: 16,
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w900,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: const TextStyle(
              color: _subtle,
              fontWeight: FontWeight.w800,
              fontSize: 7.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingInfoLine extends StatelessWidget {
  const _BookingInfoLine({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;

  final String label;
  final String value;

  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: _softBlue,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            color: _primary,
            size: 14,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: _subtle,
                  fontWeight: FontWeight.w700,
                  fontSize: 8.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: valueColor ?? _ink,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// TOURIST NOTE
// ============================================================================

class _TouristNoteCard extends StatelessWidget {
  const _TouristNoteCard({
    required this.notes,
  });

  final String notes;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFFDE7A8),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.sticky_note_2_outlined,
              color: _warning,
              size: 17,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TOURIST NOTE',
                  style: TextStyle(
                    color: _warning,
                    fontWeight: FontWeight.w900,
                    fontSize: 8,
                    letterSpacing: 0.55,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  notes,
                  style: const TextStyle(
                    color: Color(0xFF6B4A17),
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

// ============================================================================
// ITINERARY
// ============================================================================

class _ItineraryCard extends StatelessWidget {
  const _ItineraryCard({
    required this.spots,
    required this.itineraryCount,
  });

  final List<BookingItineraryItem> spots;
  final int itineraryCount;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.map_outlined,
            title: 'Selected Tour Spots',
            subtitle: itineraryCount == 0
                ? 'No itinerary destinations yet'
                : '$itineraryCount destination${itineraryCount == 1 ? '' : 's'} included in this booking',
          ),

          const SizedBox(height: 14),

          if (itineraryCount == 0)
            const _EmptyItinerary()
          else if (spots.isEmpty)
            ...List.generate(
              itineraryCount,
              (index) => _ItineraryRowPlaceholder(
                index: index + 1,
                isLast: index == itineraryCount - 1,
              ),
            )
          else
            ...spots.asMap().entries.map(
              (entry) => _ItineraryTimelineRow(
                index: entry.key + 1,
                item: entry.value,
                isLast: entry.key == spots.length - 1,
              ),
            ),
        ],
      ),
    );
  }
}

class _ItineraryTimelineRow extends StatelessWidget {
  const _ItineraryTimelineRow({
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
    ].where((part) => part.isNotEmpty).join(' – ');

    final stopOrder =
        item.orderNumber > 0 ? item.orderNumber : item.destinationOrder;

    final completed = item.spotStatus == 'completed';

    final markerColor = completed ? _success : _primary;

    final sourceLabel = item.sourceType
        .replaceAll('_', ' ')
        .trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Column(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: completed ? _successSoft : _softBlue,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: markerColor,
                    width: 1.5,
                  ),
                ),
                child: completed
                    ? const Icon(
                        Icons.check_rounded,
                        color: _success,
                        size: 15,
                      )
                    : Text(
                        '$index',
                        style: const TextStyle(
                          color: _primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                        ),
                      ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 50,
                  color: markerColor.withValues(alpha: 0.20),
                ),
            ],
          ),
        ),

        const SizedBox(width: 9),

        Expanded(
          child: Container(
            margin: EdgeInsets.only(
              bottom: isLast ? 0 : 9,
            ),
            padding: const EdgeInsets.fromLTRB(
              10,
              8,
              10,
              9,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFC),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.destinationName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.2,
                    height: 1.2,
                  ),
                ),

                const SizedBox(height: 6),

                Wrap(
                  spacing: 6,
                  runSpacing: 5,
                  children: [
                    _ItineraryChip(
                      icon: Icons.flag_outlined,
                      label:
                          'Stop ${stopOrder > 0 ? stopOrder : index}',
                      color: _primary,
                    ),
                    if (sourceLabel.isNotEmpty)
                      _ItineraryChip(
                        icon: Icons.place_outlined,
                        label: sourceLabel,
                        color: _success,
                      ),
                  ],
                ),

                if (item.destinationAddress.trim().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: _subtle,
                        size: 12,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          item.destinationAddress,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _muted,
                            fontWeight: FontWeight.w600,
                            fontSize: 9.5,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                if (timeLabel.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _softBlue,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.schedule_rounded,
                          color: _primary,
                          size: 11,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeLabel,
                          style: const TextStyle(
                            color: _primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 9,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ItineraryChip extends StatelessWidget {
  const _ItineraryChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 7,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 10,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 8.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ItineraryRowPlaceholder extends StatelessWidget {
  const _ItineraryRowPlaceholder({
    required this.index,
    required this.isLast,
  });

  final int index;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 34,
          child: Column(
            children: [
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: _softBlue,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$index',
                  style: const TextStyle(
                    color: _primary,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                  ),
                ),
              ),
              if (!isLast)
                Container(
                  width: 2,
                  height: 40,
                  color: const Color(0xFFDCE5F0),
                ),
            ],
          ),
        ),
        const SizedBox(width: 9),
        const Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              top: 7,
              bottom: 20,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    color: _primary,
                    strokeWidth: 2,
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  'Loading itinerary destination...',
                  style: TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 9.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyItinerary extends StatelessWidget {
  const _EmptyItinerary();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: _softBlue,
            child: Icon(
              Icons.map_outlined,
              color: _primary,
              size: 18,
            ),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No itinerary destinations were found for this booking.',
              style: TextStyle(
                color: _muted,
                fontWeight: FontWeight.w600,
                fontSize: 10,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// PERSISTENT ACCEPT BAR
// ============================================================================

class _AcceptBookingBar extends StatelessWidget {
  const _AcceptBookingBar({
    required this.accepting,
    required this.disabledReason,
    required this.onAccept,
  });

  final bool accepting;
  final String? disabledReason;

  final VoidCallback onAccept;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    final disabled =
        disabledReason != null && disabledReason!.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        10,
        16,
        10 + bottomInset,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(
            color: _border,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (disabled) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(
                bottom: 8,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: _warningSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: _warning,
                    size: 15,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      disabledReason!,
                      style: const TextStyle(
                        color: Color(0xFF8A5511),
                        fontWeight: FontWeight.w700,
                        fontSize: 9,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          SizedBox(
            width: double.infinity,
            height: 51,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: disabled
                    ? null
                    : const LinearGradient(
                        colors: [
                          _primary,
                          _primaryLight,
                        ],
                      ),
                color: disabled ? const Color(0xFFCBD5E1) : null,
                borderRadius: BorderRadius.circular(15),
                boxShadow: disabled
                    ? null
                    : [
                        BoxShadow(
                          color: _primary.withValues(alpha: 0.20),
                          blurRadius: 15,
                          offset: const Offset(0, 7),
                        ),
                      ],
              ),
              child: ElevatedButton(
                onPressed: accepting || disabled ? null : onAccept,
                style: ElevatedButton.styleFrom(
                  elevation: 0,
                  shadowColor: Colors.transparent,
                  backgroundColor: Colors.transparent,
                  disabledBackgroundColor: Colors.transparent,
                  foregroundColor: Colors.white,
                  disabledForegroundColor: Colors.white70,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: accepting
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          ),
                          SizedBox(width: 9),
                          Text(
                            'Accepting Booking...',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            disabled
                                ? Icons.block_rounded
                                : Icons.check_circle_outline_rounded,
                            size: 18,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            disabled
                                ? 'Booking Unavailable'
                                : 'Accept This Booking',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 12.5,
                            ),
                          ),
                          if (!disabled) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.arrow_forward_rounded,
                              size: 16,
                            ),
                          ],
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

// ============================================================================
// SECTION HEADER
// ============================================================================

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 37,
          height: 37,
          decoration: BoxDecoration(
            color: _softBlue,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            color: _primary,
            size: 17,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: _subtle,
                  fontWeight: FontWeight.w600,
                  fontSize: 9.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// SHARED CARD
// ============================================================================

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _border,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

// ============================================================================
// LOADING
// ============================================================================

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 31,
            height: 31,
            child: CircularProgressIndicator(
              color: _primary,
              strokeWidth: 3,
            ),
          ),
          SizedBox(height: 13),
          Text(
            'Loading booking details...',
            style: TextStyle(
              color: _muted,
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ERROR
// ============================================================================

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(21),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: _border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: const BoxDecoration(
                  color: _dangerSoft,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.error_outline_rounded,
                  color: _danger,
                  size: 27,
                ),
              ),
              const SizedBox(height: 13),
              const Text(
                'Unable to load booking',
                style: TextStyle(
                  color: _ink,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: onRetry,
                  style: ElevatedButton.styleFrom(
                    elevation: 0,
                    backgroundColor: _primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 17,
                  ),
                  label: const Text(
                    'Try Again',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                    ),
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
