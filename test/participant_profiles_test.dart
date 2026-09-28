import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/supabase/participant_profiles.dart';

void main() {
  test(
    'identity batches use the restricted RPC and retain contact masking',
    () async {
      final requests = <List<dynamic>>[];
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        httpClient: MockClient((request) async {
          expect(request.url.path, '/rest/v1/rpc/get_participant_profiles');
          final ids =
              (jsonDecode(request.body) as Map)['p_profile_ids'] as List;
          requests.add(ids);
          return http.Response(
            jsonEncode([
              {'id': ids.first, 'full_name': 'Participant', 'mobile': null},
            ]),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      final ids = List.generate(201, (index) => 'profile-$index');
      final rows = await ParticipantProfiles.fetchMany(client, [
        ...ids,
        ids.first,
      ]);
      expect(requests.map((batch) => batch.length), [200, 1]);
      expect(rows, hasLength(2));
      expect(rows.every((row) => row['mobile'] == null), isTrue);
    },
  );

  test(
    'a rejected identity lookup does not fall back to full profiles',
    () async {
      var requests = 0;
      final client = SupabaseClient(
        'https://example.test',
        'test-key',
        httpClient: MockClient((request) async {
          requests++;
          expect(request.url.path, '/rest/v1/rpc/get_participant_profiles');
          return http.Response(
            '{"message":"forbidden","code":"42501"}',
            403,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        ParticipantProfiles.fetchOne(client, 'target'),
        throwsA(isA<PostgrestException>()),
      );
      expect(requests, 1);
    },
  );

  test('unrelated or empty identities stay absent', () async {
    var requests = 0;
    final client = SupabaseClient(
      'https://example.test',
      'test-key',
      httpClient: MockClient((request) async {
        requests++;
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    expect(await ParticipantProfiles.fetchMany(client, ['', ' ']), isEmpty);
    expect(requests, 0);
    expect(await ParticipantProfiles.fetchOne(client, 'unrelated'), isNull);
    expect(requests, 1);
  });
}
