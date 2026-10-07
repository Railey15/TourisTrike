import 'package:supabase_flutter/supabase_flutter.dart';
import '../policies/touristrike_notices.dart';

/// Retryable after OTP verification, including when the app is restarted
/// between Supabase confirmation and profile creation.
Future<String?> completeConfirmedRegistration(SupabaseClient client) async {
  final user = (await client.auth.getUser()).user;
  if (user == null || user.emailConfirmedAt == null) return null;
  final existing = await client.from('profiles').select('role')
      .eq('id', user.id).maybeSingle();
  if (existing != null) return existing['role'] as String?;
  final role = user.userMetadata?['registration_role'];
  if (role == 'tourist') {
    final version = user.userMetadata?['privacy_notice_version'];
    if (version != privacyNoticeVersion) return null;
    await client.rpc('register_tourist_with_privacy_notice',
      params: {'p_version': version});
    return 'tourist';
  }
  if (role == 'driver') {
    await client.from('profiles').upsert({'id': user.id, 'role': 'driver'});
    return 'driver';
  }
  return null;
}
