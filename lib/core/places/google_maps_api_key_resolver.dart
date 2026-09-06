import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Resolves the Google Maps key used by native Google REST integrations.
///
/// Resolution order is an explicitly injected key, the compile-time Dart
/// define, then the native application configuration exposed by Android/iOS.
/// Web integrations intentionally use their existing server/browser proxy.
class GoogleMapsApiKeyResolver {
  GoogleMapsApiKeyResolver._();

  static const MethodChannel _configChannel = MethodChannel(
    'touristrike/config',
  );
  static const String _dartDefineKey = String.fromEnvironment(
    'GOOGLE_MAPS_API_KEY',
  );

  static String _nativeKey = '';
  static Future<String>? _nativeKeyRequest;

  static String get cachedKey {
    final defined = _dartDefineKey.trim();
    return defined.isNotEmpty ? defined : _nativeKey;
  }

  static Future<String> resolve({String? explicitKey}) async {
    final injected = explicitKey?.trim() ?? '';
    if (injected.isNotEmpty) return injected;

    final cached = cachedKey.trim();
    if (cached.isNotEmpty || kIsWeb) return cached;

    final existingRequest = _nativeKeyRequest;
    if (existingRequest != null) return existingRequest;

    final request = _loadNativeKey();
    _nativeKeyRequest = request;
    final resolved = await request;
    if (resolved.isEmpty && identical(_nativeKeyRequest, request)) {
      // A channel can be temporarily unavailable during startup or in tests.
      // Keep successful lookups cached, but allow an empty lookup to retry.
      _nativeKeyRequest = null;
    }
    return resolved;
  }

  static Future<String> _loadNativeKey() async {
    try {
      _nativeKey =
          (await _configChannel.invokeMethod<String>('getGoogleMapsApiKey') ??
                  '')
              .trim();
    } catch (_) {
      // Desktop targets and tests may not install the native channel.
      _nativeKey = '';
    }
    return _nativeKey;
  }

  @visibleForTesting
  static void resetForTesting() {
    _nativeKey = '';
    _nativeKeyRequest = null;
  }
}
