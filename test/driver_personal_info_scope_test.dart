import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';

void main() {
  test('initial municipality assignment uses the dedicated RPC', () async {
    Map<String, dynamic>? rpcBody;
    final client = SupabaseClient(
      'https://example.test',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        expect(
          request.url.path,
          '/rest/v1/rpc/assign_initial_driver_municipality',
        );
        rpcBody = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
        return http.Response(
          jsonEncode({
            'success': true,
            'municipality': 'Pulilan',
            'province': 'Bulacan',
          }),
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);

    await DriverProfileService(client: client).assignInitialMunicipality(
      'Pulilan',
    );

    expect(rpcBody, {'p_municipality': 'Pulilan'});
  });

  test('personal info save preserves backend role and tenant scope', () async {
    const userId = '10000000-0000-4000-8000-000000000001';
    final profile = <String, dynamic>{
      'id': userId,
      'role': 'driver',
      'city': 'Bustos',
      'municipality': 'Bustos',
      'province': 'Bulacan',
      'first_name': 'Old',
      'middle_name': 'Existing',
      'last_name': 'Name',
      'full_name': 'Old Existing Name',
      'mobile': '09170000000',
      'birthdate': '1990-01-01',
      'address': 'Old address',
      'barangay': 'Old barangay',
    };
    final driverDetails = <String, dynamic>{
      'driver_id': userId,
      'mobile': '09170000000',
      'license_number': 'N01-23-456789',
      'toda_name': 'Existing TODA',
    };
    Map<String, dynamic>? profilePatch;
    Map<String, dynamic>? detailsPatch;

    http.Response jsonResponse(
      http.Request request,
      Object body, {
      int status = 200,
    }) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
      request: request,
    );

    final client = SupabaseClient(
      'https://example.test',
      'test-key',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        final table = request.url.pathSegments.last;
        if (request.method == 'GET' && table == 'profiles') {
          return jsonResponse(request, [
            {'id': userId},
          ]);
        }
        if (request.method == 'PATCH' && table == 'profiles') {
          profilePatch = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          profile.addAll(profilePatch!);
          return http.Response('', 204, request: request);
        }
        if (request.method == 'GET' && table == 'driver_details') {
          return jsonResponse(request, [
            {'driver_id': userId},
          ]);
        }
        if (request.method == 'PATCH' && table == 'driver_details') {
          detailsPatch = Map<String, dynamic>.from(
            jsonDecode(request.body) as Map,
          );
          driverDetails.addAll(detailsPatch!);
          return http.Response('', 204, request: request);
        }
        throw StateError('Unexpected request ${request.method} ${request.url}');
      }),
    );
    addTearDown(client.dispose);
    final service = DriverProfileService(client: client);

    await service.savePersonalInfo(
      userId: userId,
      firstName: 'Juan',
      middleName: 'Dela',
      lastName: 'Cruz',
      fullName: '',
      mobile: '09171234567',
      address: 'New address',
      barangay: 'Poblacion',
      birthdate: DateTime.utc(1992, 3, 4),
    );

    expect(profilePatch, isNotNull);
    expect(profilePatch!.keys.toSet(), {
      'first_name',
      'middle_name',
      'last_name',
      'full_name',
      'mobile',
      'birthdate',
      'address',
      'barangay',
      'updated_at',
    });
    expect(
      profilePatch!.keys,
      isNot(containsAll(<String>['role', 'city', 'municipality', 'province'])),
    );
    expect(profile['role'], 'driver');
    expect(profile['city'], 'Bustos');
    expect(profile['municipality'], 'Bustos');
    expect(profile['province'], 'Bulacan');
    expect(profile['full_name'], 'Juan Dela Cruz');
    expect(detailsPatch, {'mobile': '09171234567'});
    expect(driverDetails['license_number'], 'N01-23-456789');
    expect(driverDetails['toda_name'], 'Existing TODA');
  });
}
