import '../models/booking_capacity.dart';
import '../models/booking_waiting_balance.dart';
import '../models/additional_tricycle_request.dart';
import 'dart:math';
import 'package:touristrike/core/models/convoy_state.dart';
import 'package:touristrike/core/places/google_media_url.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/participant_profiles.dart';

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
  static const paymentRecords = 'payment_records';
  static const paymentAllocationSummaries = 'payment_allocation_summaries';
  static const paymentDisputes = 'payment_disputes';
  static const refundRequests = 'refund_requests';
  static const bookingNoShowReports = 'booking_no_show_reports';
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
  static const bookingDrivers = 'booking_drivers';
  static const driverLiveLocations = 'driver_live_locations';
  static const bookingParticipantLiveLocations =
      'booking_participant_live_locations';
  static const tripStatusLogs = 'trip_status_logs';
  static const driverReviews = 'driver_reviews';
  static const sharedTripLinks = 'shared_trip_links';
  static const sharedTripAccessLogs = 'shared_trip_access_logs';
}

class PaymentProviderException implements Exception {
  const PaymentProviderException(this.code);

  final String code;

  @override
  String toString() => code;
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

  Future<Json> _secureTouristSpotRow(Json source) async {
    final row = Json.from(source);
    row['image_url'] = await secureGoogleMediaUrl(
      imageUrl: dbString(row['image_url']),
      photoReference: dbString(row['google_photo_reference']),
      latitude: dbDouble(row['latitude']),
      longitude: dbDouble(row['longitude']),
    );

    final images = row['tourist_spot_images'];
    if (images is List) {
      row['tourist_spot_images'] = await Future.wait(
        images.whereType<Map>().map((item) async {
          final image = Json.from(item);
          image['image_url'] = await secureGoogleMediaUrl(
            imageUrl: dbString(image['image_url']),
            photoReference: dbString(row['google_photo_reference']),
            latitude: dbDouble(row['latitude']),
            longitude: dbDouble(row['longitude']),
          );
          return image;
        }),
      );
    }
    return row;
  }

  String? get currentUserId => _client.auth.currentUser?.id;

  String requireUserId() {
    final id = currentUserId;
    if (id == null || id.isEmpty) {
      throw StateError('No active Supabase session.');
    }
    return id;
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
    final row = id == requireUserId()
        ? await fetchOne(TourisTrikeTables.profiles, equals: {'id': id})
        : await ParticipantProfiles.fetchOne(_client, id);
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

    final profileRows = await ParticipantProfiles.fetchMany(_client, ids);
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
    final securedRows = await Future.wait(
      _rows(rows).map(_secureTouristSpotRow),
    );
    return securedRows.map(TouristSpot.new).toList(growable: false);
  }

  Future<TouristSpot?> fetchTouristSpot(dynamic spotId) async {
    final row = await _client
        .from(TourisTrikeTables.touristSpots)
        .select('*, tourist_spot_images(*)')
        .eq('id', spotId)
        .maybeSingle();
    if (row == null) return null;
    return TouristSpot(await _secureTouristSpotRow(Json.from(row)));
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
    final securedRows = await Future.wait(
      rows.map((source) async {
        final row = Json.from(source);
        row['image_url'] = await secureGoogleMediaUrl(
          imageUrl: dbString(row['image_url']),
        );
        return row;
      }),
    );
    return securedRows.map(TouristSpotImage.new).toList(growable: false);
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
          .isFilter('archived_at', null)
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
    final spotRows = _rows(rows)
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
        .toList(growable: false);
    final securedRows = await Future.wait(
      spotRows.map((row) => _secureTouristSpotRow(Json.from(row))),
    );
    return securedRows.map(TouristSpot.new).toList(growable: false);
  }

  Future<void> trackTourPackageView(dynamic packageId) async {
    await _client.from(TourisTrikeTables.tourPackageViews).insert({
      'package_id': packageId,
      'user_id': currentUserId,
    });
  }

  Future<int> fetchTricyclePassengerCapacity() async {
    final value = await _client.rpc('tricycle_passenger_capacity');
    final capacity = (value as num).toInt();
    if (capacity < 1) throw StateError('Invalid tricycle capacity.');
    return capacity;
  }

  Future<PackageBooking> createPackageBooking({
    required dynamic packageId,
    required DateTime travelDate,
    required DateTime scheduledStartAt,
    required DateTime estimatedEndAt,
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
    AdditionalTricycleRequest? additionalTricycleRequest,
    required String termsVersion,
    String? fareQuoteId,
  }) async {
    final capacity = await fetchTricyclePassengerCapacity();
    if (additionalTricycleRequest == null) {
      BookingCapacity.validateSelectedTricycles(
        adults: adults,
        children: children,
        tricycles: requiredDrivers,
        capacity: capacity,
      );
    } else {
      // Historical request callers retain the old MTO review path.
      BookingCapacity.validate(adults + children, requiredDrivers, capacity);
      additionalTricycleRequest.validate();
    }
    final hasActive = await hasActiveTour();
    if (hasActive) {
      throw StateError(activeTourErrorMessage);
    }

    final bookingPayload = <String, dynamic>{
      'package_id': packageId,
      'travel_date': travelDate.toIso8601String().split('T').first,
      'scheduled_start_at': scheduledStartAt.toUtc().toIso8601String(),
      'estimated_end_at': estimatedEndAt.toUtc().toIso8601String(),
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
      if (additionalTricycleRequest == null)
        'selected_total_tricycles': requiredDrivers,
      'additional_tricycle_count': additionalTricycleRequest?.count ?? 0,
      'additional_tricycle_reason': additionalTricycleRequest?.reason,
      'additional_tricycle_explanation': additionalTricycleRequest?.explanation
          ?.trim(),
      'municipality': municipality.trim().isEmpty ? null : municipality.trim(),
      'province': province.trim().isEmpty ? null : province.trim(),
      'total_passengers': totalPassengers > 0
          ? totalPassengers
          : (adults + children),
      'booking_status': 'waiting_for_drivers',
      'status': 'pending',
      'terms_version': termsVersion,
      'fare_quote_id': fareQuoteId,
    };
    final result = await _client.rpc(
      'create_package_booking',
      params: {
        'p_booking': bookingPayload,
        'p_customized_spots': customizedSpots,
        'p_itinerary_items': itineraryItems,
      },
    );
    final row = Json.from(result as Map);
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
    final enriched = await _withSettledBookingPayments(_rows(rows));
    return enriched.map(PackageBooking.new).toList(growable: false);
  }

