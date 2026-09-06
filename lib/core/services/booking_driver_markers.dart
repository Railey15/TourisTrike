import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../models/convoy_state.dart';

/// Every viewer renders the same assignment collection. Viewer identity only
/// changes the label, never membership, coordinates, or vehicle artwork.
Set<Marker> buildBookingDriverMarkers({
  required List<ConvoyDriverSnapshot> drivers,
  required BitmapDescriptor icon,
  Map<String, LatLng> positions = const {},
  Map<String, double> headings = const {},
  String? viewerId,
  String? selectedDriverId,
  ValueChanged<String>? onSelect,
}) {
  final markers = <String, Marker>{};
  for (final (index, driver) in drivers.indexed) {
    if (!const {'accepted', 'completed'}.contains(driver.assignmentStatus)) {
      continue;
    }
    final point =
        positions[driver.driverId] ??
        (driver.latitude != null && driver.longitude != null
            ? LatLng(driver.latitude!, driver.longitude!)
            : null);
    if (point == null ||
        !validDriverCoordinates(point.latitude, point.longitude)) {
      continue;
    }
    final heading = headings[driver.driverId] ?? driver.heading;
    markers[driver.driverId] = Marker(
      markerId: MarkerId('driver_${driver.driverId}'),
      position: point,
      icon: icon,
      rotation: heading.isFinite ? heading % 360 : 0,
      anchor: const Offset(.5, .5),
      flat: true,
      zIndexInt: driver.driverId == selectedDriverId ? 4 : 3,
      infoWindow: InfoWindow(
        title:
            'Tricycle ${index + 1}: ${driver.driverName}${driver.driverId == viewerId ? ' (YOU)' : ''}',
        snippet: '${driver.plateNumber} · ${driver.journeyState.label}',
      ),
      onTap: onSelect == null ? null : () => onSelect(driver.driverId),
    );
  }
  return markers.values.toSet();
}

bool validDriverCoordinates(double latitude, double longitude) =>
    latitude.isFinite &&
    longitude.isFinite &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180 &&
    !(latitude == 0 && longitude == 0);

/// Merge only the matching driver. Ignore stale/invalid updates and leave
/// assignment membership intact when a driver has no first GPS fix yet.
List<ConvoyDriverSnapshot> mergeBookingDriverLocation(
  List<ConvoyDriverSnapshot> drivers,
  Map<String, dynamic> row,
) {
  final id = row['driver_id']?.toString();
  final lat = (row['latitude'] as num?)?.toDouble();
  final lng = (row['longitude'] as num?)?.toDouble();
  final time = DateTime.tryParse(row['updated_at']?.toString() ?? '');
  if (lat == null ||
      lng == null ||
      time == null ||
      !validDriverCoordinates(lat, lng)) {
    return drivers;
  }
  return drivers
      .map(
        (driver) =>
            driver.driverId == id &&
                (driver.lastLocationAt == null ||
                    !time.isBefore(driver.lastLocationAt!))
            ? driver.withLiveLocation(
                latitude: lat,
                longitude: lng,
                heading: (row['heading'] as num?)?.toDouble() ?? 0,
                updatedAt: time,
              )
            : driver,
      )
      .toList();
}
