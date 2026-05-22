typedef Json = Map<String, dynamic>;

String dbString(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

int dbInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().replaceAll(',', '').trim()) ?? fallback;
}

double dbDouble(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '').trim()) ??
      fallback;
}

bool dbBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  final text = value.toString().trim().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return fallback;
}

DateTime? dbDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

String dbTimeText(dynamic value) {
  if (value == null) return '';
  final text = value.toString().trim();
  if (text.isEmpty) return '';
  return text;
}

int resolveItineraryStayMinutes({
  int estimatedMinutes = 0,
  int recommendedMinutes = 0,
  int fallbackMinutes = 60,
}) {
  if (estimatedMinutes > 0) return estimatedMinutes;
  if (recommendedMinutes > 0) return recommendedMinutes;
  return fallbackMinutes;
}

String formatScheduleTimeLabel(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return '';
  final match = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?$').firstMatch(trimmed);
  if (match == null) return trimmed;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final period = hour >= 12 ? 'PM' : 'AM';
  final normalizedHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
  return '$normalizedHour:${minute.toString().padLeft(2, '0')} $period';
}

String addMinutesToScheduleTime(String value, int minutesToAdd) {
  final match = RegExp(
    r'^(\d{1,2}):(\d{2})(?::\d{2})?$',
  ).firstMatch(value.trim());
  if (match == null) return '';
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final total = (hour * 60) + minute + minutesToAdd;
  final normalized = ((total % (24 * 60)) + (24 * 60)) % (24 * 60);
  final newHour = normalized ~/ 60;
  final newMinute = normalized % 60;
  return '${newHour.toString().padLeft(2, '0')}:${newMinute.toString().padLeft(2, '0')}:00';
}

int scheduleMinutesBetween(String start, String end) {
  final startMatch = RegExp(
    r'^(\d{1,2}):(\d{2})(?::\d{2})?$',
  ).firstMatch(start.trim());
  final endMatch = RegExp(
    r'^(\d{1,2}):(\d{2})(?::\d{2})?$',
  ).firstMatch(end.trim());
  if (startMatch == null || endMatch == null) return 0;
  final startMinutes =
      (int.parse(startMatch.group(1)!) * 60) + int.parse(startMatch.group(2)!);
  final endMinutes =
      (int.parse(endMatch.group(1)!) * 60) + int.parse(endMatch.group(2)!);
  final raw = endMinutes - startMinutes;
  return raw >= 0 ? raw : raw + (24 * 60);
}

abstract class TourisTrikeRow {
  const TourisTrikeRow(this.row);

  final Json row;

  Json get raw => row;
  dynamic get id => row['id'];
}

class Profile extends TourisTrikeRow {
  const Profile(super.row);

  String get userId => dbString(row['id']);
  String get role => dbString(row['role'], fallback: 'tourist');
  DateTime? get createdAt => dbDate(row['created_at']);
  String get firstName => dbString(row['first_name']);
  String get lastName => dbString(row['last_name']);
  String get fullName => dbString(row['full_name']);
  String get mobile => dbString(row['mobile']);
  String get gender => dbString(row['gender']);
  String get address => dbString(row['address']);
  String get profileImageUrl => dbString(row['profile_image_url']);
  String get avatarUrl => dbString(row['avatar_url']);
  bool get isOnline => dbBool(row['is_online']);
  String get middleName => dbString(row['middle_name']);
  DateTime? get birthdate => dbDate(row['birthdate']);
  String get barangay => dbString(row['barangay']);
  String get city => dbString(row['city']);
  String get municipality => dbString(row['municipality'], fallback: city);
  String get province => dbString(row['province'], fallback: 'Bulacan');
  String get postalCode => dbString(row['postal_code']);
  bool get isAvailable => dbBool(row['is_available']);
  bool get isVerified => dbBool(row['is_verified']);

  String get displayName {
    if (fullName.isNotEmpty) return fullName;
    final parts = [
      firstName,
      middleName,
      lastName,
    ].where((part) => part.isNotEmpty).join(' ');
    return parts.isEmpty ? 'User' : parts;
  }

  double get averageRating => dbDouble(row['average_rating']);
  int get totalReviews => dbInt(row['total_reviews']);

  String get ratingLabel {
    if (totalReviews == 0) return 'No ratings yet';
    return '${averageRating.toStringAsFixed(1)} ($totalReviews review${totalReviews == 1 ? '' : 's'})';
  }

  bool get isTourist => role == 'tourist';
  bool get isDriver => role == 'driver';
  bool get isAdmin => role == 'admin';
  bool get isSubtenant => role == 'subtenant';
}

class DriverReview extends TourisTrikeRow {
  const DriverReview(super.row);

  String get bookingId => dbString(row['booking_id']);
  String get driverId => dbString(row['driver_id']);
  String get touristId => dbString(row['tourist_id']);
  int get rating => dbInt(row['rating']);
  String get reviewText => dbString(row['review_text']);
  DateTime? get createdAt => dbDate(row['created_at']);
}

