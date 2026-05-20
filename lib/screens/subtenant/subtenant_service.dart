import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';

class SubTenantService {
  SubTenantService({SupabaseClient? client})
    : _supabase = client ?? Supabase.instance.client;

  final SupabaseClient _supabase;

  Future<SubTenantProfile> loadCurrentProfile() async {
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
      throw StateError('Profile not found. Please complete your profile.');
    }

    final profile = SubTenantProfile.fromMap(
      Map<String, dynamic>.from(row),
      email: user.email ?? '',
    );

    if (!profile.isSubTenant) {
      throw StateError('This account is not assigned as a city admin.');
    }

    if (profile.assignedCity.isEmpty) {
      throw StateError('No assigned city found for this sub-tenant profile.');
    }

    return profile;
  }

  Future<SubTenantCityProfileData> loadCityProfile(
    SubTenantProfile profile,
  ) async {
    try {
      final row = await _supabase
          .from('subtenant_details')
          .select('*')
          .eq('id', profile.id)
          .maybeSingle();

      if (row != null) {
        return SubTenantCityProfileData.fromMap(
          Map<String, dynamic>.from(row),
          profile,
        );
      }
      // Table exists but no row yet — still fully usable, no notice needed.
      return SubTenantCityProfileData.fromProfile(
        profile,
      ).copyWith(detailsTableAvailable: true);
    } on PostgrestException {
      // Table missing or access denied — surface the fallback notice.
      return SubTenantCityProfileData.fromProfile(profile);
    }
  }

  Future<void> saveCityProfile(
    SubTenantProfile profile,
    SubTenantCityProfileData data,
  ) async {
    final lockedCity = profile.assignedCity;
    final province = profile.province.isEmpty ? 'Bulacan' : profile.province;

    try {
      await _supabase.from('subtenant_details').upsert({
        'id': profile.id,
        'city': lockedCity,
        'province': province,
        'description': data.description,
        'office_name': data.tourismOfficeName,
        'contact_person': profile.displayName,
        'contact_number': data.contactNumber,
        'email': data.email,
        'office_address': data.officeAddress,
        'cover_image_url': data.coverImageUrl,
        'logo_url': data.logoImageUrl,
      });
      await _logAudit(
        actorId: profile.id,
        action: 'update_city_profile',
        tableName: 'subtenant_details',
        recordId: profile.id,
        description: 'Updated ${profile.assignedCity} city tourism profile.',
      );
      return;
    } on PostgrestException {
      // The fallback intentionally saves only columns known to exist in profiles.
    }

    await _supabase
        .from('profiles')
        .update({
          'city': lockedCity,
          'province': province,
          'mobile': data.contactNumber,
          'address': data.officeAddress,
          'profile_image_url': data.logoImageUrl,
        })
        .eq('id', profile.id);
  }

  Future<SubTenantDashboardData> loadDashboard() async {
    final profile = await loadCurrentProfile();
    final city = profile.assignedCity;

    final spotsRows = await _supabase
        .from('tourist_spots')
        .select('id')
        .eq('city', city);
    final packageRows = await _supabase
        .from('tour_packages')
        .select('id')
        .eq('city', city);
    final driverRows = await _supabase
        .from('profiles')
        .select('id')
        .eq('role', 'driver')
        .eq('city', city);

    final packageIds = (packageRows as List)
        .map((row) => (row as Map<String, dynamic>)['id'])
        .where((id) => id != null)
        .toList(growable: false);

    final recentBookings = await fetchBookings(
      profile,
      packageIdsOverride: packageIds,
      limit: 5,
    );

    final pendingBookings =
        recentBookings.where((booking) => booking.status == 'pending').length +
        await _countBookingsByStatuses(packageIds, const [
          'pending',
        ], excludeRecentIds: recentBookings.map((e) => e.id).toSet());

    final activeTours = await _countBookingsByStatuses(packageIds, const [
      'confirmed',
      'active',
    ]);
    final announcements = await fetchAnnouncements(profile);

    return SubTenantDashboardData(
      profile: profile,
      totalSpots: (spotsRows as List).length,
      totalPackages: packageIds.length,
      totalDrivers: (driverRows as List).length,
      pendingBookings: pendingBookings,
      activeTours: activeTours,
      recentBookings: recentBookings,
      announcementsTableAvailable: announcements.tableAvailable,
      announcements: announcements.items.take(3).toList(growable: false),
    );
  }

  Future<int> _countBookingsByStatuses(
    List<dynamic> packageIds,
    List<String> statuses, {
    Set<dynamic> excludeRecentIds = const {},
  }) async {
    if (packageIds.isEmpty) return 0;

    dynamic query = _supabase
        .from('package_bookings')
        .select('id, status')
        .inFilter('package_id', packageIds);

    if (statuses.length == 1) {
      query = query.eq('status', statuses.first);
    } else {
      query = query.inFilter('status', statuses);
    }

    final rows = await query;
    return (rows as List)
        .where((row) => !excludeRecentIds.contains((row as Map)['id']))
        .length;
  }

  Future<List<SubTenantSpot>> fetchSpots(SubTenantProfile profile) async {
    final rows = await _supabase
        .from('tourist_spots')
        .select('*')
        .eq('city', profile.assignedCity)
        .order('title');

    return (rows as List)
        .map((row) => SubTenantSpot.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<CitySpotSuggestion>> loadAiSpotSuggestions(
    SubTenantProfile profile, {
    List<SubTenantSpot> existingSpots = const [],
  }) async {
    final scopedSpots = existingSpots
        .where((spot) => spot.city == profile.assignedCity)
        .toList(growable: false);

    final center =
        const CitySpotSuggestionService().centerForCity(profile.assignedCity) ??
        CitySpotSuggestionService.defaultBulacanCenter;

    return const CitySpotSuggestionService().fetchSuggestions(
      city: profile.assignedCity,
      province: profile.province.isEmpty ? 'Bulacan' : profile.province,
      center: center,
      limit: 6,
      excludeTitles: scopedSpots.map((spot) => spot.title).toSet(),
    );
  }

  Future<SubTenantSpot?> fetchSpotById(
    SubTenantProfile profile,
    dynamic spotId,
  ) async {
    final row = await _supabase
        .from('tourist_spots')
        .select('*')
        .eq('id', spotId)
        .eq('city', profile.assignedCity)
        .maybeSingle();

    if (row == null) return null;
    return SubTenantSpot.fromMap(Map<String, dynamic>.from(row));
  }

  Future<void> saveSpot({
    required SubTenantProfile profile,
    required dynamic spotId,
    required Map<String, dynamic> values,
  }) async {
    final payload = {
      ...values,
      'city': profile.assignedCity,
      'province': profile.province.isEmpty ? 'Bulacan' : profile.province,
    };

    try {
      if (spotId == null) {
        final inserted = await _supabase
            .from('tourist_spots')
            .insert(payload)
            .select('id')
            .single();
        await _logAudit(
          actorId: profile.id,
          action: 'create_spot',
          tableName: 'tourist_spots',
          recordId: stId(inserted['id']),
          description: 'Created tourist spot ${values['title']}.',
        );
      } else {
        await _supabase
            .from('tourist_spots')
            .update(payload)
            .eq('id', spotId)
            .eq('city', profile.assignedCity);
        await _logAudit(
          actorId: profile.id,
          action: 'update_spot',
          tableName: 'tourist_spots',
          recordId: stId(spotId),
          description: 'Updated tourist spot ${values['title']}.',
        );
      }
    } on PostgrestException {
      final retry = Map<String, dynamic>.from(payload)..remove('rating');
      if (spotId == null) {
        final inserted = await _supabase
            .from('tourist_spots')
            .insert(retry)
            .select('id')
            .single();
        await _logAudit(
          actorId: profile.id,
          action: 'create_spot',
          tableName: 'tourist_spots',
          recordId: stId(inserted['id']),
          description: 'Created tourist spot ${values['title']}.',
        );
      } else {
        await _supabase
            .from('tourist_spots')
            .update(retry)
            .eq('id', spotId)
            .eq('city', profile.assignedCity);
        await _logAudit(
          actorId: profile.id,
          action: 'update_spot',
          tableName: 'tourist_spots',
          recordId: stId(spotId),
          description: 'Updated tourist spot ${values['title']}.',
        );
      }
    }
  }

  Future<void> archiveSpot(SubTenantProfile profile, SubTenantSpot spot) async {
    await _supabase
        .from('tourist_spots')
        .update({'status': 'archived'})
        .eq('id', spot.id)
        .eq('city', profile.assignedCity);
    await _logAudit(
      actorId: profile.id,
      action: 'archive_spot',
      tableName: 'tourist_spots',
      recordId: stId(spot.id),
      description: 'Archived tourist spot ${spot.title}.',
    );
  }

  Future<List<SubTenantPackage>> fetchPackages(SubTenantProfile profile) async {
    final rows = await _supabase
        .from('tour_packages')
        .select('*')
        .eq('city', profile.assignedCity)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((row) => SubTenantPackage.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<SubTenantPackage?> fetchPackageById(
    SubTenantProfile profile,
    dynamic packageId,
  ) async {
    final row = await _supabase
        .from('tour_packages')
        .select('*')
        .eq('id', packageId)
        .eq('city', profile.assignedCity)
        .maybeSingle();

    if (row == null) return null;
    return SubTenantPackage.fromMap(Map<String, dynamic>.from(row));
  }

  Future<dynamic> savePackage({
    required SubTenantProfile profile,
    required dynamic packageId,
    required Map<String, dynamic> values,
  }) async {
    final payload = {
      ...values,
      'city': profile.assignedCity,
      'submitted_by': profile.id,
      'submitted_by_name': profile.displayName,
    };

    if (packageId == null) {
      final inserted = await _supabase
          .from('tour_packages')
          .insert(payload)
          .select('id')
          .single();
      await _logAudit(
        actorId: profile.id,
        action: 'create_package',
        tableName: 'tour_packages',
        recordId: stId(inserted['id']),
        description: 'Created tour package ${values['title']}.',
      );
      return inserted['id'];
    }

    await _supabase
        .from('tour_packages')
        .update(payload)
        .eq('id', packageId)
        .eq('city', profile.assignedCity);
    await _logAudit(
      actorId: profile.id,
      action: 'update_package',
      tableName: 'tour_packages',
      recordId: stId(packageId),
      description: 'Updated tour package ${values['title']}.',
    );
    return packageId;
  }

  Future<void> updatePackageStatus(
    SubTenantProfile profile,
    SubTenantPackage package,
    String status,
  ) async {
    await _supabase
        .from('tour_packages')
        .update({'status': status})
        .eq('id', package.id)
        .eq('city', profile.assignedCity);
    await _logAudit(
      actorId: profile.id,
      action: 'update_package_status',
      tableName: 'tour_packages',
      recordId: stId(package.id),
      description: 'Updated package ${package.title} status to $status.',
    );
  }

  Future<void> updatePackageVisibility(
    SubTenantProfile profile,
    SubTenantPackage package,
    String visibility,
  ) async {
    await _supabase
        .from('tour_packages')
        .update({'visibility_status': visibility})
        .eq('id', package.id)
        .eq('city', profile.assignedCity);
    await _logAudit(
      actorId: profile.id,
      action: 'update_package_visibility',
      tableName: 'tour_packages',
      recordId: stId(package.id),
      description:
          'Updated package ${package.title} visibility to $visibility.',
    );
  }

  Future<List<PackageItineraryDay>> fetchItinerary(
    SubTenantProfile profile,
    dynamic packageId,
  ) async {
    await _assertPackageInCity(profile, packageId);

    final dayRows = await _supabase
        .from('tour_package_days')
        .select('*')
        .eq('package_id', packageId)
        .order('day_number');

    final days = (dayRows as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    if (days.isEmpty) return const [];

    final dayIds = days.map((day) => day['id']).toList(growable: false);
    final itemRows = await _supabase
        .from('tour_package_day_items')
        .select('*')
        .inFilter('day_id', dayIds)
        .order('sort_order');

    final items = (itemRows as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final spotIds = items
        .map((item) => item['spot_id'])
        .where((id) => id != null)
        .toSet()
        .toList(growable: false);

    final spotById = <String, SubTenantSpot>{};
    if (spotIds.isNotEmpty) {
      final spots = await _supabase
          .from('tourist_spots')
          .select('*')
          .inFilter('id', spotIds)
          .eq('city', profile.assignedCity);
      for (final row in spots as List) {
        final spot = SubTenantSpot.fromMap(Map<String, dynamic>.from(row));
        spotById[stId(spot.id)] = spot;
      }
    }

    final itemsByDay = <String, List<PackageItineraryItem>>{};
    for (final item in items) {
      final dayId = stId(item['day_id']);
      final spot = spotById[stId(item['spot_id'])];
      itemsByDay.putIfAbsent(dayId, () => []);
      itemsByDay[dayId]!.add(PackageItineraryItem.fromMap(item, spot));
    }

    return days
        .map(
          (day) => PackageItineraryDay.fromMap(
            day,
            itemsByDay[stId(day['id'])] ?? const [],
          ),
        )
        .toList(growable: false);
  }

  Future<dynamic> addPackageDay(
    SubTenantProfile profile,
    dynamic packageId,
    int dayNumber,
  ) async {
    await _assertPackageInCity(profile, packageId);
    final inserted = await _supabase
        .from('tour_package_days')
        .insert({
          'package_id': packageId,
          'day_number': dayNumber,
          'title': 'Day $dayNumber',
        })
        .select('id')
        .single();
    return inserted['id'];
  }

  Future<void> updatePackageDayTitle(
    SubTenantProfile profile,
    dynamic packageId,
    dynamic dayId,
    String title,
  ) async {
    await _assertPackageInCity(profile, packageId);
    await _supabase
        .from('tour_package_days')
        .update({'title': title.trim().isEmpty ? 'Day' : title.trim()})
        .eq('id', dayId)
        .eq('package_id', packageId);
  }

  Future<void> saveItineraryItem({
    required SubTenantProfile profile,
    required dynamic packageId,
    required dynamic dayId,
    required dynamic itemId,
    required dynamic spotId,
    required String timeLabel,
    required String note,
    required int sortOrder,
  }) async {
    await _assertPackageInCity(profile, packageId);
    await _assertSpotInCity(profile, spotId);

    final payload = {
      'day_id': dayId,
      'spot_id': spotId,
      'time_label': timeLabel,
      'note': note,
      'sort_order': sortOrder,
    };

    if (itemId == null) {
      await _supabase.from('tour_package_day_items').insert(payload);
    } else {
      await _supabase
          .from('tour_package_day_items')
          .update(payload)
          .eq('id', itemId)
          .eq('day_id', dayId);
    }

    await _ensurePackageSpot(packageId, spotId, sortOrder);
  }

  Future<void> updateItineraryItemOrder(
    SubTenantProfile profile,
    dynamic packageId,
    List<PackageItineraryItem> items,
  ) async {
    await _assertPackageInCity(profile, packageId);
    for (var i = 0; i < items.length; i++) {
      await _supabase
          .from('tour_package_day_items')
          .update({'sort_order': i})
          .eq('id', items[i].id);
    }
  }

  Future<void> deleteItineraryItem(
    SubTenantProfile profile,
    dynamic packageId,
    PackageItineraryItem item,
  ) async {
    await _assertPackageInCity(profile, packageId);
    await _supabase.from('tour_package_day_items').delete().eq('id', item.id);
  }

  Future<void> _ensurePackageSpot(
    dynamic packageId,
    dynamic spotId,
    int sortOrder,
  ) async {
    final existing = await _supabase
        .from('tour_package_spots')
        .select('package_id')
        .eq('package_id', packageId)
        .eq('spot_id', spotId)
        .maybeSingle();

    if (existing != null) return;

    await _supabase.from('tour_package_spots').insert({
      'package_id': packageId,
      'spot_id': spotId,
      'sort_order': sortOrder,
    });
  }

  Future<List<SubTenantDriver>> fetchDrivers(SubTenantProfile profile) async {
    final profileRows = await _supabase
        .from('profiles')
        .select('*')
        .eq('role', 'driver')
        .eq('city', profile.assignedCity)
        .order('full_name');

    final driverProfiles = (profileRows as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);
    final driverIds = driverProfiles.map((row) => row['id']).toList();

    final detailsByDriver = <String, Map<String, dynamic>>{};
    final docsByDriver = <String, Map<String, dynamic>>{};

    if (driverIds.isNotEmpty) {
      final detailsRows = await _supabase
          .from('driver_details')
          .select('*')
          .inFilter('driver_id', driverIds);
      for (final row in detailsRows as List) {
        final details = Map<String, dynamic>.from(row);
        detailsByDriver[stId(details['driver_id'])] = details;
      }

      final docsRows = await _supabase
          .from('driver_documents')
          .select('*')
          .inFilter('driver_id', driverIds);
      for (final row in docsRows as List) {
        final docs = Map<String, dynamic>.from(row);
        docsByDriver[stId(docs['driver_id'])] = docs;
      }
    }

    return driverProfiles
        .map(
          (driverProfile) => SubTenantDriver(
            profile: driverProfile,
            details: detailsByDriver[stId(driverProfile['id'])],
            documents: docsByDriver[stId(driverProfile['id'])],
          ),
        )
        .toList(growable: false);
  }

  Future<SubTenantDriver?> fetchDriverById(
    SubTenantProfile profile,
    String driverId,
  ) async {
    final drivers = await fetchDrivers(profile);
    for (final driver in drivers) {
      if (driver.id == driverId) return driver;
    }
    return null;
  }

  Future<void> updateDriverStatus(
    SubTenantProfile profile,
    SubTenantDriver driver,
    String status,
  ) async {
    if (driver.city != profile.assignedCity) {
      throw StateError('Driver is outside the assigned city.');
    }

    final payload = <String, dynamic>{
      'status': status,
      if (status == 'approved') ...{
        'approved_by': profile.id,
        'approved_at': DateTime.now().toUtc().toIso8601String(),
        'suspended_reason': null,
      },
      if (status == 'suspended') 'suspended_reason': 'Suspended by city admin',
    };
    await _supabase
        .from('driver_details')
        .update(payload)
        .eq('driver_id', driver.id);
    await _supabase
        .from('driver_applications')
        .update({
          'status': status,
          'reviewed_by': profile.id,
          'reviewed_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('driver_id', driver.id)
        .eq('city', profile.assignedCity);
    await _notifyUser(
      userId: driver.id,
      title: 'Driver application update',
      body: 'Your driver status is now $status.',
      type: 'driver_status',
    );
    await _logAudit(
      actorId: profile.id,
      action: 'update_driver_status',
      tableName: 'driver_details',
      recordId: driver.id,
      description: 'Updated driver ${driver.fullName} status to $status.',
    );
  }

  Future<List<SubTenantBooking>> fetchBookings(
    SubTenantProfile profile, {
    String status = 'all',
    int? limit,
    List<dynamic>? packageIdsOverride,
  }) async {
    final packageRows = await _supabase
        .from('tour_packages')
        .select('*')
        .eq('city', profile.assignedCity);

    final packages = (packageRows as List)
        .map((row) => SubTenantPackage.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
    final packageById = {for (final item in packages) stId(item.id): item};
    final packageIds =
        packageIdsOverride ?? packages.map((item) => item.id).toList();

    if (packageIds.isEmpty) return const [];

    dynamic query = _supabase
        .from('package_bookings')
        .select('*')
        .inFilter('package_id', packageIds);

    if (status != 'all') {
      query = query.eq('status', status);
    }

    query = query.order('created_at', ascending: false);
    if (limit != null) query = query.limit(limit);

    final bookingRows = await query;
    final bookings = (bookingRows as List)
        .map((row) => Map<String, dynamic>.from(row))
        .toList(growable: false);

    final touristIds = bookings
        .map((row) => stString(row, const ['tourist_id', 'user_id']))
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);

    final touristById = <String, Map<String, dynamic>>{};
    if (touristIds.isNotEmpty) {
      final touristRows = await _supabase
          .from('profiles')
          .select('*')
          .inFilter('id', touristIds);
      for (final row in touristRows as List) {
        final tourist = Map<String, dynamic>.from(row);
        touristById[stId(tourist['id'])] = tourist;
      }
    }

    return bookings
        .map(
          (row) => SubTenantBooking(
            raw: row,
            package: packageById[stId(row['package_id'])],
            tourist:
                touristById[stString(row, const ['tourist_id', 'user_id'])],
          ),
        )
        .toList(growable: false);
  }

  Future<SubTenantBooking?> fetchBookingById(
    SubTenantProfile profile,
    dynamic bookingId,
  ) async {
    final bookings = await fetchBookings(profile);
    for (final booking in bookings) {
      if (stId(booking.id) == stId(bookingId)) return booking;
    }
    return null;
  }

  Future<void> updateBookingStatus(
    SubTenantProfile profile,
    SubTenantBooking booking,
    String status,
  ) async {
    await _assertPackageInCity(profile, booking.packageId);
    await _supabase
        .from('package_bookings')
        .update({'status': status})
        .eq('id', booking.id)
        .eq('package_id', booking.packageId);
  }

  Future<void> assignDriverToBooking(
    SubTenantProfile profile,
    SubTenantBooking booking,
    SubTenantDriver driver,
  ) async {
    await _assertPackageInCity(profile, booking.packageId);
    if (driver.city != profile.assignedCity) {
      throw StateError('Driver is outside the assigned city.');
    }

    await _supabase
        .from('package_bookings')
        .update({'assigned_driver_id': driver.id})
        .eq('id', booking.id)
        .eq('package_id', booking.packageId);
    await _supabase.from('booking_driver_assignments').insert({
      'booking_id': booking.id,
      'driver_id': driver.id,
      'assigned_by': profile.id,
      'status': 'assigned',
    });
    await _notifyUser(
      userId: driver.id,
      title: 'New package assignment',
      body: 'You have been assigned to ${booking.packageTitle}.',
      type: 'booking_assignment',
    );
    await _logAudit(
      actorId: profile.id,
      action: 'assign_driver',
      tableName: 'package_bookings',
      recordId: stId(booking.id),
      description: 'Assigned ${driver.fullName} to booking ${booking.id}.',
    );
  }

  Future<SubTenantReportData> fetchReports(SubTenantProfile profile) async {
    final spots = await fetchSpots(profile);
    final packages = await fetchPackages(profile);
    final packageIds = packages.map((item) => item.id).toList(growable: false);
    final bookings = await fetchBookings(
      profile,
      packageIdsOverride: packageIds,
    );

    final completed = bookings
        .where((booking) => booking.status == 'completed')
        .toList();
    final cancelled = bookings
        .where((booking) => booking.status == 'cancelled')
        .toList();
    final revenue = completed.fold<double>(
      0,
      (sum, booking) => sum + booking.totalAmount,
    );

    final countsByPackage = <String, int>{};
    for (final booking in bookings) {
      countsByPackage.update(
        stId(booking.packageId),
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    final topPackages = [...packages]
      ..sort(
        (a, b) => (countsByPackage[stId(b.id)] ?? 0).compareTo(
          countsByPackage[stId(a.id)] ?? 0,
        ),
      );

    final topSpots = await _fetchTopViewedSpots(spots);
    final feedback = await fetchFeedback(profile);

    final averageRating = feedback.isEmpty
        ? 0.0
        : feedback.fold<double>(0, (sum, item) => sum + item.rating) /
              feedback.length;

    return SubTenantReportData(
      totalSpots: spots.length,
      totalPackages: packages.length,
      totalBookings: bookings.length,
      completedBookings: completed.length,
      cancelledBookings: cancelled.length,
      estimatedRevenue: revenue,
      topPackages: topPackages
          .take(5)
          .map(
            (item) => SubTenantReportRow(
              title: item.title,
              subtitle: item.status,
              value: '${countsByPackage[stId(item.id)] ?? 0} bookings',
            ),
          )
          .toList(growable: false),
      topSpots: topSpots,
      averageRating: averageRating,
      feedbackCount: feedback.length,
    );
  }

  Future<List<SubTenantReportRow>> _fetchTopViewedSpots(
    List<SubTenantSpot> spots,
  ) async {
    if (spots.isEmpty) return const [];

    try {
      final spotIds = spots.map((spot) => spot.id).toList(growable: false);
      final rows = await _supabase
          .from('tourist_spot_views')
          .select('spot_id')
          .inFilter('spot_id', spotIds);

      final counts = <String, int>{};
      for (final row in rows as List) {
        final id = stId((row as Map)['spot_id']);
        counts.update(id, (value) => value + 1, ifAbsent: () => 1);
      }

      final sorted = [...spots]
        ..sort(
          (a, b) =>
              (counts[stId(b.id)] ?? 0).compareTo(counts[stId(a.id)] ?? 0),
        );

      return sorted
          .take(5)
          .map(
            (spot) => SubTenantReportRow(
              title: spot.title,
              subtitle: spot.barangay,
              value: '${counts[stId(spot.id)] ?? 0} views',
            ),
          )
          .toList(growable: false);
    } on PostgrestException {
      return const [];
    }
  }

  Future<List<SubTenantFeedback>> fetchFeedback(
    SubTenantProfile profile,
  ) async {
    final drivers = await fetchDrivers(profile);
    final driverIds = drivers
        .map((driver) => driver.id)
        .toList(growable: false);
    if (driverIds.isEmpty) return const [];

    try {
      final rows = await _supabase
          .from('ride_reviews')
          .select('*')
          .inFilter('driver_id', driverIds)
          .order('created_at', ascending: false);

      final reviewRows = (rows as List)
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);

      final touristIds = reviewRows
          .map((row) => stString(row, const ['tourist_id', 'reviewer_id']))
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList(growable: false);

      final touristById = <String, Map<String, dynamic>>{};
      if (touristIds.isNotEmpty) {
        final touristRows = await _supabase
            .from('profiles')
            .select('*')
            .inFilter('id', touristIds);
        for (final row in touristRows as List) {
          final tourist = Map<String, dynamic>.from(row);
          touristById[stId(tourist['id'])] = tourist;
        }
      }

      final driverById = {for (final driver in drivers) driver.id: driver};

      return reviewRows
          .map((row) {
            final tourist =
                touristById[stString(row, const ['tourist_id', 'reviewer_id'])];
            final driver = driverById[stString(row, const ['driver_id'])];
            return SubTenantFeedback(
              id: row['id'],
              rating: stDouble(row['rating']),
              comment: stString(row, const ['comment', 'feedback', 'body']),
              touristName: tourist == null
                  ? 'Tourist'
                  : stString(tourist, const ['full_name'], fallback: 'Tourist'),
              driverName: driver?.fullName ?? 'Driver',
              relatedLabel: stString(row, const ['ride_id', 'package_id']),
              createdAt: stDate(row['created_at']),
            );
          })
          .toList(growable: false);
    } on PostgrestException {
      return const [];
    }
  }

  Future<SubTenantAnnouncementsResult> fetchAnnouncements(
    SubTenantProfile profile,
  ) async {
    try {
      final rows = await _supabase
          .from('city_announcements')
          .select('*')
          .eq('city', profile.assignedCity)
          .order('created_at', ascending: false);

      return SubTenantAnnouncementsResult(
        tableAvailable: true,
        items: (rows as List)
            .map(
              (row) =>
                  SubTenantAnnouncement.fromMap(Map<String, dynamic>.from(row)),
            )
            .toList(growable: false),
      );
    } on PostgrestException {
      return const SubTenantAnnouncementsResult(
        tableAvailable: false,
        items: [],
      );
    }
  }

  Future<void> saveAnnouncement({
    required SubTenantProfile profile,
    required dynamic announcementId,
    required String title,
    required String body,
    required String status,
  }) async {
    final payload = {
      'created_by': profile.id,
      'city': profile.assignedCity,
      'title': title.trim(),
      'body': body.trim(),
      'status': status,
    };

    if (announcementId == null) {
      final inserted = await _supabase
          .from('city_announcements')
          .insert(payload)
          .select('id')
          .single();
      await _logAudit(
        actorId: profile.id,
        action: 'create_announcement',
        tableName: 'city_announcements',
        recordId: stId(inserted['id']),
        description: 'Created announcement $title.',
      );
    } else {
      await _supabase
          .from('city_announcements')
          .update(payload)
          .eq('id', announcementId)
          .eq('city', profile.assignedCity);
      await _logAudit(
        actorId: profile.id,
        action: 'update_announcement',
        tableName: 'city_announcements',
        recordId: stId(announcementId),
        description: 'Updated announcement $title.',
      );
    }
  }

  Future<void> deleteAnnouncement(
    SubTenantProfile profile,
    SubTenantAnnouncement announcement,
  ) async {
    await _supabase
        .from('city_announcements')
        .delete()
        .eq('id', announcement.id)
        .eq('city', profile.assignedCity);
    await _logAudit(
      actorId: profile.id,
      action: 'delete_announcement',
      tableName: 'city_announcements',
      recordId: stId(announcement.id),
      description: 'Deleted announcement ${announcement.title}.',
    );
  }

  Future<SubTenantSpot> upsertSpotFromGoogle({
    required SubTenantProfile profile,
    required String title,
    required String description,
    required String address,
    required double latitude,
    required double longitude,
    required String imageUrl,
    required double rating,
    required String tag,
    required String googlePlaceId,
    String googlePhotoReference = '',
  }) async {
    try {
      final existingByPlaceId = await _supabase
          .from('tourist_spots')
          .select('*')
          .eq('city', profile.assignedCity)
          .eq('google_place_id', googlePlaceId)
          .maybeSingle();
      if (existingByPlaceId != null) {
        return SubTenantSpot.fromMap(
          Map<String, dynamic>.from(existingByPlaceId),
        );
      }
    } on PostgrestException {
      // Fallback to title matching if the migration is not applied yet.
    }

    final existingByTitle = await _supabase
        .from('tourist_spots')
        .select('*')
        .eq('city', profile.assignedCity)
        .ilike('title', title)
        .maybeSingle();

    if (existingByTitle != null) {
      return SubTenantSpot.fromMap(Map<String, dynamic>.from(existingByTitle));
    }

    final payload = <String, dynamic>{
      'title': title,
      'description': description.isNotEmpty ? description : title,
      'address': address,
      'city': profile.assignedCity,
      'municipality': profile.assignedCity,
      'province': profile.province.isEmpty ? 'Bulacan' : profile.province,
      'barangay': '',
      'latitude': latitude,
      'longitude': longitude,
      'image_url': imageUrl,
      'status': 'active',
      'rating': rating,
      'source_type': 'google_places',
      'google_place_id': googlePlaceId,
      'google_photo_reference': googlePhotoReference,
      'verification_status': 'pending',
    };

    try {
      final row = await _supabase
          .from('tourist_spots')
          .insert(payload)
          .select('*')
          .single();
      return SubTenantSpot.fromMap(Map<String, dynamic>.from(row));
    } on PostgrestException {
      // Retry without rating in case the column type differs
      final retry = Map<String, dynamic>.from(payload)
        ..remove('rating')
        ..remove('source_type')
        ..remove('google_place_id')
        ..remove('google_photo_reference')
        ..remove('municipality');
      final row = await _supabase
          .from('tourist_spots')
          .insert(retry)
          .select('*')
          .single();
      return SubTenantSpot.fromMap(Map<String, dynamic>.from(row));
    }
  }

  Future<List<SubTenantSpot>> loadCityTouristSpots(
    SubTenantProfile profile,
  ) async {
    final rows = await _supabase
        .from('tourist_spots')
        .select('*')
        .eq('city', profile.assignedCity)
        .neq('status', 'archived')
        .order('rating', ascending: false);

    return (rows as List)
        .map((row) => SubTenantSpot.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  Future<List<SubTenantCategory>> loadTourismCategories() async {
    try {
      final rows = await _supabase
          .from('tourism_categories')
          .select('*')
          .order('name');
      return (rows as List)
          .map(
            (row) => SubTenantCategory.fromMap(Map<String, dynamic>.from(row)),
          )
          .toList(growable: false);
    } on PostgrestException {
      return const [];
    }
  }

  Future<Set<dynamic>> loadPopularSpotIdsByCity(String city) async {
    try {
      final pkgRows = await _supabase
          .from('tour_packages')
          .select('id')
          .eq('city', city);

      final pkgIds = (pkgRows as List).map((r) => (r as Map)['id']).toList();
      if (pkgIds.isEmpty) return const {};

      final rows = await _supabase
          .from('tour_package_spots')
          .select('spot_id')
          .inFilter('package_id', pkgIds);

      final counts = <dynamic, int>{};
      for (final row in rows as List) {
        final id = (row as Map)['spot_id'];
        counts[id] = (counts[id] ?? 0) + 1;
      }

      final sorted = counts.keys.toList()
        ..sort((a, b) => (counts[b] ?? 0).compareTo(counts[a] ?? 0));
      return sorted.toSet();
    } on PostgrestException {
      return const {};
    }
  }

  Future<List<SelectedPackageSpot>> loadPackageSelectedSpots(
    SubTenantProfile profile,
    dynamic packageId,
  ) async {
    try {
      final linkRows = await _supabase
          .from('tour_package_spots')
          .select(
            'spot_id, sort_order, opening_time, closing_time, '
            'estimated_arrival_time, estimated_duration_minutes, '
            'recommended_visit_duration_minutes',
          )
          .eq('package_id', packageId)
          .order('sort_order');

      if ((linkRows as List).isEmpty) return const [];

      final spotIds = linkRows.map((r) => (r as Map)['spot_id']).toList();
      final spotRows = await _supabase
          .from('tourist_spots')
          .select('*')
          .inFilter('id', spotIds)
          .eq('city', profile.assignedCity);

      final spotsById = <String, SubTenantSpot>{};
      for (final row in spotRows as List) {
        final spot = SubTenantSpot.fromMap(Map<String, dynamic>.from(row));
        spotsById[stId(spot.id)] = spot;
      }

      return linkRows
          .map((r) {
            final row = Map<String, dynamic>.from(r as Map);
            final spot = spotsById[stId(row['spot_id'])];
            if (spot == null) return null;
            return SelectedPackageSpot(
              spot: spot,
              sortOrder: stInt(row['sort_order']),
              openingTime: stString(row, const ['opening_time']),
              closingTime: stString(row, const ['closing_time']),
              estimatedArrivalTime: stString(
                row,
                const ['estimated_arrival_time'],
              ),
              estimatedDurationMinutes: stInt(
                row['estimated_duration_minutes'],
              ),
              recommendedVisitDurationMinutes: stInt(
                row['recommended_visit_duration_minutes'],
              ),
            );
          })
          .whereType<SelectedPackageSpot>()
          .toList(growable: false);
    } on PostgrestException {
      return const [];
    }
  }

  Future<void> savePackageSelectedSpots({
    required dynamic packageId,
    required List<SelectedPackageSpot> selectedSpots,
  }) async {
    await _supabase
        .from('tour_package_spots')
        .delete()
        .eq('package_id', packageId);

    if (selectedSpots.isEmpty) return;

    await _supabase.from('tour_package_spots').insert([
      for (var i = 0; i < selectedSpots.length; i++)
        {
          'package_id': packageId,
          'spot_id': selectedSpots[i].spot.id,
          'sort_order': i,
          'opening_time': selectedSpots[i].openingTime.isEmpty
              ? null
              : selectedSpots[i].openingTime,
          'closing_time': selectedSpots[i].closingTime.isEmpty
              ? null
              : selectedSpots[i].closingTime,
          'estimated_arrival_time': selectedSpots[i].estimatedArrivalTime.isEmpty
              ? null
              : selectedSpots[i].estimatedArrivalTime,
          'estimated_duration_minutes': selectedSpots[i].estimatedDurationMinutes > 0
              ? selectedSpots[i].estimatedDurationMinutes
              : null,
          'recommended_visit_duration_minutes':
              selectedSpots[i].recommendedVisitDurationMinutes > 0
                  ? selectedSpots[i].recommendedVisitDurationMinutes
                  : null,
        },
    ]);
  }

  Future<void> _notifyUser({
    required String userId,
    required String title,
    required String body,
    required String type,
  }) async {
    await _supabase.from('notifications').insert({
      'user_id': userId,
      'title': title,
      'body': body,
      'type': type,
      'is_read': false,
    });
  }

  Future<void> _logAudit({
    required String actorId,
    required String action,
    required String tableName,
    required String recordId,
    required String description,
  }) async {
    try {
      await _supabase.from('audit_logs').insert({
        'actor_id': actorId,
        'action': action,
        'table_name': tableName,
        'record_id': recordId,
        'description': description,
      });
    } on PostgrestException {
      // Audit is best-effort; a missing/inaccessible table must not block the main operation.
    }
  }

  Future<void> _assertPackageInCity(
    SubTenantProfile profile,
    dynamic packageId,
  ) async {
    final row = await _supabase
        .from('tour_packages')
        .select('id')
        .eq('id', packageId)
        .eq('city', profile.assignedCity)
        .maybeSingle();

    if (row == null) {
      throw StateError('Package is outside the assigned city.');
    }
  }

  Future<void> _assertSpotInCity(
    SubTenantProfile profile,
    dynamic spotId,
  ) async {
    final row = await _supabase
        .from('tourist_spots')
        .select('id')
        .eq('id', spotId)
        .eq('city', profile.assignedCity)
        .maybeSingle();

    if (row == null) {
      throw StateError('Tourist spot is outside the assigned city.');
    }
  }
}
