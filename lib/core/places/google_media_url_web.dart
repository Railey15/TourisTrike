import 'google_places_gateway.dart';

Future<String> secureGoogleMediaUrl({
  required String imageUrl,
  String photoReference = '',
  double? latitude,
  double? longitude,
}) async {
  final original = imageUrl.trim();
  final uri = Uri.tryParse(original);
  if (uri == null) return original;
  final host = uri.host.toLowerCase();
  if (host != 'maps.googleapis.com' && host != 'places.googleapis.com') {
    return original;
  }

  final gateway = GooglePlacesGateway(apiKey: '');
  try {
    if (uri.path == '/maps/api/place/photo' ||
        (host == 'places.googleapis.com' && uri.path.endsWith('/media'))) {
      final reference = photoReference.trim().isNotEmpty
          ? photoReference.trim()
          : uri.path.startsWith('/v1/places/')
          ? uri.path.substring('/v1/'.length).replaceFirst('/media', '')
          : (uri.queryParameters['photo_reference'] ?? '').trim();
      return reference.isEmpty ? '' : gateway.photoProxyUrl(reference);
    }

    if (uri.path == '/maps/api/staticmap') return '';
  } catch (_) {
    // A failed signing request must not fall back to exposing/requesting the
    // legacy server-key URL in the browser.
    return '';
  }

  // Never allow a server-key Google media URL to be requested by the browser.
  return '';
}
