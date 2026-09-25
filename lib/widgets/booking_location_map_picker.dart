import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../core/places/booking_location_service.dart';

/// Booking-only map; tracking, shared maps and route previews remain separate.
class BookingLocationMapPicker extends StatefulWidget {
  const BookingLocationMapPicker({super.key, required this.service});
  final BookingLocationService service;

  @override
  State<BookingLocationMapPicker> createState() =>
      _BookingLocationMapPickerState();
}

class _BookingLocationMapPickerState extends State<BookingLocationMapPicker> {
  LatLng? _pin;
  BookingLocation? _resolved;
  String? _error;
  bool _resolving = false;
  int _revision = 0;

  void _moving(LatLng point) {
    _revision++;
    setState(() {
      _pin = point;
      _resolved = null;
      _resolving = false;
      _error =
          widget.service.serviceArea.contains(point.latitude, point.longitude)
          ? null
          : widget.service.serviceArea.outsideMessage;
    });
  }

  Future<void> _select(LatLng point) async {
    _moving(point);
    if (_error != null) return;
    final revision = _revision;
    setState(() => _resolving = true);
    try {
      final location = await widget.service.currentLocation(
        point.latitude,
        point.longitude,
      );
      if (mounted && revision == _revision) {
        setState(() => _resolved = location);
      }
    } on BookingLocationException catch (e) {
      if (mounted && revision == _revision) setState(() => _error = e.message);
    } finally {
      if (mounted && revision == _revision) setState(() => _resolving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final area = widget.service.serviceArea;
    return Scaffold(
      appBar: AppBar(title: Text('Select location in ${area.municipality}')),
      body: Column(
        children: [
          Expanded(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: LatLng(area.centerLatitude, area.centerLongitude),
                zoom: 12,
              ),
              onMapCreated: (controller) => controller.animateCamera(
                CameraUpdate.newLatLngBounds(
                  LatLngBounds(
                    southwest: LatLng(area.south, area.west),
                    northeast: LatLng(area.north, area.east),
                  ),
                  32,
                ),
              ),
              onTap: _select,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              polygons: {
                for (var i = 0; i < area.rings.length; i++)
                  Polygon(
                    polygonId: PolygonId('service-area-$i'),
                    points: area.rings[i].first
                        .map((p) => LatLng(p[1], p[0]))
                        .toList(),
                    holes: area.rings[i]
                        .skip(1)
                        .map((r) => r.map((p) => LatLng(p[1], p[0])).toList())
                        .toList(),
                    strokeColor: Colors.blue,
                    strokeWidth: 2,
                    fillColor: Colors.blue.withValues(alpha: 0.08),
                  ),
              },
              markers: {
                if (_pin != null)
                  Marker(
                    markerId: const MarkerId('selection'),
                    position: _pin!,
                    draggable: true,
                    onDragStart: _moving,
                    onDrag: _moving,
                    onDragEnd: _select,
                  ),
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _error ??
                        (_resolving
                            ? 'Verifying location…'
                            : _resolved?.address ??
                                  'Tap the map or drag the pin to select a location.'),
                    style: TextStyle(
                      color: _error == null ? null : Colors.red.shade700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: _resolved == null || _resolving
                        ? null
                        : () => Navigator.of(context).pop(_resolved),
                    child: const Text('Confirm Location'),
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