class AdminSettings extends TourisTrikeRow {
  const AdminSettings(super.row);

  String get userId => dbString(row['user_id']);
  bool get notificationsEnabled =>
      dbBool(row['notifications_enabled'], fallback: true);
  bool get packageAlerts => dbBool(row['package_alerts'], fallback: true);
  bool get touristSpotAlerts =>
      dbBool(row['tourist_spot_alerts'], fallback: true);
  bool get performanceReports =>
      dbBool(row['performance_reports'], fallback: true);
  bool get systemNotices => dbBool(row['system_notices'], fallback: true);
  String get language => dbString(row['language'], fallback: 'English');
  bool get showTotalViews => dbBool(row['show_total_views'], fallback: true);
  bool get showBookings => dbBool(row['show_bookings'], fallback: true);
  bool get showPopularDestinations =>
      dbBool(row['show_popular_destinations'], fallback: true);
  bool get showTopPackages => dbBool(row['show_top_packages'], fallback: true);
  DateTime? get updatedAt => dbDate(row['updated_at']);
}

class AuditLog extends TourisTrikeRow {
  const AuditLog(super.row);

  String get actorId => dbString(row['actor_id']);
  String get action => dbString(row['action']);
  String get tableName => dbString(row['table_name']);
  String get recordId => dbString(row['record_id']);
  String get description => dbString(row['description']);
  DateTime? get createdAt => dbDate(row['created_at']);
}

class BookingDriverAssignment extends TourisTrikeRow {
  const BookingDriverAssignment(super.row);

  dynamic get bookingId => row['booking_id'];
  String get driverId => dbString(row['driver_id']);
  String get assignedBy => dbString(row['assigned_by']);
  String get status => dbString(row['status'], fallback: 'assigned');
  DateTime? get assignedAt => dbDate(row['assigned_at']);
}

class CityAnnouncement extends TourisTrikeRow {
  const CityAnnouncement(super.row);

  String get createdBy => dbString(row['created_by']);
  String get city => dbString(row['city']);
  String get title => dbString(row['title']);
  String get body => dbString(row['body']);
  String get status => dbString(row['status'], fallback: 'draft');
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);
}

class CityTenantRegistration extends TourisTrikeRow {
  const CityTenantRegistration(super.row);

  String get userId => dbString(row['user_id']);
  String get city => dbString(row['city']);
  String get officeName => dbString(row['office_name']);
  String get contactPerson => dbString(row['contact_person']);
  String get contactNumber => dbString(row['contact_number']);
  String get email => dbString(row['email']);
  String get officeAddress => dbString(row['office_address']);
  String get status => dbString(row['status'], fallback: 'pending');
  DateTime? get submittedAt => dbDate(row['submitted_at']);
  String get reviewedBy => dbString(row['reviewed_by']);
  DateTime? get reviewedAt => dbDate(row['reviewed_at']);
  String get rejectionReason => dbString(row['rejection_reason']);
}

class DriverApplication extends TourisTrikeRow {
  const DriverApplication(super.row);

  String get driverId => dbString(row['driver_id']);
  String get city => dbString(row['city']);
  String get status => dbString(row['status'], fallback: 'pending');
  DateTime? get submittedAt => dbDate(row['submitted_at']);
  String get reviewedBy => dbString(row['reviewed_by']);
  DateTime? get reviewedAt => dbDate(row['reviewed_at']);
  String get rejectionReason => dbString(row['rejection_reason']);
}

class DriverDetails extends TourisTrikeRow {
  const DriverDetails(super.row);

  @override
  String get id => driverId;
  String get driverId => dbString(row['driver_id']);
  String get mobile => dbString(row['mobile']);
  String get licenseNumber => dbString(row['license_number']);
  String get plateNumber => dbString(row['plate_number']);
  DateTime? get licenseExpiry => dbDate(row['license_expiry']);
  String get todaName => dbString(row['toda_name']);
  String get operatorCode => dbString(row['operator_code']);
  DateTime? get createdAt => dbDate(row['created_at']);
  String get status => dbString(row['status'], fallback: 'pending');
  String get approvedBy => dbString(row['approved_by']);
  DateTime? get approvedAt => dbDate(row['approved_at']);
  String get suspendedReason => dbString(row['suspended_reason']);

  String get vehicleLabel {
    final parts = [
      plateNumber,
      todaName,
      operatorCode,
    ].where((part) => part.isNotEmpty).toList(growable: false);
    return parts.join(' • ');
  }
}

class DriverInfo {
  const DriverInfo({this.profile, this.details});

  final Profile? profile;
  final DriverDetails? details;

  String get id => profile?.userId ?? details?.driverId ?? '';

  String get name {
    final profileName = profile?.displayName ?? '';
    if (profileName.isNotEmpty) return profileName;
    return 'Driver';
  }

