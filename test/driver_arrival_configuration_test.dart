import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

void main() {
  for (final radius in [150, 80.5]) {
    test(
      'driver uses server radius $radius without a hardcoded fallback',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test',
          authOptions: const AuthClientOptions(autoRefreshToken: false),
          httpClient: MockClient((request) async {
            expect(
              request.url.path,
              '/rest/v1/rpc/driver_arrival_radius_meters',
            );
            return http.Response(
              jsonEncode(radius),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        expect(
          await TourisTrikeRepository(
            client: client,
          ).fetchDriverArrivalRadiusMeters(),
          radius.toDouble(),
        );
        await client.dispose();
      },
    );
  }
  for (final value in [null, 0, -1, 'invalid']) {
    test('invalid server radius $value fails clearly', () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient(
          (request) async => http.Response(
            jsonEncode(value),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      await expectLater(
        TourisTrikeRepository(client: client).fetchDriverArrivalRadiusMeters(),
        throwsStateError,
      );
      await client.dispose();
    });
  }
}
