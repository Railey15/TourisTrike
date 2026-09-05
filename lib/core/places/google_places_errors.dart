enum GooglePlacesFailureKind {
  network,
  unauthorized,
  rateLimited,
  notConfigured,
  invalidRequest,
  upstream,
}

class GooglePlacesException implements Exception {
  const GooglePlacesException({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  final GooglePlacesFailureKind kind;
  final String message;
  final int? statusCode;

  bool get canRetry => switch (kind) {
    GooglePlacesFailureKind.network ||
    GooglePlacesFailureKind.rateLimited ||
    GooglePlacesFailureKind.upstream => true,
    _ => false,
  };

  @override
  String toString() => message;
}