  /// A booking's cached activity payment_status is not maintained by all
  /// PayMongo and group cash settlement paths. Read confirmed ledger rows.
  Future<List<Json>> _withSettledBookingPayments(List<Json> bookings) async {
    if (bookings.isEmpty) return bookings;
    final bookingIds = bookings.map((row) => dbString(row['id'])).toList();
    final results = await Future.wait<dynamic>([
      _client
          .from(TourisTrikeTables.paymentRecords)
          .select('booking_id, payer_id, status, amount')
          .inFilter('booking_id', bookingIds)
          .eq('status', 'confirmed'),
      _client
          .from('booking_payment_requirements')
          .select('booking_id, payment_stage, status')
          .inFilter('booking_id', bookingIds),
      _client
          .from(TourisTrikeTables.refundRequests)
          .select('booking_id, amount, status')
          .inFilter('booking_id', bookingIds)
          .eq('status', 'completed'),
    ]);
    final settled = <String, double>{};
    final touristIds = {
      for (final booking in bookings)
        dbString(booking['id']): dbString(booking['tourist_id']),
    };
    for (final record in _rows(results[0])) {
      final bookingId = dbString(record['booking_id']);
      if (dbString(record['payer_id']) != touristIds[bookingId]) continue;
      settled.update(
        bookingId,
        (amount) => amount + dbDouble(record['amount']),
        ifAbsent: () => dbDouble(record['amount']),
      );
    }
    final required = <String, Set<String>>{};
    final satisfied = <String, Set<String>>{};
    final refunded = <String, double>{};
    for (final refund in _rows(results[2])) {
      final bookingId = dbString(refund['booking_id']);
      refunded.update(
        bookingId,
        (amount) => amount + dbDouble(refund['amount']),
        ifAbsent: () => dbDouble(refund['amount']),
      );
    }
    for (final requirement in _rows(results[1])) {
      final bookingId = dbString(requirement['booking_id']);
      final stage = dbString(requirement['payment_stage']);
      required.putIfAbsent(bookingId, () => {}).add(stage);
      if (dbString(requirement['status']) == 'satisfied') {
        satisfied.putIfAbsent(bookingId, () => {}).add(stage);
      }
    }
    return bookings
        .map((booking) {
          final id = dbString(booking['id']);
          final grossPaid = settled[id] ?? 0;
          final refundedAmount = refunded[id] ?? 0;
          final paid = (grossPaid - refundedAmount).clamp(0, double.infinity);
          final stages = required[id] ?? const <String>{};
          final cleared = satisfied[id] ?? const <String>{};
          final fullyPaid =
              paid > 0 &&
              dbDouble(booking['remaining_balance']) <= 0.005 &&
              ((stages.isNotEmpty && cleared.containsAll(stages)) ||
                  (stages.isEmpty &&
                      paid + 0.005 >= dbDouble(booking['total_amount'])));
          return Json.from(booking)
            ..['_settled_amount'] = paid
            ..['_derived_payment_status'] = grossPaid > 0 && paid <= 0
                ? 'refunded'
                : refundedAmount > 0
                ? 'partially_refunded'
                : fullyPaid
                ? 'fully_paid'
                : paid > 0
                ? 'partially_paid'
                : 'unpaid';
        })
        .toList(growable: false);
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

  Future<CancellationEligibility> getPackageBookingCancellationEligibility(
    String bookingId,
  ) async {
    final result = await _client.rpc(
      'get_package_booking_cancellation_eligibility',
      params: {'p_booking_id': bookingId},
    );
    return CancellationEligibility.fromJson(Json.from(result as Map));
  }

  Future<BookingCancellationResult> cancelPackageBooking({
    required String bookingId,
    required String reason,
    String? note,
    String category = 'general',
  }) async {
    final result = await _client.rpc(
      'cancel_package_booking',
      params: {
        'p_booking_id': bookingId,
        'p_reason': reason,
        'p_note': note,
        'p_category': category,
      },
    );
    return BookingCancellationResult.fromJson(Json.from(result as Map));
  }

  Future<List<RefundRequest>> fetchBookingRefundRequests(
    String bookingId,
  ) async {
    final rows = await _client
        .from(TourisTrikeTables.refundRequests)
        .select()
        .eq('booking_id', bookingId)
        .order('created_at', ascending: false);
    return _rows(rows).map(RefundRequest.new).toList(growable: false);
  }

  Future<BookingNoShowReport> reportBookingNoShow({
    required String bookingId,
    required String reportedParty,
    String? note,
  }) async {
    final result = await _client.rpc(
      'report_booking_no_show',
      params: {
        'p_booking_id': bookingId,
        'p_reported_party': reportedParty,
        'p_note': note,
      },
    );
    return BookingNoShowReport(Json.from(result as Map));
  }

  Future<BookingNoShowReport> resolveBookingNoShowReport({
    required String reportId,
    required bool verified,
    String? resolutionNote,
    bool attemptReplacement = true,
  }) async {
    final result = await _client.rpc(
      'resolve_booking_no_show_report',
      params: {
        'p_report_id': reportId,
        'p_verified': verified,
        'p_resolution_note': resolutionNote,
        'p_attempt_replacement': attemptReplacement,
      },
    );
    return BookingNoShowReport(Json.from(result as Map));
  }

  Future<RefundRequest> resolvePackageRefundRequest({
    required String refundRequestId,
    required String status,
    String? referenceNo,
    String? note,
  }) async {
    final result = await _client.rpc(
      'resolve_package_refund_request',
      params: {
        'p_refund_request_id': refundRequestId,
        'p_status': status,
        'p_reference_no': referenceNo,
        'p_note': note,
      },
    );
    return RefundRequest(Json.from(result as Map));
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
      final counts = await _fetchBookingItineraryCountsFromRows(ids);
      final missingIds = counts.entries
          .where((entry) => entry.value == 0)
          .map((entry) => entry.key)
          .toList(growable: false);
      if (missingIds.isEmpty) return counts;

      for (final bookingId in missingIds) {
        try {
          await ensureBookingItinerary(bookingId);
        } catch (_) {
          // Fall through and keep the current zero count if itinerary generation
          // is unavailable for this booking in the current environment.
        }
      }

      return _fetchBookingItineraryCountsFromRows(ids);
    } on PostgrestException {
      return const {};
    }
  }

