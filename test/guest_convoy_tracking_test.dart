import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
// ignore: depend_on_referenced_packages
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/services/booking_driver_markers.dart';
import 'package:touristrike/core/services/itinerary_schedule_service.dart';
import 'package:touristrike/core/services/route_polyline_service.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/guest/guest_trip_tracking_screen.dart';
import 'package:touristrike/widgets/convoy/convoy_tourist_driver_list.dart';
import 'package:touristrike/widgets/live_itinerary_estimates.dart';

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

class _Routes extends RoutePolylineService {
  _Routes() : super(apiKey: 'test');
  final origins = <LatLng>[];
  @override
  Future<RouteResult> fetchRoute(
    LatLng origin,
    LatLng dest, {
    List<LatLng> waypoints = const [],
  }) async {
    origins.add(origin);
    return RouteResult(points: [origin, dest], durationText: '6 min');
  }
}

// Widget tests use Flutter's fake clock; keep PostgREST's background JSON
// isolate in the separate real-async repository test below.
class _GuestRepository extends TourisTrikeRepository {
  _GuestRepository(this.read, SupabaseClient client) : super(client: client);
  final Map<String, dynamic> Function() read;
  var refreshes = 0;
  @override
  Future<GuestTripDetails?> validateGuestTripLink({
    required String publicToken,
    required String accessCode,
    String? deviceInfo,
    String? userAgent,
    bool silent = false,
  }) async {
    expect(publicToken, 'token');
    expect(accessCode, 'code');
    expect(silent, true);
    refreshes++;
    final payload = read();
    if (payload['error'] != null) throw StateError('Revoked');
    return GuestTripDetails.fromJson(payload);
  }
}

