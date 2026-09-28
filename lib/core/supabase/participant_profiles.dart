import 'package:supabase_flutter/supabase_flutter.dart';

/// Identity lookup with server-side relationship checks and a fixed projection.
/// No fallback to profiles: a missing relationship must stay inaccessible.
abstract final class ParticipantProfiles {
  static Future<List<Map<String, dynamic>>> fetchMany(
    SupabaseClient client,
    Iterable<String> profileIds,
  ) async {
    final ids = profileIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final rows = <Map<String, dynamic>>[];
    for (var offset = 0; offset < ids.length; offset += 200) {
      final chunk = ids.skip(offset).take(200).toList(growable: false);
      final result = await client.rpc(
        'get_participant_profiles',
        params: {'p_profile_ids': chunk},
      );
      rows.addAll(
        (result as List).whereType<Map>().map(Map<String, dynamic>.from),
      );
    }
    return rows;
  }

  static Future<Map<String, dynamic>?> fetchOne(
    SupabaseClient client,
    String profileId,
  ) async {
    final rows = await fetchMany(client, [profileId]);
    return rows.isEmpty ? null : rows.single;
  }
}
