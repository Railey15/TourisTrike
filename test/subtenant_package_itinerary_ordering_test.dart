import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_package_itinerary_ordering.dart';

void main() {
  group('package itinerary ordering', () {
    test('first stop renders at top in ascending sequence order', () {
      final items = packageItineraryItemsInSequence([
        _item(_starbucks, 2, '8:10 AM'),
        _item(_garden, 1, '7:35 AM'),
        _item(_cafe, 0, '7:00 AM'),
      ]);

      expect(_itemTitles(items), [
        'Cafe Supremo',
        'iPlant Garden & Café',
        'Starbucks DRT',
      ]);
      expect(items.map((item) => item.timeLabel), [
        '7:00 AM',
        '7:35 AM',
        '8:10 AM',
      ]);
    });

    test('stored list order is retained without authoritative positions', () {
      final items = packageItineraryItemsInSequence([
        _item(_garden, 0, '7:00 AM'),
        _item(_cafe, 0, '7:35 AM'),
        _item(_starbucks, 0, '8:10 AM'),
      ]);

      expect(_itemTitles(items), [
        'iPlant Garden & Café',
        'Cafe Supremo',
        'Starbucks DRT',
      ]);
    });

    test('move up swaps only with the previous stop', () {
      final result = reorderPackageItineraryStops(
        selectedSpots: _selectedSpots(),
        day: _day(),
        oldIndex: 2,
        newIndex: 1,
      );

      expect(result.changed, isTrue);
      expect(_spotTitles(result.selectedSpots), [
        'Cafe Supremo',
        'Starbucks DRT',
        'iPlant Garden & Café',
      ]);
    });

    test('move down swaps only with the next stop', () {
      final result = reorderPackageItineraryStops(
        selectedSpots: _selectedSpots(),
        day: _day(),
        oldIndex: 0,
        newIndex: 1,
      );

      expect(result.changed, isTrue);
      expect(_spotTitles(result.selectedSpots), [
        'iPlant Garden & Café',
        'Cafe Supremo',
        'Starbucks DRT',
      ]);
    });

    test('first stop cannot move up', () {
      final result = reorderPackageItineraryStops(
        selectedSpots: _selectedSpots(),
        day: _day(),
        oldIndex: 0,
        newIndex: -1,
      );

      expect(result.changed, isFalse);
      expect(_spotTitles(result.selectedSpots), _initialTitles);
    });

    test('last stop cannot move down', () {
      final result = reorderPackageItineraryStops(
        selectedSpots: _selectedSpots(),
        day: _day(),
        oldIndex: 2,
        newIndex: 3,
      );

      expect(result.changed, isFalse);
      expect(_spotTitles(result.selectedSpots), _initialTitles);
    });

    test('reorder recalculates every displayed arrival and departure', () {
      final result = reorderPackageItineraryStops(
        selectedSpots: _selectedSpots(
          arrivals: const ['8:10 AM', '7:35 AM', '7:00 AM'],
        ),
        day: _day(),
        oldIndex: 0,
        newIndex: 1,
      );

      expect(result.selectedSpots.map((spot) => spot.estimatedArrivalTime), [
        '7:00 AM',
        '7:35 AM',
        '8:10 AM',
      ]);
      expect(result.day.items.map((item) => item.timeLabel), [
        '7:00 AM',
        '7:35 AM',
        '8:10 AM',
      ]);
      expect(result.day.items.map((item) => item.note), [
        'Stay 15 mins - Leave 7:15 AM',
        'Stay 15 mins - Leave 7:50 AM',
        'Stay 15 mins - Leave 8:25 AM',
      ]);
    });

    test('persisted order survives a reload round trip', () {
      final reordered = reorderPackageItineraryStops(
        selectedSpots: _selectedSpots(),
        day: _day(),
        oldIndex: 0,
        newIndex: 1,
      );
      final reloadedSpots = packageSelectedSpotsInSequence([
        for (final spot in reordered.selectedSpots.reversed)
          SelectedPackageSpot(
            spot: spot.spot,
            sortOrder: spot.sortOrder,
            estimatedArrivalTime: spot.estimatedArrivalTime,
            estimatedDurationMinutes: spot.estimatedDurationMinutes,
          ),
      ]);
      final reloadedItems = packageItineraryItemsInSequence(
        reordered.day.items.reversed,
      );

      expect(_spotTitles(reloadedSpots), [
        'iPlant Garden & Café',
        'Cafe Supremo',
        'Starbucks DRT',
      ]);
      expect(_itemTitles(reloadedItems), _spotTitles(reloadedSpots));
      expect(reloadedItems.map((item) => item.timeLabel), [
        '7:00 AM',
        '7:35 AM',
        '8:10 AM',
      ]);
    });

    test('reorder normalizes positions without duplicates or gaps', () {
      final result = reorderPackageItineraryStops(
        selectedSpots: _selectedSpots(sortOrders: const [8, 3, 3]),
        day: _day(sortOrders: const [8, 3, 3]),
        oldIndex: 2,
        newIndex: 1,
      );

      expect(result.selectedSpots.map((spot) => spot.sortOrder), [0, 1, 2]);
      expect(result.day.items.map((item) => item.sortOrder), [0, 1, 2]);
      expect(result.day.items.map((item) => item.sortOrder).toSet().length, 3);
    });

    test('preview and editor consume the same authoritative order', () {
      final selected = _selectedSpots(sortOrders: const [2, 0, 1]);
      final day = _day(sortOrders: const [2, 0, 1]);

      final previewOrder = _spotTitles(
        packageSelectedSpotsInSequence(selected),
      );
      final editorOrder = _itemTitles(
        packageItineraryItemsInSequence(day.items),
      );

      expect(previewOrder, editorOrder);
    });
  });
}

