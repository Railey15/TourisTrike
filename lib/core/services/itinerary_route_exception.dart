enum ItineraryRouteFailure {
  notConfigured,
  apiNotEnabled,
  unauthorized,
  rateLimited,
  noRoute,
  invalidCoordinates,
  invalidRequest,
  network,
  incompleteLegs,
  malformedResponse,
  upstream,
}

class ItineraryRouteException implements Exception {
  const ItineraryRouteException({
    this.kind = ItineraryRouteFailure.upstream,
    this.httpStatus,
    this.googleStatus,
    this.pointCount,
    this.legCount,
  });

  final ItineraryRouteFailure kind;
  final int? httpStatus;
  final String? googleStatus;
  final int? pointCount;
  final int? legCount;

  String get message => switch (kind) {
    ItineraryRouteFailure.notConfigured =>
      'Google Maps routing is not configured. Please contact support.',
    ItineraryRouteFailure.apiNotEnabled =>
      'Google Maps routing is unavailable because the Directions API is not enabled. Please contact support.',
    ItineraryRouteFailure.unauthorized =>
      'Google Maps routing is unavailable because its API access was rejected. Please contact support.',
    ItineraryRouteFailure.rateLimited =>
      'Google Maps routing is temporarily busy. Please retry shortly.',
    ItineraryRouteFailure.noRoute =>
      'Google Maps could not find a drivable route for these locations. Please choose different locations.',
    ItineraryRouteFailure.invalidCoordinates =>
      'One or more selected locations has invalid coordinates. Please choose the location again.',
    ItineraryRouteFailure.invalidRequest =>
      'Google Maps could not process this route. Please review the selected locations.',
    ItineraryRouteFailure.network =>
      'Could not reach Google Maps. Check your connection and retry.',
    ItineraryRouteFailure.incompleteLegs =>
      'Google Maps returned an incomplete route. Please retry or choose different locations.',
    ItineraryRouteFailure.malformedResponse || ItineraryRouteFailure.upstream =>
      'Google Maps could not calculate this route. Check your connection or locations and retry.',
  };

  @override
  String toString() => message;
}
