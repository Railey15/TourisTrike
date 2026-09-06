import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('web Places transport only invokes the Supabase proxy', () {
    final webGateway = _read('lib/core/places/google_places_gateway_web.dart');
    final cityService = _read('lib/core/places/city_spot_suggestions.dart');

    expect(webGateway, contains("'google-places'"));
    expect(webGateway, contains('Supabase.instance.client.functions'));
    expect(webGateway, isNot(contains('maps.googleapis.com')));
    expect(cityService, isNot(contains('/maps/api/place/')));
  });

  test('web build inputs contain no committed Google key', () {
    final index = _read('web/index.html');
    final manifest = _read('android/app/src/main/AndroidManifest.xml');
    final infoPlist = _read('ios/Runner/Info.plist');
    final pubspec = _read('pubspec.yaml');

    expect(index, isNot(contains('AIza')));
    expect(index, contains("if (!mapsBrowserKey.startsWith('__'))"));
    expect(manifest, isNot(contains('AIza')));
    expect(infoPlist, isNot(contains('AIza')));
    expect(
      pubspec,
      isNot(matches(RegExp(r'^\s+- \.env\s*$', multiLine: true))),
    );
  });

  test('Edge Function uses server secrets and signed media URLs', () {
    final edgeFunction = _read('supabase/functions/google-places/index.ts');

    expect(edgeFunction, contains('GOOGLE_MAPS_API_KEY'));
    expect(edgeFunction, contains('GOOGLE_MAPS_PROXY_SIGNING_SECRET'));
    expect(edgeFunction, contains('HMAC'));
    expect(edgeFunction, contains('RATE_LIMITED'));
    expect(edgeFunction, contains('GOOGLE_UNAUTHORIZED'));
    expect(edgeFunction, contains('ZERO_RESULTS'));
  });
}