  String get phoneNumber {
    final fromProfile = profile?.mobile ?? '';
    if (fromProfile.isNotEmpty) return fromProfile;
    return details?.mobile ?? '';
  }

  String get vehicleDetails => details?.vehicleLabel ?? '';

  bool get hasContactDetails =>
      phoneNumber.isNotEmpty || vehicleDetails.isNotEmpty || name.isNotEmpty;
}

class DriverDocuments extends TourisTrikeRow {
  const DriverDocuments(super.row);

  @override
  String get id => driverId;
  String get driverId => dbString(row['driver_id']);
  String get selfieUrl => dbString(row['selfie_url']);
  String get licenseFrontUrl => dbString(row['license_front_url']);
  String get licenseBackUrl => dbString(row['license_back_url']);
  String get policeClearanceUrl => dbString(row['police_clearance_url']);
  String get mtopUrl => dbString(row['mtop_url']);
  String get vehicleFrontUrl => dbString(row['vehicle_front_url']);
  String get vehicleBackUrl => dbString(row['vehicle_back_url']);
  String get vehicleLeftUrl => dbString(row['vehicle_left_url']);
  String get vehicleRightUrl => dbString(row['vehicle_right_url']);
  String get orUrl => dbString(row['or_url']);
  String get crUrl => dbString(row['cr_url']);
  DateTime? get createdAt => dbDate(row['created_at']);
}

class AppNotification extends TourisTrikeRow {
  const AppNotification(super.row);

  String get userId => dbString(row['user_id']);
  String get title => dbString(row['title']);
  String get body => dbString(row['body']);
  String get type => dbString(row['type']);
  bool get isRead => dbBool(row['is_read']);
  DateTime? get createdAt => dbDate(row['created_at']);
}

class PackageBooking extends TourisTrikeRow {
  const PackageBooking(super.row);

  dynamic get packageId => row['package_id'];
  String get touristId => dbString(row['tourist_id']);
  DateTime? get travelDate => dbDate(row['travel_date']);
  int get adults => dbInt(row['adults'], fallback: 1);
  int get children => dbInt(row['children'], fallback: 0);
  String get bookingType => dbString(row['booking_type'], fallback: 'advanced');
  double get downpaymentAmount => dbDouble(row['downpayment_amount']);
  double get remainingBalance => dbDouble(row['remaining_balance']);
  String get pickupAddress => dbString(row['pickup_address']);
  double? get pickupLatitude => row['pickup_latitude'] is num
      ? (row['pickup_latitude'] as num).toDouble()
      : null;
  double? get pickupLongitude => row['pickup_longitude'] is num
      ? (row['pickup_longitude'] as num).toDouble()
      : null;
  String get dropoffAddress => dbString(row['dropoff_address']);
  double? get dropoffLatitude => row['dropoff_latitude'] is num
      ? (row['dropoff_latitude'] as num).toDouble()
      : null;
  double? get dropoffLongitude => row['dropoff_longitude'] is num
      ? (row['dropoff_longitude'] as num).toDouble()
      : null;
  String get paymentMethod => dbString(row['payment_method'], fallback: 'cash');
  String get notes => dbString(row['notes']);
  double get totalAmount => dbDouble(row['total_amount']);
  String get status => dbString(row['status'], fallback: 'pending');
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);
  String get assignedDriverId => dbString(row['assigned_driver_id']);
  String get bookingStatus => dbString(row['booking_status'], fallback: status);
  String get municipality =>
      dbString(row['municipality'], fallback: dbString(packageRow?['city']));
  String get province => dbString(row['province'], fallback: 'Bulacan');
  int get totalPassengers =>
      dbInt(row['total_passengers'], fallback: adults + children);
  int get currentSpotIndex => dbInt(row['current_spot_index'], fallback: 0);
  int get requiredDrivers => dbInt(row['required_drivers'], fallback: 1);
  int get acceptedDriversCount =>
      dbInt(row['accepted_drivers_count'], fallback: 0);
  double? get driverLatitude => row['driver_latitude'] is num
      ? (row['driver_latitude'] as num).toDouble()
      : null;
  double? get driverLongitude => row['driver_longitude'] is num
      ? (row['driver_longitude'] as num).toDouble()
      : null;
  DateTime? get acceptedAt => dbDate(row['accepted_at']);
  DateTime? get arrivedAt => dbDate(row['arrived_at']);
  DateTime? get pickedUpAt => dbDate(row['picked_up_at']);
  String get confirmedBy => dbString(row['confirmed_by']);
  DateTime? get confirmedAt => dbDate(row['confirmed_at']);
  String get cancelledReason => dbString(row['cancelled_reason']);
  DateTime? get completedAt => dbDate(row['completed_at']);
  Json? get packageRow => row['tour_packages'] is Map
      ? Json.from(row['tour_packages'] as Map)
      : null;
  Json? get touristRow =>
      row['profiles'] is Map
      ? Json.from(row['profiles'] as Map)
      : row['tourist'] is Map
      ? Json.from(row['tourist'] as Map)
      : null;
  Json? get driverRow =>
      row['driver'] is Map ? Json.from(row['driver'] as Map) : null;
}

