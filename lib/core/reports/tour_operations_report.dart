import 'package:supabase_flutter/supabase_flutter.dart';

class TourOperationsReport {
  const TourOperationsReport(this.data);

  final Map<String, dynamic> data;

  static Future<TourOperationsReport> fetch({
    required DateTime start,
    required DateTime end,
    String? city,
  }) async {
    final result = await Supabase.instance.client.rpc(
      'get_tour_operations_report',
      params: {
        'p_start': start.toUtc().toIso8601String(),
        'p_end': end.toUtc().toIso8601String(),
        'p_city': city,
      },
    );
    if (result is! Map) throw StateError('Invalid tour operations report');
    return TourOperationsReport(Map<String, dynamic>.from(result));
  }

  int count(String key) => (data[key] as num?)?.toInt() ?? 0;

  double amount(String key) => (data[key] as num?)?.toDouble() ?? 0;

  List<Map<String, dynamic>> rows(String key) =>
      (data[key] as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
}
