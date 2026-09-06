import 'google_places_gateway.dart';

Future<String> secureGoogleMediaUrl({
  required String imageUrl,
  String photoReference = '',
  double? latitude,
  double? longitude,
}) async {
  final original = imageUrl.trim();
  final uri = Uri.tryParse(original);
  if (uri == null || uri.host.toLowerCase() != 'maps.googleapis.com') {
    return original;
  }

  final gateway = GooglePlacesGateway(apiKey: '');
  try {
    if (uri.path == '/maps/api/place/photo') {
      final reference = photoReference.trim().isNotEmpty
          ? photoReference.trim()
          : (uri.queryParameters['photo_reference'] ?? '').trim();
      return reference.isEmpty ? '' : gateway.photoProxyUrl(reference);
    }

    if (uri.path == '/maps/api/staticmap' &&
        latitude != null &&
        longitude != null) {
      return gateway.staticMapProxyUrl(
        latitude: latitude,
        longitude: longitude,
      );
    }
  } catch (_) {
    // A failed signing request must not fall back to exposing/requesting the
    // legacy server-key URL in the browser.
    return '';
  }

  // Never allow a server-key Google media URL to be requested by the browser.
  return '';
}
