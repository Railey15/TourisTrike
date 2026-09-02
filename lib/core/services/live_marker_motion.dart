import 'dart:async';

import 'package:google_maps_flutter/google_maps_flutter.dart';

typedef LiveMarkerFrame = void Function(LatLng position, double heading);

/// Interpolates sparse realtime GPS samples without owning map camera state.
/// Camera movement remains an explicit choice of the tracking screen.
class LiveMarkerMotion {
  final Map<String, LatLng> _positions = <String, LatLng>{};
  final Map<String, double> _headings = <String, double>{};
  final Map<String, Timer> _timers = <String, Timer>{};

  void seedIfAbsent(String id, LatLng position, double heading) {
    _positions.putIfAbsent(id, () => position);
    _headings.putIfAbsent(id, () => _normalHeading(heading));
  }

  void animateTo(
    String id,
    LatLng target,
    double targetHeading,
    LiveMarkerFrame onFrame, {
    Duration duration = const Duration(milliseconds: 600),
  }) {
    if (!_valid(target)) return;
    final start = _positions[id] ?? target;
    final startHeading = _headings[id] ?? _normalHeading(targetHeading);
    final endHeading = _normalHeading(targetHeading);
    final headingDelta = ((endHeading - startHeading + 540) % 360) - 180;
    const frames = 12;
    var frame = 0;
    _timers.remove(id)?.cancel();
    _timers[id] = Timer.periodic(duration ~/ frames, (timer) {
      frame++;
      final linear = (frame / frames).clamp(0.0, 1.0);
      final progress = 1 - (1 - linear) * (1 - linear);
      final position = LatLng(
        start.latitude + (target.latitude - start.latitude) * progress,
        start.longitude + (target.longitude - start.longitude) * progress,
      );
      final heading = _normalHeading(startHeading + headingDelta * progress);
      _positions[id] = position;
      _headings[id] = heading;
      onFrame(position, heading);
      if (frame >= frames) {
        timer.cancel();
        _timers.remove(id);
      }
    });
  }

  bool _valid(LatLng value) =>
      value.latitude.isFinite &&
      value.longitude.isFinite &&
      value.latitude >= -90 &&
      value.latitude <= 90 &&
      value.longitude >= -180 &&
      value.longitude <= 180;

  double _normalHeading(double value) =>
      value.isFinite ? ((value % 360) + 360) % 360 : 0;

  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
  }
}