class PaymentRecord extends TourisTrikeRow {
  const PaymentRecord(super.row);

  dynamic get bookingId => row['booking_id'];
  String get userId => dbString(row['user_id']);
  double get amount => dbDouble(row['amount']);
  String get paymentMethod => dbString(row['payment_method']);
  String get paymentStatus =>
      dbString(row['payment_status'], fallback: 'pending');
  String get paymentType =>
      dbString(row['payment_type'], fallback: 'full_payment');
  String get paymentReference => dbString(row['payment_reference']);
  String get checkoutUrl => dbString(row['checkout_url']);
  DateTime? get paidAt => dbDate(row['paid_at']);
  DateTime? get createdAt => dbDate(row['created_at']);
}

class Ride extends TourisTrikeRow {
  const Ride(super.row);

  String get touristId => dbString(row['tourist_id']);
  String get driverId => dbString(row['driver_id']);
  String get pickupName => dbString(row['pickup_name']);
  double get pickupLat => dbDouble(row['pickup_lat']);
  double get pickupLng => dbDouble(row['pickup_lng']);
  String get dropoffName => dbString(row['dropoff_name']);
  double get dropoffLat => dbDouble(row['dropoff_lat']);
  double get dropoffLng => dbDouble(row['dropoff_lng']);
  double get distanceKm => dbDouble(row['distance_km']);
  double get fareAmount => dbDouble(row['fare_amount']);
  String get paymentMethod => dbString(row['payment_method']);
  String get status => dbString(row['status'], fallback: 'requested');
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get completedAt => dbDate(row['completed_at']);
  double get driverLat => dbDouble(row['driver_lat']);
  double get driverLng => dbDouble(row['driver_lng']);
  DateTime? get driverLastSeen => dbDate(row['driver_last_seen']);
}

class RideFeedback extends TourisTrikeRow {
  const RideFeedback(super.row);

  dynamic get rideId => row['ride_id'];
  String get touristId => dbString(row['tourist_id']);
  String get driverId => dbString(row['driver_id']);
  double get rating => dbDouble(row['rating']);
  String get comment => dbString(row['comment']);
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);
}

class RideReview extends RideFeedback {
  const RideReview(super.row);
}

class SavedPlaceRecord extends TourisTrikeRow {
  const SavedPlaceRecord(super.row);

  String get userId => dbString(row['user_id']);
  String get label => dbString(row['label']);
  String get address => dbString(row['address']);
  double? get latitude =>
      row['latitude'] == null ? null : dbDouble(row['latitude']);
  double? get longitude =>
      row['longitude'] == null ? null : dbDouble(row['longitude']);
  String get kind => dbString(row['kind']);
  String get tag => dbString(row['tag']);
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);
}

class SubtenantDetails extends TourisTrikeRow {
  const SubtenantDetails(super.row);

  @override
  String get id => dbString(row['id']);
  String get officeName => dbString(row['office_name']);
  String get city => dbString(row['city']);
  String get province => dbString(row['province'], fallback: 'Bulacan');
  String get contactPerson => dbString(row['contact_person']);
  String get contactNumber => dbString(row['contact_number']);
  String get email => dbString(row['email']);
  String get officeAddress => dbString(row['office_address']);
  String get description => dbString(row['description']);
  String get logoUrl => dbString(row['logo_url']);
  String get coverImageUrl => dbString(row['cover_image_url']);
  String get verificationStatus => dbString(row['verification_status']);
  bool get isActive => dbBool(row['is_active']);
  String get approvedBy => dbString(row['approved_by']);
  DateTime? get approvedAt => dbDate(row['approved_at']);
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);
}

class TourPackageDayItem extends TourisTrikeRow {
  const TourPackageDayItem(super.row);

  dynamic get dayId => row['day_id'];
  dynamic get spotId => row['spot_id'];
  String get timeLabel => dbString(row['time_label']);
  String get note => dbString(row['note']);
  int get sortOrder => dbInt(row['sort_order']);
  DateTime? get createdAt => dbDate(row['created_at']);
  Json? get spotRow => row['tourist_spots'] is Map
      ? Json.from(row['tourist_spots'] as Map)
      : null;
}

class TourPackageDay extends TourisTrikeRow {
  const TourPackageDay(super.row);

  dynamic get packageId => row['package_id'];
  int get dayNumber => dbInt(row['day_number']);
  String get title => dbString(row['title'], fallback: 'Day $dayNumber');
  DateTime? get createdAt => dbDate(row['created_at']);
  List<TourPackageDayItem> get items {
    final value = row['tour_package_day_items'];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => TourPackageDayItem(Json.from(item)))
        .toList(growable: false);
  }
}

