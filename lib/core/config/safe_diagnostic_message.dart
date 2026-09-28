/// Redacts credential-shaped values without logging request URLs or payloads.
String safeDiagnosticMessage(
  String message, {
  Iterable<String> secrets = const [],
}) {
  var safe = message;
  for (final secret in secrets) {
    if (secret.isNotEmpty) safe = safe.replaceAll(secret, '[REDACTED]');
  }
  safe = safe.replaceAll(RegExp(r'AIza[\w-]+'), '[REDACTED]');
  safe = safe.replaceAllMapped(
    RegExp(
      r'(key|api_key|token|authorization)\s*[=:]\s*[^\s&]+',
      caseSensitive: false,
    ),
    (match) => '${match[1]}=[REDACTED]',
  );
  safe = safe.replaceAll(RegExp(r'eyJ[\w-]+\.[\w-]+\.[\w-]+'), '[REDACTED]');
  return safe.replaceAll(RegExp(r'[\r\n]+'), ' ');
}
