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
    'native Home REST logs actual HTTP 200 REQUEST_DENIED and billing message',
    () async {
      final client = MockClient((request) async {
        expect(request.url.path, '/maps/api/place/textsearch/json');
        expect(request.url.queryParameters['key'], key);
        return http.Response(
          jsonEncode({
            'status': 'REQUEST_DENIED',
            'error_message':
                'You must enable Billing on the Google Cloud Project',
          }),
          200,
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
            GooglePlacesFailureKind.unauthorized,
          ),
        ),
      );
      expect(logs.single, contains('"http_status":200'));
      expect(logs.single, contains('REQUEST_DENIED'));
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
                'message': 'API not enabled',
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
        expect(logs.single, contains('API not enabled'));
        expect(logs.single, contains('"http_status":$code'));
      },
    );
  }

  for (final entry in {
    'OVER_QUERY_LIMIT': GooglePlacesFailureKind.rateLimited,
    'INVALID_REQUEST': GooglePlacesFailureKind.invalidRequest,
    'UNKNOWN_ERROR': GooglePlacesFailureKind.upstream,
  }.entries) {
    test('${entry.key} retains error mapping', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'status': entry.key}), 200),
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
            'https://maps.googleapis.com/maps/api/place/textsearch/json?key=$key&query=private#fragment',
        key: key,
        httpStatus: 200,
        googleStatus: 'REQUEST_DENIED',
        googleMessage:
            'Rejected $key and AIzaAnotherCredential12345; api_key=other-secret\nretry',
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
          '"endpoint":"https://maps.googleapis.com/maps/api/place/textsearch/json"',
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
