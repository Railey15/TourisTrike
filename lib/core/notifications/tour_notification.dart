class TourNotification {
  const TourNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.createdAt,
    required this.isRead,
    required this.pushEnabled,
    bool? inAppEnabled,
  }) : inAppEnabled = inAppEnabled ?? pushEnabled;

  factory TourNotification.fromMap(Map<String, dynamic> row) =>
      TourNotification(
        id: row['id'].toString(),
        title: row['title'] as String? ?? 'Tour Update',
        body: row['body'] as String? ?? '',
        type: row['type'] as String? ?? '',
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        isRead: row['is_read'] == true,
        pushEnabled: row['push_enabled'] == true,
        inAppEnabled: (row['in_app_enabled'] ?? row['push_enabled']) == true,
      );
  final String id, title, body, type;
  final DateTime createdAt;
  final bool isRead, pushEnabled;
  final bool inAppEnabled;

  // Use the existing event eligibility, with a presentation-only noise guard.
  bool get foregroundEligible =>
      inAppEnabled &&
      !isRead &&
      !RegExp(
        r'^(debug|notification_test|gps_|eta_|map_|polyline_|realtime_|typing_|loading$|screen_refresh|sync_)',
      ).hasMatch(type);

  static String? payloadId(Map<String, dynamic> data) {
    final id = data['notification_id'];
    if (id is! String ||
        !RegExp(
          r'^(?:[0-9]+|[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})$',
        ).hasMatch(id)) {
      return null;
    }
    return id;
  }
}