const _initialTitles = <String>[
  'Cafe Supremo',
  'iPlant Garden & Café',
  'Starbucks DRT',
];

const _cafe = SubTenantSpot(
  id: 'cafe',
  title: 'Cafe Supremo',
  description: '',
  address: '',
  barangay: '',
  city: 'DRT',
  municipality: 'DRT',
  province: 'Bulacan',
  latitude: 0,
  longitude: 0,
  rating: 0,
  imageUrl: '',
  status: 'active',
  createdAt: null,
);

const _garden = SubTenantSpot(
  id: 'garden',
  title: 'iPlant Garden & Café',
  description: '',
  address: '',
  barangay: '',
  city: 'DRT',
  municipality: 'DRT',
  province: 'Bulacan',
  latitude: 0,
  longitude: 0,
  rating: 0,
  imageUrl: '',
  status: 'active',
  createdAt: null,
);

const _starbucks = SubTenantSpot(
  id: 'starbucks',
  title: 'Starbucks DRT',
  description: '',
  address: '',
  barangay: '',
  city: 'DRT',
  municipality: 'DRT',
  province: 'Bulacan',
  latitude: 0,
  longitude: 0,
  rating: 0,
  imageUrl: '',
  status: 'active',
  createdAt: null,
);

List<SelectedPackageSpot> _selectedSpots({
  List<int> sortOrders = const [0, 1, 2],
  List<String> arrivals = const ['7:00 AM', '7:35 AM', '8:10 AM'],
}) {
  final spots = [_cafe, _garden, _starbucks];
  return [
    for (var index = 0; index < spots.length; index++)
      SelectedPackageSpot(
        spot: spots[index],
        sortOrder: sortOrders[index],
        estimatedArrivalTime: arrivals[index],
        estimatedDurationMinutes: 15,
      ),
  ];
}

PackageItineraryDay _day({List<int> sortOrders = const [0, 1, 2]}) {
  final spots = [_cafe, _garden, _starbucks];
  const times = ['7:00 AM', '7:35 AM', '8:10 AM'];
  return PackageItineraryDay(
    id: 'day',
    dayNumber: 1,
    title: 'Day Tour',
    items: [
      for (var index = 0; index < spots.length; index++)
        _item(spots[index], sortOrders[index], times[index]),
    ],
  );
}

PackageItineraryItem _item(SubTenantSpot spot, int sortOrder, String time) {
  return PackageItineraryItem(
    id: 'item-${spot.id}',
    dayId: 'day',
    spotId: spot.id,
    spotTitle: spot.title,
    spotImageUrl: spot.imageUrl,
    timeLabel: time,
    note: '',
    sortOrder: sortOrder,
  );
}

List<String> _spotTitles(Iterable<SelectedPackageSpot> spots) =>
    spots.map((spot) => spot.spot.title).toList(growable: false);

List<String> _itemTitles(Iterable<PackageItineraryItem> items) =>
    items.map((item) => item.spotTitle).toList(growable: false);
