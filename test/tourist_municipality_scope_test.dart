import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/screens/tourist/tourist_available_municipalities.dart';
import 'package:touristrike/screens/tourist/tourist_location_state.dart';

void main() {
  test('Google addresses require the chosen municipality component', () {
    expect(
      CitySpotSuggestionService.matchesMunicipalityAddress(
        address: 'Museum Road, Bustos, Bulacan, Philippines',
        city: 'Bustos',
      ),
      isTrue,
    );
    expect(
      CitySpotSuggestionService.matchesMunicipalityAddress(
        address: 'Bustos Road, Plaridel, Bulacan, Philippines',
        city: 'Bustos',
      ),
      isFalse,
    );
    expect(
      CitySpotSuggestionService.matchesMunicipalityAddress(
        address: 'Museum, Pulilan, Bulacan, Philippines',
        city: 'Bustos',
      ),
      isFalse,
    );
    expect(
      CitySpotSuggestionService.matchesMunicipalityAddress(
        address: 'Museum, Plaridel, Bulacan, Philippines',
        city: 'Plaridel',
      ),
      isTrue,
    );
    expect(
      CitySpotSuggestionService.matchesMunicipalityAddress(
        address: 'Museum, Plaridel, Bulacan, Philippines',
        city: 'Bulakan',
      ),
      isFalse,
    );
  });

  test('only municipalities represented by eligible rows are available', () {
    final available = availableMunicipalitiesFromActiveSpotRows([
      {'municipality': 'Bustos', 'city': 'Bustos'},
      {'municipality': 'Municipality of Plaridel', 'city': 'Bustos'},
    ]);
    expect(available, containsAll(['Bustos', 'Plaridel']));
    expect(available, isNot(contains('Pulilan')));
  });

  test(
    'the saved spot municipality takes precedence over a conflicting city',
    () {
      expect(
        CitySpotSuggestionService.matchesMunicipalityName(
          'Municipality of Plaridel',
          'Bustos',
        ),
        isFalse,
      );
      expect(
        CitySpotSuggestionService.matchesMunicipalityName(
          'Municipality of Plaridel',
          'Plaridel',
        ),
        isTrue,
      );
    },
  );

  test(
    'manual municipality remains selected until phone location is chosen',
    () {
      final store = TouristLocationStore();
      const bustos = TouristMunicipalityArea(
        name: 'Bustos',
        center: LatLng(14.9597, 120.9206),
      );
      store.useManualLocation(bustos);
      expect(store.value.manualArea?.name, 'Bustos');
      store.usePhoneLocation();
      expect(store.value.manualArea, isNull);
      store.dispose();
    },
  );
}
