import 'package:touristrike/core/places/booking_service_area.dart';

// Synthetic boundary solely for tests; production geometry comes from Supabase.
final testAreaJson = <String, dynamic>{
  'id': 'test-area',
  'municipality': 'Bustos',
  'province': 'Bulacan',
  'version': 'test-v1',
  'geometry': {
    'type': 'Polygon',
    'coordinates': [
      [
        [120.90, 14.90],
        [120.99, 14.90],
        [120.99, 15.00],
        [120.90, 15.00],
        [120.90, 14.90],
      ],
    ],
  },
};
final testServiceArea = BookingServiceArea.fromJson(testAreaJson);
