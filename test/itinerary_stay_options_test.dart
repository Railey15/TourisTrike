import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/itinerary_stay_options.dart';

void main() {
  test('all controlled stay options remain integer minutes', () {
    expect(ItineraryStayOptions.minutes, [15, 30, 45, 60, 90, 120, 150, 180]);
    expect(ItineraryStayOptions.label(15), '15 minutes');
    expect(ItineraryStayOptions.label(60), '1 hour');
    expect(ItineraryStayOptions.label(90), '1 hour 30 minutes');
    expect(ItineraryStayOptions.label(120), '2 hours');
    expect(ItineraryStayOptions.label(150), '2 hours 30 minutes');
    expect(ItineraryStayOptions.label(180), '3 hours');
  });

  test(
    'an existing spot recommendation selects the closest valid duration',
    () {
      expect(ItineraryStayOptions.nearest(60), 60);
      expect(ItineraryStayOptions.nearest(100), 90);
      expect(ItineraryStayOptions.nearest(200), 180);
    },
  );
}
