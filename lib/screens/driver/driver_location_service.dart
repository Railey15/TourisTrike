import 'dart:async';
import 'package:geolocator/geolocator.dart';

class DriverLocationService {
  StreamSubscription<Position>? _sub;

  Future<bool> ensurePermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return false;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.deniedForever) return false;

    return perm == LocationPermission.always || perm == LocationPermission.whileInUse;
  }

  Stream<Position> start() async* {
    final ok = await ensurePermission();
    if (!ok) {
      yield* const Stream.empty();
      return;
    }

    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 5,
      ),
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }
}