class TourPackageSpot extends TourisTrikeRow {
  const TourPackageSpot(super.row);

  @override
  String get id => '${row['package_id']}:${row['spot_id']}';
  dynamic get packageId => row['package_id'];
  dynamic get spotId => row['spot_id'];
  int get sortOrder => dbInt(row['sort_order']);
  String get openingTime => dbTimeText(row['opening_time']);
  String get closingTime => dbTimeText(row['closing_time']);
  String get estimatedArrivalTime => dbTimeText(row['estimated_arrival_time']);
  int get estimatedDurationMinutes =>
      dbInt(row['estimated_duration_minutes'], fallback: 0);
  int get recommendedVisitDurationMinutes =>
      dbInt(row['recommended_visit_duration_minutes'], fallback: 0);
  DateTime? get createdAt => dbDate(row['created_at']);
}

class CustomizedPackageSpot extends TourisTrikeRow {
  const CustomizedPackageSpot(super.row);

  dynamic get bookingId => row['booking_id'];
  String get touristId => dbString(row['tourist_id']);
  dynamic get packageId => row['package_id'];
  dynamic get spotId => row['spot_id'];
  String get actionType => dbString(row['action_type'], fallback: 'kept');
  String get sourceType => dbString(row['source_type'], fallback: 'manual');
  String get googlePlaceId => dbString(row['google_place_id']);
  String get spotTitle => dbString(row['spot_title']);
  String get spotAddress => dbString(row['spot_address']);
  String get municipality =>
      dbString(row['municipality'], fallback: dbString(row['city']));
  String get barangay => dbString(row['barangay']);
  double get latitude => dbDouble(row['latitude']);
  double get longitude => dbDouble(row['longitude']);
  String get imageUrl => dbString(row['image_url']);
  double get additionalFee => dbDouble(row['additional_fee']);
  int get sortOrder => dbInt(row['sort_order']);
  String get openingTime => dbTimeText(row['opening_time']);
  String get closingTime => dbTimeText(row['closing_time']);
  String get estimatedArrivalTime => dbTimeText(row['estimated_arrival_time']);
  int get estimatedDurationMinutes =>
      dbInt(row['estimated_duration_minutes'], fallback: 0);
  int get recommendedVisitDurationMinutes =>
      dbInt(row['recommended_visit_duration_minutes'], fallback: 0);
  DateTime? get createdAt => dbDate(row['created_at']);
}

class BookingItineraryItem extends TourisTrikeRow {
  const BookingItineraryItem(super.row);

  dynamic get bookingId => row['booking_id'];
  dynamic get spotId => row['spot_id'];
  int get orderNumber => dbInt(
    row['order_number'],
    fallback: dbInt(row['destination_order'], fallback: 1),
  );
  String get destinationName =>
      dbString(row['destination_name'], fallback: dbString(row['spot_title']));
  String get destinationAddress => dbString(
    row['destination_address'],
    fallback: dbString(row['spot_address']),
  );
  int get destinationOrder =>
      dbInt(row['destination_order'], fallback: orderNumber);
  String get arrivalTime => dbTimeText(row['arrival_time']);
  int get estimatedStayDurationMinutes =>
      dbInt(row['estimated_stay_duration_minutes'], fallback: 0);
  String get departureTime => dbTimeText(row['departure_time']);
  String get activityNote =>
      dbString(row['activity_note'], fallback: dbString(row['activity']));
  String get sourceType => dbString(
    row['itinerary_source'] ?? row['source_type'],
    fallback: 'ai_suggested',
  );
  String get googlePlaceId => dbString(row['google_place_id']);
  String get municipality =>
      dbString(row['municipality'], fallback: dbString(row['city']));
  String get barangay => dbString(row['barangay']);
  double get latitude => dbDouble(row['latitude']);
  double get longitude => dbDouble(row['longitude']);
  String get imageUrl => dbString(row['image_url']);
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);

  String get formattedArrivalTime => formatScheduleTimeLabel(arrivalTime);
  String get formattedDepartureTime => formatScheduleTimeLabel(departureTime);
  bool get isCustomized => sourceType == 'customized';
  DateTime? get actualArrivalTime => dbDate(row['actual_arrival_time']);
  DateTime? get actualDepartureTime => dbDate(row['actual_departure_time']);
  String get spotStatus => dbString(row['spot_status'], fallback: 'pending');
}

class TourPackageView extends TourisTrikeRow {
  const TourPackageView(super.row);

  dynamic get packageId => row['package_id'];
  String get userId => dbString(row['user_id']);
  DateTime? get createdAt => dbDate(row['created_at']);
}

class TourPackage extends TourisTrikeRow {
  const TourPackage(super.row);

