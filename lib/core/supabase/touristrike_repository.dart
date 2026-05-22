import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';

class TourisTrikeTables {
  const TourisTrikeTables._();

  static const profiles = 'profiles';
  static const adminSettings = 'admin_settings';
  static const auditLogs = 'audit_logs';
  static const bookingDriverAssignments = 'booking_driver_assignments';
  static const bookingItineraryItems = 'booking_itinerary_items';
  static const cityAnnouncements = 'city_announcements';
  static const customizedPackageSpots = 'customized_package_spots';
  static const cityTenantRegistrations = 'city_tenant_registrations';
  static const driverApplications = 'driver_applications';
  static const driverDetails = 'driver_details';
  static const driverDocuments = 'driver_documents';
  static const emergencyContacts = 'emergency_contacts';
  static const notifications = 'notifications';
  static const packageBookings = 'package_bookings';
  static const packageActivities = 'package_activities';
  static const payments = 'payments';
  static const rides = 'rides';
  static const rideFeedback = 'ride_feedback';
  static const rideReviews = 'ride_reviews';
  static const savedPlaces = 'saved_places';
  static const subtenantDetails = 'subtenant_details';
  static const tourPackageDayItems = 'tour_package_day_items';
  static const tourPackageDays = 'tour_package_days';
  static const tourPackageSpots = 'tour_package_spots';
  static const tourPackageViews = 'tour_package_views';
  static const tourPackages = 'tour_packages';
  static const tourismCategories = 'tourism_categories';
  static const tourismPolicies = 'tourism_policies';
  static const touristSpotImages = 'tourist_spot_images';
  static const touristSpotViews = 'tourist_spot_views';
  static const touristSpots = 'tourist_spots';
  static const conversations = 'conversations';
  static const messages = 'messages';
  static const wallets = 'wallets';
  static const walletTransactions = 'wallet_transactions';
  static const bookingDrivers = 'booking_drivers';
  static const driverLiveLocations = 'driver_live_locations';
  static const tripStatusLogs = 'trip_status_logs';
  static const driverReviews = 'driver_reviews';
  static const sharedTripLinks = 'shared_trip_links';
  static const sharedTripAccessLogs = 'shared_trip_access_logs';
}

class TourisTrikeRepository {
  static const activeTourErrorMessage =
      'You already have an active tour. Please complete or cancel it before booking another package.';
  static const Set<String> approvedDriverStatuses = {
    'active',
    'approved',
    'verified',
  };
  static const Set<String> blockedDriverStatuses = {
    'disabled',
    'inactive',
    'rejected',
    'suspended',
  };

  TourisTrikeRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  String requireUserId() {
    final id = currentUserId;
    if (id == null || id.isEmpty) {
      throw StateError('No active Supabase session.');
    }
    return id;
  }

  String _normalizeLocationText(String value) {
    final lowered = value.trim().toLowerCase();
    return lowered.replaceAll(RegExp(r'\s+'), ' ');
  }

