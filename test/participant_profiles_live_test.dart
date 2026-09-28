import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/config/app_config.dart';
import 'package:touristrike/core/supabase/participant_profiles.dart';

// Opt-in integration checks against the linked, deployed database. The SQL
// transport runs the actual RPC under authenticated RLS, without creating
// production sessions or storing a signing secret. Anonymous denial separately
// uses the real PostgREST endpoint. This does not test authenticated HTTP/UI.
const _enabled = bool.fromEnvironment('TOURISTRIKE_LIVE_DB_TESTS');
var _queryNumber = 0;

Future<List<dynamic>> _query(String sql) async {
  final file = File(
    'build/migration-audit-20260927/dart_live_query_${_queryNumber++}.sql',
  );
  await file.writeAsString(sql);
  final result = await Process.run('npx', [
    'supabase',
    'db',
    'query',
    '--linked',
    '--file',
    file.path,
    '--output',
    'json',
  ], runInShell: Platform.isWindows);
  if (result.exitCode != 0) {
    throw StateError('Linked SQL query failed: ${result.stderr}');
  }
  final output = result.stdout.toString().trim();
  return (jsonDecode(output) as Map<String, dynamic>)['rows'] as List<dynamic>;
}

String _uuid(String value) {
  if (!RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(value)) {
    throw ArgumentError('Expected a UUID');
  }
  return "'$value'::uuid";
}

class _LinkedRpcTransport extends http.BaseClient {
  _LinkedRpcTransport(this.actor);
  final String actor;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request.url.path, '/rest/v1/rpc/get_participant_profiles');
    expect(request.method, 'POST');
    final body = jsonDecode(await request.finalize().bytesToString()) as Map;
    expect(body.keys, ['p_profile_ids']);
    final ids = (body['p_profile_ids'] as List).cast<String>();
    final rows = await _query('''
begin;
select set_config('request.jwt.claim.sub', ${_uuid(actor)}::text, true);
select set_config('request.jwt.claim.role', 'authenticated', true);
set local role authenticated;
select coalesce(jsonb_agg(to_jsonb(p)), '[]'::jsonb) as rpc_payload
from public.get_participant_profiles(array[${ids.map(_uuid).join(',')}]::uuid[]) p;
rollback;
''');
    return http.StreamedResponse(
      Stream.value(
        utf8.encode(jsonEncode((rows.single as Map)['rpc_payload'])),
      ),
      200,
      headers: {'content-type': 'application/json'},
      request: request,
    );
  }
}

void main() {
  Map<String, dynamic> fixture = {};
  SupabaseClient clientFor(String actor) => SupabaseClient(
    AppConfig.supabaseUrl,
    'role-scoped-sql-transport',
    httpClient: _LinkedRpcTransport(actor),
  );

  setUpAll(() async {
    if (!_enabled) return;
    final rows = await _query('''
select jsonb_build_object(
  'tourist', b.tourist_id, 'driver', b.assigned_driver_id,
  'tourist_mobile_present', (select mobile is not null from public.profiles where id=b.tourist_id),
  'driver_mobile_present', (select mobile is not null from public.profiles where id=b.assigned_driver_id),
  'administrator', (select id from public.profiles where role='administrator' limit 1)
) as fixture
from public.package_bookings b
where b.assigned_driver_id is not null
 and lower(coalesce(b.booking_status,b.status,'')) in ('accepted','confirmed','driver_on_the_way','arrived','picked_up','tour_started','on_tour','ongoing','in_progress','waiting_for_drivers')
limit 1;
''');
    fixture = Map<String, dynamic>.from((rows.single as Map)['fixture'] as Map);
    // Find a genuinely unrelated target under the same authenticated RPC.
    final unrelated = await _query('''
begin;
select set_config('request.jwt.claim.sub', ${_uuid(fixture['tourist'] as String)}::text, true);
select p.id from public.profiles p where p.id <> auth.uid()
 and p.role in ('tourist','driver')
 and not exists(select 1 from public.get_participant_profiles(array[p.id])) limit 1;
rollback;
''');
    fixture['unrelated'] = (unrelated.single as Map)['id'];
  });

  for (final direction in ['tourist', 'driver']) {
    test(
      'deployed RPC: $direction assigned identity and conditional contact',
      () async {
        final client = clientFor(fixture[direction] as String);
        addTearDown(client.dispose);
        final target =
            fixture[direction == 'tourist' ? 'driver' : 'tourist'] as String;
        final row = await ParticipantProfiles.fetchOne(client, target);
        expect(row, isNotNull);
        expect(row!['id'], target);
        expect(row.keys.toSet(), {
          'id',
          'role',
          'full_name',
          'first_name',
          'last_name',
          'avatar_url',
          'profile_image_url',
          'average_rating',
          'total_reviews',
          'mobile',
        });
        expect(
          [
            row['full_name'],
            row['first_name'],
            row['last_name'],
          ].any((value) => value != null && value.toString().trim().isNotEmpty),
          isTrue,
        );
        expect(
          row['mobile'] != null,
          fixture[direction == 'tourist'
              ? 'driver_mobile_present'
              : 'tourist_mobile_present'],
        );
      },
      skip: !_enabled,
    );
  }

  test('deployed RPC: unrelated UUID returns no identity', () async {
    final client = clientFor(fixture['tourist'] as String);
    addTearDown(client.dispose);
    expect(
      await ParticipantProfiles.fetchOne(
        client,
        fixture['unrelated'] as String,
      ),
      isNull,
    );
  }, skip: !_enabled);

  test('deployed RPC: Administrator limited identity masks contact', () async {
    final client = clientFor(fixture['administrator'] as String);
    addTearDown(client.dispose);
    final row = await ParticipantProfiles.fetchOne(
      client,
      fixture['tourist'] as String,
    );
    expect(row, isNotNull);
    expect(row!['mobile'], isNull);
    expect(row.containsKey('birthdate'), isFalse);
    expect(row.containsKey('verification_status'), isFalse);
  }, skip: !_enabled);

  test('live PostgREST: anonymous participant RPC denied', () async {
    final source = await File('lib/main.dart').readAsString();
    final publicKey = RegExp(
      r"anonKey:\s*'([^']+)'",
    ).firstMatch(source)!.group(1)!;
    final client = SupabaseClient(AppConfig.supabaseUrl, publicKey);
    addTearDown(client.dispose);
    await expectLater(
      ParticipantProfiles.fetchOne(client, fixture['tourist'] as String),
      throwsA(
        isA<PostgrestException>().having(
          (error) => error.message.toLowerCase(),
          'permission failure',
          contains('permission denied'),
        ),
      ),
    );
  }, skip: !_enabled);
}