  Future<Map<String, int>> _fetchBookingItineraryCountsFromRows(
    List<String> ids,
  ) async {
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
  }

  // PayMongo-backed package payment records; no raw card data is accepted.
  // The current user is always the payer here; the payee confirms receipt separately via confirmPaymentRecord.
  Future<PaymentRecord> createPaymentRecord({
    dynamic rideId,
    dynamic bookingId,
    required String payeeId,
    required double amount,
    required String paymentMethod,
    String paymentStage = 'full',
    String? externalReferenceNo,
    String? proofImageUrl,
    String? serviceDescription,
  }) async {
    final row = await insertRow(TourisTrikeTables.paymentRecords, {
      'ride_id': rideId,
      'booking_id': bookingId,
      'payer_id': requireUserId(),
      'payee_id': payeeId,
      'amount': amount,
      'payment_method': paymentMethod,
      'payment_stage': paymentStage,
      'external_reference_no': externalReferenceNo,
      'proof_image_url': proofImageUrl,
      'service_description': serviceDescription,
    });
    return PaymentRecord(row);
  }

  Future<PaymentRecord> attachPaymentProof({
    required String paymentRecordId,
    required String proofImageUrl,
  }) async {
    final result = await _client.rpc(
      'attach_payment_proof',
      params: {
        'p_payment_record_id': paymentRecordId,
        'p_proof_image_url': proofImageUrl,
      },
    );
    return PaymentRecord(Json.from(result as Map));
  }

  Future<PaymentRecord> confirmPaymentRecord(String id) async {
    final result = await _client.rpc(
      'confirm_payment_record',
      params: {'p_payment_record_id': id},
    );
    return PaymentRecord(Json.from(result as Map));
  }

  /// [role]: 'payer' (money sent) or 'payee' (money received) relative to the current user.
  Future<List<PaymentRecord>> fetchPaymentRecords({
    String role = 'payer',
    dynamic bookingId,
    dynamic rideId,
    int limit = 80,
  }) async {
    final equals = <String, dynamic>{
      role == 'payee' ? 'payee_id' : 'payer_id': requireUserId(),
    };
    if (bookingId != null) equals['booking_id'] = bookingId;
    if (rideId != null) equals['ride_id'] = rideId;
    final rows = await fetchRows(
      TourisTrikeTables.paymentRecords,
      equals: equals,
      orderBy: 'created_at',
      ascending: false,
      limit: limit,
    );
    return rows.map(PaymentRecord.new).toList(growable: false);
  }

  /// Returns the tourist's outgoing payments and their linked refunds as one
  /// chronological ledger. Refunds remain separate `refund_requests` rows and
  /// retain their authoritative `payment_record_id` relationship.
  Future<List<PaymentHistoryEntry>> fetchTouristPaymentHistory({
    int limit = 200,
  }) async {
    final touristId = requireUserId();
    final results = await Future.wait([
      _client
          .from(TourisTrikeTables.paymentRecords)
          .select('*, package_bookings(id, tour_packages(title))')
          .eq('payer_id', touristId)
          .order('created_at', ascending: false)
          .limit(limit),
      _client
          .from(TourisTrikeTables.refundRequests)
          .select(
            '*, payment_records!inner(*, package_bookings(id, tour_packages(title)))',
          )
          .eq('payment_records.payer_id', touristId)
          .order('created_at', ascending: false)
          .limit(limit),
    ]);

    final entries = <PaymentHistoryEntry>[
      for (final row in _rows(results[0]))
        PaymentHistoryEntry.payment(PaymentRecord(row)),
      for (final row in _rows(results[1]))
        if (row['payment_records'] is Map)
          PaymentHistoryEntry.refund(
            payment: PaymentRecord(Json.from(row['payment_records'] as Map)),
            refund: RefundRequest(row),
          ),
    ];
    entries.sort((a, b) {
      final left = a.occurredAt;
      final right = b.occurredAt;
      if (left == null && right == null) return 0;
      if (left == null) return 1;
      if (right == null) return -1;
      return right.compareTo(left);
    });
    return entries;
  }

  /// All payment records for a booking/ride, regardless of payer/payee — used by
  /// booking-detail and dispute screens where either participant may be viewing.
  Future<List<PaymentRecord>> fetchPaymentRecordsFor({
    dynamic bookingId,
    dynamic rideId,
  }) async {
    assert(bookingId != null || rideId != null);
    final equals = <String, dynamic>{
      'booking_id': ?bookingId,
      'ride_id': ?rideId,
    };
    final rows = await fetchRows(
      TourisTrikeTables.paymentRecords,
      equals: equals,
      orderBy: 'created_at',
      ascending: false,
    );
    return rows.map(PaymentRecord.new).toList(growable: false);
  }

  Future<PaymentRecord?> fetchPaymentRecordById(String paymentRecordId) async {
    final row = await _client
        .from(TourisTrikeTables.paymentRecords)
        .select()
        .eq('id', paymentRecordId)
        .maybeSingle();
    return row == null ? null : PaymentRecord(Json.from(row));
  }

