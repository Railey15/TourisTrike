import 'package:flutter/foundation.dart';

class TouristSavedPlace {
  const TouristSavedPlace({
    required this.id,
    required this.label,
    required this.address,
    required this.tag,
    this.latitude,
    this.longitude,
    this.imageUrl,
    this.rating,
  });

  final String id;
  final String label;
  final String address;
  final String tag;
  final double? latitude;
  final double? longitude;
  final String? imageUrl;
  final double? rating;

  TouristSavedPlace copyWith({
    String? label,
    String? address,
    String? tag,
    double? latitude,
    double? longitude,
    String? imageUrl,
    double? rating,
  }) {
    return TouristSavedPlace(
      id: id,
      label: label ?? this.label,
      address: address ?? this.address,
      tag: tag ?? this.tag,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      imageUrl: imageUrl ?? this.imageUrl,
      rating: rating ?? this.rating,
    );
  }
}

class TouristSavedPlacesStore extends ValueNotifier<List<TouristSavedPlace>> {
  TouristSavedPlacesStore() : super(const []);

  bool isSaved(String id) => value.any((place) => place.id == id);

  void addOrUpdate(TouristSavedPlace place) {
    final next = [...value];
    final index = next.indexWhere((item) => item.id == place.id);

    if (index == -1) {
      next.add(place);
    } else {
      next[index] = place;
    }

    value = List.unmodifiable(next);
  }

  void remove(String id) {
    value = List.unmodifiable(value.where((place) => place.id != id));
  }

  bool toggle(TouristSavedPlace place) {
    if (isSaved(place.id)) {
      remove(place.id);
      return false;
    }

    addOrUpdate(place);
    return true;
  }
}

final touristSavedPlacesStore = TouristSavedPlacesStore();