Map<String, dynamic> _payload(int count) => {
  'booking_id': 'booking',
  'tour_status': 'driver_en_route',
  'booking_status': 'accepted',
  'pickup_latitude': 15.1,
  'pickup_longitude': 121.1,
  'dropoff_latitude': 15.2,
  'dropoff_longitude': 121.2,
  'pickup_landmark': 'Pickup Area',
  'dropoff_landmark': 'Dropoff Area',
  'itinerary_items': [
    {
      'name': 'Cafe',
      'order': 1,
      'status': 'pending',
      'latitude': 15.15,
      'longitude': 121.15,
      'estimated_stay_duration_minutes': 60,
    },
  ],
  'drivers': [
    for (var i = 0; i < count; i++)
      <String, dynamic>{
        'driver_id': 'd$i',
        'driver_name': 'Driver ${i + 1}',
        'plate_number': 'ABC-$i',
        'toda_name': 'Bustos TODA',
        'status': 'accepted',
        'journey_state': 'en_route_pickup',
        'current_stop_index': 0,
        'state_updated_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'latitude': 15.0 + i / 100,
        'longitude': 121.0 + i / 100,
        'phone': 'PRIVATE',
        'license_number': 'PRIVATE',
      },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SupabaseClient widgetClient;
  setUpAll(() {
    widgetClient = SupabaseClient(
      'https://test.invalid',
      'test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        fail('Guest UI attempted an unexpected database request.');
      }),
    );
  });
  tearDownAll(() => widgetClient.dispose());
  test(
    'repository reads the complete roster only through the validated RPC',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'https://test.invalid',
        'test',
        httpClient: MockClient((request) async {
          requests.add(request);
          expect(request.url.path, '/rest/v1/rpc/get_shared_trip_details');
          final args = jsonDecode(request.body) as Map;
          expect(args['p_public_token'], 'token');
          expect(args['p_access_code'], 'code');
          expect(args['p_silent'], true);
          return http.Response(
            jsonEncode(_payload(2)),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      try {
        final details = await TourisTrikeRepository(client: client)
            .validateGuestTripLink(
              publicToken: 'token',
              accessCode: 'code',
              silent: true,
            );
        expect(details!.drivers, hasLength(2));
        expect(requests, hasLength(1));
      } finally {
        await client.dispose();
      }
    },
  );
  test(
    'guest projection keeps safe identity, freshness and same ETA inputs',
    () {
      final details = GuestTripDetails.fromJson(_payload(2));
      expect(details.drivers.map((d) => d.driverName), [
        'Driver 1',
        'Driver 2',
      ]);
      expect(details.drivers.every((d) => d.phoneNumber.isEmpty), isTrue);
      expect(details.drivers.every((d) => d.lastLocationAt != null), isTrue);
      expect(details.trackingBooking.pickupLatitude, 15.1);
      expect(details.trackingStops.single.destinationName, 'Cafe');
      expect(details.trackingStops.single.estimatedStayDurationMinutes, 60);
      final markers = buildBookingDriverMarkers(
        drivers: details.drivers,
        icon: BitmapDescriptor.defaultMarker,
      );
      expect(markers.map((m) => m.markerId.value).toSet(), {
        'driver_d0',
        'driver_d1',
      });
    },
  );

  for (final count in [1, 2]) {
    testWidgets(
      '$count drivers: roster, markers, routes, ETA and token-scoped refresh',
      (tester) async {
        final previous = GoogleMapsFlutterPlatform.instance;
        GoogleMapsFlutterPlatform.instance = _Maps();
        addTearDown(() => GoogleMapsFlutterPlatform.instance = previous);
        await tester.binding.setSurfaceSize(const Size(430, 1800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var payload = _payload(count);
        final repository = _GuestRepository(() => payload, widgetClient);
        final routes = _Routes();
        final etaOrigins = <LatLng>[];
        final etaService = ItineraryScheduleService.live(
          apiKey: 'test',
          directionsLoader: (_, points) async {
            etaOrigins.add(points.first);
            return {
              'status': 'OK',
              'routes': [
                {
                  'legs': [
                    {
                      'duration': {
                        'value': points.first.latitude == 15 ? 360 : 480,
                      },
                      'distance': {'value': 1000},
                    },
                  ],
                },
              ],
            };
          },
        );
        await tester.pumpWidget(
          MaterialApp(
            home: GuestTripTrackingScreen(
              publicToken: 'token',
              accessCode: 'code',
              initialDetails: GuestTripDetails.fromJson(payload),
              repository: repository,
              routeService: routes,
              etaService: etaService,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Drivers ($count)'), findsOneWidget);
        expect(find.byType(LiveItineraryEstimates), findsOneWidget);
        expect(find.textContaining('Pickup ETA:'), findsNWidgets(count));
        expect(etaOrigins.toSet(), hasLength(count));
        expect(routes.origins.toSet(), hasLength(count));
        Set<Marker> drivers() => tester
            .widget<GoogleMap>(find.byType(GoogleMap))
            .markers
            .where((m) => m.markerId.value.startsWith('driver_'))
            .toSet();
        expect(drivers(), hasLength(count));
        expect(drivers().map((m) => m.markerId.value).toSet(), {
          for (var i = 0; i < count; i++) 'driver_d$i',
        });
        expect(find.byIcon(Icons.call_rounded), findsNothing);
        expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
        expect(
          tester
              .widget<ConvoyTouristDriverList>(
                find.byType(ConvoyTouristDriverList),
              )
              .guestView,
          true,
        );

        final rows = payload['drivers'] as List;
        rows[0]['latitude'] = 15.05;
        if (count == 2) rows[1]['latitude'] = 15.07;
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(
          drivers()
              .singleWhere((m) => m.markerId.value == 'driver_d0')
              .position
              .latitude,
          15.05,
        );
        if (count == 2) {
          expect(
            drivers()
                .singleWhere((m) => m.markerId.value == 'driver_d1')
                .position
                .latitude,
            15.07,
          );
          rows[1]['latitude'] = null;
          rows[1]['longitude'] = null;
          await tester.pump(const Duration(seconds: 5));
          await tester.pumpAndSettle();
          expect(find.text('Drivers (2)'), findsOneWidget);
          expect(drivers(), hasLength(1));
        }
        expect(repository.refreshes, greaterThan(0));
        // There is no guest write endpoint behind map/roster selection.
        await tester.tap(find.byType(ConvoyTouristDriverList));
        await tester.pumpAndSettle();
        expect(find.text('Confirm Pickup'), findsNothing);
        expect(find.text('Proceed to Next Stop'), findsNothing);
        final readsBeforeEmergency = repository.refreshes;
        await tester.ensureVisible(find.text('Emergency Assistance'));
        await tester.tap(find.text('Emergency Assistance'));
        await tester.pumpAndSettle();
        expect(find.textContaining('Call 911'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(repository.refreshes, readsBeforeEmergency);
        payload = {'error': 'invalid_or_expired', 'message': 'Revoked'};
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        expect(find.byType(GoogleMap), findsNothing);
        expect(
          find.text('Trip access or connection unavailable.'),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
}