  String _firstNonEmptyLocation(Iterable<dynamic> values) {
    for (final value in values) {
      final text = value?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  bool _matchesNormalizedLocation(String actual, String expected) {
    final normalizedActual = _normalizeLocationText(actual);
    final normalizedExpected = _normalizeLocationText(expected);
    return normalizedActual.isNotEmpty &&
        normalizedExpected.isNotEmpty &&
        normalizedActual == normalizedExpected;
  }

  Future<List<Json>> fetchRows(
    String table, {
    String columns = '*',
    Map<String, dynamic> equals = const {},
    String? orderBy,
    bool ascending = true,
    int? limit,
    int? offset,
  }) async {
    dynamic query = _client.from(table).select(columns);
    for (final entry in equals.entries) {
      query = query.eq(entry.key, entry.value);
    }
    if (orderBy != null) query = query.order(orderBy, ascending: ascending);
    if (limit != null) query = query.limit(limit);
    if (offset != null && limit != null) {
      query = query.range(offset, offset + limit - 1);
    }
    final rows = await query;
    return _rows(rows);
  }

  Future<Json?> fetchOne(
    String table, {
    String columns = '*',
    Map<String, dynamic> equals = const {},
  }) async {
    dynamic query = _client.from(table).select(columns);
    for (final entry in equals.entries) {
      query = query.eq(entry.key, entry.value);
    }
    final row = await query.maybeSingle();
    return row == null ? null : Json.from(row as Map);
  }

  Future<Json> insertRow(
    String table,
    Json values, {
    String returning = '*',
  }) async {
    final row = await _client
        .from(table)
        .insert(values)
        .select(returning)
        .single();
    return Json.from(row);
  }

  Future<Json> upsertRow(
    String table,
    Json values, {
    String returning = '*',
    String? onConflict,
  }) async {
    dynamic query = _client.from(table).upsert(values, onConflict: onConflict);
    final row = await query.select(returning).single();
    return Json.from(row);
  }

  Future<void> updateRows(
    String table,
    Json values, {
    required Map<String, dynamic> equals,
  }) async {
    dynamic query = _client.from(table).update(values);
    for (final entry in equals.entries) {
      query = query.eq(entry.key, entry.value);
    }
    await query;
  }

  Future<void> deleteRows(
    String table, {
    required Map<String, dynamic> equals,
  }) async {
    dynamic query = _client.from(table).delete();
    for (final entry in equals.entries) {
      query = query.eq(entry.key, entry.value);
    }
    await query;
  }

  Future<Profile> currentProfile() async {
    final id = requireUserId();
    final row = await fetchOne(TourisTrikeTables.profiles, equals: {'id': id});
    if (row == null) throw StateError('Current profile was not found.');
    return Profile(row);
  }

  Future<Profile?> fetchProfile(String id) async {
    final row = await fetchOne(TourisTrikeTables.profiles, equals: {'id': id});
    return row == null ? null : Profile(row);
  }

  bool isApprovedDriverStatus(String? status) {
    if (status == null) return false;
    return approvedDriverStatuses.contains(status.trim().toLowerCase());
  }

  bool isBlockedDriverStatus(String? status) {
    if (status == null) return false;
    return blockedDriverStatuses.contains(status.trim().toLowerCase());
  }

  Future<bool> currentDriverCanAcceptPackageBookings() async {
    final driverId = requireUserId();

    final details = await fetchOne(
      TourisTrikeTables.driverDetails,
      columns: 'status, approved_at',
      equals: {'driver_id': driverId},
    );
    final detailsStatus = dbString(details?['status']);
    if (isBlockedDriverStatus(detailsStatus)) return false;
    if (isApprovedDriverStatus(detailsStatus) ||
        (detailsStatus.isEmpty && details?['approved_at'] != null)) {
      return true;
    }

    final applications = await _client
        .from(TourisTrikeTables.driverApplications)
        .select('status')
        .eq('driver_id', driverId)
        .order('submitted_at', ascending: false)
        .limit(1);
    final rows = _rows(applications);
    if (rows.isEmpty) return false;

    final application = rows.first;
    return isApprovedDriverStatus(dbString(application['status']));
  }

  Future<List<EmergencyContactRecord>> fetchEmergencyContacts({
    int limit = 10,
  }) async {
    final rows = await fetchRows(
      TourisTrikeTables.emergencyContacts,
      equals: {'tourist_id': requireUserId()},
      orderBy: 'created_at',
      ascending: true,
      limit: limit,
    );
    return rows.map(EmergencyContactRecord.new).toList(growable: false);
  }

  Future<EmergencyContactRecord> saveEmergencyContact({
    dynamic contactId,
    required String name,
    required String phoneNumber,
    String relationship = '',
  }) async {
    final values = {
      'tourist_id': requireUserId(),
      'name': name.trim(),
      'phone_number': phoneNumber.trim(),
      'relationship': relationship.trim(),
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (contactId == null) {
      return EmergencyContactRecord(
        await insertRow(TourisTrikeTables.emergencyContacts, values),
      );
    }
    await updateRows(
      TourisTrikeTables.emergencyContacts,
      values,
      equals: {'id': contactId, 'tourist_id': requireUserId()},
    );
    final row = await fetchOne(
      TourisTrikeTables.emergencyContacts,
      equals: {'id': contactId, 'tourist_id': requireUserId()},
    );
    if (row == null) {
      throw StateError('Emergency contact was not found after saving.');
    }
    return EmergencyContactRecord(row);
  }

  Future<void> deleteEmergencyContact(dynamic contactId) async {
    await deleteRows(
      TourisTrikeTables.emergencyContacts,
      equals: {'id': contactId, 'tourist_id': requireUserId()},
    );
  }

  Future<DriverInfo?> fetchDriverInfo(String driverId) async {
    if (driverId.trim().isEmpty) return null;
    final results = await Future.wait([
      fetchProfile(driverId),
      fetchDriverDetails(driverId),
    ]);
    final profile = results[0] as Profile?;
    final details = results[1] as DriverDetails?;
    if (profile == null && details == null) return null;
    return DriverInfo(profile: profile, details: details);
  }

  Future<Map<String, DriverInfo>> fetchDriverInfos(
    Iterable<String> driverIds,
  ) async {
    final ids = driverIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const {};

    final profileRows = await _client
        .from(TourisTrikeTables.profiles)
        .select('*')
        .inFilter('id', ids);
    final detailsRows = await _client
        .from(TourisTrikeTables.driverDetails)
        .select('*')
        .inFilter('driver_id', ids);

    final profiles = {
      for (final row in _rows(profileRows)) dbString(row['id']): Profile(row),
    };
    final details = {
      for (final row in _rows(detailsRows))
        dbString(row['driver_id']): DriverDetails(row),
    };

    final data = <String, DriverInfo>{};
    for (final id in ids) {
      final profile = profiles[id];
      final driverDetails = details[id];
      if (profile == null && driverDetails == null) continue;
      data[id] = DriverInfo(profile: profile, details: driverDetails);
    }
    return data;
  }

  Future<List<TouristSpot>> fetchTouristSpots({
    String? city,
    dynamic categoryId,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    dynamic query = _client
        .from(TourisTrikeTables.touristSpots)
        .select('*, tourist_spot_images(*)')
        .neq('status', 'archived');
    if (city != null && city.trim().isNotEmpty) {
      query = query.eq('city', city.trim());
    }
    if (categoryId != null) query = query.eq('category_id', categoryId);
    if (search != null && search.trim().isNotEmpty) {
      query = query.ilike('title', '%${search.trim()}%');
    }
    final rows = await query
        .order('title', ascending: true)
        .range(offset, offset + limit - 1);
    return _rows(rows).map(TouristSpot.new).toList(growable: false);
  }

  Future<TouristSpot?> fetchTouristSpot(dynamic spotId) async {
    final row = await _client
        .from(TourisTrikeTables.touristSpots)
        .select('*, tourist_spot_images(*)')
        .eq('id', spotId)
        .maybeSingle();
    return row == null ? null : TouristSpot(Json.from(row));
  }

  Future<void> trackTouristSpotView(dynamic spotId) async {
    await _client.from(TourisTrikeTables.touristSpotViews).insert({
      'spot_id': spotId,
      'user_id': currentUserId,
    });
  }

  Future<List<TouristSpotImage>> fetchTouristSpotImages(dynamic spotId) async {
    final rows = await fetchRows(
      TourisTrikeTables.touristSpotImages,
      equals: {'spot_id': spotId},
      orderBy: 'sort_order',
    );
    return rows.map(TouristSpotImage.new).toList(growable: false);
  }

  Future<List<TourPackage>> fetchTourPackages({
    String? city,
    dynamic categoryId,
    String? search,
    int limit = 50,
    int offset = 0,
    bool publishedOnly = true,
  }) async {
    dynamic query = _client.from(TourisTrikeTables.tourPackages).select('*');
    if (publishedOnly) {
      query = query
          .eq('status', 'published')
          .eq('visibility_status', 'visible');
    }
    if (city != null && city.trim().isNotEmpty) {
      query = query.eq('city', city.trim());
    }
    if (categoryId != null) query = query.eq('category_id', categoryId);
    if (search != null && search.trim().isNotEmpty) {
      query = query.ilike('title', '%${search.trim()}%');
    }
    final rows = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return _rows(rows).map(TourPackage.new).toList(growable: false);
  }

  Future<TourPackage?> fetchTourPackage(dynamic packageId) async {
    final row = await _client
        .from(TourisTrikeTables.tourPackages)
        .select('*')
        .eq('id', packageId)
        .maybeSingle();
    return row == null ? null : TourPackage(Json.from(row));
  }

  Future<List<TourPackageDay>> fetchPackageItinerary(dynamic packageId) async {
    final dayRows = await _client
        .from(TourisTrikeTables.tourPackageDays)
        .select('*')
        .eq('package_id', packageId)
        .order('day_number');
    final days = _rows(dayRows);
    if (days.isEmpty) return const [];

    final dayIds = days.map((day) => day['id']).toList(growable: false);
    final itemRows = await _client
        .from(TourisTrikeTables.tourPackageDayItems)
        .select('*, tourist_spots(*)')
        .inFilter('day_id', dayIds)
        .order('sort_order');
    final items = _rows(itemRows);
    final byDay = <String, List<Json>>{};
    for (final item in items) {
      byDay.putIfAbsent(dbString(item['day_id']), () => []).add(item);
    }

    return days
        .map((day) {
          final row = Json.from(day);
          row['tour_package_day_items'] =
              byDay[dbString(day['id'])] ?? const [];
          return TourPackageDay(row);
        })
        .toList(growable: false);
  }

  Future<List<TouristSpot>> fetchPackageSpots(dynamic packageId) async {
    final rows = await _client
        .from(TourisTrikeTables.tourPackageSpots)
        .select(
          'sort_order, opening_time, closing_time, estimated_arrival_time, '
          'estimated_duration_minutes, recommended_visit_duration_minutes, '
          'tourist_spots(*)',
        )
        .eq('package_id', packageId)
        .order('sort_order');
    return _rows(rows)
        .map((row) {
          final nested = row['tourist_spots'];
          if (nested is! Map) return null;
          return Json.from({
            ...Map<String, dynamic>.from(nested),
            'sort_order': row['sort_order'],
            'opening_time': row['opening_time'],
            'closing_time': row['closing_time'],
            'estimated_arrival_time': row['estimated_arrival_time'],
            'estimated_duration_minutes': row['estimated_duration_minutes'],
            'recommended_visit_duration_minutes':
                row['recommended_visit_duration_minutes'],
          });
        })
        .whereType<Map>()
        .map((row) => TouristSpot(Json.from(row)))
        .toList(growable: false);
  }

  Future<void> trackTourPackageView(dynamic packageId) async {
    await _client.from(TourisTrikeTables.tourPackageViews).insert({
      'package_id': packageId,
      'user_id': currentUserId,
    });
  }

  Future<PackageBooking> createPackageBooking({
    required dynamic packageId,
    required DateTime travelDate,
    required int adults,
    int children = 0,
    required String paymentMethod,
    required double totalAmount,
    double downpaymentAmount = 0,
    double remainingBalance = 0,
    String bookingType = 'advanced',
    String pickupAddress = '',
    double? pickupLatitude,
    double? pickupLongitude,
    String pickupProvince = '',
    String pickupLocality = '',
    String pickupCountryCode = 'PH',
    String dropoffAddress = '',
    double? dropoffLatitude,
    double? dropoffLongitude,
    String dropoffProvince = '',
    String dropoffLocality = '',
    String dropoffCountryCode = 'PH',
    String notes = '',
    List<Json> customizedSpots = const [],
    List<Json> itineraryItems = const [],
    int requiredDrivers = 1,
    String municipality = '',
    String province = '',
    int totalPassengers = 0,
  }) async {
    final hasActive = await hasActiveTour();
    if (hasActive) {
      throw StateError(activeTourErrorMessage);
    }

    final row = await insertRow(TourisTrikeTables.packageBookings, {
      'package_id': packageId,
      'tourist_id': requireUserId(),
      'travel_date': travelDate.toIso8601String().split('T').first,
      'adults': adults,
      'children': children,
      'payment_method': paymentMethod,
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'total_amount': totalAmount,
      'downpayment_amount': downpaymentAmount,
      'remaining_balance': remainingBalance,
      'booking_type': bookingType,
      'pickup_address': pickupAddress.trim().isEmpty
          ? null
          : pickupAddress.trim(),
      'pickup_latitude': pickupLatitude,
      'pickup_longitude': pickupLongitude,
      'pickup_province': pickupProvince.trim().isEmpty
          ? null
          : pickupProvince.trim(),
      'pickup_locality': pickupLocality.trim().isEmpty
          ? null
          : pickupLocality.trim(),
      'pickup_country_code': pickupCountryCode.trim().isEmpty
          ? null
          : pickupCountryCode.trim(),
      'dropoff_address': dropoffAddress.trim().isEmpty
          ? null
          : dropoffAddress.trim(),
      'dropoff_latitude': dropoffLatitude,
      'dropoff_longitude': dropoffLongitude,
      'dropoff_province': dropoffProvince.trim().isEmpty
          ? null
          : dropoffProvince.trim(),
      'dropoff_locality': dropoffLocality.trim().isEmpty
          ? null
          : dropoffLocality.trim(),
      'dropoff_country_code': dropoffCountryCode.trim().isEmpty
          ? null
          : dropoffCountryCode.trim(),
      'required_drivers': requiredDrivers,
      'municipality': municipality.trim().isEmpty ? null : municipality.trim(),
      'province': province.trim().isEmpty ? null : province.trim(),
      'total_passengers': totalPassengers > 0
          ? totalPassengers
          : (adults + children),
      'booking_status': 'waiting_for_drivers',
      'status': 'pending',
    });
    if (customizedSpots.isNotEmpty) {
      await _trySaveCustomizedPackageSpots(
        bookingId: row['id'],
        packageId: packageId,
        rows: customizedSpots,
      );
    }
    if (itineraryItems.isNotEmpty) {
      await replaceBookingItinerary(
        bookingId: row['id'],
        items: itineraryItems,
      );
    }
    // Auto-create the activity record so the tourist can track the booking
    try {
      await insertRow(TourisTrikeTables.packageActivities, {
        'booking_id': row['id'],
        'tourist_id': requireUserId(),
        'package_id': packageId,
        'status': 'pending',
        'price': totalAmount,
        'payment_status': 'unpaid',
      });
    } catch (_) {
      // Non-fatal: admin can create the activity manually if this fails
    }
    return PackageBooking(row);
  }

  Future<void> replaceBookingItinerary({
    required dynamic bookingId,
    required List<Json> items,
  }) async {
    final touristId = requireUserId();
    await deleteRows(
      TourisTrikeTables.bookingItineraryItems,
      equals: {'booking_id': bookingId},
    );
    if (items.isEmpty) return;

    final payload = items.indexed
        .map((entry) {
          final index = entry.$1;
          final row = entry.$2;
          return <String, dynamic>{
            'booking_id': bookingId,
            'tourist_id': touristId,
            'spot_id': row['spot_id'],
            'destination_name': row['destination_name'],
            'destination_address': row['destination_address'],
            'order_number':
                row['order_number'] ?? row['destination_order'] ?? index + 1,
            'destination_order': row['destination_order'] ?? index + 1,
            'arrival_time': row['arrival_time'],
            'estimated_stay_duration_minutes':
                row['estimated_stay_duration_minutes'],
            'departure_time': row['departure_time'],
            'activity_note': row['activity_note'],
            'itinerary_source': row['itinerary_source'] ?? row['source_type'],
            'source_type': row['source_type'],
            'google_place_id': row['google_place_id'],
            'municipality': row['municipality'],
            'barangay': row['barangay'],
            'latitude': row['latitude'],
            'longitude': row['longitude'],
            'image_url': row['image_url'],
          }..removeWhere((_, value) => value == null);
        })
        .toList(growable: false);

    await _client.from(TourisTrikeTables.bookingItineraryItems).insert(payload);
  }

  Future<void> _trySaveCustomizedPackageSpots({
    required dynamic bookingId,
    required dynamic packageId,
    required List<Json> rows,
  }) async {
    final touristId = requireUserId();
    final payload = rows
        .map(
          (row) => <String, dynamic>{
            'booking_id': bookingId,
            'tourist_id': touristId,
            'package_id': packageId,
            'spot_id': row['spot_id'],
            'action_type': row['action_type'],
            'source_type': row['source_type'],
            'google_place_id': row['google_place_id'],
            'spot_title': row['spot_title'],
            'spot_address': row['spot_address'],
            'municipality': row['municipality'],
            'barangay': row['barangay'],
            'latitude': row['latitude'],
            'longitude': row['longitude'],
            'image_url': row['image_url'],
            'additional_fee': row['additional_fee'],
            'sort_order': row['sort_order'],
            'opening_time': row['opening_time'],
            'closing_time': row['closing_time'],
            'estimated_arrival_time': row['estimated_arrival_time'],
            'estimated_duration_minutes': row['estimated_duration_minutes'],
            'recommended_visit_duration_minutes':
                row['recommended_visit_duration_minutes'],
          }..removeWhere((_, value) => value == null),
        )
        .toList(growable: false);

    try {
      await _client
          .from(TourisTrikeTables.customizedPackageSpots)
          .insert(payload);
    } on PostgrestException {
      // Allow bookings to proceed even if the customization snapshot table
      // has not been migrated yet.
    }
  }

  Future<List<PackageBooking>> fetchTouristPackageBookings({
    int limit = 80,
    int offset = 0,
  }) async {
    final rows = await _client
        .from(TourisTrikeTables.packageBookings)
        .select('*, tour_packages(*)')
        .eq('tourist_id', requireUserId())
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return _rows(rows).map(PackageBooking.new).toList(growable: false);
  }

  Future<PackageBooking?> fetchPackageBooking(dynamic bookingId) async {
    final row = await _client
        .from(TourisTrikeTables.packageBookings)
        .select('*, tour_packages(*)')
        .eq('id', bookingId)
        .maybeSingle();
    return row == null ? null : PackageBooking(Json.from(row));
  }

  Future<PackageBooking?> fetchPackageBookingDetails(String bookingId) async {
    final row = await _client
        .from(TourisTrikeTables.packageBookings)
        .select(
          '*, '
          'tour_packages(title, city, cover_image_url, image_url)',
        )
        .eq('id', bookingId)
        .maybeSingle();
    if (row == null) return null;

    final bookingRow = Json.from(row);
    final touristId = dbString(bookingRow['tourist_id']);
    final driverId = dbString(bookingRow['assigned_driver_id']);

    final touristFuture = touristId.isEmpty
        ? Future<Profile?>.value(null)
        : fetchProfile(touristId);
    final driverFuture = driverId.isEmpty
        ? Future<Profile?>.value(null)
        : fetchProfile(driverId);
    final results = await Future.wait<Profile?>([touristFuture, driverFuture]);

    final tourist = results[0];
    final driver = results[1];

    if (tourist != null) {
      bookingRow['tourist'] = tourist.row;
    }
    if (driver != null) {
      bookingRow['driver'] = driver.row;
    }

    return PackageBooking(bookingRow);
  }

  Future<List<BookingItineraryItem>> fetchBookingItinerary(
    String bookingId,
  ) async {
    final rows = await _client
        .from(TourisTrikeTables.bookingItineraryItems)
        .select()
        .eq('booking_id', bookingId)
        .order('order_number', ascending: true)
        .order('destination_order', ascending: true)
        .order('arrival_time', ascending: true)
        .order('created_at', ascending: true);
    return _rows(rows).map(BookingItineraryItem.new).toList(growable: false);
  }

  Future<int> ensureBookingItinerary(String bookingId) async {
    final result = await _client.rpc(
      'ensure_booking_itinerary',
      params: {'p_booking_id': bookingId},
    );
    return (result as num?)?.toInt() ?? 0;
  }

  Future<Map<String, int>> fetchBookingItineraryCounts(
    Iterable<String> bookingIds,
  ) async {
    final ids = bookingIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (ids.isEmpty) return const {};

    try {
      final rows = await _client
          .from(TourisTrikeTables.bookingItineraryItems)
          .select('booking_id')
          .inFilter('booking_id', ids);
      final counts = <String, int>{for (final id in ids) id: 0};
      for (final row in _rows(rows)) {
        final bookingId = dbString(row['booking_id']);
        if (bookingId.isEmpty) continue;
        counts[bookingId] = (counts[bookingId] ?? 0) + 1;
      }
      return counts;
    } on PostgrestException {
      return const {};
    }
  }

  Future<PaymentRecord> createPayment({
    required dynamic bookingId,
    required double amount,
    required String paymentMethod,
    String paymentStatus = 'pending',
    String paymentType = 'full_payment',
    String? paymentReference,
    String? checkoutUrl,
  }) async {
    final row = await insertRow(TourisTrikeTables.payments, {
      'booking_id': bookingId,
      'user_id': requireUserId(),
      'amount': amount,
      'payment_method': paymentMethod,
      'payment_status': paymentStatus,
      'payment_type': paymentType,
      'payment_reference': paymentReference,
      'checkout_url': checkoutUrl,
    });
    return PaymentRecord(row);
  }

  Future<List<PaymentRecord>> fetchPayments({int limit = 80}) async {
    final rows = await fetchRows(
      TourisTrikeTables.payments,
      equals: {'user_id': requireUserId()},
      orderBy: 'created_at',
      ascending: false,
      limit: limit,
    );
    return rows.map(PaymentRecord.new).toList(growable: false);
  }

  Future<List<SavedPlaceRecord>> fetchSavedPlaces({int limit = 100}) async {
    final rows = await fetchRows(
      TourisTrikeTables.savedPlaces,
      equals: {'user_id': requireUserId()},
      orderBy: 'updated_at',
      ascending: false,
      limit: limit,
    );
    return rows.map(SavedPlaceRecord.new).toList(growable: false);
  }

  Future<SavedPlaceRecord> savePlace({
    dynamic id,
    required String label,
    required String address,
    double? latitude,
    double? longitude,
    String kind = 'favorite',
    String tag = '',
  }) async {
    final values = {
      'user_id': requireUserId(),
      'label': label.trim(),
      'address': address.trim(),
      'latitude': latitude,
      'longitude': longitude,
      'kind': kind,
      'tag': tag.trim(),
    };
    if (id == null) {
      return SavedPlaceRecord(
        await insertRow(TourisTrikeTables.savedPlaces, values),
      );
    }
    await updateRows(
      TourisTrikeTables.savedPlaces,
      values,
      equals: {'id': id, 'user_id': requireUserId()},
    );
    final row = await fetchOne(
      TourisTrikeTables.savedPlaces,
      equals: {'id': id, 'user_id': requireUserId()},
    );
    return SavedPlaceRecord(row ?? values);
  }

  Future<void> deleteSavedPlace(dynamic id) async {
    await deleteRows(
      TourisTrikeTables.savedPlaces,
      equals: {'id': id, 'user_id': requireUserId()},
    );
  }

  Future<List<AppNotification>> fetchNotifications({
    bool unreadOnly = false,
    int limit = 80,
  }) async {
    dynamic query = _client
        .from(TourisTrikeTables.notifications)
        .select('*')
        .eq('user_id', requireUserId());
    if (unreadOnly) query = query.eq('is_read', false);
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return _rows(rows).map(AppNotification.new).toList(growable: false);
  }

  Future<void> markNotificationRead(dynamic notificationId) async {
    await updateRows(
      TourisTrikeTables.notifications,
      {'is_read': true},
      equals: {'id': notificationId, 'user_id': requireUserId()},
    );
  }

  Future<RideReview> submitRideReview({
    required dynamic rideId,
    required String driverId,
    required double rating,
    String comment = '',
  }) async {
    final row = await insertRow(TourisTrikeTables.rideReviews, {
      'ride_id': rideId,
      'tourist_id': requireUserId(),
      'driver_id': driverId,
      'rating': rating,
      'comment': comment.trim(),
    });
    return RideReview(row);
  }

  Future<RideFeedback> submitRideFeedback({
    required dynamic rideId,
    required String driverId,
    required double rating,
    String comment = '',
  }) async {
    final row = await insertRow(TourisTrikeTables.rideFeedback, {
      'ride_id': rideId,
      'tourist_id': requireUserId(),
      'driver_id': driverId,
      'rating': rating,
      'comment': comment.trim(),
    });
    return RideFeedback(row);
  }

  Future<void> updateDriverOnlineStatus(bool online) async {
    await updateRows(
      TourisTrikeTables.profiles,
      {'is_online': online},
      equals: {'id': requireUserId()},
    );
  }

  Future<DriverDetails?> fetchDriverDetails(String driverId) async {
    final row = await fetchOne(
      TourisTrikeTables.driverDetails,
      equals: {'driver_id': driverId},
    );
    return row == null ? null : DriverDetails(row);
  }

  Future<DriverApplication?> fetchCurrentDriverApplication() async {
    final id = requireUserId();
    final row = await fetchOne(
      TourisTrikeTables.driverApplications,
      equals: {'driver_id': id},
    );
    return row == null ? null : DriverApplication(row);
  }

  Future<DriverDocuments?> fetchDriverDocuments(String driverId) async {
    final row = await fetchOne(
      TourisTrikeTables.driverDocuments,
      equals: {'driver_id': driverId},
    );
    return row == null ? null : DriverDocuments(row);
  }

  Future<void> upsertDriverDetails(Json values) async {
    await upsertRow(TourisTrikeTables.driverDetails, {
      'driver_id': requireUserId(),
      ...values,
    }, onConflict: 'driver_id');
  }

  Future<void> upsertDriverDocuments(Json values) async {
    await upsertRow(TourisTrikeTables.driverDocuments, {
      'driver_id': requireUserId(),
      ...values,
    }, onConflict: 'driver_id');
  }

  Future<DriverApplication> submitDriverApplication(String city) async {
    final row = await insertRow(TourisTrikeTables.driverApplications, {
      'driver_id': requireUserId(),
      'city': city,
      'status': 'pending',
    });
    return DriverApplication(row);
  }

  Future<List<BookingDriverAssignment>> fetchDriverAssignments({
    String status = 'assigned',
  }) async {
    dynamic query = _client
        .from(TourisTrikeTables.bookingDriverAssignments)
        .select('*, package_bookings(*, tour_packages(*))')
        .eq('driver_id', requireUserId());
    if (status != 'all') query = query.eq('status', status);
    final rows = await query.order('assigned_at', ascending: false);
    return _rows(rows).map(BookingDriverAssignment.new).toList(growable: false);
  }

  Future<List<Ride>> fetchDriverRides({
    String status = 'all',
    int limit = 80,
  }) async {
    dynamic query = _client
        .from(TourisTrikeTables.rides)
        .select('*')
        .eq('driver_id', requireUserId());
    if (status != 'all') query = query.eq('status', status);
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return _rows(rows).map(Ride.new).toList(growable: false);
  }

  Future<BookingDriverAssignment> assignDriverToBooking({
    required dynamic bookingId,
    required String driverId,
    String status = 'assigned',
  }) async {
    final actorId = requireUserId();
    final assignment =
        await insertRow(TourisTrikeTables.bookingDriverAssignments, {
          'booking_id': bookingId,
          'driver_id': driverId,
          'assigned_by': actorId,
          'status': status,
        });
    await updateRows(
      TourisTrikeTables.packageBookings,
      {'assigned_driver_id': driverId},
      equals: {'id': bookingId},
    );
    await notifyUser(
      userId: driverId,
      title: 'New package assignment',
      body: 'A city tourism admin assigned you to a package booking.',
      type: 'booking_assignment',
    );
    await logAudit(
      action: 'assign_driver',
      tableName: TourisTrikeTables.packageBookings,
      recordId: dbString(bookingId),
      description: 'Assigned driver $driverId to booking $bookingId.',
    );
    return BookingDriverAssignment(assignment);
  }

  Future<void> notifyUser({
    required String userId,
    required String title,
    required String body,
    required String type,
  }) async {
    await _client.from(TourisTrikeTables.notifications).insert({
      'user_id': userId,
      'title': title,
      'body': body,
      'type': type,
      'is_read': false,
    });
  }

  Future<void> logAudit({
    required String action,
    required String tableName,
    required String recordId,
    required String description,
  }) async {
    await _client.from(TourisTrikeTables.auditLogs).insert({
      'actor_id': currentUserId,
      'action': action,
      'table_name': tableName,
      'record_id': recordId,
      'description': description,
    });
  }

  // ── WALLET ──────────────────────────────────────────────────

  Future<Wallet> fetchOrCreateWallet({String role = 'tourist'}) async {
    final result = await _client.rpc(
      'get_or_create_wallet',
      params: {'p_user_id': requireUserId(), 'p_role': role},
    );
    if (result is Map) return Wallet(Json.from(result));
    if (result is List && result.isNotEmpty) {
      return Wallet(Json.from(result.first as Map));
    }
    throw StateError('get_or_create_wallet returned no data.');
  }

  Future<List<WalletTransaction>> fetchWalletTransactions({
    String role = 'tourist',
    int limit = 60,
  }) async {
    final rows = await fetchRows(
      TourisTrikeTables.walletTransactions,
      equals: {'user_id': requireUserId(), 'role': role},
      orderBy: 'created_at',
      ascending: false,
      limit: limit,
    );
    return rows.map(WalletTransaction.new).toList(growable: false);
  }

  /// Calls the wallet-cash-in edge function. Returns:
  /// { 'checkout_url': '...', 'transaction_id': '...' }
  Future<Map<String, dynamic>> cashIn({
    required double amount,
    required String paymentMethod,
    String role = 'tourist',
  }) async {
    final response = await _client.functions.invoke(
      'wallet-cash-in',
      body: {'amount': amount, 'payment_method': paymentMethod, 'role': role},
    );
    if (response.status != 200) {
      final msg = response.data is Map
          ? response.data['error'] ?? 'Cash in failed'
          : 'Cash in failed';
      throw Exception(msg);
    }
    return Map<String, dynamic>.from(response.data as Map);
  }

  Future<bool> hasActiveTour({String? touristId}) async {
    final userId = touristId ?? requireUserId();

    try {
      final result = await _client.rpc(
        'has_active_tour',
        params: {'p_tourist_id': userId},
      );
      if (result is bool) return result;
      if (result is List && result.isNotEmpty) {
        final first = result.first;
        if (first is bool) return first;
        if (first is Map && first['has_active_tour'] is bool) {
          return first['has_active_tour'] as bool;
        }
      }
      if (result is Map && result['has_active_tour'] is bool) {
        return result['has_active_tour'] as bool;
      }
    } on PostgrestException {
      // Fall back to direct table checks when the RPC migration
      // has not been applied yet.
    }

    return _hasActiveTourFallback(userId);
  }

  Future<bool> _hasActiveTourFallback(String touristId) async {
    final bookingRows = await _client
        .from(TourisTrikeTables.packageBookings)
        .select('id, status, booking_status')
        .eq('tourist_id', touristId)
        .order('created_at', ascending: false)
        .limit(25);
    final bookings = _rows(bookingRows);
    for (final row in bookings) {
      if (_isActiveTourStatus(row['status']) ||
          _isActiveTourStatus(row['booking_status'])) {
        return true;
      }
    }

    final activityRows = await _client
        .from(TourisTrikeTables.packageActivities)
        .select('id, status, tour_status')
        .eq('tourist_id', touristId)
        .order('created_at', ascending: false)
        .limit(25);
    final activities = _rows(activityRows);
    for (final row in activities) {
      if (_isActiveTourStatus(row['status']) ||
          _isActiveTourStatus(row['tour_status'])) {
        return true;
      }
    }

    return false;
  }

  bool _isActiveTourStatus(dynamic raw) {
    final value = dbString(raw).trim().toLowerCase();
    return switch (value) {
      'pending' => true,
      'confirmed' => true,
      'accepted' => true,
      'driver_on_the_way' => true,
      'on_tour' => true,
      'arrived' => true,
      'picked_up' => true,
      'tour_started' => true,
      'ongoing' => true,
      'in_progress' => true,
      _ => false,
    };
  }

  // ── PACKAGE ACTIVITIES ───────────────────────────────────────

  Future<List<PackageActivity>> fetchTouristActivities({int limit = 60}) async {
    final rows = await _client
        .from(TourisTrikeTables.packageActivities)
        .select(
          '*, '
          'tour_packages(title, city, cover_image_url, image_url), '
          'driver:profiles!package_activities_driver_id_fkey(full_name, first_name, last_name, mobile), '
          'package_bookings('
          '  travel_date, adults, children, payment_method, booking_type, '
          '  total_amount, assigned_driver_id, status, booking_status, '
          '  pickup_address, dropoff_address, required_drivers, accepted_drivers_count, '
          '  municipality, province, total_passengers'
          ')',
        )
        .eq('tourist_id', requireUserId())
        .order('created_at', ascending: false)
        .limit(limit);
    return _rows(rows).map(PackageActivity.new).toList(growable: false);
  }

  Future<List<PackageActivity>> fetchDriverActivities({int limit = 60}) async {
    final rows = await _client
        .from(TourisTrikeTables.packageActivities)
        .select(
          '*, '
          'tour_packages(title, city, cover_image_url, image_url), '
          'tourist:profiles!package_activities_tourist_id_fkey(full_name, first_name, last_name, profile_image_url, mobile), '
          'package_bookings('
          '  travel_date, adults, children, payment_method, booking_type, '
          '  total_amount, assigned_driver_id, status, booking_status, '
          '  pickup_address, dropoff_address, completed_at, '
          '  municipality, province, total_passengers, '
          '  required_drivers, accepted_drivers_count'
          ')',
        )
        .eq('driver_id', requireUserId())
        .order('created_at', ascending: false)
        .limit(limit);
    return _rows(rows).map(PackageActivity.new).toList(growable: false);
  }

  // ── PACKAGE ACTIVITY TRACKING ───────────────────────────────

  Future<PackageActivity> createPackageActivity({
    required String bookingId,
    required dynamic packageId,
    required double price,
  }) async {
    final row = await insertRow(TourisTrikeTables.packageActivities, {
      'booking_id': bookingId,
      'tourist_id': requireUserId(),
      'package_id': packageId,
      'status': 'pending',
      'price': price,
      'payment_status': 'unpaid',
    });
    return PackageActivity(row);
  }

  Future<PackageActivity?> fetchActivityForBooking(String bookingId) async {
    final rows = await _client
        .from(TourisTrikeTables.packageActivities)
        .select(
          '*, '
          'tour_packages(title, city, cover_image_url, image_url), '
          'tourist:profiles!package_activities_tourist_id_fkey('
          '  full_name, first_name, last_name, profile_image_url, mobile'
          '), '
          'driver:profiles!package_activities_driver_id_fkey('
          '  full_name, first_name, last_name, profile_image_url, mobile'
          '), '
          'package_bookings('
          '  id, tourist_id, travel_date, adults, children, booking_type, '
          '  pickup_address, pickup_latitude, pickup_longitude, '
          '  dropoff_address, dropoff_latitude, dropoff_longitude, '
          '  total_amount, downpayment_amount, remaining_balance, '
          '  payment_method, assigned_driver_id, status, booking_status, '
          '  current_spot_index, driver_latitude, driver_longitude, '
          '  accepted_at, arrived_at, picked_up_at, completed_at, '
          '  municipality, province, total_passengers, notes'
          ')',
        )
        .eq('booking_id', bookingId)
        .limit(1);
    final list = _rows(rows);
    if (list.isEmpty) return null;
    return PackageActivity(list.first);
  }

  Future<List<CustomizedPackageSpot>> fetchBookingSpots(
    String bookingId,
  ) async {
    final rows = await _client
        .from(TourisTrikeTables.customizedPackageSpots)
        .select()
        .eq('booking_id', bookingId)
        .inFilter('action_type', ['kept', 'added'])
        .order('sort_order');
    final customized = _rows(
      rows,
    ).map(CustomizedPackageSpot.new).toList(growable: false);
    if (customized.isNotEmpty) return customized;

    final booking = await fetchPackageBooking(bookingId);
    if (booking == null) return const [];
    final packageSpots = await fetchPackageSpots(booking.packageId);
    return packageSpots.indexed
        .map((entry) {
          final index = entry.$1;
          final spot = entry.$2;
          return CustomizedPackageSpot({
            'booking_id': booking.id,
            'tourist_id': booking.touristId,
            'package_id': booking.packageId,
            'spot_id': spot.id,
            'action_type': 'kept',
            'source_type': spot.sourceType,
            'google_place_id': spot.googlePlaceId,
            'spot_title': spot.title,
            'spot_address': spot.address,
            'municipality': spot.municipality,
            'barangay': spot.barangay,
            'latitude': spot.latitude,
            'longitude': spot.longitude,
            'image_url': spot.imageUrl,
            'additional_fee': 0,
            'sort_order': index,
            'opening_time': spot.openingTime.isEmpty ? null : spot.openingTime,
            'closing_time': spot.closingTime.isEmpty ? null : spot.closingTime,
            'estimated_arrival_time': spot.estimatedArrivalTime.isEmpty
                ? null
                : spot.estimatedArrivalTime,
            'estimated_duration_minutes': spot.estimatedDurationMinutes > 0
                ? spot.estimatedDurationMinutes
                : null,
            'recommended_visit_duration_minutes':
                spot.recommendedVisitDurationMinutes > 0
                ? spot.recommendedVisitDurationMinutes
                : null,
          });
        })
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> getOrCreateConversation({
    required String touristId,
    required String driverId,
    dynamic bookingId,
  }) async {
    dynamic existingQuery = _client
        .from(TourisTrikeTables.conversations)
        .select('*')
        .eq('tourist_id', touristId)
        .eq('driver_id', driverId);
    existingQuery = bookingId == null
        ? existingQuery.isFilter('booking_id', null)
        : existingQuery.eq('booking_id', bookingId);
    final existing = await existingQuery.maybeSingle();
    if (existing != null) {
      return Map<String, dynamic>.from(existing);
    }

    try {
      final created = await _client
          .from(TourisTrikeTables.conversations)
          .insert({
            'tourist_id': touristId,
            'driver_id': driverId,
            'booking_id': bookingId,
            'last_message': '',
            'last_message_at': DateTime.now().toIso8601String(),
          })
          .select('*')
          .single();
      return Map<String, dynamic>.from(created);
    } on PostgrestException {
      dynamic retryQuery = _client
          .from(TourisTrikeTables.conversations)
          .select('*')
          .eq('tourist_id', touristId)
          .eq('driver_id', driverId);
      retryQuery = bookingId == null
          ? retryQuery.isFilter('booking_id', null)
          : retryQuery.eq('booking_id', bookingId);
      final retried = await retryQuery.maybeSingle();
      if (retried != null) {
        return Map<String, dynamic>.from(retried);
      }
      rethrow;
    }
  }

  Future<PackageActivity?> fetchPackageActivityById(String activityId) async {
    final rows = await _client
        .from(TourisTrikeTables.packageActivities)
        .select(
          '*, '
          'tour_packages(title, city, cover_image_url, image_url), '
          'tourist:profiles!package_activities_tourist_id_fkey('
          '  full_name, first_name, last_name, profile_image_url, mobile'
          '), '
          'driver:profiles!package_activities_driver_id_fkey('
          '  full_name, first_name, last_name, profile_image_url, mobile'
          '), '
          'package_bookings('
          '  id, tourist_id, travel_date, adults, children, booking_type, '
          '  pickup_address, pickup_latitude, pickup_longitude, '
          '  dropoff_address, dropoff_latitude, dropoff_longitude, '
          '  total_amount, downpayment_amount, remaining_balance, '
          '  payment_method, assigned_driver_id, status, booking_status, '
          '  current_spot_index, driver_latitude, driver_longitude, '
          '  accepted_at, arrived_at, picked_up_at, completed_at, '
          '  municipality, province, total_passengers, notes'
          ')',
        )
        .eq('id', activityId)
        .limit(1);
    final list = _rows(rows);
    if (list.isEmpty) return null;
    return PackageActivity(list.first);
  }

  Future<List<PackageActivity>> fetchPendingPackageActivities({
    int limit = 30,
  }) async {
    // Fetch driver's municipality for filtering.
    // Some deployments may not have profiles.municipality in older schema versions.
    final profileRow = await _client
        .from('profiles')
        .select('city, province')
        .eq('id', requireUserId())
        .maybeSingle();
    final driverMunicipality = _normalizeLocationText(
      _firstNonEmptyLocation([profileRow?['city']]),
    );
    final driverProvince = _normalizeLocationText(
      _firstNonEmptyLocation([profileRow?['province'], 'Bulacan']),
    );
    if (driverMunicipality.isEmpty || driverProvince.isEmpty) {
      return const [];
    }

    final rows = await _client
        .from(TourisTrikeTables.packageActivities)
        .select(
          '*, '
          'tour_packages(title, city, cover_image_url, image_url), '
          'tourist:profiles!package_activities_tourist_id_fkey('
          '  full_name, first_name, last_name, profile_image_url, mobile'
          '), '
          'package_bookings('
          '  id, travel_date, adults, children, booking_type, status, booking_status, '
          '  pickup_address, pickup_latitude, pickup_longitude, '
          '  dropoff_address, dropoff_latitude, dropoff_longitude, '
          '  required_drivers, accepted_drivers_count, municipality, province, '
          '  total_amount, total_passengers, notes'
          ')',
        )
        .eq('status', 'pending')
        .isFilter('driver_id', null)
        .order('created_at', ascending: true)
        .limit(limit * 3); // over-fetch so client filter doesn't under-return

    return _rows(rows)
        .map(PackageActivity.new)
        .where((activity) {
          final booking = activity.bookingRow;
          final required = (booking?['required_drivers'] as num?)?.toInt() ?? 1;
          final accepted =
              (booking?['accepted_drivers_count'] as num?)?.toInt() ?? 0;
          // Exclude fully-staffed bookings
          if (accepted >= required) return false;

          // Municipality filter — strict: legacy (no municipality) passes through;
          // area-specific bookings only shown to drivers in that municipality.
          final bookingStatus = dbString(
            booking?['booking_status'],
            fallback: dbString(booking?['status'], fallback: activity.status),
          );
          if (bookingStatus != 'pending' &&
              bookingStatus != 'waiting_for_drivers') {
            return false;
          }

          final bookingMunicipality = _normalizeLocationText(
            _firstNonEmptyLocation([
              booking?['municipality'],
              activity.packageRow?['city'],
            ]),
          );
          final bookingProvince = _normalizeLocationText(
            _firstNonEmptyLocation([booking?['province'], 'Bulacan']),
          );
          return _matchesNormalizedLocation(
                bookingMunicipality,
                driverMunicipality,
              ) &&
              _matchesNormalizedLocation(bookingProvince, driverProvince);
        })
        .take(limit)
        .toList(growable: false);
  }

  Future<bool> driverHasActivePackageTour() async {
    final driverId = requireUserId();

    // Terminal statuses — never block on these
    const doneStatuses = {'completed', 'done', 'cancelled'};
    // Active statuses for package_activities.status
    const activeActivityStatuses = ['pending', 'accepted', 'ongoing'];

    // Check direct driver_id link in package_activities
    final direct = await _client
        .from(TourisTrikeTables.packageActivities)
        .select('id, status, tour_status')
        .eq('driver_id', driverId)
        .inFilter('status', activeActivityStatuses)
        .limit(20);

    final hasActiveDirect = _rows(direct).any((row) {
      final status = dbString(row['status']).toLowerCase();
      final tourStatus = dbString(row['tour_status']).toLowerCase();
      final blocked =
          doneStatuses.contains(status) || doneStatuses.contains(tourStatus);
      debugPrint(
        '[driverHasActiveTour] direct activity status=$status '
        'tour_status=$tourStatus blocked=$blocked', // ignore: unnecessary_brace_in_string_interps
      );
      return !blocked;
    });

    if (hasActiveDirect) return true;

    // Check via booking_drivers — join package_bookings to verify the booking
    // is still active (booking_drivers.status stays 'accepted' forever otherwise)
    final grouped = await _client
        .from(TourisTrikeTables.bookingDrivers)
        .select(
          'booking_id, '
          'package_bookings(status, booking_status)',
        )
        .eq('driver_id', driverId)
        .eq('status', 'accepted')
        .limit(20);

    final hasActiveGrouped = _rows(grouped).any((row) {
      final b = row['package_bookings'];
      final bookingStatus =
          (b is Map ? (b['booking_status'] ?? b['status'] ?? '') : '')
              .toString()
              .toLowerCase();
      final blocked = doneStatuses.contains(bookingStatus);
      debugPrint(
        '[driverHasActiveTour] group booking bookingId=${row['booking_id']} '
        'booking_status=$bookingStatus blocked=$blocked',
      );
      return !blocked;
    });

    debugPrint('[driverHasActiveTour] result=$hasActiveGrouped');
    return hasActiveGrouped;
  }

  Future<Set<String>> fetchDriverAcceptedBookingIds() async {
    // Only exclude bookings this driver has accepted that are still active
    final rows = await _client
        .from(TourisTrikeTables.bookingDrivers)
        .select('booking_id')
        .eq('driver_id', requireUserId())
        .eq('status', 'accepted');
    return _rows(rows)
        .map((r) => r['booking_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<Map<String, dynamic>> acceptPackageBooking({
    required String bookingId,
    // activityId kept for backwards-compat callers but ignored; RPC resolves it
    String? activityId,
  }) async {
    try {
      final result = await _client.rpc(
        'accept_package_booking',
        params: {'p_booking_id': bookingId},
      );
      return (result as Map<String, dynamic>?) ?? {};
    } catch (error, stackTrace) {
      debugPrint(
        'acceptPackageBooking failed '
        'bookingId=$bookingId driverId=${currentUserId ?? 'unknown'} '
        'error=$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> updateActivityTourStatus({
    required String activityId,
    required String tourStatus,
    String? activityStatus,
    String? bookingStatus,
    int? currentSpotIndex,
    double? driverLat,
    double? driverLng,
    Map<String, dynamic> extra = const {},
  }) async {
    final update = <String, dynamic>{
      'tour_status': tourStatus,
      'updated_at': DateTime.now().toIso8601String(),
      ...extra,
    };
    if (activityStatus != null) update['status'] = activityStatus;
    if (currentSpotIndex != null) {
      update['current_spot_index'] = currentSpotIndex;
    }
    if (driverLat != null) {
      update['driver_latitude'] = driverLat;
      update['driver_longitude'] = driverLng;
      update['driver_last_seen'] = DateTime.now().toIso8601String();
    }
    await _client
        .from(TourisTrikeTables.packageActivities)
        .update(update)
        .eq('id', activityId);

    final activity = await fetchPackageActivityById(activityId);
    final bookingId = activity?.bookingId;
    if (bookingId == null || bookingId.isEmpty) return;

    final bookingUpdate = <String, dynamic>{
      'booking_status':
          bookingStatus ??
          activityStatus ??
          _bookingStatusFromTourStatus(tourStatus),
      'current_spot_index': currentSpotIndex ?? activity?.currentSpotIndex ?? 0,
      'updated_at': DateTime.now().toIso8601String(),
      ...extra,
    };
    if (driverLat != null) {
      bookingUpdate['driver_latitude'] = driverLat;
      bookingUpdate['driver_longitude'] = driverLng;
    }
    await _client
        .from(TourisTrikeTables.packageBookings)
        .update(bookingUpdate)
        .eq('id', bookingId);
  }

  Future<void> updateDriverLocation({
    required String activityId,
    required double latitude,
    required double longitude,
  }) async {
    await _client
        .from(TourisTrikeTables.packageActivities)
        .update({
          'driver_latitude': latitude,
          'driver_longitude': longitude,
          'driver_last_seen': DateTime.now().toIso8601String(),
        })
        .eq('id', activityId);

    final activity = await fetchPackageActivityById(activityId);
    final bookingId = activity?.bookingId;
    if (bookingId == null || bookingId.isEmpty) return;
    await _client
        .from(TourisTrikeTables.packageBookings)
        .update({
          'driver_latitude': latitude,
          'driver_longitude': longitude,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', bookingId);
  }

  Future<void> completePackageActivity(
    String activityId, {
    String remainingPaymentMethod = '',
  }) async {
    await _client.rpc(
      'complete_package_tour',
      params: {
        'p_activity_id': activityId,
        'p_remaining_payment_method': remainingPaymentMethod.trim().isEmpty
            ? null
            : remainingPaymentMethod,
      },
    );
  }

  Future<Map<String, dynamic>> completeCurrentItineraryItem(
    String activityId, {
    String itineraryItemId = '',
    String remainingPaymentMethod = '',
  }) async {
    final result = await _client.rpc(
      'complete_current_itinerary_item',
      params: {
        'p_activity_id': activityId,
        'p_itinerary_item_id': itineraryItemId.trim().isEmpty
            ? null
            : itineraryItemId.trim(),
        'p_remaining_payment_method': remainingPaymentMethod.trim().isEmpty
            ? null
            : remainingPaymentMethod,
      },
    );
    return (result as Map<String, dynamic>?) ?? {};
  }

  // ── WALLET DEDUCTION ─────────────────────────────────────────

  Future<void> deductWalletForBooking({
    required String bookingId,
    required double amount,
    required String transactionType,
    String description = '',
    String referenceKey = '',
  }) async {
    await _client.rpc(
      'deduct_wallet_balance',
      params: {
        'p_user_id': requireUserId(),
        'p_role': 'tourist',
        'p_amount': amount,
        'p_booking_id': bookingId,
        'p_transaction_type': transactionType,
        'p_description': description,
        'p_reference_key': referenceKey,
      },
    );
  }

  String _bookingStatusFromTourStatus(String tourStatus) {
    switch (tourStatus) {
      case 'driver_accepted':
      case 'driver_en_route':
      case 'driver_arrived':
        return 'driver_on_the_way';
      case 'picked_up':
      case 'on_tour':
      case 'en_route_to_spot':
      case 'at_spot':
      case 'en_route_to_dropoff':
      case 'ready_to_complete':
        return 'on_tour';
      case 'dropped_off':
      case 'completed':
        return 'completed';
      default:
        return 'accepted';
    }
  }

  // ── LIVE LOCATION ────────────────────────────────────────────

  Future<void> upsertDriverLiveLocation({
    required String activityId,
    required double latitude,
    required double longitude,
    double heading = 0,
    double speed = 0,
  }) async {
    final driverId = requireUserId();
    await _client.from(TourisTrikeTables.driverLiveLocations).upsert({
      'driver_id': driverId,
      'activity_id': activityId,
      'latitude': latitude,
      'longitude': longitude,
      'heading': heading,
      'speed': speed,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'driver_id');
  }

  Future<DriverLiveLocation?> fetchDriverLiveLocation(String driverId) async {
    final row = await fetchOne(
      TourisTrikeTables.driverLiveLocations,
      equals: {'driver_id': driverId},
    );
    return row == null ? null : DriverLiveLocation(row);
  }

  // ── TRIP STATUS LOGS ─────────────────────────────────────────

  Future<void> logTripStatus({
    required String activityId,
    required String bookingId,
    required String status,
    int? spotIndex,
    double? latitude,
    double? longitude,
    String notes = '',
  }) async {
    final payload = <String, dynamic>{
      'activity_id': activityId,
      'booking_id': bookingId,
      'status': status,
      'logged_at': DateTime.now().toIso8601String(),
    };
    if (spotIndex != null) payload['spot_index'] = spotIndex;
    if (latitude != null) {
      payload['latitude'] = latitude;
      payload['longitude'] = longitude;
    }
    if (notes.isNotEmpty) payload['notes'] = notes;
    await _client.from(TourisTrikeTables.tripStatusLogs).insert(payload);
  }

  // ── ITINERARY ACTUAL TIMES ───────────────────────────────────

  Future<void> markSpotActualArrival({
    required String bookingId,
    int spotIndex = 0,
    String? itineraryItemId,
  }) async {
    String? targetId = itineraryItemId;
    if (targetId == null || targetId.isEmpty) {
      final rows = await _client
          .from(TourisTrikeTables.bookingItineraryItems)
          .select('id')
          .eq('booking_id', bookingId)
          .order('order_number', ascending: true)
          .order('destination_order', ascending: true)
          .order('arrival_time', ascending: true)
          .range(spotIndex, spotIndex);
      final list = _rows(rows);
      if (list.isEmpty) return;
      targetId = dbString(list.first['id']);
    }
    await _client
        .from(TourisTrikeTables.bookingItineraryItems)
        .update({
          'actual_arrival_time': DateTime.now().toIso8601String(),
          'spot_status': 'at_spot',
        })
        .eq('id', targetId);
  }

  Future<void> markSpotActualDeparture({
    required String bookingId,
    int spotIndex = 0,
    String? itineraryItemId,
  }) async {
    String? targetId = itineraryItemId;
    if (targetId == null || targetId.isEmpty) {
      final rows = await _client
          .from(TourisTrikeTables.bookingItineraryItems)
          .select('id')
          .eq('booking_id', bookingId)
          .order('order_number', ascending: true)
          .order('destination_order', ascending: true)
          .order('arrival_time', ascending: true)
          .range(spotIndex, spotIndex);
      final list = _rows(rows);
      if (list.isEmpty) return;
      targetId = dbString(list.first['id']);
    }
    // Use .select() so we can detect when RLS silently blocks the update
    // (Supabase returns an empty list instead of throwing when 0 rows match).
    final updated = await _client
        .from(TourisTrikeTables.bookingItineraryItems)
        .update({
          'actual_departure_time': DateTime.now().toIso8601String(),
          'spot_status': 'completed',
        })
        .eq('id', targetId)
        .select('id');
    if (_rows(updated).isEmpty) {
      throw StateError(
        'markSpotActualDeparture: 0 rows updated for id=$targetId. '
        'RLS may be blocking the update — apply migration '
        '20260521040000_fix_spot_complete_driver_access.sql.',
      );
    }
  }

  Future<void> markSpotTravelling({
    required String bookingId,
    int spotIndex = 0,
    String? itineraryItemId,
  }) async {
    String? targetId = itineraryItemId;
    if (targetId == null || targetId.isEmpty) {
      final rows = await _client
          .from(TourisTrikeTables.bookingItineraryItems)
          .select('id')
          .eq('booking_id', bookingId)
          .order('order_number', ascending: true)
          .order('destination_order', ascending: true)
          .order('arrival_time', ascending: true)
          .range(spotIndex, spotIndex);
      final list = _rows(rows);
      if (list.isEmpty) return;
      targetId = dbString(list.first['id']);
    }
    await _client
        .from(TourisTrikeTables.bookingItineraryItems)
        .update({'spot_status': 'travelling'})
        .eq('id', targetId);
  }

  // ── GROUP BOOKING ────────────────────────────────────────────

  Future<void> updateBookingRequiredDrivers({
    required String bookingId,
    required int requiredDrivers,
  }) async {
    await updateRows(
      TourisTrikeTables.packageBookings,
      {'required_drivers': requiredDrivers},
      equals: {'id': bookingId},
    );
  }

  Future<List<BookingDriver>> fetchBookingDrivers(String bookingId) async {
    final rows = await fetchRows(
      TourisTrikeTables.bookingDrivers,
      equals: {'booking_id': bookingId},
      orderBy: 'accepted_at',
    );
    return rows.map(BookingDriver.new).toList(growable: false);
  }

  // ── DRIVER REVIEWS ───────────────────────────────────────────

  Future<bool> hasReviewedDriver(String bookingId) async {
    final userId = currentUserId;
    if (userId == null) return false;
    final row = await _client
        .from(TourisTrikeTables.driverReviews)
        .select('id')
        .eq('booking_id', bookingId)
        .eq('tourist_id', userId)
        .maybeSingle();
    return row != null;
  }

  /// Returns true only when BOTH driver review and package review exist.
  Future<bool> hasReviewedBooking(String bookingId) async {
    final userId = currentUserId;
    if (userId == null) return false;
    final driverRow = await _client
        .from(TourisTrikeTables.driverReviews)
        .select('id')
        .eq('booking_id', bookingId)
        .eq('tourist_id', userId)
        .maybeSingle();
    if (driverRow == null) return false;
    final packageRow = await _client
        .from('package_reviews')
        .select('id')
        .eq('booking_id', bookingId)
        .eq('tourist_id', userId)
        .maybeSingle();
    return packageRow != null;
  }

  Future<void> submitDriverReview({
    required String bookingId,
    required String driverId,
    required int rating,
    String reviewText = '',
  }) async {
    final userId = requireUserId();
    await _client.from(TourisTrikeTables.driverReviews).insert({
      'booking_id': bookingId,
      'driver_id': driverId,
      'tourist_id': userId,
      'rating': rating,
      'review_text': reviewText.trim().isEmpty ? null : reviewText.trim(),
    });
  }

  Future<void> submitPackageReview({
    required String bookingId,
    required int rating,
    String reviewText = '',
    dynamic packageId,
  }) async {
    final userId = requireUserId();
    await _client.from('package_reviews').insert({
      'booking_id': bookingId,
      'tourist_id': userId,
      'rating': rating,
      'review_text': reviewText.trim().isEmpty ? null : reviewText.trim(),
      ?'package_id': packageId,
    });
  }

  Future<bool> hasReviewedPackage(String bookingId) async {
    final userId = currentUserId;
    if (userId == null) return false;
    final row = await _client
        .from('package_reviews')
        .select('id')
        .eq('booking_id', bookingId)
        .eq('tourist_id', userId)
        .maybeSingle();
    return row != null;
  }

  Future<String?> fetchAssignedDriverIdForBooking(String bookingId) async {
    final bd = await _client
        .from(TourisTrikeTables.bookingDrivers)
        .select('driver_id')
        .eq('booking_id', bookingId)
        .eq('status', 'accepted')
        .limit(1)
        .maybeSingle();
    if (bd != null) {
      final id = bd['driver_id']?.toString();
      if (id != null && id.isNotEmpty) return id;
    }
    final pa = await _client
        .from(TourisTrikeTables.packageActivities)
        .select('driver_id, assigned_driver_id')
        .eq('booking_id', bookingId)
        .limit(1)
        .maybeSingle();
    if (pa != null) {
      return (pa['driver_id'] ?? pa['assigned_driver_id'])?.toString();
    }
    return null;
  }

  Future<Profile?> fetchDriverProfile(String driverId) async {
    final row = await fetchOne(
      TourisTrikeTables.profiles,
      equals: {'id': driverId},
    );
    return row == null ? null : Profile(row);
  }

  List<Json> _rows(dynamic rows) {
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => Json.from(row))
        .toList(growable: false);
  }

  // ── SHARED TRIP LINKS ────────────────────────────────────────

  String _generateShareToken() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rng = Random.secure();
    return List.generate(12, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  String _generateAccessCode() {
    final rng = Random.secure();
    return (100000 + rng.nextInt(900000)).toString();
  }

  Future<SharedTripLink?> getActiveShareTripLink(String bookingId) async {
    final userId = requireUserId();
    final row = await _client
        .from(TourisTrikeTables.sharedTripLinks)
        .select()
        .eq('booking_id', bookingId)
        .eq('tourist_id', userId)
        .eq('is_active', true)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (row == null) return null;
    return SharedTripLink(Json.from(row));
  }

  Future<SharedTripLink> generateShareTripLink({
    required String bookingId,
    DateTime? travelDate,
  }) async {
    final userId = requireUserId();
    final expiresAt = travelDate != null
        ? DateTime(
            travelDate.year,
            travelDate.month,
            travelDate.day,
            23,
            59,
            59,
          )
        : DateTime.now().add(const Duration(hours: 24));

    final row = await _client
        .from(TourisTrikeTables.sharedTripLinks)
        .insert({
          'booking_id': bookingId,
          'tourist_id': userId,
          'public_token': _generateShareToken(),
          'access_code': _generateAccessCode(),
          'is_active': true,
          'expires_at': expiresAt.toUtc().toIso8601String(),
        })
        .select()
        .single();
    return SharedTripLink(Json.from(row));
  }

  Future<void> disableShareTripLink(dynamic linkId) async {
    final userId = requireUserId();
    await _client
        .from(TourisTrikeTables.sharedTripLinks)
        .update({
          'is_active': false,
          'revoked_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', linkId)
        .eq('tourist_id', userId);
  }

  Future<SharedTripLink> regenerateShareTripLink({
    required dynamic oldLinkId,
    required String bookingId,
    DateTime? travelDate,
  }) async {
    final userId = requireUserId();
    await _client
        .from(TourisTrikeTables.sharedTripLinks)
        .update({
          'is_active': false,
          'revoked_at': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('id', oldLinkId)
        .eq('tourist_id', userId);

    final expiresAt = travelDate != null
        ? DateTime(
            travelDate.year,
            travelDate.month,
            travelDate.day,
            23,
            59,
            59,
          )
        : DateTime.now().add(const Duration(hours: 24));

    final row = await _client
        .from(TourisTrikeTables.sharedTripLinks)
        .insert({
          'booking_id': bookingId,
          'tourist_id': userId,
          'public_token': _generateShareToken(),
          'access_code': _generateAccessCode(),
          'is_active': true,
          'expires_at': expiresAt.toUtc().toIso8601String(),
          'regenerated_from': oldLinkId,
        })
        .select()
        .single();
    return SharedTripLink(Json.from(row));
  }

  // Called by guests (unauthenticated) via Supabase anon key.
  // Set silent=true for background refresh calls to avoid re-logging/notifying.
  Future<GuestTripDetails?> validateGuestTripLink({
    required String publicToken,
    required String accessCode,
    String? deviceInfo,
    String? userAgent,
    bool silent = false,
  }) async {
    try {
      final result = await _client.rpc('get_shared_trip_details', params: {
        'p_public_token': publicToken,
        'p_access_code': accessCode,
        'p_device_info': deviceInfo,
        'p_user_agent': userAgent,
        'p_silent': silent,
      });
      if (result == null) return null;
      final map = Map<String, dynamic>.from(result as Map);
      if (map['error'] != null) throw Exception(map['message']);
      return GuestTripDetails.fromJson(map);
    } catch (_) {
      rethrow;
    }
  }
}