  String get title => dbString(row['title'], fallback: 'Untitled Package');
  String get subtitle => dbString(row['subtitle']);
  String get city => dbString(row['city']);
  String get priceText => dbString(row['price_text']);
  String get durationText => dbString(row['duration_text']);
  String get imageUrl => dbString(row['image_url']);
  DateTime? get createdAt => dbDate(row['created_at']);
  String get status => dbString(row['status'], fallback: 'draft');
  String get description => dbString(row['description']);
  String get submittedBy => dbString(row['submitted_by']);
  String get submittedByName => dbString(row['submitted_by_name']);
  DateTime? get updatedAt => dbDate(row['updated_at']);
  String get visibilityStatus =>
      dbString(row['visibility_status'], fallback: 'visible');
  double get estimatedBudget => dbDouble(row['estimated_budget']);
  int get groupSize => dbInt(row['group_size']);
  double get routeDistanceKm => dbDouble(row['route_distance_km']);
  String get coverImageUrl => dbString(row['cover_image_url']);
  dynamic get categoryId => row['category_id'];
  String get approvedBy => dbString(row['approved_by']);
  DateTime? get approvedAt => dbDate(row['approved_at']);
  String get returnReason => dbString(row['return_reason']);
  String get displayImageUrl =>
      coverImageUrl.isNotEmpty ? coverImageUrl : imageUrl;
  double get numericPrice {
    if (estimatedBudget > 0) return estimatedBudget;
    final match = RegExp(
      r'(\d+(?:\.\d+)?)',
    ).firstMatch(priceText.replaceAll(',', ''));
    return match == null ? 0 : dbDouble(match.group(1));
  }
}

class TourismCategory extends TourisTrikeRow {
  const TourismCategory(super.row);

  String get name => dbString(row['name']);
  String get description => dbString(row['description']);
  String get icon => dbString(row['icon']);
  String get status => dbString(row['status'], fallback: 'active');
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);
}

class TourismPolicy extends TourisTrikeRow {
  const TourismPolicy(super.row);

  String get title => dbString(row['title']);
  String get content => dbString(row['content']);
  String get status => dbString(row['status'], fallback: 'draft');
  String get createdBy => dbString(row['created_by']);
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);
}

class TouristSpotImage extends TourisTrikeRow {
  const TouristSpotImage(super.row);

  dynamic get spotId => row['spot_id'];
  String get imageUrl => dbString(row['image_url']);
  int get sortOrder => dbInt(row['sort_order']);
  bool get isCover => dbBool(row['is_cover']);
  DateTime? get createdAt => dbDate(row['created_at']);
}

class TouristSpotView extends TourisTrikeRow {
  const TouristSpotView(super.row);

  dynamic get spotId => row['spot_id'];
  String get userId => dbString(row['user_id']);
  DateTime? get createdAt => dbDate(row['created_at']);
}

class Wallet extends TourisTrikeRow {
  const Wallet(super.row);

  String get userId => dbString(row['user_id']);
  String get role => dbString(row['role'], fallback: 'tourist');
  double get balance => dbDouble(row['balance']);
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);
}

class WalletTransaction extends TourisTrikeRow {
  const WalletTransaction(super.row);

  String get walletId => dbString(row['wallet_id']);
  String get userId => dbString(row['user_id']);
  String get role => dbString(row['role'], fallback: 'tourist');
  String get type => dbString(row['type']);
  double get amount => dbDouble(row['amount']);
  String get status => dbString(row['status'], fallback: 'pending');
  String get paymentMethod => dbString(row['payment_method']);
  String get bookingId => dbString(row['booking_id']);
  String get description => dbString(row['description']);
  String get referenceKey => dbString(row['reference_key']);
  String get paymongoReferenceId => dbString(row['paymongo_reference_id']);
  String get checkoutUrl => dbString(row['checkout_url']);
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);
}

class PackageActivity extends TourisTrikeRow {
  const PackageActivity(super.row);

  String get bookingId => dbString(row['booking_id']);
  String get touristId => dbString(row['tourist_id']);
  String get driverId => dbString(row['driver_id']);
  dynamic get packageId => row['package_id'];
  String get status => dbString(row['status'], fallback: 'pending');
  double get price => dbDouble(row['price']);
  String get paymentStatus =>
      dbString(row['payment_status'], fallback: 'unpaid');
  // Tour tracking
  String get tourStatus =>
      dbString(row['tour_status'], fallback: 'waiting_driver');
  int get currentSpotIndex => dbInt(row['current_spot_index'], fallback: 0);
  double? get driverLatitude => row['driver_latitude'] is num
      ? (row['driver_latitude'] as num).toDouble()
      : null;
  double? get driverLongitude => row['driver_longitude'] is num
      ? (row['driver_longitude'] as num).toDouble()
      : null;
  DateTime? get driverLastSeen => dbDate(row['driver_last_seen']);
  DateTime? get acceptedAt => dbDate(row['accepted_at']);
  DateTime? get arrivedAt => dbDate(row['arrived_at']);
  DateTime? get pickedUpAt => dbDate(row['picked_up_at']);
  DateTime? get droppedOffAt => dbDate(row['dropped_off_at']);
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);

  Json? get packageRow => row['tour_packages'] is Map
      ? Json.from(row['tour_packages'] as Map)
      : null;
  Json? get driverRow =>
      row['driver'] is Map ? Json.from(row['driver'] as Map) : null;
  Json? get touristRow =>
      row['tourist'] is Map ? Json.from(row['tourist'] as Map) : null;
  Json? get bookingRow => row['package_bookings'] is Map
      ? Json.from(row['package_bookings'] as Map)
      : null;
}

