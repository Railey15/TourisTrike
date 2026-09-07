import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/services/emergency_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final emailSuccess in [false, true]) {
    test(
      'database alert survives email result=$emailSuccess with truthful outcome',
      () async {
        final calls = <String>[];
        final id = EmergencyService.newAlertId();
        final client = SupabaseClient(
          'https://test.invalid',
          'test-key',
          httpClient: MockClient((request) async {
            calls.add('${request.method.toUpperCase()} ${request.url.path}');
            if (request.url.path == '/rest/v1/emergency_alerts') {
              final body = jsonDecode(request.body) as Map;
              expect(body['id'], id);
              expect(body['tourist_note'], 'Please help');
              return http.Response(
                jsonEncode({...body, 'created_at': '2026-09-07T01:00:00Z'}),
                201,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            if (request.url.path == '/functions/v1/send-emergency-email') {
              expect(jsonDecode(request.body)['alert_id'], id);
              return http.Response(
                jsonEncode({'email_sent': emailSuccess}),
                200,
                request: request,
                headers: {'content-type': 'application/json'},
              );
            }
            return http.Response(
              '[]',
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }),
        );
        final result = await EmergencyService(client).triggerAlert(
          alertId: id,
          touristId: 'tourist',
          bookingId: 'booking',
          tripStatus: 'on_tour',
          note: ' Please help ',
        );
        expect(result.alertId, id);
        expect(result.emailSent, emailSuccess);
        expect(
          calls.where((c) => c == 'POST /rest/v1/emergency_alerts'),
          hasLength(1),
        );
        expect(
          calls.indexOf('POST /rest/v1/emergency_alerts'),
          lessThan(calls.indexOf('POST /functions/v1/send-emergency-email')),
        );
        await client.dispose();
      },
    );
  }

  test(
    'retry reuses the existing alert and does not duplicate notifications',
    () async {
      final id = EmergencyService.newAlertId();
      final calls = <String>[];
      final client = SupabaseClient(
        'https://test.invalid',
        'test-key',
        httpClient: MockClient((request) async {
          calls.add('${request.method.toUpperCase()} ${request.url.path}');
          if (request.url.path == '/rest/v1/emergency_alerts' &&
              request.method == 'POST') {
            return http.Response(
              jsonEncode({'code': '23505', 'message': 'duplicate key'}),
              409,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          if (request.url.path == '/rest/v1/emergency_alerts') {
            expect(request.url.queryParameters['tourist_id'], 'eq.tourist');
            return http.Response(
              jsonEncode({'id': id, 'created_at': '2026-09-07T01:00:00Z'}),
              200,
              request: request,
              headers: {'content-type': 'application/json'},
            );
          }
          return http.Response(
            '{"email_sent":true}',
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final result = await EmergencyService(client).triggerAlert(
        alertId: id,
        touristId: 'tourist',
        bookingId: 'booking',
        tripStatus: 'on_tour',
      );
      expect(result.alertId, id);
      expect(calls.any((c) => c.contains('/notifications')), isFalse);
      await client.dispose();
    },
  );
}
