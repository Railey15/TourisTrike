import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/screens/tourist/spot_details_screen.dart';
import 'package:touristrike/screens/tourist/tourist_activity_tracking_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      anonKey: 'test',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });
  tearDownAll(() async => Supabase.instance.dispose());

  test('stored placeholder tails are removed without discarding real copy', () {
    expect(
      spotDescriptionForDisplay(
        'A garden cafe by the town square. Visitors can enjoy the area, take memorable photos, and experience one of the local highlights of the municipality.',
      ),
      'A garden cafe by the town square.',
    );
    expect(
      spotDescriptionForDisplay(
        'Nature destination suggestion for visitors exploring Baliwag, Bulacan.',
      ),
      'No description has been added for this destination yet.',
    );
  });

  testWidgets(
    'Share Trip is the last itinerary action and collapses when hidden',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final stops = [
        for (var i = 0; i < 5; i++)
          BookingItineraryItem({
            'id': i + 1,
            'destination_name': 'Destination ${i + 1}',
            'spot_status': 'pending',
          }),
      ];
      var shared = false;
      Widget card(VoidCallback? onShare) => MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: TourItineraryProgressCard(
              spots: stops,
              currentItemId: null,
              tourStatus: 'driver_accepted',
              onShare: onShare,
            ),
          ),
        ),
      );
      await tester.pumpWidget(card(() => shared = true));
      expect(find.text('Share this trip'), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Share this trip')).dy,
        greaterThan(tester.getTopLeft(find.text('Destination 5')).dy),
      );
      await tester.tap(find.text('Share'));
      expect(shared, true);
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(card(null));
      expect(find.text('Share this trip'), findsNothing);
      expect(find.byIcon(Icons.share_outlined), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'spot details handles long content and missing description without Share',
    (tester) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const spot = TouristSpotDetailsData(
        id: '1',
        title:
            'A very long destination title with accented Café characters and more words',
        address:
            'A long street address in a barangay with several landmarks, Baliwag, Bulacan',
        distance: '376m away',
        distanceKm: 0.376,
        tag: 'Nature',
        rating: 0,
        userRatingsTotal: 0,
        imageUrl: '',
        latitude: 14.8,
        longitude: 120.8,
        openNow: null,
        municipality: 'Baliwag',
        description:
            'Nature destination suggestion for visitors exploring Baliwag, Bulacan.',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
            child: const TouristSpotDetailsScreen(
              spot: spot,
              googleMapsApiKey: '',
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.ios_share_rounded), findsNothing);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      expect(
        find.text('No description has been added for this destination yet.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('destination suggestion for visitors'),
        findsNothing,
      );
      expect(
        tester.getBottomLeft(find.text(spot.title)).dy,
        lessThan(tester.getTopLeft(find.text('Ratings')).dy),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('spot specific long description stays intact', (tester) async {
    tester.view.physicalSize = const Size(420, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const description =
        'This is the actual description for this destination. '
        'It is long enough to span several lines and must remain attached to '
        'this spot, without generated municipality wording or clipped text.';
    const spot = TouristSpotDetailsData(
      id: '2',
      title: 'Cafe Test',
      address: 'Baliwag, Bulacan',
      distance: '1km away',
      distanceKm: 1,
      tag: 'Cafe',
      rating: 4.8,
      userRatingsTotal: 12,
      imageUrl: '',
      latitude: 14.8,
      longitude: 120.8,
      openNow: true,
      municipality: 'Baliwag',
      description: description,
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: TouristSpotDetailsScreen(spot: spot, googleMapsApiKey: ''),
      ),
    );
    expect(find.text(description), findsOneWidget);
    expect(find.text('Open in Maps'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed hero image falls back without disturbing details', (
    tester,
  ) async {
    const spot = TouristSpotDetailsData(
      id: '3',
      title: 'Photo fallback spot',
      address: 'Bustos, Bulacan',
      distance: 'Nearby',
      distanceKm: 0,
      tag: 'Nature',
      rating: 0,
      userRatingsTotal: 0,
      imageUrl: 'https://example.invalid/missing-photo.jpg',
      latitude: 14.8,
      longitude: 120.8,
      openNow: false,
      municipality: 'Bustos',
      description: 'A specific destination description.',
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: TouristSpotDetailsScreen(spot: spot, googleMapsApiKey: ''),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.image_not_supported_rounded), findsOneWidget);
    expect(find.text('Photo fallback spot'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
