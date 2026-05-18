import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class TouristMunicipalityArea {
  final String name;
  final LatLng center;

  const TouristMunicipalityArea({required this.name, required this.center});
}

class TouristLocationSelection {
  final TouristMunicipalityArea? manualArea;

  const TouristLocationSelection({this.manualArea});

  bool get isManual => manualArea != null;
}

class TouristLocationStore extends ValueNotifier<TouristLocationSelection> {
  TouristLocationStore() : super(const TouristLocationSelection());

  bool _didOpenHomeThisSession = false;

  bool usePhoneLocationForFirstHomeOpen() {
    if (_didOpenHomeThisSession) return false;

    _didOpenHomeThisSession = true;
    if (!value.isManual) return false;

    value = const TouristLocationSelection();
    return true;
  }

  void useManualLocation(TouristMunicipalityArea area) {
    value = TouristLocationSelection(manualArea: area);
  }

  void usePhoneLocation() {
    value = const TouristLocationSelection();
  }
}

final touristLocationStore = TouristLocationStore();

const touristBulacanMunicipalities = [
  TouristMunicipalityArea(name: 'Bustos', center: LatLng(14.9597, 120.9206)),
  TouristMunicipalityArea(name: 'Baliwag', center: LatLng(14.9547, 120.8969)),
  TouristMunicipalityArea(name: 'Malolos', center: LatLng(14.8434, 120.8114)),
  TouristMunicipalityArea(name: 'Pulilan', center: LatLng(14.9017, 120.8492)),
  TouristMunicipalityArea(name: 'Plaridel', center: LatLng(14.8873, 120.8572)),
  TouristMunicipalityArea(
    name: 'San Rafael',
    center: LatLng(15.0265, 120.9283),
  ),
  TouristMunicipalityArea(
    name: 'San Ildefonso',
    center: LatLng(15.0809, 120.9410),
  ),
  TouristMunicipalityArea(
    name: 'San Miguel',
    center: LatLng(15.1458, 120.9783),
  ),
  TouristMunicipalityArea(name: 'Calumpit', center: LatLng(14.9164, 120.7658)),
  TouristMunicipalityArea(name: 'Hagonoy', center: LatLng(14.8340, 120.7328)),
  TouristMunicipalityArea(name: 'Paombong', center: LatLng(14.8319, 120.7897)),
  TouristMunicipalityArea(name: 'Guiguinto', center: LatLng(14.8333, 120.8833)),
  TouristMunicipalityArea(name: 'Balagtas', center: LatLng(14.8167, 120.8667)),
  TouristMunicipalityArea(name: 'Bocaue', center: LatLng(14.7983, 120.9261)),
  TouristMunicipalityArea(name: 'Marilao', center: LatLng(14.7581, 120.9481)),
  TouristMunicipalityArea(
    name: 'Meycauayan',
    center: LatLng(14.7369, 120.9608),
  ),
  TouristMunicipalityArea(
    name: 'Norzagaray',
    center: LatLng(14.9109, 121.0493),
  ),
  TouristMunicipalityArea(
    name: 'Santa Maria',
    center: LatLng(14.8208, 120.9636),
  ),
  TouristMunicipalityArea(name: 'Angat', center: LatLng(14.9285, 121.0292)),
  TouristMunicipalityArea(name: 'Pandi', center: LatLng(14.8650, 120.9572)),
  TouristMunicipalityArea(name: 'Obando', center: LatLng(14.7098, 120.9362)),
  TouristMunicipalityArea(name: 'Bulakan', center: LatLng(14.7928, 120.8789)),
  TouristMunicipalityArea(
    name: 'Dona Remedios Trinidad',
    center: LatLng(15.0005, 121.0838),
  ),
  TouristMunicipalityArea(
    name: 'San Jose del Monte',
    center: LatLng(14.8139, 121.0453),
  ),
];
