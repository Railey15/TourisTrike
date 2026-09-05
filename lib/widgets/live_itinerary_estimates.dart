import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:intl/intl.dart';
import '../core/models/convoy_state.dart';
import '../core/places/city_spot_suggestions.dart';
import '../core/services/itinerary_schedule_service.dart';
import '../core/supabase/touristrike_models.dart';

/// Transient live forecasts. Planned database times are never overwritten.
class LiveItineraryEstimates extends StatefulWidget {
  const LiveItineraryEstimates({
    super.key,
    required this.booking,
    required this.drivers,
    required this.stops,
    this.onlyDriverId,
  });
  final PackageBooking booking;
  final List<ConvoyDriverSnapshot> drivers;
  final List<BookingItineraryItem> stops;
  final String? onlyDriverId;
  @override
  State<LiveItineraryEstimates> createState() => _LiveItineraryEstimatesState();
}

class _LiveItineraryEstimatesState extends State<LiveItineraryEstimates> {
  final _service = ItineraryScheduleService.live(
    apiKey: CitySpotSuggestionService.resolveApiKey(),
  );
  Timer? _timer;
  int _revision = 0;
  Map<String, List<String>> _estimates = {};
  bool _loading = false;
  String _key() => widget.drivers
      .map(
        (d) =>
            '${d.driverId}:${d.journeyState}:${d.currentStopIndex}:${d.stateUpdatedAt}',
      )
      .join('|');
  String _lastKey = '';
  @override
  void initState() {
    super.initState();
    _lastKey = _key();
    unawaited(_refresh());
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  @override
  void didUpdateWidget(covariant LiveItineraryEstimates oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_lastKey != _key()) {
      _lastKey = _key();
      unawaited(_refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _revision++;
    super.dispose();
  }

  Future<void> _refresh() async {
    final revision = ++_revision;
    final booking = widget.booking;
    final stops = widget.stops;
    final drivers = widget.drivers
        .where(
          (d) =>
              widget.onlyDriverId == null || widget.onlyDriverId == d.driverId,
        )
        .toList();
    setState(() {
      _loading = true;
      _estimates = {};
    });
    final results = await Future.wait(
      drivers.map((driver) async {
        final state = driver.journeyState;
        if (state == ConvoyJourneyState.assigned ||
            state == ConvoyJourneyState.completed ||
            state == ConvoyJourneyState.atDropoff) {
          return MapEntry(driver.driverId, <String>[]);
        }
        if (state == ConvoyJourneyState.atPickup ||
            state == ConvoyJourneyState.boarded ||
            state == ConvoyJourneyState.stopDone) {
          return MapEntry(driver.driverId, [
            'Waiting for departure. Live ETAs refresh when navigation begins.',
          ]);
        }
        if (driver.latitude == null ||
            driver.longitude == null ||
            driver.lastLocationAt == null ||
            DateTime.now().difference(driver.lastLocationAt!) >
                const Duration(minutes: 2)) {
          return MapEntry(driver.driverId, [
            'Live ETA unavailable: waiting for a fresh driver location.',
          ]);
        }
        try {
          final origin = LatLng(driver.latitude!, driver.longitude!);
          if (state == ConvoyJourneyState.enRoutePickup) {
            if (booking.pickupLatitude == null ||
                booking.pickupLongitude == null) {
              throw const ItineraryRouteException();
            }
            final legs = await _service.fetchTravelLegs([
              origin,
              LatLng(booking.pickupLatitude!, booking.pickupLongitude!),
            ]);
            return MapEntry(driver.driverId, [
              'Pickup ETA: ${DateFormat('h:mm a').format(DateTime.now().add(Duration(minutes: legs.first.durationMinutes)))}',
            ]);
          }
          if (booking.dropoffLatitude == null ||
              booking.dropoffLongitude == null) {
            throw const ItineraryRouteException();
          }
          final index = state == ConvoyJourneyState.enRouteDropoff
              ? stops.length
              : driver.currentStopIndex;
          if (index < 0 || index > stops.length) {
            throw const ItineraryRouteException();
          }
          var cursor = DateTime.now();
          final labels = <String>[];
          final atStop =
              state == ConvoyJourneyState.atStop && index < stops.length;
          final remainingStops = stops.skip(index + (atStop ? 1 : 0)).toList();
          if (atStop) {
            final earliestDeparture = driver.stateUpdatedAt.add(
              Duration(minutes: stops[index].estimatedStayDurationMinutes),
            );
            if (earliestDeparture.isAfter(cursor)) cursor = earliestDeparture;
            labels.add(
              'Actual arrival: ${DateFormat('h:mm a').format(driver.stateUpdatedAt.toLocal())} · Stay ends: ${DateFormat('h:mm a').format(earliestDeparture.toLocal())}',
            );
          }
          final points = [
            origin,
            ...remainingStops.map((s) => LatLng(s.latitude, s.longitude)),
            LatLng(booking.dropoffLatitude!, booking.dropoffLongitude!),
          ];
          final legs = await _service.fetchTravelLegs(points);
          // Use response time for an en-route driver's current estimate.
          if (!atStop) cursor = DateTime.now();
          for (var i = 0; i < remainingStops.length; i++) {
            cursor = cursor.add(Duration(minutes: legs[i].durationMinutes));
            labels.add(
              '${remainingStops[i].destinationName}: ${DateFormat('h:mm a').format(cursor.toLocal())}',
            );
            cursor = cursor.add(
              Duration(minutes: remainingStops[i].estimatedStayDurationMinutes),
            );
          }
          cursor = cursor.add(Duration(minutes: legs.last.durationMinutes));
          labels.add(
            'Estimated drop-off: ${DateFormat('h:mm a').format(cursor.toLocal())}',
          );
          return MapEntry(driver.driverId, labels);
        } catch (_) {
          return MapEntry(driver.driverId, [
            'Google Maps could not refresh live ETAs. Retry below.',
          ]);
        }
      }),
    );
    if (!mounted || revision != _revision) return;
    setState(() {
      _estimates = Map.fromEntries(results);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Live Arrival Estimates',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          const Text(
            'Estimates include remaining stays. Convoy and payment waits can delay departure.',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          if (_loading) const LinearProgressIndicator(),
          for (final driver in widget.drivers)
            if ((_estimates[driver.driverId] ?? []).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver.driverName,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final label in _estimates[driver.driverId]!)
                      Text(label),
                  ],
                ),
              ),
          TextButton(
            onPressed: _loading ? null : _refresh,
            child: const Text('Refresh live ETAs'),
          ),
        ],
      ),
    ),
  );
}
