import 'package:touristrike/screens/subtenant/subtenant_models.dart';

const int packageItineraryStartMinutes = 7 * 60;
const int packageItineraryTravelMinutes = 20;

List<PackageItineraryItem> packageItineraryItemsInSequence(
  Iterable<PackageItineraryItem> items,
) {
  final indexed = items.indexed.toList(growable: false);
  if (indexed.every((entry) => entry.$2.sortOrder == 0)) {
    return indexed.map((entry) => entry.$2).toList(growable: false);
  }

  final sorted = [...indexed]
    ..sort((a, b) {
      final byOrder = a.$2.sortOrder.compareTo(b.$2.sortOrder);
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
  return sorted.map((entry) => entry.$2).toList(growable: false);
}

List<SelectedPackageSpot> packageSelectedSpotsInSequence(
  Iterable<SelectedPackageSpot> spots,
) {
  final indexed = spots.indexed.toList(growable: false);
  if (indexed.every((entry) => entry.$2.sortOrder == 0)) {
    return indexed.map((entry) => entry.$2).toList(growable: false);
  }

  final sorted = [...indexed]
    ..sort((a, b) {
      final byOrder = a.$2.sortOrder.compareTo(b.$2.sortOrder);
      return byOrder != 0 ? byOrder : a.$1.compareTo(b.$1);
    });
  return sorted.map((entry) => entry.$2).toList(growable: false);
}

class PackageItineraryReorderResult {
  const PackageItineraryReorderResult({
    required this.selectedSpots,
    required this.day,
    required this.changed,
  });

  final List<SelectedPackageSpot> selectedSpots;
  final PackageItineraryDay day;
  final bool changed;
}

List<SelectedPackageSpot> moveSelectedPackageStop(
  List<SelectedPackageSpot> selectedSpots,
  int oldIndex,
  int newIndex,
) {
  final ordered = packageSelectedSpotsInSequence(selectedSpots);
  if (oldIndex < 0 ||
      oldIndex >= ordered.length ||
      newIndex < 0 ||
      newIndex >= ordered.length ||
      oldIndex == newIndex) {
    return ordered;
  }

  final reordered = [...ordered];
  final moved = reordered.removeAt(oldIndex);
  reordered.insert(newIndex, moved);
  return recalculatePackageItinerarySchedule(reordered);
}

PackageItineraryReorderResult reorderPackageItineraryStops({
  required List<SelectedPackageSpot> selectedSpots,
  required PackageItineraryDay day,
  required int oldIndex,
  required int newIndex,
}) {
  final orderedItems = packageItineraryItemsInSequence(day.items);
  final alignedSpots = _alignSelectedSpots(orderedItems, selectedSpots);
  if (oldIndex < 0 ||
      oldIndex >= orderedItems.length ||
      newIndex < 0 ||
      newIndex >= orderedItems.length ||
      oldIndex == newIndex) {
    return PackageItineraryReorderResult(
      selectedSpots: alignedSpots,
      day: _dayWithItems(day, orderedItems),
      changed: false,
    );
  }

  final movedSpotId = stId(orderedItems[oldIndex].spotId);
  final sourceIndex = alignedSpots.indexWhere(
    (spot) => stId(spot.spot.id) == movedSpotId,
  );
  if (sourceIndex < 0) {
    return PackageItineraryReorderResult(
      selectedSpots: alignedSpots,
      day: _dayWithItems(day, orderedItems),
      changed: false,
    );
  }

  final scheduled = moveSelectedPackageStop(
    alignedSpots,
    sourceIndex,
    newIndex,
  );

  return PackageItineraryReorderResult(
    selectedSpots: scheduled,
    day: _rebuildDayFromSelectedSpots(day, orderedItems, scheduled),
    changed: true,
  );
}

List<SelectedPackageSpot> recalculatePackageItinerarySchedule(
  Iterable<SelectedPackageSpot> spots, {
  int startMinutes = packageItineraryStartMinutes,
  int travelMinutes = packageItineraryTravelMinutes,
}) {
  var cursor = startMinutes;
  final source = spots.toList(growable: false);
  final scheduled = <SelectedPackageSpot>[];
  for (var index = 0; index < source.length; index++) {
    final spot = source[index];
    scheduled.add(
      _copySelectedSpot(
        spot,
        sortOrder: index,
        estimatedArrivalTime: formatPackageItineraryTime(cursor),
      ),
    );
    cursor += _stayMinutes(spot) + travelMinutes;
  }
  return scheduled;
}

String formatPackageItineraryTime(int rawMinutes) {
  var minutes = rawMinutes;
  if (minutes < 0) minutes = 0;
  final hour24 = (minutes ~/ 60) % 24;
  final minute = minutes % 60;
  final meridiem = hour24 >= 12 ? 'PM' : 'AM';
  var hour12 = hour24 % 12;
  if (hour12 == 0) hour12 = 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $meridiem';
}

List<SelectedPackageSpot> _alignSelectedSpots(
  List<PackageItineraryItem> orderedItems,
  List<SelectedPackageSpot> selectedSpots,
) {
  final remaining = packageSelectedSpotsInSequence(selectedSpots).toList();
  final aligned = <SelectedPackageSpot>[];
  for (final item in orderedItems) {
    final index = remaining.indexWhere(
      (spot) => stId(spot.spot.id) == stId(item.spotId),
    );
    if (index >= 0) aligned.add(remaining.removeAt(index));
  }
  aligned.addAll(remaining);
  return aligned;
}

PackageItineraryDay _rebuildDayFromSelectedSpots(
  PackageItineraryDay day,
  List<PackageItineraryItem> existingItems,
  List<SelectedPackageSpot> selectedSpots,
) {
  final existingBySpotId = {
    for (final item in existingItems) stId(item.spotId): item,
  };
  final items = <PackageItineraryItem>[];
  var arrivalMinutes = packageItineraryStartMinutes;
  for (var index = 0; index < selectedSpots.length; index++) {
    final selectedSpot = selectedSpots[index];
    final existing = existingBySpotId[stId(selectedSpot.spot.id)];
    final stayMinutes = _stayMinutes(selectedSpot);
    final departureMinutes = arrivalMinutes + stayMinutes;
    items.add(
      PackageItineraryItem(
        id: existing?.id,
        dayId: day.id,
        spotId: selectedSpot.spot.id,
        spotTitle: existing?.spotTitle ?? selectedSpot.spot.title,
        spotImageUrl: existing?.spotImageUrl ?? selectedSpot.spot.imageUrl,
        timeLabel: selectedSpot.estimatedArrivalTime,
        note:
            'Stay $stayMinutes mins - Leave ${formatPackageItineraryTime(departureMinutes)}',
        sortOrder: index,
      ),
    );
    arrivalMinutes = departureMinutes + packageItineraryTravelMinutes;
  }
  return _dayWithItems(day, items);
}

PackageItineraryDay _dayWithItems(
  PackageItineraryDay day,
  List<PackageItineraryItem> items,
) {
  return PackageItineraryDay(
    id: day.id,
    dayNumber: day.dayNumber,
    title: day.title,
    items: items,
  );
}

SelectedPackageSpot _copySelectedSpot(
  SelectedPackageSpot source, {
  required int sortOrder,
  required String estimatedArrivalTime,
}) {
  return SelectedPackageSpot(
    spot: source.spot,
    sortOrder: sortOrder,
    openingTime: source.openingTime,
    closingTime: source.closingTime,
    estimatedArrivalTime: estimatedArrivalTime,
    estimatedDurationMinutes: source.estimatedDurationMinutes,
    recommendedVisitDurationMinutes: source.recommendedVisitDurationMinutes,
  );
}

int _stayMinutes(SelectedPackageSpot spot) {
  if (spot.estimatedDurationMinutes > 0) {
    return spot.estimatedDurationMinutes;
  }
  if (spot.recommendedVisitDurationMinutes > 0) {
    return spot.recommendedVisitDurationMinutes;
  }
  return 60;
}
