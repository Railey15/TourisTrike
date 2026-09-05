import '../supabase/touristrike_models.dart';

class BookingFeedback {
  BookingFeedback(this.row);
  final Json row;
  String get bookingId => dbString(row['booking_id']);
  String get packageName =>
      dbString(row['package_name'], fallback: 'Tour Package');
  bool get canReview => row['can_review'] == true;
  Json? get packageReview =>
      row['package_review'] is Map ? Json.from(row['package_review']) : null;
  List<Json> get drivers => (row['drivers'] as List? ?? const [])
      .whereType<Map>()
      .map(Json.from)
      .toList();
  bool get complete =>
      packageReview != null &&
      drivers.isNotEmpty &&
      drivers.every((d) => d['review'] is Map);
}

/// Reserve the session before any network read. Never reopen automatically
/// after dismissal, failure, submission or a concurrent Realtime refresh.
class BookingFeedbackGate {
  bool _handled = false;
  bool reserve() {
    if (_handled) return false;
    _handled = true;
    return true;
  }
}
