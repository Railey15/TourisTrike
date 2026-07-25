import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/core/supabase/touristrike_repository.dart';
import '../driver/driver_location_service.dart';

class IncomingRideScreen extends StatefulWidget {
  final String rideId;
  const IncomingRideScreen({super.key, required this.rideId});

  @override
  State<IncomingRideScreen> createState() => _IncomingRideScreenState();
}

class _IncomingRideScreenState extends State<IncomingRideScreen> {
  final supabase = Supabase.instance.client;
  final _repo = TourisTrikeRepository();

  Map<String, dynamic>? _ride;
  Map<String, dynamic>? _touristProfile;

  RealtimeChannel? _rideChannel;

  bool _loading = true;
  bool _updatingStatus = false;

  // Map controller
  GoogleMapController? _mapController;

  // Live location
  final DriverLocationService _loc = DriverLocationService();
  StreamSubscription<Position>? _posSub;
  LatLng? _driverLatLng;

  // Lock map to PH / Bulacan-ish
  static final LatLngBounds _phBulacanBounds = LatLngBounds(
    southwest: const LatLng(14.35, 120.35),
    northeast: const LatLng(15.55, 121.55),
  );

  // Fallback center
  static const LatLng _fallbackCenter = LatLng(14.8448, 120.8104);

  @override
  void initState() {
    super.initState();
    _loadRideAndTourist();
    _subscribeRideRealtime();
    _startDriverLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _loc.stop();
    final ch = _rideChannel;
    _rideChannel = null;
    if (ch != null) supabase.removeChannel(ch);
    super.dispose();
  }