  Future<List<Json>> fetchBookingPaymentRequirements(String bookingId) =>
      fetchRows(
        'booking_payment_requirements',
        equals: {'booking_id': bookingId},
      );

  Future<BookingWaitingBalance> fetchBookingWaitingBalance(
    String bookingId,
  ) async {
    final value = await _client.rpc(
      'get_booking_waiting_summary',
      params: {'p_booking_id': bookingId},
    );
    if (value is! Map) {
      throw const FormatException('Missing server waiting balance.');
    }
    return BookingWaitingBalance.fromJson(Map<String, dynamic>.from(value));
  }

  String _paymentAttemptKey(String bookingId, String stage) {
    final rng = Random.secure();
    final nonce = List.generate(
      24,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return 'touristrike:$bookingId:$stage:$nonce';
  }

  Future<void> paymentEmailVerification({
    required String action,
    required String bookingId,
    required String paymentStage,
    String? code,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'payment-email-verification',
        body: {
          'action': action,
          'booking_id': bookingId,
          'payment_stage': paymentStage,
          'code': ?code,
        },
      );
      if (response.data is! Map ||
          response.data['status'] !=
              (action == 'request' ? 'SENT' : 'VERIFIED')) {
        throw const PaymentProviderException('VERIFICATION_UNAVAILABLE');
      }
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map
          ? dbString(details['error'], fallback: 'VERIFICATION_UNAVAILABLE')
          : 'VERIFICATION_UNAVAILABLE';
      throw PaymentProviderException(code);
    }
  }

  Future<PayMongoCheckout> createPayMongoCheckout({
    required String bookingId,
    required String paymentStage,
    required String paymentMethod,
    String? customerName,
    String? customerEmail,
  }) async {
    final idempotencyKey = _paymentAttemptKey(
      bookingId,
      '${paymentStage}_$paymentMethod',
    );
    try {
      debugPrint(
        '[PayMongo] invoking paymongo-create-payment '
        'booking=$bookingId stage=$paymentStage method=$paymentMethod',
      );
      final response = await _client.functions.invoke(
        'paymongo-create-payment',
        body: {
          'booking_id': bookingId,
          'payment_stage': paymentStage,
          'payment_method': paymentMethod,
          'idempotency_key': idempotencyKey,
          'customer_name': ?customerName,
          'customer_email': ?customerEmail,
        },
      );
      final data = response.data;
      if (data is! Map) {
        throw const PaymentProviderException('INVALID_PAYMENT_RESPONSE');
      }
      final checkout = PayMongoCheckout.fromJson(Json.from(data));
      if (checkout.paymentRecordId.isEmpty || checkout.checkoutUrl.isEmpty) {
        throw const PaymentProviderException('INVALID_PAYMENT_RESPONSE');
      }
      final checkoutHost =
          Uri.tryParse(checkout.checkoutUrl)?.host ?? 'invalid';
      debugPrint('[PayMongo] checkout URL received host=$checkoutHost');
      return checkout;
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map
          ? dbString(details['error'], fallback: 'PAYMENT_PROVIDER_UNAVAILABLE')
          : 'PAYMENT_PROVIDER_UNAVAILABLE';
      throw PaymentProviderException(code);
    }
  }

  Future<PaymentRecord> prepareGroupCashRemainingBalance({
    required String bookingId,
  }) async {
    final result = await _client.rpc(
      'prepare_group_cash_remaining_balance',
      params: {
        'p_booking_id': bookingId,
        'p_idempotency_key': _paymentAttemptKey(
          bookingId,
          'remaining_balance_cash',
        ),
      },
    );
    return PaymentRecord(Json.from(result as Map));
  }

  Future<PaymentRecord> prepareGroupCashWithCheckoutRecovery({
    required String bookingId,
  }) async {
    try {
      final response = await _client.functions.invoke(
        'paymongo-switch-to-cash',
        body: {
          'booking_id': bookingId,
          'idempotency_key': _paymentAttemptKey(
            bookingId,
            'remaining_balance_cash',
          ),
        },
      );
      final data = response.data;
      if (data is! Map || data['payment'] is! Map) {
        throw const PaymentProviderException('INVALID_PAYMENT_RESPONSE');
      }
      return PaymentRecord(Json.from(data['payment'] as Map));
    } on FunctionException catch (error) {
      final details = error.details;
      final code = details is Map
          ? dbString(details['error'], fallback: 'PAYMENT_STATE_UNAVAILABLE')
          : 'PAYMENT_STATE_UNAVAILABLE';
      throw PaymentProviderException(code);
    }
  }

  Future<bool> reconcilePayMongoRemainingPayment(String bookingId) async {
    final response = await _client.functions.invoke(
      'paymongo-switch-to-cash',
      body: {'booking_id': bookingId, 'action': 'reconcile'},
    );
    final data = response.data;
    return data is Map && data['reconciled'] == true;
  }

  Future<PaymentRecord> confirmGroupCashShare(String paymentRecordId) async {
    final result = await _client.rpc(
      'confirm_group_cash_share',
      params: {'p_payment_record_id': paymentRecordId},
    );
    return PaymentRecord(Json.from(result as Map));
  }

  Future<List<PaymentAllocation>> fetchPaymentAllocationsForBooking(
    String bookingId,
  ) async {
    final rows = await _client
        .from(TourisTrikeTables.paymentAllocationSummaries)
        .select()
        .eq('booking_id', bookingId)
        .order('created_at');
    return _rows(rows).map(PaymentAllocation.new).toList(growable: false);
  }

