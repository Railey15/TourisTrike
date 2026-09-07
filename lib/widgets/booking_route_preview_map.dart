import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../core/services/booking_driver_markers.dart';
import '../core/services/route_polyline_service.dart';
import '../core/places/city_spot_suggestions.dart';

/// Coordinates, rather than address text or a successful route, own the map.
class BookingRoutePreviewMap extends StatefulWidget {
  const BookingRoutePreviewMap({
    super.key,
    this.pickup,
    this.dropoff,
    this.loadRoute,
  });
  final LatLng? pickup;
  final LatLng? dropoff;
  final Future<RouteResult> Function(LatLng, LatLng)? loadRoute;

  @override
  State<BookingRoutePreviewMap> createState() => _BookingRoutePreviewMapState();
}

class _BookingRoutePreviewMapState extends State<BookingRoutePreviewMap> {
  final _routes = RoutePolylineService(
    apiKey: CitySpotSuggestionService.resolveApiKey(),
  );
  GoogleMapController? _controller;
  List<LatLng> _route = const [];
  bool _loading = false;
  bool _failed = false;
  int _generation = 0;

  LatLng? _valid(LatLng? point) =>
      point != null && validDriverCoordinates(point.latitude, point.longitude)
      ? point
      : null;
  List<LatLng> get _points => [?_valid(widget.pickup), ?_valid(widget.dropoff)];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant BookingRoutePreviewMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pickup != oldWidget.pickup ||
        widget.dropoff != oldWidget.dropoff) {
      _load();
      WidgetsBinding.instance.addPostFrameCallback((_) => _fit());
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    final points = _points;
    setState(() {
      _route = [];
      _failed = false;
      _loading = points.length == 2;
    });
    if (points.length != 2) return;
    try {
      final result = await (widget.loadRoute ?? _routes.fetchRoute)(
        points.first,
        points.last,
      ).timeout(const Duration(seconds: 20));
      if (!mounted || generation != _generation) return;
      setState(() {
        // The existing service returns a straight line with no ETA on failure.
        _failed = result.durationText == null;
        _route = _failed
            ? []
            : result.points
                  .where((p) => validDriverCoordinates(p.latitude, p.longitude))
                  .toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _fit() async {
    final controller = _controller;
    final points = _points;
    if (!mounted || controller == null || points.isEmpty) return;
    final a = points.first;
    final b = points.last;
    try {
      if ((a.latitude - b.latitude).abs() < .0005 &&
          (a.longitude - b.longitude).abs() < .0005) {
        await controller.animateCamera(CameraUpdate.newLatLngZoom(a, 16));
      } else {
        await controller.animateCamera(
          CameraUpdate.newLatLngBounds(
            LatLngBounds(
              southwest: LatLng(
                a.latitude < b.latitude ? a.latitude : b.latitude,
                a.longitude < b.longitude ? a.longitude : b.longitude,
              ),
              northeast: LatLng(
                a.latitude > b.latitude ? a.latitude : b.latitude,
                a.longitude > b.longitude ? a.longitude : b.longitude,
              ),
            ),
            40,
          ),
        );
      }
    } catch (_) {
      debugPrint('[BookingMap] Camera fit unavailable; markers retained.');
    }
  }

  @override
  void dispose() {
    _generation++;
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_points.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(child: Text('Select a pickup point to preview the map.')),
      );
    }
    return Column(
      children: [
        SizedBox(
          height: 220,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _points.first,
                zoom: 15,
              ),
              onMapCreated: (controller) {
                _controller = controller;
                _fit();
              },
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              markers: {
                if (_valid(widget.pickup) case final point?)
                  Marker(
                    markerId: const MarkerId('pickup'),
                    position: point,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen,
                    ),
                    infoWindow: const InfoWindow(title: 'Pickup'),
                  ),
                if (_valid(widget.dropoff) case final point?)
                  Marker(
                    markerId: const MarkerId('dropoff'),
                    position: point,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueRed,
                    ),
                    infoWindow: const InfoWindow(title: 'Drop-off'),
                  ),
              },
              polylines: {
                if (_route.isNotEmpty)
                  Polyline(
                    polylineId: const PolylineId('route'),
                    points: _route,
                    color: const Color(0xFF2A86FF),
                    width: 5,
                  ),
              },
            ),
          ),
        ),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Calculating route...'),
          ),
        if (_failed) ...[
          const Text('Route unavailable. Selected locations are shown.'),
          TextButton(onPressed: _load, child: const Text('Retry route')),
        ],
      ],
    );
  }
}