  User get _user {
    final u = supabase.auth.currentUser;
    if (u == null) throw Exception("No logged-in user.");
    return u;
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- LOAD ----------------

  Future<void> _loadRideAndTourist() async {
    setState(() => _loading = true);
    try {
      final ride = await supabase
          .from('rides')
          .select('*')
          .eq('id', widget.rideId)
          .maybeSingle();

      if (ride == null) {
        if (!mounted) return;
        setState(() {
          _ride = null;
          _touristProfile = null;
          _loading = false;
        });
        return;
      }

      Map<String, dynamic>? tourist;
      final touristId = ride['tourist_id'];
      if (touristId != null) {
        tourist = await supabase
            .from('profiles')
            .select(
              'id, full_name, first_name, last_name, profile_image_url, mobile',
            )
            .eq('id', touristId)
            .maybeSingle();
      }

      final dl = ride['driver_lat'];
      final dln = ride['driver_lng'];
      if (dl is num &&
          dln is num &&
          _isValidLatLng(dl.toDouble(), dln.toDouble())) {
        _driverLatLng = LatLng(dl.toDouble(), dln.toDouble());
      }

      if (!mounted) return;
      setState(() {
        _ride = Map<String, dynamic>.from(ride);
        _touristProfile = tourist == null
            ? null
            : Map<String, dynamic>.from(tourist);
        _loading = false;
      });

      _scheduleFit();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Failed to load tour assignment.');
    }
  }

  // ---------------- REALTIME ----------------

  void _subscribeRideRealtime() {
    _rideChannel = supabase.channel('ride-${widget.rideId}');
    _rideChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.rideId,
          ),
          callback: (payload) {
            final newRow = payload.newRecord;
            if (!mounted) return;

            setState(() => _ride = Map<String, dynamic>.from(newRow));

            final dl = newRow['driver_lat'];
            final dln = newRow['driver_lng'];
            if (dl is num &&
                dln is num &&
                _isValidLatLng(dl.toDouble(), dln.toDouble())) {
              _driverLatLng = LatLng(dl.toDouble(), dln.toDouble());
            }

            final status = (newRow['status'] ?? '').toString();
            if (status == 'completed') {
              _stopDriverLocation();
            }

            _scheduleFit();
          },
        )
        .subscribe();
  }

  // ---------------- DRIVER GPS ----------------

  Future<void> _startDriverLocation() async {
    _posSub?.cancel();

    _posSub = _loc.start().listen((pos) async {
      if (!_isValidLatLng(pos.latitude, pos.longitude)) return;

      final rideStatus = (_ride?['status'] ?? '').toString();
      if (rideStatus == 'completed') return;

      _driverLatLng = LatLng(pos.latitude, pos.longitude);

      if (_ride != null) {
        try {
          await supabase
              .from('rides')
              .update({
                'driver_lat': pos.latitude,
                'driver_lng': pos.longitude,
                'driver_last_seen': DateTime.now().toIso8601String(),
              })
              .eq('id', widget.rideId);
        } catch (_) {
          // possibly RLS issue
        }
      }

      _maybeFollowDriver();

      if (mounted) setState(() {});
    });
  }

  Future<void> _stopDriverLocation() async {
    await _posSub?.cancel();
    _posSub = null;
    _loc.stop();
  }

  void _maybeFollowDriver() {
    final ride = _ride;
    if (ride == null) return;

    final status = (ride['status'] ?? '').toString();
    if (status != 'enroute_pickup' && status != 'ongoing') return;

    final driver = _driverLatLng;
    final target = _currentTarget();
    if (driver == null || target == null) return;

    _fitBounds(driver, target);
  }

  // ---------------- LATLNG HELPERS ----------------

  bool _isValidLatLng(double lat, double lng) {
    if (lat == 0 && lng == 0) return false;
    if (lat.isNaN || lng.isNaN) return false;
    if (lat.abs() > 90 || lng.abs() > 180) return false;
    return true;
  }

  LatLng? _pickupLatLng() {
    final ride = _ride;
    if (ride == null) return null;
    final lat = ride['pickup_lat'];
    final lng = ride['pickup_lng'];
    if (lat is num &&
        lng is num &&
        _isValidLatLng(lat.toDouble(), lng.toDouble())) {
      return LatLng(lat.toDouble(), lng.toDouble());
    }
    return null;
  }

  LatLng? _dropoffLatLng() {
    final ride = _ride;
    if (ride == null) return null;
    final lat = ride['dropoff_lat'];
    final lng = ride['dropoff_lng'];
    if (lat is num &&
        lng is num &&
        _isValidLatLng(lat.toDouble(), lng.toDouble())) {
      return LatLng(lat.toDouble(), lng.toDouble());
    }
    return null;
  }

  LatLng? _currentTarget() {
    final ride = _ride;
    if (ride == null) return null;
    final status = (ride['status'] ?? '').toString();

    if (status == 'ongoing') return _dropoffLatLng();
    return _pickupLatLng();
  }

  void _scheduleFit() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitToTarget();
    });
  }

  void _fitToTarget() {
    if (_mapController == null) return;

    final pickup = _pickupLatLng();
    final driver = _driverLatLng;
    final target = _currentTarget();

    if (driver != null && target != null) {
      _fitBounds(driver, target);
      return;
    }

    if (pickup != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: pickup, zoom: 16),
        ),
      );
      return;
    }

    _mapController!.animateCamera(
      CameraUpdate.newCameraPosition(
        const CameraPosition(target: _fallbackCenter, zoom: 13.5),
      ),
    );
  }

  void _fitBounds(LatLng a, LatLng b) {
    final dist =
        Geolocator.distanceBetween(
          a.latitude,
          a.longitude,
          b.latitude,
          b.longitude,
        ) /
        1000;
    if (dist > 120) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(_phBulacanBounds, 40),
      );
      return;
    }

    final bounds = LatLngBounds(
      southwest: LatLng(
        math.min(a.latitude, b.latitude),
        math.min(a.longitude, b.longitude),
      ),
      northeast: LatLng(
        math.max(a.latitude, b.latitude),
        math.max(a.longitude, b.longitude),
      ),
    );
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 60));
  }

  // ---------------- STATUS UPDATES ----------------

  Future<void> _setStatus(String status) async {
    if (_ride == null || _updatingStatus) return;

    setState(() => _updatingStatus = true);
    try {
      final payload = <String, dynamic>{'status': status};

      if (status == 'completed') {
        payload['completed_at'] = DateTime.now().toIso8601String();

        if (_driverLatLng != null) {
          payload['driver_lat'] = _driverLatLng!.latitude;
          payload['driver_lng'] = _driverLatLng!.longitude;
          payload['driver_last_seen'] = DateTime.now().toIso8601String();
        }
      }

      final updated = await supabase
          .from('rides')
          .update(payload)
          .eq('id', widget.rideId)
          .eq('driver_id', _user.id)
          .select()
          .maybeSingle();

      if (updated == null) {
        _snack('Status update failed.');
        return;
      }

      if (status == 'completed') {
        await _stopDriverLocation();
      }

      if (!mounted) return;
      setState(() => _ride = Map<String, dynamic>.from(updated));
      _scheduleFit();

      if (status == 'completed') {
        _snack('TOUR COMPLETED');
      }
    } catch (_) {
      _snack('Status update blocked. Check RLS.');
    } finally {
      if (mounted) setState(() => _updatingStatus = false);
    }
  }

  // TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
  // No live tourist-facing ride screen exists yet for this flow, so the driver
  // records what the tourist already paid them (cash-in-hand, or a GCash
  // reference the tourist shared verbally) rather than the tourist submitting
  // it themselves, unlike the package-booking flow.
  Future<bool> _recordRidePaymentBeforeCompleting() async {
    final ride = _ride;
    if (ride == null) return true;
    final fare = ride['fare_amount'];
    final amount = fare is num ? fare.toDouble() : 0.0;
    if (amount <= 0) return true;

    final rawMethod = (ride['payment_method'] ?? 'cash').toString().trim().toLowerCase();
    final method = rawMethod == 'gcash' || rawMethod == 'maya' ? rawMethod : 'cash';
    final refController = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Confirm Payment Received',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            const SizedBox(height: 6),
            Text(
              '₱${amount.toStringAsFixed(2)} via ${method.toUpperCase()}',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 22,
                color: Color(0xFF2F6FFF),
              ),
            ),
            const SizedBox(height: 14),
            if (method != 'cash')
              TextField(
                controller: refController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'GCash/Maya Reference Number',
                  border: OutlineInputBorder(),
                ),
              )
            else
              const Text(
                'Confirm that you have received this fare in cash from the tourist.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Confirm & Complete Tour'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return false;

    try {
      await _repo.recordRidePayment(
        rideId: widget.rideId,
        paymentMethod: method,
        amount: amount,
        externalReferenceNo: refController.text.trim().isEmpty
            ? null
            : refController.text.trim(),
      );
      return true;
    } catch (e) {
      _snack('Unable to record payment: $e');
      return false;
    }
  }

  _Action? _primaryAction(String status) {
    switch (status) {
      case 'accepted':
        return _Action(
          label: 'Navigate to Pickup',
          nextStatus: 'enroute_pickup',
          toast: 'EN ROUTE TO PICKUP',
          icon: Icons.navigation,
        );
      case 'enroute_pickup':
        return _Action(
          label: 'Arrived at Pickup',
          nextStatus: 'arrived',
          toast: 'ARRIVED AT PICKUP',
          icon: Icons.location_on,
        );
      case 'arrived':
        return _Action(
          label: 'Start Tour',
          nextStatus: 'ongoing',
          toast: 'TOUR STARTED',
          icon: Icons.play_arrow,
        );
      case 'ongoing':
        return _Action(
          label: 'Complete Tour',
          nextStatus: 'completed',
          toast: 'TOUR COMPLETED',
          icon: Icons.flag,
        );
      default:
        return null;
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final ride = _ride;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ride == null
            ? _emptyState()
            : _content(ride),
      ),
    );
  }

  Widget _emptyState() {
    return Column(
      children: [
        _topBar(title: 'Tour Assignment'),
        const Spacer(),
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                blurRadius: 18,
                offset: Offset(0, 8),
                color: Color(0x12000000),
              ),
            ],
          ),
          child: const Text(
            'Tour assignment not found or already ended.',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _content(Map<String, dynamic> ride) {
    final pickupName = (ride['pickup_name'] ?? '').toString();
    final dropoffName = (ride['dropoff_name'] ?? '').toString();
    final status = (ride['status'] ?? '').toString();

    final pickup = _pickupLatLng();
    final dropoff = _dropoffLatLng();
    final driver = _driverLatLng;

    final touristName = _touristName();
    final touristMobile = (_touristProfile?['mobile'] ?? '').toString().trim();
    final touristImg = (_touristProfile?['profile_image_url'] ?? '')
        .toString()
        .trim();

    final fare = ride['fare_amount'];
    final fareText = (fare is num) ? '₱ ${fare.toStringAsFixed(2)}' : '₱ 0.00';

    final distance = ride['distance_km'];
    final distText = (distance is num)
        ? '${distance.toStringAsFixed(1)} KM'
        : '—';

    final action = _primaryAction(status);

    final target = _currentTarget();
    final routePoints = <LatLng>[];
    if (driver != null && target != null && status != 'completed') {
      routePoints.addAll([driver, target]);
    }

    final initialCenter = pickup ?? _fallbackCenter;

    return Column(
      children: [
        _topBar(title: 'Tour Assignment'),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 18,
                      offset: Offset(0, 8),
                      color: Color(0x12000000),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: SizedBox(
                    height: 300,
                    child: Stack(
                      children: [
                        GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: initialCenter,
                            zoom: 15,
                          ),
                          cameraTargetBounds: CameraTargetBounds(
                            _phBulacanBounds,
                          ),
                          minMaxZoomPreference: const MinMaxZoomPreference(
                            11,
                            19,
                          ),
                          zoomControlsEnabled: false,
                          myLocationButtonEnabled: false,
                          compassEnabled: false,
                          mapToolbarEnabled: false,
                          onMapCreated: (controller) {
                            _mapController = controller;
                            _scheduleFit();
                          },
                          markers: {
                            if (pickup != null)
                              Marker(
                                markerId: const MarkerId('pickup'),
                                position: pickup,
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueGreen,
                                ),
                                infoWindow: InfoWindow(title: pickupName),
                              ),
                            if (dropoff != null)
                              Marker(
                                markerId: const MarkerId('dropoff'),
                                position: dropoff,
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueRed,
                                ),
                                infoWindow: InfoWindow(title: dropoffName),
                              ),
                            if (driver != null)
                              Marker(
                                markerId: const MarkerId('driver'),
                                position: driver,
                                icon: BitmapDescriptor.defaultMarkerWithHue(
                                  BitmapDescriptor.hueAzure,
                                ),
                                infoWindow: const InfoWindow(title: 'Driver'),
                              ),
                          },
                          polylines: {
                            if (routePoints.length == 2)
                              Polyline(
                                polylineId: const PolylineId('incoming-route'),
                                points: routePoints,
                                width: 6,
                                color: const Color(
                                  0xFF2F6FFF,
                                ).withValues(alpha: 0.85),
                              ),
                          },
                        ),
                        Positioned(
                          top: 12,
                          left: 12,
                          right: 12,
                          child: Row(
                            children: [
                              _statusChip(status),
                              const Spacer(),
                              _softChip('BULACAN'),
                            ],
                          ),
                        ),
                        Positioned(
                          bottom: 12,
                          right: 12,
                          child: Column(
                            children: [
                              _floatingMapBtn(
                                icon: Icons.my_location,
                                onTap: () {
                                  if (_driverLatLng != null) {
                                    _mapController?.animateCamera(
                                      CameraUpdate.newCameraPosition(
                                        CameraPosition(
                                          target: _driverLatLng!,
                                          zoom: 16.5,
                                        ),
                                      ),
                                    );
                                  } else {
                                    _snack(
                                      'Driver location not available yet.',
                                    );
                                  }
                                },
                              ),
                              const SizedBox(height: 10),
                              _floatingMapBtn(
                                icon: Icons.place,
                                onTap: () {
                                  final t = _currentTarget();
                                  if (t != null) {
                                    _mapController?.animateCamera(
                                      CameraUpdate.newCameraPosition(
                                        CameraPosition(target: t, zoom: 16.2),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: const [
                    BoxShadow(
                      blurRadius: 18,
                      offset: Offset(0, 8),
                      color: Color(0x12000000),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tour Details',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: const Color(0xFFE9EEF8),
                          backgroundImage: touristImg.isNotEmpty
                              ? NetworkImage(touristImg)
                              : null,
                          child: touristImg.isEmpty
                              ? const Icon(
                                  Icons.person,
                                  color: Color(0xFF7B8AA6),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                touristName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF111827),
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                touristMobile.isEmpty
                                    ? 'No number on profile'
                                    : touristMobile,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        _iconButton(
                          Icons.call,
                          onTap: () => _snack('Call (TODO)'),
                        ),
                        const SizedBox(width: 8),
                        _iconButton(
                          Icons.chat_bubble_outline,
                          onTap: () => _snack('Chat (TODO)'),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),
                    _placeTile(
                      dot: const Color(0xFF2F6FFF),
                      title: 'PICK-UP',
                      value: pickupName,
                      subtitle: 'Tourist pickup',
                    ),
                    const SizedBox(height: 10),
                    _placeTile(
                      dot: const Color(0xFFEF4444),
                      title: 'DROP-OFF',
                      value: dropoffName,
                      subtitle: 'Destination',
                    ),
                    const SizedBox(height: 14),

                    Row(
                      children: [
                        Expanded(
                          child: _miniStat(
                            label: 'EST. EARNINGS',
                            value: fareText,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _miniStat(label: 'DISTANCE', value: distText),
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    if (status == 'completed')
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFDF5),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0xFF86EFAC)),
                        ),
                        child: const Center(
                          child: Text(
                            'TOUR COMPLETED',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: Color(0xFF166534),
                            ),
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_updatingStatus || action == null)
                              ? null
                              : () async {
                                  if (action.nextStatus == 'completed') {
                                    final ok =
                                        await _recordRidePaymentBeforeCompleting();
                                    if (!ok) return;
                                  }
                                  await _setStatus(action.nextStatus);
                                  if (action.nextStatus != 'completed') {
                                    _snack(action.toast);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2F6FFF),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                          icon: _updatingStatus
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Icon(action?.icon ?? Icons.check, size: 18),
                          label: Text(
                            _updatingStatus
                                ? 'Updating...'
                                : action?.label ?? 'Action',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),

                    const SizedBox(height: 10),
                    _hint(
                      status == 'completed'
                          ? 'This tour has been completed successfully.'
                          : 'Map locked to Philippines/Bulacan. Route line shows driver to target.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------- UI bits ----------------

  Widget _topBar({required String title}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      child: Row(
        children: [
          InkResponse(
            onTap: () => Navigator.of(context).pop(),
            radius: 22,
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(
                Icons.arrow_back_ios_new,
                size: 18,
                color: Color(0xFF111827),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF111827),
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _floatingMapBtn({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkResponse(
      onTap: onTap,
      radius: 26,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [
            BoxShadow(
              blurRadius: 14,
              offset: Offset(0, 6),
              color: Color(0x14000000),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF111827)),
      ),
    );
  }

  Widget _statusChip(String status) {
    final s = status.trim().isEmpty ? 'accepted' : status;
    Color bg = const Color(0xFFEFF6FF);
    Color fg = const Color(0xFF2F6FFF);

    if (s == 'searching') {
      bg = const Color(0xFFF1F5F9);
      fg = const Color(0xFF64748B);
    } else if (s == 'accepted' ||
        s == 'enroute_pickup' ||
        s == 'arrived' ||
        s == 'ongoing') {
      bg = const Color(0xFFECFDF5);
      fg = const Color(0xFF16A34A);
    } else if (s == 'completed') {
      bg = const Color(0xFFDCFCE7);
      fg = const Color(0xFF166534);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        s.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w900,
          fontSize: 11,
          letterSpacing: 0.4,
        ),
      ),
    );
  }

  Widget _softChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 11,
          color: Color(0xFF111827),
        ),
      ),
    );
  }

  Widget _placeTile({
    required Color dot,
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: dot.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(child: Icon(Icons.location_on, size: 16, color: dot)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF6B7280),
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF111827),
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniStat({required String label, required String value}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w900,
              color: Color(0xFF64748B),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
        ],
      ),
    );
  }

  Widget _iconButton(IconData icon, {required VoidCallback onTap}) {
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: const Color(0xFF111827)),
      ),
    );
  }

  Widget _hint(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1D4ED8),
        ),
      ),
    );
  }

  String _touristName() {
    if (_touristProfile == null) return 'Tourist';
    final full = (_touristProfile?['full_name'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    final first = (_touristProfile?['first_name'] ?? '').toString().trim();
    final last = (_touristProfile?['last_name'] ?? '').toString().trim();
    final joined = ('$first $last').trim();
    return joined.isNotEmpty ? joined : 'Tourist';
  }
}

class _Action {
  final String label;
  final String nextStatus;
  final String toast;
  final IconData icon;

  _Action({
    required this.label,
    required this.nextStatus,
    required this.toast,
    required this.icon,
  });
}