  Future<List<PaymentAllocation>> fetchConfirmedDriverPaymentAllocations({
    int limit = 500,
  }) async {
    final rows = await _client
        .from('payment_allocations')
        .select(
          '*, payment_records!inner('
          'status, provider, payment_method, payment_stage, paid_at'
          ')',
        )
        .eq('driver_id', requireUserId())
        .eq('payment_records.status', 'confirmed')
        .neq('status', 'cancelled')
        .neq('status', 'manual_review')
        .order('created_at', ascending: false)
        .limit(limit);
    return _rows(rows).map(PaymentAllocation.new).toList(growable: false);
  }

  /// Tricycle single-ride flow only — see `record_ride_payment` in the
  /// payment-trail migration for why this is driver-attested rather than
  /// tourist-submitted like package-booking payments.
  Future<PaymentRecord> recordRidePayment({
    required dynamic rideId,
    required String paymentMethod,
    required double amount,
    String? externalReferenceNo,
  }) async {
    final result = await _client.rpc(
      'record_ride_payment',
      params: {
        'p_ride_id': rideId,
        'p_payment_method': paymentMethod,
        'p_amount': amount,
        'p_external_reference_no': externalReferenceNo,
      },
    );
    return PaymentRecord(Json.from(result as Map));
  }

  Future<PaymentDispute> raisePaymentDispute({
    required String paymentRecordId,
    required String reason,
    String? description,
    String? evidenceUrl,
  }) async {
    final result = await _client.rpc(
      'raise_payment_dispute',
      params: {
        'p_payment_record_id': paymentRecordId,
        'p_reason': reason,
        'p_description': description,
        'p_evidence_url': evidenceUrl,
      },
    );
    return PaymentDispute(Json.from(result as Map));
  }

  Future<PaymentDispute> resolvePaymentDispute({
    required String disputeId,
    required String newStatus,
    String? resolutionNote,
  }) async {
    final result = await _client.rpc(
      'resolve_payment_dispute',
      params: {
        'p_dispute_id': disputeId,
        'p_new_status': newStatus,
        'p_resolution_note': resolutionNote,
      },
    );
    return PaymentDispute(Json.from(result as Map));
  }

