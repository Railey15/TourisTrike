import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/admin/admin_models.dart';

class ProvincialAdminService {
  ProvincialAdminService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<ProvincialAdminProfile> loadCurrentAdminProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw StateError('No active session. Please sign in again.');
    }

    final row = await _supabase
        .from('profiles')
        .select('*')
        .eq('id', user.id)
        .maybeSingle();

    if (row == null) {
      throw StateError('Admin profile not found.');
    }

    final profile = ProvincialAdminProfile.fromMap(
      Map<String, dynamic>.from(row),
      email: user.email ?? '',
    );

    if (!profile.isAdmin) {
      throw StateError(
        'Unauthorized: this page requires profiles.role = admin.',
      );
    }

    return profile;
  }

  Future<AdminDashboardData> loadDashboard() async {
    final profile = await loadCurrentAdminProfile();
    final tenants = await fetchCityTenants();
    final packages = await fetchProvincePackages();
    final spots = await fetchProvinceSpots();
    final bookings = await fetchBookings(packages);
    final feedback = await fetchFeedback();
    final registrations = await fetchRegistrations();

    return AdminDashboardData(
      profile: profile,
      tenants: tenants,
      packages: packages,
      spots: spots,
      bookings: bookings,
      feedback: feedback.items,
      registrations: registrations.items,
      registrationsTableAvailable: registrations.available,
    );
  }

  Future<List<AdminSearchResult>> searchProvince(String query) async {
    await loadCurrentAdminProfile();
    final term = query
        .trim()
        .replaceAll(RegExp(r'[%_,()]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (term.length < 2) return const [];

    final results = await Future.wait([
      _searchTenants(term),
      _searchSpots(term),
      _searchPackages(term),
      _searchDrivers(term),
      _searchBookings(term),
    ]);
    return results.expand((items) => items).toList(growable: false);
  }

  Future<List<AdminSearchResult>> _searchTenants(String term) async {
    final rows = await _supabase
        .from('subtenant_details')
        .select(
          'id,city,province,office_name,contact_person,email,office_address,'
          'verification_status,is_active,local_government_type,'
          'local_government_type_reviewed',
        )
        .or(
          'city.ilike.%$term%,office_name.ilike.%$term%,'
          'contact_person.ilike.%$term%,email.ilike.%$term%',
        )
        .order('city')
        .limit(5);
    return _asRows(rows)
        .map(
          (row) => AdminSearchResult(
            type: AdminSearchResultType.tenant,
            id: adminId(row['id']),
            title: adminString(row, const ['office_name', 'city']),
            subtitle:
                '${adminString(row, const ['city'])} · ${adminString(row, const ['province'])}',
            raw: row,
          ),
        )
        .toList(growable: false);
  }

  Future<List<AdminSearchResult>> _searchSpots(String term) async {
    final rows = await _supabase
        .from('tourist_spots')
        .select('id,title,city,barangay,status,verification_status')
        .or(
          'title.ilike.%$term%,city.ilike.%$term%,'
          'barangay.ilike.%$term%',
        )
        .order('created_at', ascending: false)
        .limit(5);
    return _asRows(rows)
        .map(
          (row) => AdminSearchResult(
            type: AdminSearchResultType.spot,
            id: adminId(row['id']),
            title: adminString(row, const ['title']),
            subtitle:
                '${adminString(row, const ['city'])} · ${adminString(row, const ['verification_status'], fallback: 'unverified')}',
            raw: row,
          ),
        )
        .toList(growable: false);
  }

  Future<List<AdminSearchResult>> _searchPackages(String term) async {
    final rows = await _supabase
        .from('tour_packages')
        .select('id,title,city,status,visibility_status')
        .or('title.ilike.%$term%,city.ilike.%$term%')
        .order('created_at', ascending: false)
        .limit(5);
    return _asRows(rows)
        .map(
          (row) => AdminSearchResult(
            type: AdminSearchResultType.package,
            id: adminId(row['id']),
            title: adminString(row, const ['title']),
            subtitle:
                '${adminString(row, const ['city'])} · ${adminString(row, const ['status'])}',
            raw: row,
          ),
        )
        .toList(growable: false);
  }

  Future<List<AdminSearchResult>> _searchDrivers(String term) async {
    final rows = await _supabase
        .from('profiles')
        .select('id,full_name,first_name,last_name,mobile,city')
        .eq('role', 'driver')
        .or(
          'full_name.ilike.%$term%,first_name.ilike.%$term%,'
          'last_name.ilike.%$term%,mobile.ilike.%$term%,'
          'city.ilike.%$term%',
        )
        .order('created_at', ascending: false)
        .limit(5);
    return _asRows(rows)
        .map((row) {
          final generated = [
            adminString(row, const ['first_name']),
            adminString(row, const ['last_name']),
          ].where((value) => value.isNotEmpty).join(' ');
          return AdminSearchResult(
            type: AdminSearchResultType.driver,
            id: adminId(row['id']),
            title: adminString(row, const [
              'full_name',
            ], fallback: generated.isEmpty ? 'Driver' : generated),
            subtitle:
                '${adminString(row, const ['city'], fallback: 'Unassigned')} · ${adminString(row, const ['mobile'], fallback: 'No mobile number')}',
            raw: row,
          );
        })
        .toList(growable: false);
  }

  Future<List<AdminSearchResult>> _searchBookings(String term) async {
    dynamic query = _supabase
        .from('package_bookings')
        .select(
          'id,package_id,tourist_id,status,booking_status,total_amount,'
          'travel_date,created_at,tour_packages(title,city)',
        );
    final isUuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-'
      r'[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    ).hasMatch(term);
    query = !isUuid
        ? query.or('status.ilike.%$term%,booking_status.ilike.%$term%')
        : query.eq('id', term);
    final rows = await query.order('created_at', ascending: false).limit(5);
    return _asRows(rows)
        .map((row) {
          final nested = row['tour_packages'];
          final package = nested is Map
              ? Map<String, dynamic>.from(nested)
              : const <String, dynamic>{};
          return AdminSearchResult(
            type: AdminSearchResultType.booking,
            id: adminId(row['id']),
            title: 'Booking #${adminId(row['id'])}',
            subtitle:
                '${adminString(package, const ['title'], fallback: 'Package')} · ${adminString(package, const ['city'], fallback: 'Unknown')}',
            raw: {...row, 'tour_packages': package},
          );
        })
        .toList(growable: false);
  }

  Future<List<AdminNotification>> fetchAdminNotifications({
    int limit = 30,
  }) async {
    final profile = await loadCurrentAdminProfile();
    final rows = await _supabase
        .from('notifications')
        .select('*')
        .eq('user_id', profile.id)
        .order('created_at', ascending: false)
        .limit(limit);
    return _asRows(rows).map(AdminNotification.fromMap).toList(growable: false);
  }

  Future<void> markAdminNotificationRead(dynamic notificationId) async {
    final profile = await loadCurrentAdminProfile();
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('id', notificationId)
        .eq('user_id', profile.id)
        .select('id')
        .single();
  }

  Future<void> markAllAdminNotificationsRead() async {
    final profile = await loadCurrentAdminProfile();
    await _supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', profile.id)
        .eq('is_read', false)
        .select('id');
  }

  Future<List<CityTenant>> fetchCityTenants() async {
    final profiles = await _selectRows(
      'profiles',
      equals: const {'role': 'subtenant'},
      orderBy: 'city',
    );

    final detailsRows = await _selectRows('subtenant_details');
    final detailsById = {
      for (final row in detailsRows) adminId(row['id']): row,
    };
    final registrations = await fetchRegistrations();
    final latestRegistrationByUserId = <String, CityRegistration>{};
    if (registrations.available) {
      for (final registration in registrations.items) {
        if (registration.userId.isEmpty) continue;
        latestRegistrationByUserId.putIfAbsent(
          registration.userId,
          () => registration,
        );
      }
    }

    final spots = await fetchProvinceSpots();
    final packages = await fetchProvincePackages();
    final bookings = await fetchBookings(packages);
    final drivers = await _selectRows(
      'profiles',
      equals: const {'role': 'driver'},
    );

    final spotCounts = _countByCity(spots.map((item) => item.city));
    final packageCounts = _countByCity(packages.map((item) => item.city));
    final bookingCounts = _countByCity(bookings.map((item) => item.city));
    final driverCounts = _countByCity(
      drivers.map((item) => adminString(item, const ['city'])),
    );

    return profiles
        .map((row) {
          final id = adminId(row['id']);
          final merged = _mergeTenantRows(
            profile: row,
            details: detailsById[id],
            registration: latestRegistrationByUserId[id],
          );
          final tenant = CityTenant.fromProfile(merged);

          return tenant.copyWith(
            spotsCount: spotCounts[tenant.city] ?? 0,
            packagesCount: packageCounts[tenant.city] ?? 0,
            bookingsCount: bookingCounts[tenant.city] ?? 0,
            driversCount: driverCounts[tenant.city] ?? 0,
          );
        })
        .toList(growable: false);
  }

  Map<String, dynamic> _mergeTenantRows({
    required Map<String, dynamic> profile,
    Map<String, dynamic>? details,
    CityRegistration? registration,
  }) {
    final merged = <String, dynamic>{...profile};

    if (details != null) {
      for (final entry in details.entries) {
        if (!_hasTenantValue(entry.value)) continue;
        merged[entry.key] = entry.value;
      }
    }

    if (registration != null) {
      void fillMissing(String key, dynamic value) {
        if (_hasTenantValue(merged[key]) || !_hasTenantValue(value)) return;
        merged[key] = value;
      }

      fillMissing('city', registration.city);
      fillMissing('office_name', registration.officeName);
      fillMissing('contact_person', registration.contactPerson);
      fillMissing('full_name', registration.contactPerson);
      fillMissing('email', registration.email);
      fillMissing('contact_number', registration.contactNumber);
      fillMissing('mobile', registration.contactNumber);
      fillMissing('office_address', registration.address);
      fillMissing('address', registration.address);
    }

    return merged;
  }

  bool _hasTenantValue(dynamic value) {
    if (value == null) return false;
    if (value is String) return value.trim().isNotEmpty;
    return true;
  }

  Future<CityTenantDetailsData> fetchTenantDetails(String tenantId) async {
    final row = await _supabase
        .from('profiles')
        .select('*')
        .eq('id', tenantId)
        .maybeSingle();

    if (row == null) {
      throw StateError('City tenant not found.');
    }

    final profileRow = Map<String, dynamic>.from(row);

    final detailsRow = await _supabase
        .from('subtenant_details')
        .select('*')
        .eq('id', tenantId)
        .maybeSingle();

    final registrationResult = await fetchRegistrations();
    CityRegistration? registration;
    if (registrationResult.available) {
      for (final item in registrationResult.items) {
        if (item.userId == tenantId) {
          registration = item;
          break;
        }
      }
    }

    final baseTenant = CityTenant.fromProfile(
      _mergeTenantRows(
        profile: profileRow,
        details: detailsRow == null
            ? null
            : Map<String, dynamic>.from(detailsRow),
        registration: registration,
      ),
    );

    final city = baseTenant.city;

    final packageRows = await _selectRows(
      'tour_packages',
      equals: {'city': city},
      orderBy: 'created_at',
      ascending: false,
    );
    final basePackages = packageRows
        .map(ProvincePackage.fromMap)
        .toList(growable: false);
    final packageById = {
      for (final package in basePackages) adminId(package.id): package,
    };

    final bookingRows = await _supabase
        .from('package_bookings')
        .select('*, tour_packages!inner(id,title,city)')
        .eq('tour_packages.city', city)
        .order('created_at', ascending: false);
    final bookings = _asRows(bookingRows)
        .map(
          (row) => ProvinceBooking.fromMap(
            row,
            package: packageById[adminId(row['package_id'])],
          ),
        )
        .toList(growable: false);
    final bookingCounts = <String, int>{};
    final packageRevenue = <String, double>{};
    for (final booking in bookings) {
      final packageId = adminId(booking.packageId);
      bookingCounts.update(packageId, (value) => value + 1, ifAbsent: () => 1);
      packageRevenue.update(
        packageId,
        (value) => value + booking.totalAmount,
        ifAbsent: () => booking.totalAmount,
      );
    }
    final packages = packageRows
        .map(
          (row) => ProvincePackage.fromMap(
            row,
            bookingsCount: bookingCounts[adminId(row['id'])] ?? 0,
            revenue: packageRevenue[adminId(row['id'])] ?? 0,
          ),
        )
        .toList(growable: false);

    final spotRows = await _selectRows(
      'tourist_spots',
      equals: {'city': city},
      orderBy: 'created_at',
      ascending: false,
    );
    final spots = spotRows.map(ProvinceSpot.fromMap).toList(growable: false);

    final drivers = await _selectRows(
      'profiles',
      equals: {'role': 'driver', 'city': city},
    );

    final feedback = (await fetchFeedback()).items
        .where((item) => item.city == city)
        .toList(growable: false);

    final tenant = baseTenant.copyWith(
      spotsCount: spots.length,
      packagesCount: packages.length,
      bookingsCount: bookings.length,
      driversCount: drivers.length,
    );

    return CityTenantDetailsData(
      tenant: tenant,
      packages: packages,
      spots: spots,
      bookings: bookings,
      feedback: feedback,
      driversCount: drivers.length,
    );
  }

  Future<void> updateTenantStatus(CityTenant tenant, String status) async {
    final active = const {
      'active',
      'approved',
      'verified',
    }.contains(status.toLowerCase().trim());

    await _supabase
        .from('subtenant_details')
        .upsert({
          'id': tenant.id,
          'office_name': tenant.raw['office_name'] ?? tenant.adminName,
          'city': tenant.city,
          'province': tenant.province.isEmpty ? 'Bulacan' : tenant.province,
          'contact_number': tenant.mobile,
          'email': tenant.email,
          'office_address': tenant.address,
          'verification_status': active ? 'verified' : status,
          'is_active': active,
        })
        .select('id')
        .single();

    await _logAudit(
      action: active ? 'activate_subtenant' : 'deactivate_subtenant',
      tableName: 'subtenant_details',
      recordId: tenant.id,
      description: 'Updated ${tenant.city} subtenant status to $status.',
    );
  }

  Future<void> updateTenantCity(CityTenant tenant, String city) async {
    final normalizedCity = city.trim();
    if (normalizedCity.isEmpty) {
      throw ArgumentError('City / municipality is required.');
    }
    await _supabase
        .from('subtenant_details')
        .update({'city': normalizedCity})
        .eq('id', tenant.id)
        .select('id')
        .single();
    await _logAudit(
      action: 'update_subtenant_city',
      tableName: 'subtenant_details',
      recordId: tenant.id,
      description: 'Changed assignment from ${tenant.city} to $normalizedCity.',
    );
  }

  Future<void> updateTenantClassification(
    CityTenant tenant,
    String localGovernmentType,
  ) async {
    if (!const {'city', 'municipality'}.contains(localGovernmentType)) {
      throw ArgumentError('Invalid local government type.');
    }
    await _supabase
        .from('subtenant_details')
        .update({
          'local_government_type': localGovernmentType,
          'local_government_type_reviewed': true,
        })
        .eq('id', tenant.id)
        .select('id')
        .single();
    await _logAudit(
      action: 'review_lgu_classification',
      tableName: 'subtenant_details',
      recordId: tenant.id,
      description: 'Classified ${tenant.city} as $localGovernmentType.',
    );
  }

  Future<void> verifyTenant(CityTenant tenant) async {
    final admin = await loadCurrentAdminProfile();
    final now = DateTime.now().toUtc().toIso8601String();

    await _supabase
        .from('subtenant_details')
        .upsert({
          'id': tenant.id,
          'office_name': tenant.raw['office_name'] ?? tenant.adminName,
          'city': tenant.city,
          'province': tenant.province.isEmpty ? 'Bulacan' : tenant.province,
          'contact_number': tenant.mobile,
          'email': tenant.email,
          'office_address': tenant.address,
          'verification_status': 'verified',
          'is_active': true,
          'approved_by': admin.id,
          'approved_at': now,
        })
        .select('id')
        .single();

    await _logAudit(
      action: 'verify_subtenant',
      tableName: 'subtenant_details',
      recordId: tenant.id,
      description: 'Verified ${tenant.city} tourism office.',
    );
  }

  Future<TableResult<CityRegistration>> fetchRegistrations() async {
    try {
      final rows = await _selectRows(
        'city_tenant_registrations',
        orderBy: 'submitted_at',
        ascending: false,
      );

      return TableResult(
        available: true,
        items: rows.map(CityRegistration.fromMap).toList(growable: false),
      );
    } on PostgrestException {
      return const TableResult(available: false, items: []);
    }
  }

  Future<void> reviewRegistration(
    CityRegistration registration,
    String status, {
    String rejectionReason = '',
  }) async {
    final normalizedStatus = status.toLowerCase().trim();

    if (normalizedStatus != 'approved' && normalizedStatus != 'rejected') {
      throw ArgumentError('Invalid review status: $status');
    }

    if (registration.id == null || adminId(registration.id).isEmpty) {
      throw StateError('Registration ID is missing.');
    }

    if (normalizedStatus == 'approved' && registration.userId.isEmpty) {
      throw StateError('This registration is not linked to a user account.');
    }

    final admin = await loadCurrentAdminProfile();
    final now = DateTime.now().toUtc().toIso8601String();

    try {
      var reviewedWithRpc = false;
      try {
        await _reviewRegistrationWithRpc(
          registration: registration,
          status: normalizedStatus,
          rejectionReason: rejectionReason,
        );
        reviewedWithRpc = true;
      } on PostgrestException catch (e) {
        if (!_canFallbackFromReviewRpc(e)) rethrow;
      }

      if (!reviewedWithRpc) {
        if (normalizedStatus == 'approved') {
          await _activateRegistrationProfile(
            registration: registration,
            adminIdValue: admin.id,
            reviewedAtIso: now,
          );
        }

        await _supabase
            .from('city_tenant_registrations')
            .update({
              'status': normalizedStatus,
              'reviewed_by': admin.id,
              'reviewed_at': now,
              'rejection_reason': normalizedStatus == 'rejected'
                  ? rejectionReason.trim()
                  : null,
            })
            .eq('id', registration.id)
            .select('id')
            .single();
      }

      if (normalizedStatus == 'approved') {
        await _assertRegistrationActivated(registration.userId);
      }

      if (registration.userId.isNotEmpty) {
        await _notifyApplicant(
          userId: registration.userId,
          approved: normalizedStatus == 'approved',
          reason: rejectionReason,
          city: registration.city,
        );
      }

      await _logAudit(
        action: normalizedStatus == 'approved'
            ? 'approve_city_registration'
            : 'reject_city_registration',
        tableName: 'city_tenant_registrations',
        recordId: adminId(registration.id),
        description:
            'Marked ${registration.officeName} (${registration.city}) as $normalizedStatus.',
      );
    } on PostgrestException catch (e) {
      throw StateError('Failed to review registration: ${e.message}');
    } catch (e) {
      throw StateError('Failed to review registration: $e');
    }
  }

  Future<void> _reviewRegistrationWithRpc({
    required CityRegistration registration,
    required String status,
    required String rejectionReason,
  }) async {
    await _supabase.rpc(
      'approve_city_registration',
      params: {
        'p_registration_id': adminId(registration.id),
        'p_status': status,
        'p_rejection_reason': status == 'rejected'
            ? rejectionReason.trim()
            : '',
      },
    );
  }

  Future<void> _assertRegistrationActivated(String userId) async {
    final profile = await _supabase
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();

    final role = (profile?['role'] ?? '').toString().toLowerCase().trim();
    if (role != 'subtenant') {
      throw StateError(
        'The registration was approved, but the applicant profile is still not active. Run the latest Supabase migration and retry approval.',
      );
    }
  }

  bool _canFallbackFromReviewRpc(PostgrestException e) {
    final message = e.message.toLowerCase();
    return e.code == '42883' ||
        e.code == 'PGRST202' ||
        message.contains('schema cache') ||
        message.contains('function') ||
        message.contains('column "address" does not exist') ||
        message.contains('invalid input syntax for type uuid') ||
        message.contains('invalid input syntax for type bigint');
  }

  Future<void> _activateRegistrationProfile({
    required CityRegistration registration,
    required String adminIdValue,
    required String reviewedAtIso,
  }) async {
    final nameParts = _nameParts(registration.contactPerson);

    final profilePayload = {
      'id': registration.userId,
      'role': 'subtenant',
      'first_name': nameParts.$1,
      'last_name': nameParts.$2,
      'full_name': registration.contactPerson,
      'mobile': registration.contactNumber,
      'address': registration.address,
      'city': registration.city,
      'province': 'Bulacan',
    };

    await _supabase.from('profiles').upsert(profilePayload);

    final rows = await _supabase
        .from('profiles')
        .select('id, role')
        .eq('id', registration.userId);

    final list = rows as List;

    if (list.isEmpty) {
      throw StateError(
        'Profile still missing after repair. Check profiles RLS insert/update policy.',
      );
    }

    final role = (list.first['role'] ?? '').toString().toLowerCase().trim();

    if (role != 'subtenant') {
      throw StateError(
        'Profile exists, but role was not changed to subtenant. Check profiles RLS update policy.',
      );
    }

    await _supabase
        .from('subtenant_details')
        .upsert({
          'id': registration.userId,
          'office_name': registration.officeName,
          'city': registration.city,
          'province': 'Bulacan',
          'contact_person': registration.contactPerson,
          'contact_number': registration.contactNumber,
          'email': registration.email,
          'office_address': registration.address,
          'verification_status': 'verified',
          'is_active': true,
          'approved_by': adminIdValue,
          'approved_at': reviewedAtIso,
        })
        .select('id')
        .single();
  }

  Future<List<ProvincePackage>> fetchProvincePackages() async {
    final packageRows = await _selectRows(
      'tour_packages',
      orderBy: 'created_at',
      ascending: false,
    );

    final basePackages = packageRows
        .map(ProvincePackage.fromMap)
        .toList(growable: false);

    final bookings = await fetchBookings(basePackages);
    final counts = <String, int>{};
    final revenue = <String, double>{};

    for (final booking in bookings) {
      final id = adminId(booking.packageId);
      counts.update(id, (value) => value + 1, ifAbsent: () => 1);
      revenue.update(
        id,
        (value) => value + booking.totalAmount,
        ifAbsent: () => booking.totalAmount,
      );
    }

    return packageRows
        .map((row) {
          return ProvincePackage.fromMap(
            row,
            bookingsCount: counts[adminId(row['id'])] ?? 0,
            revenue: revenue[adminId(row['id'])] ?? 0,
          );
        })
        .toList(growable: false);
  }

  Future<List<String>> fetchPackageSpotTitles(dynamic packageId) async {
    try {
      final rows = await _supabase
          .from('tour_package_spots')
          .select('sort_order, tourist_spots(title)')
          .eq('package_id', packageId)
          .order('sort_order');

      return (rows as List)
          .map((row) {
            final nested = (row as Map)['tourist_spots'];
            if (nested is! Map) return '';
            return adminString(Map<String, dynamic>.from(nested), const [
              'title',
              'name',
            ]);
          })
          .where((title) => title.trim().isNotEmpty)
          .toList(growable: false);
    } on PostgrestException {
      return const [];
    }
  }

  Future<void> updatePackageStatus(
    ProvincePackage package,
    String status,
  ) async {
    await _supabase
        .from('tour_packages')
        .update({'status': status})
        .eq('id', package.id)
        .select('id')
        .single();

    await _logAudit(
      action: 'update_package_status',
      tableName: 'tour_packages',
      recordId: adminId(package.id),
      description: 'Updated ${package.title} status to $status.',
    );
  }

  Future<void> updatePackageVisibility(
    ProvincePackage package,
    String visibility,
  ) async {
    await _supabase
        .from('tour_packages')
        .update({'visibility_status': visibility})
        .eq('id', package.id)
        .select('id')
        .single();

    await _logAudit(
      action: 'update_package_visibility',
      tableName: 'tour_packages',
      recordId: adminId(package.id),
      description: 'Updated ${package.title} visibility to $visibility.',
    );
  }

  Future<List<ProvinceSpot>> fetchProvinceSpots() async {
    final rows = await _selectRows(
      'tourist_spots',
      orderBy: 'created_at',
      ascending: false,
    );

    return rows.map(ProvinceSpot.fromMap).toList(growable: false);
  }

  Future<void> archiveSpot(ProvinceSpot spot) async {
    await _supabase
        .from('tourist_spots')
        .update({'status': 'archived'})
        .eq('id', spot.id)
        .select('id')
        .single();

    await _logAudit(
      action: 'archive_spot',
      tableName: 'tourist_spots',
      recordId: adminId(spot.id),
      description: 'Archived tourist spot ${spot.title}.',
    );
  }

  Future<void> unarchiveSpot(ProvinceSpot spot) async {
    await _supabase
        .from('tourist_spots')
        .update({'status': 'active'})
        .eq('id', spot.id)
        .select('id')
        .single();
    await _logAudit(
      action: 'unarchive_spot',
      tableName: 'tourist_spots',
      recordId: adminId(spot.id),
      description: 'Restored tourist spot ${spot.title}.',
    );
  }

  Future<void> verifySpot(ProvinceSpot spot) async {
    final admin = await loadCurrentAdminProfile();
    final now = DateTime.now().toUtc().toIso8601String();

    await _supabase
        .from('tourist_spots')
        .update({
          'verified_by': admin.id,
          'verified_at': now,
          'verification_status': 'verified',
        })
        .eq('id', spot.id)
        .select('id')
        .single();

    await _logAudit(
      action: 'verify_spot',
      tableName: 'tourist_spots',
      recordId: adminId(spot.id),
      description: 'Verified tourist spot ${spot.title}.',
    );
  }

  Future<void> flagSpot(ProvinceSpot spot) async {
    await _supabase
        .from('tourist_spots')
        .update({'verification_status': 'flagged'})
        .eq('id', spot.id)
        .select('id')
        .single();

    await _logAudit(
      action: 'flag_spot',
      tableName: 'tourist_spots',
      recordId: adminId(spot.id),
      description: 'Flagged tourist spot ${spot.title}.',
    );
  }

  Future<List<ProvinceBooking>> fetchBookings(
    List<ProvincePackage> packages,
  ) async {
    final packageById = {
      for (final package in packages) adminId(package.id): package,
    };

    final rows = await _selectRows(
      'package_bookings',
      orderBy: 'created_at',
      ascending: false,
    );

    return rows
        .map((row) {
          return ProvinceBooking.fromMap(
            row,
            package: packageById[adminId(row['package_id'])],
          );
        })
        .toList(growable: false);
  }

  Future<AdminReportData> fetchReports() async {
    final tenants = await fetchCityTenants();
    final packages = await fetchProvincePackages();
    final spots = await fetchProvinceSpots();
    final bookings = await fetchBookings(packages);
    final feedback = (await fetchFeedback()).items;

    return AdminReportData(
      tenants: tenants,
      packages: packages,
      spots: spots,
      bookings: bookings,
      feedback: feedback,
    );
  }

  Future<RevenueSummaryData> fetchRevenueSummary() async {
    final packages = await fetchProvincePackages();
    final bookings = await fetchBookings(packages);

    return RevenueSummaryData(packages: packages, bookings: bookings);
  }

  Future<TableResult<ProvinceFeedback>> fetchFeedback() async {
    final reviewRows = <_FeedbackSourceRow>[];

    for (final source in const [
      'ride_reviews',
      'ride_feedback',
      'driver_reviews',
      'package_reviews',
    ]) {
      final rows = await _selectOptionalRows(
        source,
        orderBy: 'created_at',
        ascending: false,
      );

      reviewRows.addAll(
        rows.map((row) => _FeedbackSourceRow(source: source, row: row)),
      );
    }

    if (reviewRows.isEmpty) {
      return const TableResult(available: true, items: []);
    }

    final packages = await _safeFetchProvincePackages();
    final packageById = {for (final item in packages) adminId(item.id): item};
    final bookings = await _safeFetchBookings(packages);
    final bookingById = {for (final item in bookings) adminId(item.id): item};
    final spots = await _safeFetchProvinceSpots();
    final spotById = {for (final item in spots) adminId(item.id): item};

    final profileIds = <String>{};
    for (final item in reviewRows) {
      final row = item.row;
      profileIds.addAll(
        [
          adminId(row['tourist_id']),
          adminId(row['user_id']),
          adminId(row['reviewer_id']),
          adminId(row['customer_id']),
          adminId(row['driver_id']),
          adminId(row['subject_id']),
        ].where((id) => id.isNotEmpty),
      );

      final booking = bookingById[adminId(row['booking_id'])];
      if (booking != null) {
        profileIds.addAll(
          [
            adminId(booking.raw['tourist_id']),
            adminId(booking.raw['assigned_driver_id']),
          ].where((id) => id.isNotEmpty),
        );
      }
    }

    final profileById = await _fetchProfilesByIds(profileIds);
    final items = reviewRows
        .map((item) {
          return _normalizeFeedbackRow(
            source: item.source,
            row: item.row,
            packageById: packageById,
            bookingById: bookingById,
            spotById: spotById,
            profileById: profileById,
          );
        })
        .toList(growable: false);

    items.sort((a, b) {
      final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final right = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return right.compareTo(left);
    });

    return TableResult(available: true, items: items);
  }

  Future<FeedbackTrendData> fetchFeedbackTrends() async {
    final result = await fetchFeedback();
    return FeedbackTrendData(feedback: result.items);
  }

  Future<List<Map<String, dynamic>>> _selectOptionalRows(
    String table, {
    String columns = '*',
    String? orderBy,
    bool ascending = true,
  }) async {
    try {
      return await _selectRows(
        table,
        columns: columns,
        orderBy: orderBy,
        ascending: ascending,
      );
    } on PostgrestException {
      return const [];
    }
  }

  Future<List<ProvincePackage>> _safeFetchProvincePackages() async {
    try {
      return await fetchProvincePackages();
    } on PostgrestException {
      return const [];
    }
  }

  Future<List<ProvinceBooking>> _safeFetchBookings(
    List<ProvincePackage> packages,
  ) async {
    try {
      return await fetchBookings(packages);
    } on PostgrestException {
      return const [];
    }
  }

  Future<List<ProvinceSpot>> _safeFetchProvinceSpots() async {
    try {
      return await fetchProvinceSpots();
    } on PostgrestException {
      return const [];
    }
  }

  Future<Map<String, Map<String, dynamic>>> _fetchProfilesByIds(
    Iterable<String> ids,
  ) async {
    final cleanIds = ids
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    if (cleanIds.isEmpty) return const {};

    try {
      final rows = await _supabase
          .from('profiles')
          .select('*')
          .inFilter('id', cleanIds);

      return {for (final row in _asRows(rows)) adminId(row['id']): row};
    } on PostgrestException {
      return const {};
    }
  }

  ProvinceFeedback _normalizeFeedbackRow({
    required String source,
    required Map<String, dynamic> row,
    required Map<String, ProvincePackage> packageById,
    required Map<String, ProvinceBooking> bookingById,
    required Map<String, ProvinceSpot> spotById,
    required Map<String, Map<String, dynamic>> profileById,
  }) {
    final booking =
        bookingById[adminId(row['booking_id'] ?? row['package_booking_id'])];
    final package =
        packageById[adminId(row['package_id'] ?? booking?.packageId)];
    final spot = spotById[adminId(row['spot_id'] ?? row['tourist_spot_id'])];
    final touristId = adminId(
      row['tourist_id'] ??
          row['user_id'] ??
          row['reviewer_id'] ??
          row['customer_id'] ??
          booking?.raw['tourist_id'],
    );
    final driverId = adminId(
      row['driver_id'] ??
          row['subject_id'] ??
          row['assigned_driver_id'] ??
          booking?.raw['assigned_driver_id'],
    );
    final tourist = profileById[touristId];
    final driver = profileById[driverId];

    final city = adminString(
      row,
      const ['city', 'municipality', 'locality'],
      fallback: _firstNonEmpty([
        package?.city,
        booking?.city,
        spot?.city,
        adminString(driver ?? const <String, dynamic>{}, const ['city']),
        adminString(tourist ?? const <String, dynamic>{}, const ['city']),
        'Unknown',
      ]),
    );

    final reviewerName = adminString(row, const [
      'tourist_name',
      'reviewer_name',
      'customer_name',
      'user_name',
    ], fallback: _profileName(tourist, fallback: 'Tourist'));

    final isDriverFeedback =
        source.contains('ride') ||
        source.contains('driver') ||
        driverId.isNotEmpty;
    final subjectName = adminString(
      row,
      const [
        'driver_name',
        'subject_name',
        'package_title',
        'spot_title',
        'related_title',
      ],
      fallback: _firstNonEmpty([
        isDriverFeedback ? _profileName(driver, fallback: '') : '',
        package?.title,
        spot?.title,
        booking?.packageTitle,
        isDriverFeedback ? 'Transport service' : 'Tourism experience',
      ]),
    );

    final normalized = Map<String, dynamic>.from(row)
      ..['city'] = city
      ..['tourist_name'] = reviewerName
      ..['subject_name'] = subjectName
      ..['package_title'] = package?.title ?? booking?.packageTitle ?? ''
      ..['driver_name'] = _profileName(driver, fallback: '')
      ..['spot_title'] = spot?.title ?? ''
      ..['comment'] = adminString(row, const [
        'comment',
        'review_text',
        'feedback',
        'message',
        'body',
        'content',
      ])
      ..['source_table'] = source;

    return ProvinceFeedback.fromMap(normalized, source: source, city: city);
  }

  String _profileName(Map<String, dynamic>? profile, {String fallback = ''}) {
    if (profile == null) return fallback;

    final fullName = adminString(profile, const ['full_name', 'name']);
    if (fullName.isNotEmpty) return fullName;

    final generated = [
      adminString(profile, const ['first_name']),
      adminString(profile, const ['last_name']),
    ].where((value) => value.isNotEmpty).join(' ');

    if (generated.trim().isNotEmpty) return generated.trim();
    return fallback;
  }

  String _firstNonEmpty(Iterable<String?> values) {
    for (final value in values) {
      final cleaned = value?.trim() ?? '';
      if (cleaned.isNotEmpty && cleaned.toLowerCase() != 'unknown') {
        return cleaned;
      }
    }
    return 'Unknown';
  }

  Future<TableResult<AdminPolicy>> fetchPolicies() async {
    try {
      final rows = await _selectRows(
        'tourism_policies',
        orderBy: 'created_at',
        ascending: false,
      );

      return TableResult(
        available: true,
        items: rows.map(AdminPolicy.fromMap).toList(growable: false),
      );
    } on PostgrestException {
      return const TableResult(available: false, items: []);
    }
  }

  Future<void> savePolicy({
    dynamic policyId,
    required String title,
    required String content,
    required String status,
  }) async {
    final admin = await loadCurrentAdminProfile();

    final payload = {
      'title': title.trim(),
      'content': content.trim(),
      'status': status,
      'created_by': admin.id,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };

    if (policyId == null) {
      await _supabase.from('tourism_policies').insert(payload);
    } else {
      await _supabase
          .from('tourism_policies')
          .update(payload)
          .eq('id', policyId);
    }

    await _logAudit(
      action: policyId == null ? 'create_policy' : 'update_policy',
      tableName: 'tourism_policies',
      recordId: adminId(policyId ?? 'new'),
      description: '${policyId == null ? 'Created' : 'Updated'} policy $title.',
    );
  }

  Future<void> updatePolicyStatus(AdminPolicy policy, String status) async {
    await _supabase
        .from('tourism_policies')
        .update({'status': status})
        .eq('id', policy.id);

    await _logAudit(
      action: 'update_policy_status',
      tableName: 'tourism_policies',
      recordId: adminId(policy.id),
      description: 'Updated policy ${policy.title} status to $status.',
    );
  }

  Future<TableResult<AdminCategory>> fetchCategories() async {
    try {
      final rows = await _selectRows(
        'tourism_categories',
        orderBy: 'created_at',
        ascending: false,
      );

      return TableResult(
        available: true,
        items: rows.map(AdminCategory.fromMap).toList(growable: false),
      );
    } on PostgrestException {
      return const TableResult(available: false, items: []);
    }
  }

  Future<void> saveCategory({
    dynamic categoryId,
    required String name,
    required String description,
    required String icon,
    required String status,
  }) async {
    final payload = {
      'name': name.trim(),
      'description': description.trim(),
      'icon': icon.trim(),
      'status': status,
    };

    if (categoryId == null) {
      await _supabase.from('tourism_categories').insert(payload);
    } else {
      await _supabase
          .from('tourism_categories')
          .update(payload)
          .eq('id', categoryId);
    }

    await _logAudit(
      action: categoryId == null ? 'create_category' : 'update_category',
      tableName: 'tourism_categories',
      recordId: adminId(categoryId ?? 'new'),
      description:
          '${categoryId == null ? 'Created' : 'Updated'} category $name.',
    );
  }

  Future<void> updateCategoryStatus(
    AdminCategory category,
    String status,
  ) async {
    await _supabase
        .from('tourism_categories')
        .update({'status': status})
        .eq('id', category.id);

    await _logAudit(
      action: 'update_category_status',
      tableName: 'tourism_categories',
      recordId: adminId(category.id),
      description: 'Updated category ${category.name} status to $status.',
    );
  }

  Future<void> _logAudit({
    required String action,
    required String tableName,
    required String recordId,
    required String description,
  }) async {
    try {
      final user = _supabase.auth.currentUser;

      await _supabase.from('audit_logs').insert({
        'actor_id': user?.id,
        'action': action,
        'table_name': tableName,
        'record_id': recordId,
        'description': description,
      });
    } on PostgrestException catch (error, stack) {
      developer.log(
        'Admin audit logging failed: ${error.message}',
        name: 'ProvincialAdminService',
        error: error,
        stackTrace: stack,
      );
    }
  }

  Future<void> _notifyApplicant({
    required String userId,
    required bool approved,
    required String reason,
    required String city,
  }) async {
    try {
      await _supabase.from('notifications').insert({
        'user_id': userId,
        'title': 'City admin application ${approved ? 'approved' : 'rejected'}',
        'body': approved
            ? 'Your $city tourism office account has been approved. You can sign in to the web portal now.'
            : (reason.trim().isEmpty
                  ? 'Your TourisTrike city admin application was rejected.'
                  : 'Your TourisTrike city admin application was rejected: ${reason.trim()}'),
        'type': 'city_admin_application',
        'is_read': false,
      });
    } on PostgrestException catch (error, stack) {
      developer.log(
        'Applicant notification failed: ${error.message}',
        name: 'ProvincialAdminService',
        error: error,
        stackTrace: stack,
      );
    }
  }

  Future<List<Map<String, dynamic>>> _selectRows(
    String table, {
    String columns = '*',
    Map<String, dynamic> equals = const {},
    String? orderBy,
    bool ascending = true,
  }) async {
    try {
      dynamic query = _supabase.from(table).select(columns);

      for (final entry in equals.entries) {
        query = query.eq(entry.key, entry.value);
      }

      if (orderBy != null) {
        query = query.order(orderBy, ascending: ascending);
      }

      final rows = await query;
      return _asRows(rows);
    } on PostgrestException {
      if (orderBy == null) rethrow;

      dynamic query = _supabase.from(table).select(columns);

      for (final entry in equals.entries) {
        query = query.eq(entry.key, entry.value);
      }

      final rows = await query;
      return _asRows(rows);
    }
  }

  List<Map<String, dynamic>> _asRows(dynamic rows) {
    if (rows is! List) return const [];

    return rows
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
  }

  Map<String, int> _countByCity(Iterable<String> cities) {
    final counts = <String, int>{};

    for (final city in cities) {
      if (city.trim().isEmpty) continue;
      counts.update(city, (value) => value + 1, ifAbsent: () => 1);
    }

    return counts;
  }

  (String, String) _nameParts(String fullName) {
    final cleaned = fullName.trim();
    if (cleaned.isEmpty) return ('', '');

    final parts = cleaned.split(RegExp(r'\s+'));
    if (parts.length == 1) return (parts.first, '');

    return (parts.first, parts.sublist(1).join(' '));
  }
}

class CityTenantDetailsData {
  const CityTenantDetailsData({
    required this.tenant,
    required this.packages,
    required this.spots,
    required this.bookings,
    required this.feedback,
    required this.driversCount,
  });

  final CityTenant tenant;
  final List<ProvincePackage> packages;
  final List<ProvinceSpot> spots;
  final List<ProvinceBooking> bookings;
  final List<ProvinceFeedback> feedback;
  final int driversCount;

  double get revenue => bookings.fold<double>(
    0,
    (sum, booking) => booking.status.toLowerCase() == 'completed'
        ? sum + booking.totalAmount
        : sum,
  );

  double get averageRating {
    if (feedback.isEmpty) return 0;
    return feedback.fold<double>(0, (sum, item) => sum + item.rating) /
        feedback.length;
  }
}

class _FeedbackSourceRow {
  const _FeedbackSourceRow({required this.source, required this.row});

  final String source;
  final Map<String, dynamic> row;
}
