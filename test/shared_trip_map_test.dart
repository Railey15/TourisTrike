import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// Use the interface version resolved by the production Google Maps plugin.
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:touristrike/core/services/booking_driver_markers.dart';
import 'package:touristrike/core/services/route_polyline_service.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/widgets/booking_route_preview_map.dart';

// Keep platform tiles out of widget tests; inspect the real GoogleMap inputs.
class _Maps extends GoogleMapsFlutterPlatform {
  @override
  Widget buildViewWithConfiguration(
    int creationId,
    void Function(int) onPlatformViewCreated, {
    required MapWidgetConfiguration widgetConfiguration,
    MapConfiguration mapConfiguration = const MapConfiguration(),
    MapObjects mapObjects = const MapObjects(),
  }) => const SizedBox.expand();
}

void main() {
  test(
    'shared roster uses the existing marker normalizer for all vehicles',
    () {
      final details = GuestTripDetails.fromJson({
        'tour_status': 'at_spot',
        'pickup_latitude': '15.1',
        'pickup_longitude': '120.9',
        'dropoff_latitude': double.nan,
        'dropoff_longitude': 121,
        'drivers': [
          for (var i = 0; i < 3; i++)
            {
              'driver_id': '$i',
              'status': 'accepted',
              'journey_state': 'at_stop',
              'latitude': '15.$i',
              'longitude': '121',
              'driver_name': 'Driver Name',
              'phone': 'Private Phone',
            },
          {'driver_id': 'missing', 'status': 'accepted'},
          {'driver_id': 'invalid', 'latitude': 999, 'longitude': 121},
        ],
      });
      final markers = buildBookingDriverMarkers(
        drivers: details.drivers,
        icon: BitmapDescriptor.defaultMarker,
      );
      expect(markers, hasLength(3));
      expect(details.pickupLatitude, 15.1);
      expect(details.dropoffLatitude, isNull);
      expect(details.dropoffLongitude, isNull);
      expect(details.tourStatus, 'at_spot');
      expect(details.drivers.every((d) => d.phoneNumber.isEmpty), isTrue);
      for (final marker in markers) {
        expect(marker.infoWindow.title, contains('Driver Name'));
        expect(marker.infoWindow.title, isNot(contains('Private')));
        expect(marker.infoWindow.title, isNot(contains('YOU')));
      }
    },
  );

  test('persisted terminal booking states stop shared tracking', () {
    for (final status in ['completed', 'cancelled', 'rejected', 'done']) {
      expect(
        GuestTripDetails.fromJson({
          'booking_status_detail': status,
          'tour_status': 'on_tour',
        }).isTripEnded,
        isTrue,
      );
    }
    expect(
      GuestTripDetails.fromJson({
        'tour_status': 'awaiting_remaining_payment',
      }).isTripEnded,
      isFalse,
    );
  });

  testWidgets(
    'pickup displays immediately; route failure retains both markers',
    (tester) async {
      final previous = GoogleMapsFlutterPlatform.instance;
      GoogleMapsFlutterPlatform.instance = _Maps();
      addTearDown(() => GoogleMapsFlutterPlatform.instance = previous);
      final route = Completer<RouteResult>();
      Future<RouteResult> load(LatLng a, LatLng b) => route.future;
      Widget page(LatLng? dropoff) => MaterialApp(
        home: Scaffold(
          body: BookingRoutePreviewMap(
            pickup: const LatLng(15, 121),
            dropoff: dropoff,
            loadRoute: load,
          ),
        ),
      );
      await tester.pumpWidget(page(null));
      expect(
        tester.widget<GoogleMap>(find.byType(GoogleMap)).markers,
        hasLength(1),
      );
      expect(find.text('Calculating route...'), findsNothing);
      await tester.pumpWidget(page(const LatLng(15.1, 121.1)));
      expect(
        tester.widget<GoogleMap>(find.byType(GoogleMap)).markers,
        hasLength(2),
      );
      expect(find.text('Calculating route...'), findsOneWidget);
      route.completeError(StateError('Directions unavailable'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<GoogleMap>(find.byType(GoogleMap)).markers,
        hasLength(2),
      );
      expect(find.text('Retry route'), findsOneWidget);
      expect(tester.getSize(find.byType(GoogleMap)).height, 220);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'late route response cannot overwrite newly selected coordinates',
    (tester) async {
      final previous = GoogleMapsFlutterPlatform.instance;
      GoogleMapsFlutterPlatform.instance = _Maps();
      addTearDown(() => GoogleMapsFlutterPlatform.instance = previous);
      final oldRoute = Completer<RouteResult>();
      final newRoute = Completer<RouteResult>();
      var calls = 0;
      Future<RouteResult> load(LatLng a, LatLng b) =>
          calls++ == 0 ? oldRoute.future : newRoute.future;
      Widget page(double latitude) => MaterialApp(
        home: Scaffold(
          body: BookingRoutePreviewMap(
            pickup: const LatLng(15, 121),
            dropoff: LatLng(latitude, 121),
            loadRoute: load,
          ),
        ),
      );
      await tester.pumpWidget(page(15.1));
      await tester.pumpWidget(page(15.2));
      newRoute.complete(
        const RouteResult(
          points: [LatLng(15, 121), LatLng(15.2, 121)],
          durationText: '5 min',
        ),
      );
      await tester.pump();
      oldRoute.complete(
        const RouteResult(
          points: [LatLng(15, 121), LatLng(15.1, 121)],
          durationText: '3 min',
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .polylines
            .single
            .points
            .last,
        const LatLng(15.2, 121),
      );
      await tester.pumpWidget(const SizedBox());
    },
  );
}
