import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:touristrike/core/notifications/notification_diagnostics.dart';
import 'package:touristrike/core/places/google_maps_api_key_resolver.dart';
import 'package:touristrike/core/places/google_places_diagnostics.dart';
import 'package:touristrike/core/places/google_places_errors.dart';
import 'package:touristrike/core/places/google_places_gateway_mobile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('touristrike/config');
  const key = 'test-device-secret-never-log';
  final logs = <String>[];
  late DebugPrintCallback previousPrint;
  var nativeRequests = 0;
  var nativeKey = key;

  setUp(() {
    logs.clear();
    nativeRequests = 0;
    nativeKey = key;
    GoogleMapsApiKeyResolver.resetForTesting();
    previousPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) logs.add(message);
    };
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getGoogleMapsApiKey') {
            nativeRequests++;
            return nativeKey;
          }
          if (call.method == 'getGooglePlacesDiagnosticContext') {
            return {
              'package_name': 'com.example.touristrike',
              'native_key_sha256': 'safe-hash',
              'signing_sha1': 'safe-certificate',
            };
          }
          throw MissingPluginException();
        });
  });

  tearDown(() {
    debugPrint = previousPrint;
    GoogleMapsApiKeyResolver.resetForTesting();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'Android resolves manifest channel key, shares and caches lookup',
    () async {
      final keys = await Future.wait([
        GoogleMapsApiKeyResolver.resolve(),
        GoogleMapsApiKeyResolver.resolve(),
      ]);
      expect(keys, [key, key]);
      expect(await GoogleMapsApiKeyResolver.resolve(), key);
      expect(nativeRequests, 1);
      expect(GoogleMapsApiKeyResolver.sourceFor(key), contains('native'));
    },
  );

  test('explicit key overrides native configuration', () async {
    expect(
      await GoogleMapsApiKeyResolver.resolve(explicitKey: ' override '),
      'override',
    );
    expect(nativeRequests, 0);
    expect(
      GoogleMapsApiKeyResolver.sourceFor('override'),
      'explicitly injected key',
    );
  });

  test('missing native config can recover without restart', () async {
    nativeKey = '';
    expect(await GoogleMapsApiKeyResolver.resolve(), '');
    expect(GoogleMapsApiKeyResolver.sourceFor(''), 'unavailable');
    nativeKey = key;
    expect(await GoogleMapsApiKeyResolver.resolve(), key);
    expect(nativeRequests, 2);
  });

  test('temporarily missing channel can recover without restart', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    expect(await GoogleMapsApiKeyResolver.resolve(), '');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => key);
    expect(await GoogleMapsApiKeyResolver.resolve(), key);
  });

  test('missing key makes no HTTP request and emits safe context', () async {
    nativeKey = '';
    var requests = 0;
    final client = MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    });
    await expectLater(
      GooglePlacesGateway(apiKey: '', client: client).request('textSearch', {}),
      throwsA(
        isA<GooglePlacesException>().having(
          (e) => e.kind,
          'kind',
          GooglePlacesFailureKind.notConfigured,
        ),
      ),
    );
    expect(requests, 0);
    expect(logs.single, contains('NOT_CONFIGURED'));
    expect(logs.single, contains('"key_present":false'));
  });

  test(
    'native Home uses Places API New and classifies billing failures',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.host, 'places.googleapis.com');
        expect(request.url.path, '/v1/places:searchText');
        expect(request.headers['x-goog-api-key'], key);
        expect(request.headers['x-goog-fieldmask'], contains('places.id'));
        expect(jsonDecode(request.body)['textQuery'], 'Baliwag');
        return http.Response(
          jsonEncode({
            'error': {
              'status': 'PERMISSION_DENIED',
              'message': 'You must enable Billing on the Google Cloud Project',
            },
          }),
          403,
        );
      });
      await expectLater(
        GooglePlacesGateway(
          apiKey: '',
          client: client,
        ).request('textSearch', {'query': 'Baliwag'}),
        throwsA(
          isA<GooglePlacesException>().having(
            (e) => e.kind,
            'kind',
            GooglePlacesFailureKind.billing,
          ),
        ),
      );
      expect(logs.single, contains('"http_status":403'));
      expect(logs.single, contains('PERMISSION_DENIED'));
      expect(logs.single, contains('enable Billing'));
      expect(logs.single, contains('native application configuration'));
      expect(logs.single, contains('safe-hash'));
      expect(logs.single, isNot(contains(key)));
    },
  );

  for (final code in [401, 403]) {
    test(
      'HTTP $code permission failure maps unauthorized with original error',
      () async {
        final client = MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': {
                'status': 'PERMISSION_DENIED',
                'message': 'Permission denied',
              },
            }),
            code,
          ),
        );
        await expectLater(
          GooglePlacesGateway(
            apiKey: key,
            client: client,
          ).request('nearbySearch', {}),
          throwsA(
            isA<GooglePlacesException>().having(
              (e) => e.kind,
              'kind',
              GooglePlacesFailureKind.unauthorized,
            ),
          ),
        );
        expect(logs.single, contains('PERMISSION_DENIED'));
        expect(logs.single, contains('Permission denied'));
        expect(logs.single, contains('"http_status":$code'));
      },
    );
  }

  test(
    'legacy endpoint diagnostics remain distinct from API enablement',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {
              'status': 'FAILED_PRECONDITION',
              'message': 'This request is calling a legacy API endpoint.',
            },
          }),
          400,
        ),
      );
      await expectLater(
        GooglePlacesGateway(
          apiKey: key,
          client: client,
        ).request('textSearch', {}),
        throwsA(
          isA<GooglePlacesException>().having(
            (e) => e.kind,
            'kind',
            GooglePlacesFailureKind.legacyEndpoint,
          ),
        ),
      );
    },
  );

  for (final entry in {
    429: GooglePlacesFailureKind.rateLimited,
    400: GooglePlacesFailureKind.invalidRequest,
    500: GooglePlacesFailureKind.upstream,
  }.entries) {
    test('HTTP ${entry.key} retains error mapping', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'status': 'ERROR', 'message': 'Request failed'},
          }),
          entry.key,
        ),
      );
      await expectLater(
        GooglePlacesGateway(apiKey: key, client: client).request('details', {}),
        throwsA(
          isA<GooglePlacesException>().having(
            (e) => e.kind,
            'kind',
            entry.value,
          ),
        ),
      );
    });
  }

  test(
    'Places API New search response is normalized for existing callers',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/v1/places:searchText');
        return http.Response(
          jsonEncode({
            'places': [
              {
                'id': 'place-1',
                'displayName': {'text': 'Bustos Heritage Park'},
                'formattedAddress': 'Bustos, Bulacan, Philippines',
                'location': {'latitude': 14.95, 'longitude': 120.91},
                'photos': [
                  {'name': 'places/place-1/photos/photo-1'},
                ],
                'types': ['tourist_attraction'],
              },
            ],
          }),
          200,
        );
      });
      final body = await GooglePlacesGateway(
        apiKey: key,
        client: client,
      ).request('textSearch', {'query': 'Bustos'});
      expect(body['status'], 'OK');
      final result = (body['results'] as List).single as Map;
      expect(result['place_id'], 'place-1');
      expect(result['name'], 'Bustos Heritage Park');
      expect(
        ((result['photos'] as List).single as Map)['photo_reference'],
        'places/place-1/photos/photo-1',
      );
    },
  );

  test('photo URLs use Places API New media resources', () {
    final url = GooglePlacesGateway(
      apiKey: key,
    ).photoUrl('places/place-1/photos/photo-1');
    expect(url, startsWith('https://places.googleapis.com/v1/'));
    expect(url, contains('/photos/photo-1/media'));
    expect(url, isNot(contains('/maps/api/place/photo')));
  });

  test('network failure never logs exception containing keyed URL', () async {
    final client = MockClient(
      (request) async =>
          throw http.ClientException('Failed: $key', request.url),
    );
    await expectLater(
      GooglePlacesGateway(
        apiKey: key,
        client: client,
      ).request('autocomplete', {}),
      throwsA(
        isA<GooglePlacesException>().having(
          (e) => e.kind,
          'kind',
          GooglePlacesFailureKind.network,
        ),
      ),
    );
    expect(logs.single, contains('NETWORK_FAILURE'));
    expect(logs.single, isNot(contains(key)));
    expect(logs.single, isNot(contains('key=')));
  });

  test(
    'diagnostics strip URL query and redact upstream echoed credentials',
    () async {
      await GooglePlacesDiagnostics.record(
        operation: 'textSearch',
        endpoint:
            'https://places.googleapis.com/v1/places:searchText?key=$key&query=private#fragment',
        key: key,
        httpStatus: 200,
        googleStatus: 'REQUEST_DENIED',
        googleMessage:
            'Rejected $key and AI'
            'zaAnotherCredential12345; api_key=other-secret\nretry',
      );
      final log = logs.single;
      expect(log, isNot(contains(key)));
      expect(log, isNot(contains('AIza')));
      expect(log, isNot(contains('other-secret')));
      expect(log, isNot(contains('private')));
      expect(log, isNot(contains('#fragment')));
      expect(
        log,
        contains(
          '"endpoint":"https://places.googleapis.com/v1/places:searchText"',
        ),
      );
    },
  );

  test('unreadable Google response remains sanitized and retryable', () async {
    final client = MockClient(
      (_) async => http.Response('<html>$key</html>', 502),
    );
    await expectLater(
      GooglePlacesGateway(apiKey: key, client: client).request('geocode', {}),
      throwsA(
        isA<GooglePlacesException>().having(
          (e) => e.canRetry,
          'retryable',
          isTrue,
        ),
      ),
    );
    expect(logs.single, contains('UNREADABLE_RESPONSE'));
    expect(logs.single, isNot(contains(key)));
  });

  test(
    'Firebase initialization captures real platform code and safe message',
    () {
      NotificationDiagnostics().failure(
        'Firebase initialization',
        PlatformException(
          code: 'Exception',
          message: 'Failed to load FirebaseOptions from resource. key=$key',
        ),
      );
      expect(logs.join(), contains('code=Exception'));
      expect(logs.join(), contains('Failed to load FirebaseOptions'));
      expect(logs.join(), isNot(contains(key)));
      expect(logs.join(), contains('FCM push unavailable'));
    },
  );
}
