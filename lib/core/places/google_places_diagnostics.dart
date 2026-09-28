import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../config/safe_diagnostic_message.dart';
import 'google_maps_api_key_resolver.dart';

class GooglePlacesDiagnostics {
  static Future<void> record({
    required String operation,
    required String endpoint,
    required String key,
    int? httpStatus,
    required String googleStatus,
    String googleMessage = '',
    void Function(String)? output,
  }) async {
    if (!kDebugMode) return;
    final context = await GoogleMapsApiKeyResolver.diagnosticContext();
    final source = GoogleMapsApiKeyResolver.sourceFor(key);
    final uri = Uri.parse(endpoint);
    (output ?? debugPrint)(
      '[GOOGLE PLACES DIAGNOSTIC] ${jsonEncode({
        'request_type': 'Dart REST / $operation',
        // Never include query parameters, coordinates, or the key.
        'endpoint': Uri(scheme: uri.scheme, host: uri.host, path: uri.path).toString(),
        'http_status': httpStatus,
        'google_status/error_code': googleStatus,
        'google_error_message': safeDiagnosticMessage(googleMessage, secrets: [key]),
        'key_source': source,
        'key_present': key.isNotEmpty,
        'key_length': key.length,
        if (source == 'Android/iOS native application configuration') 'key_sha256': context['native_key_sha256'],
        'build_mode': 'debug',
        'package_name': context['package_name'] ?? 'unavailable',
        'signing_sha1': context['signing_sha1'],
        'signing_sha256': context['signing_sha256'],
      })}',
    );
  }
}