class TouristSpot extends TourisTrikeRow {
  const TouristSpot(super.row);

  String get title => dbString(row['title'], fallback: 'Untitled Spot');
  String get city => dbString(row['city']);
  String get municipality => dbString(row['municipality'], fallback: city);
  double get latitude => dbDouble(row['latitude']);
  double get longitude => dbDouble(row['longitude']);
  double get rating => dbDouble(row['rating']);
  String get imageUrl => dbString(row['image_url']);
  DateTime? get createdAt => dbDate(row['created_at']);
  String get description => dbString(row['description']);
  String get address => dbString(row['address']);
  String get barangay => dbString(row['barangay']);
  String get province => dbString(row['province'], fallback: 'Bulacan');
  String get status => dbString(row['status'], fallback: 'active');
  DateTime? get updatedAt => dbDate(row['updated_at']);
  dynamic get categoryId => row['category_id'];
  String get sourceType => dbString(row['source_type'], fallback: 'manual');
  String get googlePlaceId => dbString(row['google_place_id']);
  String get submittedBy => dbString(row['submitted_by']);
  String get verifiedBy => dbString(row['verified_by']);
  DateTime? get verifiedAt => dbDate(row['verified_at']);
  String get verificationStatus =>
      dbString(row['verification_status'], fallback: 'pending');
  String get openingTime => dbTimeText(row['opening_time']);
  String get closingTime => dbTimeText(row['closing_time']);
  String get estimatedArrivalTime => dbTimeText(row['estimated_arrival_time']);
  int get estimatedDurationMinutes =>
      dbInt(row['estimated_duration_minutes'], fallback: 0);
  int get recommendedVisitDurationMinutes =>
      dbInt(row['recommended_visit_duration_minutes'], fallback: 0);
  List<TouristSpotImage> get images {
    final value = row['tourist_spot_images'];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => TouristSpotImage(Json.from(item)))
        .toList(growable: false);
  }
}

class BookingDriver extends TourisTrikeRow {
  const BookingDriver(super.row);

  dynamic get bookingId => row['booking_id'];
  String get driverId => dbString(row['driver_id']);
  dynamic get activityId => row['activity_id'];
  String get status => dbString(row['status'], fallback: 'accepted');
  DateTime? get acceptedAt => dbDate(row['accepted_at']);
  DateTime? get completedAt => dbDate(row['completed_at']);
  DateTime? get createdAt => dbDate(row['created_at']);
}

class DriverLiveLocation extends TourisTrikeRow {
  const DriverLiveLocation(super.row);

  String get driverId => dbString(row['driver_id']);
  dynamic get activityId => row['activity_id'];
  double get latitude => dbDouble(row['latitude']);
  double get longitude => dbDouble(row['longitude']);
  double get heading => dbDouble(row['heading']);
  double get speed => dbDouble(row['speed']);
  DateTime? get updatedAt => dbDate(row['updated_at']);
}

class TripStatusLog extends TourisTrikeRow {
  const TripStatusLog(super.row);

  dynamic get activityId => row['activity_id'];
  dynamic get bookingId => row['booking_id'];
  String get status => dbString(row['status']);
  int? get spotIndex =>
      row['spot_index'] is int ? row['spot_index'] as int : null;
  double? get latitude =>
      row['latitude'] is num ? (row['latitude'] as num).toDouble() : null;
  double? get longitude =>
      row['longitude'] is num ? (row['longitude'] as num).toDouble() : null;
  DateTime? get loggedAt => dbDate(row['logged_at']);
  String get notes => dbString(row['notes']);
}

class EmergencyContactRecord extends TourisTrikeRow {
  const EmergencyContactRecord(super.row);

  String get touristId => dbString(row['tourist_id']);
  String get name => dbString(row['name']);
  String get phoneNumber => dbString(row['phone_number']);
  String get relationship => dbString(row['relationship']);
  String get email => dbString(row['email']);
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);
}

class SharedTripLink extends TourisTrikeRow {
  const SharedTripLink(super.row);

  String get bookingId => dbString(row['booking_id']);
  String get touristId => dbString(row['tourist_id']);
  String get publicToken => dbString(row['public_token']);
  String get accessCode => dbString(row['access_code']);
  bool get isActive => dbBool(row['is_active'], fallback: true);
  DateTime? get expiresAt => dbDate(row['expires_at']);
  DateTime? get revokedAt => dbDate(row['revoked_at']);
  dynamic get regeneratedFrom => row['regenerated_from'];
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);

  String get shareUrl => 'https://touris-trike.vercel.app/trip/$publicToken';

  bool get isExpired {
    final expires = expiresAt;
    if (expires == null) return true;
    return DateTime.now().isAfter(expires);
  }

  bool get isValid => isActive && !isExpired && revokedAt == null;
}