  Future<List<PaymentDispute>> fetchPaymentDisputes({
    List<String>? statuses,
    int limit = 80,
  }) async {
    dynamic query = _client.from(TourisTrikeTables.paymentDisputes).select();
    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter('status', statuses);
    }
    final rows = await query.order('created_at', ascending: false).limit(limit);
    return _rows(rows).map(PaymentDispute.new).toList(growable: false);
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
        .from(TourisTrikeTables.packageBookings)
        .select(
          '*, '
          'tour_packages(title, city, cover_image_url, image_url), '
          'package_activities(*)',
        )
        .eq('tourist_id', requireUserId())
        .order('created_at', ascending: false)
        .limit(limit);
    final activities = await _withActivityParticipantIdentities(
      await _withSettledBookingPayments(_rows(rows)),
    );
    return activities
        .map(packageActivityFromPersistedBooking)
        .toList(growable: false);
  }

  Future<List<PackageActivity>> fetchDriverActivities({int limit = 60}) async {
    final driverId = requireUserId();
    final rows = await _client
        .from(TourisTrikeTables.bookingDrivers)
        .select(
          'booking_id, status, journey_state, accepted_at, completed_at, created_at, '
          'package_bookings('
          '  *, '
          '  tour_packages(title, city, cover_image_url, image_url), '
          '  package_activities(*)'
          ')',
        )
        .eq('driver_id', driverId)
        .inFilter('status', const ['accepted', 'completed'])
        .order('created_at', ascending: false)
        .limit(limit);
    return (await _withActivityParticipantIdentities(_rows(rows)))
        .map((membership) {
          final bookingValue = membership['package_bookings'];
          if (bookingValue is! Map) return null;
          return packageActivityFromPersistedBooking(
            Json.from(bookingValue),
            bookingDriver: membership,
            effectiveDriverId: driverId,
          );
        })
        .whereType<PackageActivity>()
        .toList(growable: false);
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
          'package_bookings('
          '  id, tourist_id, travel_date, scheduled_start_at, estimated_end_at, '
          '  adults, children, booking_type, '
          '  pickup_address, pickup_latitude, pickup_longitude, '
          '  dropoff_address, dropoff_latitude, dropoff_longitude, '
          '  total_amount, downpayment_amount, remaining_balance, '
          '  payment_method, assigned_driver_id, status, booking_status, tracking_interrupted_at, '
          '  current_spot_index, driver_latitude, driver_longitude, '
          '  accepted_at, arrived_at, picked_up_at, completed_at, '
          '  municipality, province, total_passengers, notes, '
          '  cancelled_at, cancelled_by, cancelled_reason, cancellation_note, '
          '  cancellation_category, cancellation_type, cancellation_fee, '
          '  refundable_amount, refund_status'
          ')',
        )
        .eq('booking_id', bookingId)
        .limit(1);
    final list = await _withActivityParticipantIdentities(_rows(rows));
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

  Future<Map<String, dynamic>> ensureBookingGroupConversation(
    String bookingId,
  ) async {
    final conversationId = await _client.rpc(
      'ensure_booking_group_conversation',
      params: {'p_booking_id': bookingId},
    );
    final row = await _client
        .from(TourisTrikeTables.conversations)
        .select('*')
        .eq('id', conversationId)
        .single();
    return Json.from(row);
  }

  Future<PackageActivity?> fetchPackageActivityById(String activityId) async {
    final rows = await _client
        .from(TourisTrikeTables.packageActivities)
        .select(
          '*, '
          'tour_packages(title, city, cover_image_url, image_url), '
          'package_bookings('
          '  id, tourist_id, travel_date, adults, children, booking_type, '
          '  pickup_address, pickup_latitude, pickup_longitude, '
          '  dropoff_address, dropoff_latitude, dropoff_longitude, '
          '  total_amount, downpayment_amount, remaining_balance, '
          '  payment_method, assigned_driver_id, status, booking_status, tracking_interrupted_at, '
          '  current_spot_index, driver_latitude, driver_longitude, '
          '  accepted_at, arrived_at, picked_up_at, completed_at, '
          '  municipality, province, total_passengers, notes'
          ')',
        )
        .eq('id', activityId)
        .limit(1);
    final list = await _withActivityParticipantIdentities(_rows(rows));
    if (list.isEmpty) return null;
    return PackageActivity(list.first);
  }

  Future<List<PackageActivity>> fetchPendingPackageActivities({
    int limit = 30,
  }) async {
    final result = await _client.rpc(
      'get_available_tour_assignments',
      params: {'p_limit': limit},
    );
    return _rows(result).map(PackageActivity.new).toList(growable: false);
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
    final bookingExtra = Map<String, dynamic>.from(extra)
      ..remove('dropped_off_at');
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
      ...bookingExtra,
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

  Future<Map<String, dynamic>> completePackageActivity(
    String activityId, {
    String bookingId = '',
    String remainingPaymentMethod = '',
  }) async {
    final params = {
      'p_activity_id': activityId,
      'p_remaining_payment_method': remainingPaymentMethod.trim().isEmpty
          ? null
          : remainingPaymentMethod,
    };
    final result = await _client.rpc('complete_package_tour', params: params);
    return result is Map
        ? Map<String, dynamic>.from(result)
        : const {'success': true, 'overall_completed': true};
  }

  Future<Map<String, dynamic>> completeCurrentItineraryItem(
    String activityId, {
    String bookingId = '',
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

  Future<LiveTourTrackingEligibility> fetchLiveTourTrackingEligibility(
    String bookingId,
  ) async {
    final result = await _client.rpc(
      'get_live_tour_tracking_eligibility',
      params: {'p_booking_id': bookingId},
    );
    return LiveTourTrackingEligibility.fromJson(Json.from(result as Map));
  }

  Future<void> upsertDriverLiveLocation({
    required String activityId,
    required double latitude,
    required double longitude,
    double heading = 0,
    double speed = 0,
  }) async {
    final driverId = requireUserId();
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw ArgumentError('Invalid live-location coordinates.');
    }
    final safeHeading = heading.isFinite ? heading.clamp(0, 360).toDouble() : 0;
    final safeSpeed = speed.isFinite ? max(0, speed) : 0.0;
    await _client.from(TourisTrikeTables.driverLiveLocations).upsert({
      'driver_id': driverId,
      'activity_id': activityId,
      'latitude': latitude,
      'longitude': longitude,
      'heading': safeHeading,
      'speed': safeSpeed,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'driver_id');
  }

  String newClientMessageId() {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes
        .map((value) => value.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Future<List<Json>> fetchConversationMessageFeed(String conversationId) async {
    final result = await _client.rpc(
      'get_conversation_message_feed',
      params: {'p_conversation_id': conversationId},
    );
    return _rows(result);
  }

  Future<Json> sendConversationMessage({
    required String conversationId,
    required String messageText,
    required String clientMessageId,
  }) async {
    final result = await _client.rpc(
      'send_conversation_message',
      params: {
        'p_conversation_id': conversationId,
        'p_message_text': messageText,
        'p_client_message_id': clientMessageId,
      },
    );
    return Json.from(result as Map);
  }

  Future<void> upsertTouristLiveLocation({
    required String bookingId,
    required double latitude,
    required double longitude,
    double heading = 0,
    double speed = 0,
    double? accuracyMeters,
  }) async {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      throw ArgumentError('Invalid live-location coordinates.');
    }
    await _client.rpc(
      'upsert_tourist_live_location',
      params: {
        'p_booking_id': bookingId,
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_heading': heading.isFinite ? heading.clamp(0, 360).toDouble() : 0,
        'p_speed': speed.isFinite ? max(0, speed) : 0,
        'p_accuracy_meters': accuracyMeters?.isFinite == true
            ? accuracyMeters!.clamp(0, 500).toDouble()
            : null,
      },
    );
  }

  Future<Json?> fetchTouristLiveLocation(String bookingId) async {
    final rows = await _client
        .from(TourisTrikeTables.bookingParticipantLiveLocations)
        .select()
        .eq('booking_id', bookingId)
        .eq('participant_role', 'tourist')
        .order('updated_at', ascending: false)
        .limit(1);
    final parsed = _rows(rows);
    return parsed.isEmpty ? null : parsed.first;
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

  Future<bool> markSpotActualArrival({
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
      if (list.isEmpty) return false;
      targetId = dbString(list.first['id']);
    }
    final params = {'p_booking_id': bookingId, 'p_itinerary_item_id': targetId};
    final result = await _client.rpc(
      'mark_itinerary_stop_arrived',
      params: params,
    );
    return result == true;
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

  Future<Map<String, dynamic>> fetchMyBookingTestAuthorization(
    String bookingId,
  ) async {
    final normalizedBookingId = bookingId.trim();
    if (normalizedBookingId.isEmpty) return const {'authorized': false};

    final result = await _client.rpc(
      'get_my_booking_test_authorization',
      params: {'p_booking_id': normalizedBookingId},
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : const {'authorized': false};
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

  /// Returns this driver's authoritative assignment row, including withdrawn
  /// and cancelled history. A non-active row must never be treated as a live
  /// booking after refresh or relogin.
  Future<BookingDriver?> fetchMyBookingDriverAssignment(
    String bookingId,
  ) async {
    final row = await _client
        .from(TourisTrikeTables.bookingDrivers)
        .select()
        .eq('booking_id', bookingId)
        .eq('driver_id', requireUserId())
        .maybeSingle();
    return row == null ? null : BookingDriver(Json.from(row));
  }

  Future<List<ConvoyDriverSnapshot>> fetchConvoyRoster(String bookingId) async {
    final bookingDrivers = await fetchBookingDrivers(bookingId);

    final accepted = bookingDrivers
        .where((bd) => bd.status == 'accepted' || bd.status == 'completed')
        .toList(growable: false);

    if (accepted.isEmpty) {
      return const [];
    }

    final driverIds = accepted.map((bd) => bd.driverId).toSet().toList();

    final infos = await fetchDriverInfos(driverIds);

    // Fetch the whole assignment roster's locations. Optional missing GPS or
    // profile data must never remove an assignment from the convoy.
    final locationRows = await _client
        .from(TourisTrikeTables.driverLiveLocations)
        .select()
        .inFilter('driver_id', driverIds);
    final locationByDriverId = <String, DriverLiveLocation>{
      for (final row in locationRows)
        row['driver_id'].toString(): DriverLiveLocation(row),
    };

    return accepted
        .map((bd) {
          final info = infos[bd.driverId];

          final displayName = info?.name.isNotEmpty == true
              ? info!.name
              : 'Driver';

          final plate = info?.details?.plateNumber ?? '';

          final avatar = info?.profile?.profileImageUrl.isNotEmpty == true
              ? info!.profile!.profileImageUrl
              : (info?.profile?.avatarUrl ?? '');

          final loc = locationByDriverId[bd.driverId];
          final hasValidLocation =
              loc != null &&
              loc.latitude.isFinite &&
              loc.longitude.isFinite &&
              loc.latitude >= -90 &&
              loc.latitude <= 90 &&
              loc.longitude >= -180 &&
              loc.longitude <= 180 &&
              !(loc.latitude == 0 && loc.longitude == 0);

          return ConvoyDriverSnapshot(
            driverId: bd.driverId,
            driverName: displayName,
            plateNumber: plate,
            journeyState: bd.journeyState,
            currentStopIndex: bd.currentStopIndex,
            stateUpdatedAt: bd.stateUpdatedAt,
            assignmentStatus: bd.status,
            lastLocationAt: loc?.updatedAt,
            phoneNumber: info?.phoneNumber ?? '',
            avatarUrl: avatar,
            latitude: hasValidLocation ? loc.latitude : null,
            longitude: hasValidLocation ? loc.longitude : null,
            heading: hasValidLocation && loc.heading.isFinite
                ? loc.heading.clamp(0, 360).toDouble()
                : 0,
            todaName: info?.details?.todaName ?? '',
            rating: info?.profile?.averageRating ?? 0,
            assignedPassengers: bd.assignedPassengers,
          );
        })
        .toList(growable: false);
  }

  Future<ConvoyStageProgress> fetchConvoyStageProgress({
    required String bookingId,
    required String stage,
    int? stopIndex,
  }) async {
    final result = await _client.rpc(
      'get_convoy_stage_progress',
      params: {
        'p_booking_id': bookingId,
        'p_stage': stage,
        'p_stop_index': stopIndex,
      },
    );
    if (result is! Map) {
      throw StateError('INVALID_CONVOY_PROGRESS_RESPONSE');
    }
    return ConvoyStageProgress.fromJson(Map<String, dynamic>.from(result));
  }

  Future<double> fetchDriverArrivalRadiusMeters() async {
    final result = await _client.rpc('driver_arrival_radius_meters');
    if (result is! num || !result.isFinite || result <= 0) {
      throw StateError('Unable to load the GPS arrival radius. Please retry.');
    }
    return result.toDouble();
  }

  Future<Json> fetchDriverTourPaymentGate(String bookingId) async => Json.from(
    await _client.rpc(
          'get_driver_tour_payment_gate',
          params: {'p_booking_id': bookingId},
        )
        as Map,
  );

  Future<Json> fetchTourTrackingStatus(String bookingId) async => Json.from(
    await _client.rpc(
          'get_tour_tracking_status',
          params: {'p_booking_id': bookingId},
        )
        as Map,
  );

  Future<Json> observeDriverJourneyLocation({
    required String bookingId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required double speedMps,
    required DateTime sampledAt,
  }) async => Json.from(
    await _client.rpc(
          'observe_driver_journey_location',
          params: {
            'p_booking_id': bookingId,
            'p_latitude': latitude,
            'p_longitude': longitude,
            'p_accuracy_meters': accuracyMeters,
            'p_speed_mps': speedMps,
            'p_sampled_at': sampledAt.toUtc().toIso8601String(),
          },
        )
        as Map,
  );

  Future<Json> recoverDriverJourney({
    required String bookingId,
    required ConvoyJourneyState expectedState,
    required int stopIndex,
    required String reason,
  }) async => Json.from(
    await _client.rpc(
          'recover_driver_journey',
          params: {
            'p_booking_id': bookingId,
            'p_expected_state': expectedState.dbValue,
            'p_stop_index': stopIndex,
            'p_reason': reason,
          },
        )
        as Map,
  );

  Future<Map<String, dynamic>> advanceDriverJourneyState({
    required String bookingId,
    required ConvoyJourneyState targetState,
    bool automaticArrival = false,
  }) async {
    try {
      final params = {
        'p_booking_id': bookingId,
        'p_target_state': targetState.dbValue,
      };
      final result = await _client.rpc(
        'advance_driver_journey_state',
        params: params,
      );

      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }

      return const {'success': true};
    } on PostgrestException catch (e) {
      if (e.message.contains('BARRIER_NOT_MET')) {
        throw const ConvoyBarrierNotMetException();
      }

      rethrow;
    }
  }

  Future<Map<String, dynamic>> advanceDriverTourAction({
    required String bookingId,
    required ConvoyJourneyState expectedState,
    required int stopIndex,
  }) async {
    final result = await _client.rpc(
      'advance_driver_tour_action',
      params: {
        'p_booking_id': bookingId,
        'p_expected_state': expectedState.dbValue,
        'p_stop_index': stopIndex,
      },
    );
    return result is Map
        ? Map<String, dynamic>.from(result)
        : const {'success': true};
  }

  Future<Map<String, dynamic>> cancelDriverSlot(String bookingId) async {
    final result = await _client.rpc(
      'cancel_driver_slot',
      params: {'p_booking_id': bookingId},
    );

    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }

    return const {'success': true};
  }

  Future<Map<String, dynamic>> requestDriverWithdrawal({
    required String bookingId,
    required String reason,
    String? note,
  }) async {
    final result = await _client.rpc(
      'request_driver_withdrawal',
      params: {'p_booking_id': bookingId, 'p_reason': reason, 'p_note': note},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  // ── DRIVER REVIEWS ───────────────────────────────────────────

  Future<Json> fetchTouristReputation(String bookingId) async => Json.from(
    await _client.rpc(
          'get_booking_tourist_reputation',
          params: {'p_booking_id': bookingId},
        )
        as Map,
  );

  Future<Json> fetchBookingFeedback(String bookingId) async => Json.from(
    await _client.rpc(
          'get_booking_feedback',
          params: {'p_booking_id': bookingId},
        )
        as Map,
  );

  Future<Json> submitBookingFeedback({
    required String bookingId,
    int? packageRating,
    String packageComment = '',
    required List<Json> driverReviews,
  }) async => Json.from(
    await _client.rpc(
          'submit_booking_feedback',
          params: {
            'p_booking_id': bookingId,
            'p_package_rating': packageRating,
            'p_package_comment': packageComment,
            'p_driver_reviews': driverReviews,
          },
        )
        as Map,
  );

  Future<Json> fetchDriverHomeOverview() async =>
      Json.from(await _client.rpc('get_driver_home_overview') as Map);

  Future<void> confirmDriverArrivalFallback(
    String bookingId,
    String reason,
  ) async {
    await _client.rpc(
      'confirm_driver_arrival_fallback',
      params: {'p_booking_id': bookingId, 'p_reason': reason},
    );
  }

  Future<bool> hasReviewedDriver(String bookingId, {String? driverId}) async {
    final userId = currentUserId;
    if (userId == null) return false;
    dynamic query = _client
        .from(TourisTrikeTables.driverReviews)
        .select('id')
        .eq('booking_id', bookingId)
        .eq('tourist_id', userId);
    if (driverId != null && driverId.isNotEmpty) {
      query = query.eq('driver_id', driverId);
    }
    final rows = await query.limit(1);
    return rows is List && rows.isNotEmpty;
  }

  /// Returns true only when BOTH driver review and package review exist.
  Future<bool> hasReviewedBooking(String bookingId) async {
    final userId = currentUserId;
    if (userId == null) return false;
    final result = await _client.rpc(
      'tourist_has_reviewed_booking',
      params: {'p_booking_id': bookingId},
    );
    return result == true;
  }

  Future<void> submitDriverReview({
    required String bookingId,
    required String driverId,
    required int rating,
    String reviewText = '',
  }) async {
    final userId = requireUserId();
    await _client.from(TourisTrikeTables.driverReviews).upsert({
      'booking_id': bookingId,
      'driver_id': driverId,
      'tourist_id': userId,
      'rating': rating,
      'review_text': reviewText.trim().isEmpty ? null : reviewText.trim(),
    }, onConflict: 'booking_id,driver_id,tourist_id');
  }

  Future<void> submitPackageReview({
    required String bookingId,
    required int rating,
    String reviewText = '',
    dynamic packageId,
  }) async {
    final userId = requireUserId();
    final payload = <String, dynamic>{
      'booking_id': bookingId,
      'tourist_id': userId,
      'rating': rating,
      'review_text': reviewText.trim().isEmpty ? null : reviewText.trim(),
    };
    if (packageId != null) {
      payload['package_id'] = packageId;
    }
    await _client
        .from('package_reviews')
        .upsert(payload, onConflict: 'booking_id,tourist_id');
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
    return fetchProfile(driverId);
  }

  Future<List<Json>> _withActivityParticipantIdentities(List<Json> rows) async {
    final participantRows = <Map>[];
    final ids = <String>{};
    void collect(dynamic value) {
      if (value is Map) {
        if (value.containsKey('tourist_id') || value.containsKey('driver_id')) {
          participantRows.add(value);
          for (final key in ['tourist_id', 'driver_id', 'assigned_driver_id']) {
            final id = dbString(value[key]).trim();
            if (id.isNotEmpty) ids.add(id);
          }
        }
        for (final child in value.values) {
          collect(child);
        }
      } else if (value is List) {
        for (final child in value) {
          collect(child);
        }
      }
    }

    collect(rows);
    final identities = await ParticipantProfiles.fetchMany(_client, ids);
    final byId = {
      for (final identity in identities) dbString(identity['id']): identity,
    };
    for (final row in participantRows) {
      if (row.containsKey('tourist_id')) {
        row['tourist'] = byId[dbString(row['tourist_id'])];
      }
      final driverId = dbString(row['driver_id']).isNotEmpty
          ? dbString(row['driver_id'])
          : dbString(row['assigned_driver_id']);
      if (driverId.isNotEmpty) row['driver'] = byId[driverId];
    }
    return rows;
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
      final result = await _client.rpc(
        'get_shared_trip_details',
        params: {
          'p_public_token': publicToken,
          'p_access_code': accessCode,
          'p_device_info': deviceInfo,
          'p_user_agent': userAgent,
          'p_silent': silent,
        },
      );
      if (result == null) return null;
      final map = Map<String, dynamic>.from(result as Map);
      if (map['error'] != null) throw Exception(map['message']);
      return GuestTripDetails.fromJson(map);
    } catch (_) {
      rethrow;
    }
  }

  Future<Set<String>> fetchActiveMunicipalities() async {
    try {
      final rows = await _client
          .from(TourisTrikeTables.tourPackages)
          .select('city')
          .isFilter('archived_at', null)
          .eq('status', 'published')
          .eq('visibility_status', 'visible');
      return {
        for (final row in _rows(rows))
          if (row['city'] is String &&
              (row['city'] as String).trim().isNotEmpty)
            (row['city'] as String).trim(),
      };
    } catch (_) {
      return const {};
    }
  }
}
