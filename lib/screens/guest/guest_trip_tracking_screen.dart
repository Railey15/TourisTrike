import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:url_launcher/url_launcher.dart';

/// Limited trip view for guests who verified via a shared trip link.
/// Shows only safe, non-sensitive trip info.
class GuestTripTrackingScreen extends StatefulWidget {
  const GuestTripTrackingScreen({
    super.key,
    required this.publicToken,
    required this.accessCode,
    required this.initialDetails,
  });

  final String publicToken;
  final String accessCode;
  final GuestTripDetails initialDetails;

  @override
  State<GuestTripTrackingScreen> createState() =>
      _GuestTripTrackingScreenState();
}

class _GuestTripTrackingScreenState extends State<GuestTripTrackingScreen> {
  final _repo = TourisTrikeRepository();

  late GuestTripDetails _details;
  GoogleMapController? _mapCtrl;
  Timer? _refreshTimer;

  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _details = widget.initialDetails;
    _buildMarkers();
    _startPeriodicRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _mapCtrl?.dispose();
    super.dispose();
  }

  void _startPeriodicRefresh() {
    // Refresh trip details every 30s so the guest view stays current
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshDetails();
    });
  }

  Future<void> _refreshDetails() async {
    try {
      final updated = await _repo.validateGuestTripLink(
        publicToken: widget.publicToken,
        accessCode: widget.accessCode,
      );
      if (!mounted || updated == null) return;
      setState(() => _details = updated);
      _buildMarkers();
    } catch (_) {
      // Silently fail on refresh errors
    }
  }

  void _buildMarkers() {
    final lat = _details.driverLatitude;
    final lng = _details.driverLongitude;
    if (lat == null || lng == null) {
      setState(() => _markers = {});
      return;
    }
    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(lat, lng),
          infoWindow: InfoWindow(
            title: 'Tricycle ${_details.tricycleNumber}',
            snippet: _details.driverPhoneMasked ?? '',
          ),
        ),
      };
    });
    _mapCtrl?.animateCamera(
      CameraUpdate.newLatLng(LatLng(lat, lng)),
    );
  }

  Future<void> _callEmergency() async {
    final uri = Uri.parse('tel:911');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showEmergencySheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmergencySheet(onCall: _callEmergency),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _buildBody(bottom),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: const Color(0xFF2A86FF),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Row(
        children: [
          const Icon(
            Icons.share_location_rounded,
            color: Colors.white,
            size: 22,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TourisTrike — Trip Tracking',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'Guest View — Limited info shown',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _refreshDetails,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(double bottomPadding) {
    if (_details.isTripEnded) {
      return _FullScreenMessage(
        icon: Icons.check_circle_outline_rounded,
        iconColor: const Color(0xFF16A34A),
        title: 'This trip has ended.',
        subtitle: 'The tour has been completed. Thank you for using TourisTrike!',
      );
    }

    final isActive = _details.isLiveTrackingAvailable;
    final hasLocation = _details.driverLatitude != null &&
        _details.driverLongitude != null;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + bottomPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status card
          _StatusCard(tourStatus: _details.tourStatus),
          const SizedBox(height: 12),

          // Live map
          if (isActive && hasLocation) ...[
            _SectionLabel(label: 'Live Location'),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 220,
                child: GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: LatLng(
                      _details.driverLatitude!,
                      _details.driverLongitude!,
                    ),
                    zoom: 15,
                  ),
                  markers: _markers,
                  onMapCreated: (ctrl) => _mapCtrl = ctrl,
                  zoomControlsEnabled: false,
                  myLocationButtonEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ] else if (!isActive) ...[
            _InfoBanner(
              icon: Icons.access_time_rounded,
              color: const Color(0xFF0EA5E9),
              message: 'Trip tracking will be available once the tour starts.',
            ),
            const SizedBox(height: 12),
          ],

          // Driver info
          if (_details.tricycleNumber.isNotEmpty ||
              _details.driverPhoneMasked != null) ...[
            _SectionLabel(label: 'Driver Info'),
            const SizedBox(height: 8),
            _DriverCard(
              tricycleNumber: _details.tricycleNumber,
              phoneMasked: _details.driverPhoneMasked,
            ),
            const SizedBox(height: 12),
          ],

          // Itinerary
          if (_details.itineraryItems.isNotEmpty) ...[
            _SectionLabel(label: 'Itinerary'),
            const SizedBox(height: 8),
            _ItineraryCard(items: _details.itineraryItems),
            const SizedBox(height: 12),
          ],

          // Pickup landmark
          if (_details.pickupLandmark.isNotEmpty) ...[
            _SectionLabel(label: 'Pickup Area'),
            const SizedBox(height: 8),
            _SimpleInfoCard(
              icon: Icons.place_rounded,
              value: _details.pickupLandmark,
            ),
            const SizedBox(height: 12),
          ],

          // Emergency button
          const SizedBox(height: 4),
          OutlinedButton.icon(
            onPressed: _showEmergencySheet,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.emergency_rounded, size: 18),
            label: const Text(
              'Emergency',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
          const SizedBox(height: 12),

          // Privacy notice
          const Text(
            'Personal details, full addresses, and payment information are not shown in guest view.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF94A3B8),
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.tourStatus});

  final String tourStatus;

  static const _statusInfo = <String, (String, String, Color, IconData)>{
    'not_started': (
      'Not Started',
      'The tour has not started yet.',
      Color(0xFF64748B),
      Icons.hourglass_empty_rounded,
    ),
    'waiting_driver': (
      'Finding Driver',
      'Looking for an available driver.',
      Color(0xFFF59E0B),
      Icons.search_rounded,
    ),
    'driver_accepted': (
      'Driver Found',
      'A driver has accepted and will be on the way.',
      Color(0xFF2A86FF),
      Icons.check_circle_rounded,
    ),
    'driver_en_route': (
      'Driver On the Way',
      'Your driver is heading to the pickup point.',
      Color(0xFF2A86FF),
      Icons.directions_car_rounded,
    ),
    'driver_arrived': (
      'Driver Arrived',
      'Driver is at the pickup point.',
      Color(0xFF7C3AED),
      Icons.location_on_rounded,
    ),
    'picked_up': (
      'Tour Started!',
      'The group has been picked up. Tour is in progress.',
      Color(0xFF16A34A),
      Icons.tour_rounded,
    ),
    'on_tour': (
      'On Tour',
      'The tour is active and itinerary is being completed.',
      Color(0xFF0EA5E9),
      Icons.route_rounded,
    ),
    'en_route_to_spot': (
      'Heading to Next Stop',
      'Driving to the next itinerary stop.',
      Color(0xFF0EA5E9),
      Icons.navigation_rounded,
    ),
    'at_spot': (
      'At Tour Spot',
      'Currently at a tour destination.',
      Color(0xFF16A34A),
      Icons.place_rounded,
    ),
    'en_route_to_dropoff': (
      'Heading to Drop-off',
      'All spots done! Heading to drop-off point.',
      Color(0xFF2A86FF),
      Icons.home_rounded,
    ),
    'ready_to_complete': (
      'All Spots Done',
      'Every booked spot is completed.',
      Color(0xFF16A34A),
      Icons.task_alt_rounded,
    ),
    'dropped_off': (
      'Dropped Off',
      'The tour group has been dropped off.',
      Color(0xFF16A34A),
      Icons.check_circle_outline_rounded,
    ),
    'completed': (
      'Tour Completed',
      'The tour has been completed.',
      Color(0xFF16A34A),
      Icons.star_rounded,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final data = _statusInfo[tourStatus] ??
        (
          tourStatus.replaceAll('_', ' ').toUpperCase(),
          '',
          const Color(0xFF64748B),
          Icons.info_rounded,
        );
    final (label, desc, color, icon) = data;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: color,
                  ),
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF475569),
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

class _DriverCard extends StatelessWidget {
  const _DriverCard({required this.tricycleNumber, required this.phoneMasked});

  final String tricycleNumber;
  final String? phoneMasked;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          if (tricycleNumber.isNotEmpty)
            _Row(
              icon: Icons.electric_rickshaw_rounded,
              label: 'Tricycle No.',
              value: tricycleNumber,
            ),
          if (phoneMasked != null && phoneMasked!.isNotEmpty) ...[
            if (tricycleNumber.isNotEmpty)
              const Divider(height: 16, color: Color(0xFFE2E8F0)),
            _Row(
              icon: Icons.phone_rounded,
              label: 'Driver Phone',
              value: phoneMasked!,
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
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
      children: [
        Icon(icon, size: 18, color: const Color(0xFF2A86FF)),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFF94A3B8),
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ItineraryCard extends StatelessWidget {
  const _ItineraryCard({required this.items});

  final List<Map<String, dynamic>> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            const Divider(height: 1, color: Color(0xFFE2E8F0)),
        itemBuilder: (_, i) => _ItineraryRow(item: items[i], index: i),
      ),
    );
  }
}

class _ItineraryRow extends StatelessWidget {
  const _ItineraryRow({required this.item, required this.index});

  final Map<String, dynamic> item;
  final int index;

  @override
  Widget build(BuildContext context) {
    final name = item['name']?.toString() ?? 'Stop ${index + 1}';
    final status = item['status']?.toString() ?? '';
    final arrivedAt = item['arrived_at'] != null
        ? DateTime.tryParse(item['arrived_at'].toString())?.toLocal()
        : null;
    final departedAt = item['departed_at'] != null
        ? DateTime.tryParse(item['departed_at'].toString())?.toLocal()
        : null;

    final isDone = status == 'completed';
    final isCurrent = status == 'travelling' || status == 'visiting';

    Color dotColor = const Color(0xFFCBD5E1);
    if (isDone) dotColor = const Color(0xFF16A34A);
    if (isCurrent) dotColor = const Color(0xFF2A86FF);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDone
                      ? Icons.check_rounded
                      : isCurrent
                          ? Icons.navigation_rounded
                          : Icons.circle,
                  size: isDone || isCurrent ? 12 : 6,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: isDone
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF1E293B),
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                if (arrivedAt != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Arrived ${DateFormat.jm().format(arrivedAt)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ],
                if (departedAt != null)
                  Text(
                    'Departed ${DateFormat.jm().format(departedAt)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF94A3B8),
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

class _SimpleInfoCard extends StatelessWidget {
  const _SimpleInfoCard({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF2A86FF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({
    required this.icon,
    required this.color,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: Color(0xFF94A3B8),
        letterSpacing: 0.8,
      ),
    );
  }
}

class _FullScreenMessage extends StatelessWidget {
  const _FullScreenMessage({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: iconColor),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmergencySheet extends StatelessWidget {
  const _EmergencySheet({required this.onCall});

  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        20,
        24,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Emergency',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 20,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'If you or someone is in danger, call emergency services immediately.',
            style: TextStyle(fontSize: 13, color: Color(0xFF64748B), height: 1.5),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              onCall();
            },
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.call_rounded, size: 20),
            label: const Text(
              'Call 911 — Emergency',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}