class SharedTripAccessLog extends TourisTrikeRow {
  const SharedTripAccessLog(super.row);

  dynamic get sharedLinkId => row['shared_link_id'];
  String get bookingId => dbString(row['booking_id']);
  String? get deviceInfo => row['device_info']?.toString();
  String? get ipAddress => row['ip_address']?.toString();
  String? get userAgent => row['user_agent']?.toString();
  String get accessStatus => dbString(row['access_status'], fallback: 'pending');
  DateTime? get accessedAt => dbDate(row['accessed_at']);
}

class GuestTripDetails {
  const GuestTripDetails({
    required this.bookingId,
    required this.driverId,
    required this.bookingStatus,
    required this.tourStatus,
    required this.bookingStatusDetail,
    required this.itineraryItems,
    required this.driverCode,
    required this.tricycleNumber,
    this.driverPhoneMasked,
    required this.driverName,
    required this.pickupLandmark,
    required this.dropoffLandmark,
    this.pickupLatitude,
    this.pickupLongitude,
    this.dropoffLatitude,
    this.dropoffLongitude,
    this.driverLatitude,
    this.driverLongitude,
  });

  final String bookingId;
  final String driverId;
  final String bookingStatus;
  final String tourStatus;
  final String bookingStatusDetail;
  final List<Map<String, dynamic>> itineraryItems;
  final String driverCode;
  final String tricycleNumber;
  final String? driverPhoneMasked;
  final String driverName;
  final String pickupLandmark;
  final String dropoffLandmark;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final double? dropoffLatitude;
  final double? dropoffLongitude;
  final double? driverLatitude;
  final double? driverLongitude;

  factory GuestTripDetails.fromJson(Map<String, dynamic> json) {
    return GuestTripDetails(
      bookingId: json['booking_id']?.toString() ?? '',
      driverId: json['driver_id']?.toString() ?? '',
      bookingStatus: json['booking_status']?.toString() ?? '',
      tourStatus: json['tour_status']?.toString() ?? '',
      bookingStatusDetail: json['booking_status_detail']?.toString() ?? '',
      itineraryItems: (json['itinerary_items'] as List?)
              ?.whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList() ??
          [],
      driverCode: json['driver_code']?.toString() ?? '',
      tricycleNumber: json['tricycle_number']?.toString() ?? '',
      driverPhoneMasked: json['driver_phone_masked']?.toString(),
      driverName: json['driver_name']?.toString() ?? '',
      pickupLandmark: json['pickup_landmark']?.toString() ?? '',
      dropoffLandmark: json['dropoff_landmark']?.toString() ?? '',
      pickupLatitude: (json['pickup_latitude'] as num?)?.toDouble(),
      pickupLongitude: (json['pickup_longitude'] as num?)?.toDouble(),
      dropoffLatitude: (json['dropoff_latitude'] as num?)?.toDouble(),
      dropoffLongitude: (json['dropoff_longitude'] as num?)?.toDouble(),
      driverLatitude: (json['driver_latitude'] as num?)?.toDouble(),
      driverLongitude: (json['driver_longitude'] as num?)?.toDouble(),
    );
  }

  GuestTripDetails withLocation(double? lat, double? lng) => GuestTripDetails(
        bookingId: bookingId,
        driverId: driverId,
        bookingStatus: bookingStatus,
        tourStatus: tourStatus,
        bookingStatusDetail: bookingStatusDetail,
        itineraryItems: itineraryItems,
        driverCode: driverCode,
        tricycleNumber: tricycleNumber,
        driverPhoneMasked: driverPhoneMasked,
        driverName: driverName,
        pickupLandmark: pickupLandmark,
        dropoffLandmark: dropoffLandmark,
        pickupLatitude: pickupLatitude,
        pickupLongitude: pickupLongitude,
        dropoffLatitude: dropoffLatitude,
        dropoffLongitude: dropoffLongitude,
        driverLatitude: lat,
        driverLongitude: lng,
      );

  bool get isLiveTrackingAvailable {
    return tourStatus == 'driver_en_route' ||
        tourStatus == 'driver_arrived' ||
        tourStatus == 'picked_up' ||
        tourStatus == 'on_tour' ||
        tourStatus == 'en_route_to_spot' ||
        tourStatus == 'at_spot' ||
        tourStatus == 'en_route_to_dropoff' ||
        tourStatus == 'ready_to_complete';
  }

  bool get isTripEnded {
    return tourStatus == 'dropped_off' ||
        tourStatus == 'completed' ||
        bookingStatus == 'completed';
  }
}
