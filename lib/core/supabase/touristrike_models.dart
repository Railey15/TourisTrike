import 'package:touristrike/core/models/convoy_state.dart';
import 'package:touristrike/core/auth/app_role.dart';

typedef Json = Map<String, dynamic>;

const payMongoPaymentMethods = <String>['gcash', 'paymaya', 'qrph', 'card'];

String paymentMethodLabel(String value) => switch (value.toLowerCase()) {
  'gcash' => 'GCash',
  'paymaya' || 'maya' => 'Maya',
  'qrph' => 'QR Ph',
  'card' => 'Credit / Debit Card',
  'cash' => 'Cash',
  final method =>
    method
        .replaceAll('_', ' ')
        .split(' ')
        .where((word) => word.isNotEmpty)
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' '),
};

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

  AppRole? get appRole => AppRole.tryParse(role);
  bool get isTourist => appRole == AppRole.tourist;
  bool get isDriver => appRole == AppRole.driver;
  bool get isAdministrator => appRole == AppRole.administrator;
  bool get isMainTenant => appRole == AppRole.mainTenant;
  bool get isSubtenant => appRole == AppRole.subtenant;
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
  String get gcashNumber => dbString(row['gcash_number']);
  String get gcashName => dbString(row['gcash_name']);
  String get gcashQrUrl => dbString(row['gcash_qr_url']);
  bool get hasGcashDetails =>
      gcashQrUrl.isNotEmpty || (gcashNumber.isNotEmpty && gcashName.isNotEmpty);

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
  DateTime? get scheduledStartAt => dbDate(row['scheduled_start_at']);
  DateTime? get estimatedEndAt => dbDate(row['estimated_end_at']);
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
  double get settledAmount => dbDouble(row['_settled_amount']);
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
  int get additionalTricycleCount => dbInt(row['additional_tricycle_count']);
  String get additionalTricycleRequestStatus =>
      dbString(row['additional_tricycle_request_status'], fallback: 'none');
  String get additionalTricycleReason =>
      dbString(row['additional_tricycle_reason']);
  String get additionalTricycleExplanation =>
      dbString(row['additional_tricycle_explanation']);
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
  DateTime? get cancelledAt => dbDate(row['cancelled_at']);
  String get cancelledBy => dbString(row['cancelled_by']);
  String get cancellationNote => dbString(row['cancellation_note']);
  String get cancellationCategory => dbString(row['cancellation_category']);
  String get cancellationType => dbString(row['cancellation_type']);
  String get cancellationParty => dbString(row['cancellation_party']);
  String get cancellationReasonCode =>
      dbString(row['cancellation_reason_code']);
  String get replacementStatus =>
      dbString(row['replacement_status'], fallback: 'none');
  DateTime? get replacementSearchStartedAt =>
      dbDate(row['replacement_search_started_at']);
  DateTime? get replacementDeadlineAt => dbDate(row['replacement_deadline_at']);
  String get payoutEligibilityReason =>
      dbString(row['payout_eligibility_reason']);
  bool get isSearchingForReplacement =>
      replacementStatus == 'awaiting_replacement';
  bool get hasReplacementDriver => replacementStatus == 'replacement_assigned';
  double get cancellationFee => dbDouble(row['cancellation_fee']);
  double get refundableAmount => dbDouble(row['refundable_amount']);
  String get refundStatus =>
      dbString(row['refund_status'], fallback: 'not_required');
  DateTime? get completedAt => dbDate(row['completed_at']);
  Json? get packageRow => row['tour_packages'] is Map
      ? Json.from(row['tour_packages'] as Map)
      : null;
  Json? get touristRow => row['profiles'] is Map
      ? Json.from(row['profiles'] as Map)
      : row['tourist'] is Map
      ? Json.from(row['tourist'] as Map)
      : null;
  Json? get driverRow =>
      row['driver'] is Map ? Json.from(row['driver'] as Map) : null;
}

class LiveTourTrackingEligibility {
  const LiveTourTrackingEligibility({
    required this.canAccess,
    required this.reasonCode,
    required this.serverNow,
    required this.scheduledStartAt,
    required this.deviceReceivedAt,
  });

  factory LiveTourTrackingEligibility.fromJson(Json json) =>
      LiveTourTrackingEligibility(
        canAccess: dbBool(json['can_access']),
        reasonCode: dbString(json['reason_code']),
        serverNow: dbDate(json['server_now']),
        scheduledStartAt: dbDate(json['scheduled_start_at']),
        deviceReceivedAt: DateTime.now().toUtc(),
      );

  static const locked = LiveTourTrackingEligibility(
    canAccess: false,
    reasonCode: 'NOT_CHECKED',
    serverNow: null,
    scheduledStartAt: null,
    deviceReceivedAt: null,
  );

  final bool canAccess;
  final String reasonCode;
  final DateTime? serverNow;
  final DateTime? scheduledStartAt;
  final DateTime? deviceReceivedAt;

  DateTime authoritativeNow([DateTime? deviceNow]) {
    final current = (deviceNow ?? DateTime.now()).toUtc();
    final server = serverNow;
    final received = deviceReceivedAt;
    if (server == null || received == null) return current;
    return server.add(current.difference(received));
  }

  bool get isBeforeScheduledStart {
    final scheduled = scheduledStartAt;
    return !canAccess &&
        reasonCode == 'BEFORE_SCHEDULED_START' &&
        scheduled != null &&
        authoritativeNow().isBefore(scheduled);
  }
}

// PayMongo-backed package payment records; raw card data is never persisted.
class CancellationEligibility {
  const CancellationEligibility({
    required this.canCancel,
    required this.reasonCode,
    required this.displayMessage,
    required this.cancellationType,
    required this.amountPaid,
    required this.cancellationFee,
    required this.refundableAmount,
    required this.nonRefundableAmount,
    required this.refundRate,
    required this.refundType,
    required this.hasAssignedDrivers,
    this.scheduledAt,
    this.packageTitle = 'Tour package',
    this.hoursBeforeTour = 0,
    this.requiresReview = false,
  });

  factory CancellationEligibility.fromJson(Map<String, dynamic> json) {
    return CancellationEligibility(
      canCancel: dbBool(json['can_cancel']),
      reasonCode: dbString(
        json['reason_code'],
        fallback: 'CANCELLATION_NOT_ALLOWED',
      ),
      displayMessage: dbString(
        json['display_message'],
        fallback: 'This booking cannot be cancelled right now.',
      ),
      cancellationType: dbString(json['cancellation_type']),
      amountPaid: dbDouble(json['amount_paid']),
      cancellationFee: dbDouble(json['cancellation_fee']),
      refundableAmount: dbDouble(json['refundable_amount']),
      nonRefundableAmount: dbDouble(json['non_refundable_amount']),
      refundRate: dbDouble(json['refund_rate']),
      refundType: dbString(json['refund_type'], fallback: 'no_payment'),
      hasAssignedDrivers: dbBool(json['has_assigned_drivers']),
      scheduledAt: dbDate(json['scheduled_at']),
      packageTitle: dbString(json['package_title'], fallback: 'Tour package'),
      hoursBeforeTour: dbDouble(json['hours_before_tour']),
      requiresReview: dbBool(json['requires_review']),
    );
  }

  final bool canCancel;
  final String reasonCode;
  final String displayMessage;
  final String cancellationType;
  final double amountPaid;
  final double cancellationFee;
  final double refundableAmount;
  final double nonRefundableAmount;
  final double refundRate;
  final String refundType;
  final bool hasAssignedDrivers;
  final DateTime? scheduledAt;
  final String packageTitle;
  final double hoursBeforeTour;
  final bool requiresReview;
}

class BookingCancellationResult {
  const BookingCancellationResult({
    required this.eligibility,
    required this.bookingId,
    required this.reason,
    required this.refundStatus,
    required this.refundRequestCount,
    required this.releasedDriverCount,
    this.note,
    this.cancelledAt,
  });

  factory BookingCancellationResult.fromJson(Map<String, dynamic> json) {
    return BookingCancellationResult(
      eligibility: CancellationEligibility.fromJson(json),
      bookingId: dbString(json['booking_id']),
      reason: dbString(json['cancellation_reason']),
      note: dbString(json['cancellation_note']),
      refundStatus: dbString(json['refund_status'], fallback: 'not_required'),
      refundRequestCount: dbInt(json['refund_request_count']),
      releasedDriverCount: dbInt(json['released_driver_count']),
      cancelledAt: dbDate(json['cancelled_at']),
    );
  }

  final CancellationEligibility eligibility;
  final String bookingId;
  final String reason;
  final String? note;
  final String refundStatus;
  final int refundRequestCount;
  final int releasedDriverCount;
  final DateTime? cancelledAt;
}

class RefundRequest extends TourisTrikeRow {
  const RefundRequest(super.row);

  String get bookingId => dbString(row['booking_id']);
  String get paymentRecordId => dbString(row['payment_record_id']);
  String get requestedBy => dbString(row['requested_by']);
  String get payeeId => dbString(row['payee_id']);
  double get amount => dbDouble(row['amount']);
  String get reason => dbString(row['reason']);
  String get status => dbString(row['status'], fallback: 'pending');
  DateTime? get requestedAt => dbDate(row['requested_at']);
  DateTime? get completedAt => dbDate(row['completed_at']);
  String get referenceNo => dbString(row['reference_no']);
  String get providerRefundId => dbString(row['provider_refund_id']);
  String get providerRefundStatus => dbString(row['provider_refund_status']);
  DateTime? get createdAt => dbDate(row['created_at']) ?? requestedAt;
}

class BookingNoShowReport extends TourisTrikeRow {
  const BookingNoShowReport(super.row);

  String get bookingId => dbString(row['booking_id']);
  String get bookingDriverId => dbString(row['booking_driver_id']);
  String get reportedBy => dbString(row['reported_by']);
  String get reportedParty => dbString(row['reported_party']);
  String get status => dbString(row['status'], fallback: 'pending');
  String get reportNote => dbString(row['report_note']);
  Json get arrivalEvidence => row['arrival_evidence'] is Map
      ? Json.from(row['arrival_evidence'] as Map)
      : <String, dynamic>{};
  Json get progressionEvidence => row['progression_evidence'] is Map
      ? Json.from(row['progression_evidence'] as Map)
      : <String, dynamic>{};
  DateTime? get reportedAt => dbDate(row['reported_at']);
  DateTime? get resolvedAt => dbDate(row['resolved_at']);
  String get resolutionNote => dbString(row['resolution_note']);
}

class PaymentRecord extends TourisTrikeRow {
  const PaymentRecord(super.row);

  dynamic get rideId => row['ride_id'];
  dynamic get bookingId => row['booking_id'];
  String get payerId => dbString(row['payer_id']);
  String get payeeId => dbString(row['payee_id']);
  double get amount => dbDouble(row['amount']);
  String get paymentMethod => dbString(row['payment_method']);
  String get paymentStage => dbString(row['payment_stage'], fallback: 'full');
  String get externalReferenceNo => dbString(row['external_reference_no']);
  String get proofImageUrl => dbString(row['proof_image_url']);
  String get status =>
      dbString(row['status'], fallback: 'pending_confirmation');
  DateTime? get payerSubmittedAt => dbDate(row['payer_submitted_at']);
  DateTime? get payeeConfirmedAt => dbDate(row['payee_confirmed_at']);
  String get receiptNo => dbString(row['receipt_no']);
  String get serviceDescription => dbString(row['service_description']);
  String get notes => dbString(row['notes']);
  String get provider => dbString(row['provider'], fallback: 'manual');
  String get providerStatus => dbString(row['provider_status']);
  String get providerPaymentId => dbString(row['provider_payment_id']);
  String get providerReference => dbString(row['provider_reference']);
  String get checkoutUrl => dbString(row['checkout_url']);
  DateTime? get paidAt => dbDate(row['paid_at']);
  DateTime? get createdAt => dbDate(row['created_at']);

  bool get isPayMongo => provider == 'paymongo';
  bool get isLegacyManualGcash =>
      provider == 'manual' && paymentMethod == 'gcash';
  bool get isGroupCash =>
      provider == 'manual' && paymentMethod == 'cash' && payeeId.isEmpty;
  bool get isConfirmed => status == 'confirmed';
  bool get isPending => status == 'pending_confirmation';
  bool get isDisputed => status == 'disputed';
  bool get isCancelled => status == 'cancelled';

  Json get bookingRow {
    final value = row['package_bookings'];
    if (value is Map) return Json.from(value);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Json.from(value.first as Map);
    }
    return <String, dynamic>{};
  }

  String get packageName {
    final value = bookingRow['tour_packages'];
    if (value is Map) return dbString(value['title']);
    if (value is List && value.isNotEmpty && value.first is Map) {
      return dbString((value.first as Map)['title']);
    }
    return '';
  }
}

/// A tourist-facing ledger entry. Refunds remain linked to their immutable
/// original [payment] through `refund_requests.payment_record_id`; they are not
/// represented as synthetic payments or as a stored-value balance.
class PaymentHistoryEntry {
  const PaymentHistoryEntry.payment(this.payment) : refund = null;

  const PaymentHistoryEntry.refund({
    required this.payment,
    required this.refund,
  });

  final PaymentRecord payment;
  final RefundRequest? refund;

  bool get isRefund => refund != null;
  double get amount => refund?.amount ?? payment.amount;
  DateTime? get occurredAt => isRefund
      ? refund!.completedAt ?? refund!.requestedAt ?? refund!.createdAt
      : payment.paidAt ??
            payment.payeeConfirmedAt ??
            payment.payerSubmittedAt ??
            payment.createdAt;

  String get packageName =>
      payment.packageName.isEmpty ? 'Tour Package' : payment.packageName;

  String get transactionType {
    if (isRefund) {
      final reason = refund!.reason.toLowerCase();
      if (reason.contains('cancel') ||
          reason.contains('no replacement') ||
          reason.contains('no_replacement')) {
        return 'Cancellation Refund';
      }
      if (payment.paymentStage == 'down_payment') {
        return 'Down Payment Refund';
      }
      return 'Payment Refund';
    }
    return switch (payment.paymentStage) {
      'down_payment' => 'Down Payment',
      'remaining_balance' => 'Remaining Balance',
      'full' || 'full_payment' => 'Full Payment',
      'waiting_charge' || 'additional_charge' => 'Waiting Charge',
      final value => _titleCase(value.replaceAll('_', ' ')),
    };
  }

  String get title => '$packageName - $transactionType';
  String get amountPrefix => isRefund ? '+' : '-';

  String get bookingReference {
    for (final key in const [
      'booking_reference',
      'reference_no',
      'booking_code',
    ]) {
      final value = dbString(payment.bookingRow[key]);
      if (value.isNotEmpty) return value;
    }
    final id = payment.bookingId?.toString() ?? '';
    return id.isEmpty
        ? 'Not available'
        : '#${id.substring(0, id.length.clamp(0, 8)).toUpperCase()}';
  }

  String get statusLabel {
    if (isRefund) {
      return switch (refund!.status.toLowerCase()) {
        'completed' || 'refunded' => 'Refunded',
        'rejected' || 'failed' => 'Refund Failed',
        _ => 'Refund Pending',
      };
    }
    return switch (payment.status.toLowerCase()) {
      'confirmed' => 'Paid',
      'cancelled' => 'Cancelled',
      'disputed' => 'Disputed',
      'failed' => 'Failed',
      _ => 'Pending',
    };
  }

  String get originalPaymentReference {
    if (payment.receiptNo.isNotEmpty) return payment.receiptNo;
    if (payment.providerReference.isNotEmpty) return payment.providerReference;
    if (payment.externalReferenceNo.isNotEmpty) {
      return payment.externalReferenceNo;
    }
    return '$bookingReference - ${_titleCase(payment.paymentStage.replaceAll('_', ' '))}';
  }

  String get providerReference {
    if (isRefund) {
      if (refund!.providerRefundId.isNotEmpty) return refund!.providerRefundId;
      if (refund!.referenceNo.isNotEmpty) return refund!.referenceNo;
    }
    if (payment.providerReference.isNotEmpty) return payment.providerReference;
    if (payment.providerPaymentId.isNotEmpty) return payment.providerPaymentId;
    return payment.externalReferenceNo;
  }

  static String _titleCase(String value) => value
      .split(' ')
      .where((word) => word.isNotEmpty)
      .map(
        (word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}

class PaymentAllocation extends TourisTrikeRow {
  const PaymentAllocation(super.row);

  String get paymentRecordId => dbString(row['payment_record_id']);
  String get bookingId => dbString(row['booking_id']);
  String get driverId => dbString(row['driver_id']);
  double get grossAmount => dbDouble(row['gross_amount']);
  double get driverAmount => dbDouble(row['driver_amount']);
  int get splitBasisPoints => dbInt(row['split_basis_points']);
  String get status => dbString(row['status']);
  DateTime? get paidAt => dbDate(row['paid_at']);
  Json get paymentRecord {
    final value = row['payment_records'];
    return value is Map ? Json.from(value) : <String, dynamic>{};
  }

  String get paymentRecordStatus => dbString(paymentRecord['status']);
  String get provider => dbString(paymentRecord['provider']);
  String get paymentMethod => dbString(paymentRecord['payment_method']);
  String get paymentStage => dbString(paymentRecord['payment_stage']);
  DateTime? get confirmedAt => dbDate(paymentRecord['paid_at']) ?? paidAt;

  bool get isAwaitingCash => status == 'awaiting_cash';
  bool get isCashConfirmed => status == 'cash_confirmed';
  bool get isPayoutPending => status == 'pending' || status == 'held';
  bool get isPayoutEligible => status == 'eligible';
  bool get isPaidOut => status == 'paid';
  String get payoutStatusLabel => switch (status) {
    'pending' || 'held' => 'Pending payout',
    'eligible' => 'Eligible after tour completion',
    'processing' => 'Payout processing',
    'paid' => 'Payout paid',
    'cancelled' => 'Payout cancelled',
    'manual_review' => 'Payout under review',
    'failed' => 'Payout retry needed',
    _ => status.replaceAll('_', ' '),
  };
  bool get isConfirmedEarning =>
      paymentRecordStatus == 'confirmed' &&
      status != 'cancelled' &&
      status != 'manual_review';
}

class PayMongoCheckout {
  const PayMongoCheckout({
    required this.paymentRecordId,
    required this.checkoutUrl,
    required this.reused,
    required this.livemode,
    required this.paymentMethod,
    required this.paymentFlow,
    required this.qrPaymentUrl,
  });

  factory PayMongoCheckout.fromJson(Json json) => PayMongoCheckout(
    paymentRecordId: dbString(json['payment_record_id']),
    checkoutUrl: dbString(json['checkout_url']),
    reused: dbBool(json['reused']),
    livemode: dbBool(json['livemode']),
    paymentMethod: dbString(json['payment_method']),
    paymentFlow: dbString(json['payment_flow'], fallback: 'redirect'),
    qrPaymentUrl: json['qr_payment'] is Map
        ? dbString((json['qr_payment'] as Map)['checkout_url'])
        : '',
  );

  final String paymentRecordId;
  final String checkoutUrl;
  final bool reused;
  final bool livemode;
  final String paymentMethod;
  final String paymentFlow;
  final String qrPaymentUrl;

  bool get isHostedQr => paymentFlow == 'hosted_qr';
}

class PaymentDispute extends TourisTrikeRow {
  const PaymentDispute(super.row);

  String get paymentRecordId => dbString(row['payment_record_id']);
  dynamic get bookingId => row['booking_id'];
  dynamic get rideId => row['ride_id'];
  String get raisedBy => dbString(row['raised_by']);
  String get reason => dbString(row['reason']);
  String get description => dbString(row['description']);
  String get evidenceUrl => dbString(row['evidence_url']);
  String get category => dbString(row['category'], fallback: 'payment');
  String get subject => dbString(row['subject'], fallback: 'Payment dispute');
  String get priority => dbString(row['priority'], fallback: 'normal');
  String get municipality => dbString(row['municipality']);
  String get status => dbString(row['status'], fallback: 'needs_review');
  String get resolvedBy => dbString(row['resolved_by']);
  String get resolutionNote => dbString(row['resolution_note']);
  String get resolutionType => dbString(row['resolution_type']);
  DateTime? get reviewedAt => dbDate(row['reviewed_at']);
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get resolvedAt => dbDate(row['resolved_at']);
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
  int get travelDurationMinutes =>
      dbInt(row['travel_duration_minutes'], fallback: 0);
  int get routeDistanceMeters =>
      dbInt(row['route_distance_meters'], fallback: 0);
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
  double get settledAmount => dbDouble(row['_settled_amount']);
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
  DateTime? get cancelledAt => dbDate(row['cancelled_at']);
  DateTime? get createdAt => dbDate(row['created_at']);
  DateTime? get updatedAt => dbDate(row['updated_at']);
  String get bookingStatus => dbString(
    bookingRow?['booking_status'],
    fallback: dbString(bookingRow?['status']),
  );
  String get bookingDriverStatus =>
      dbString(row['booking_driver_status']).trim().toLowerCase();
  String get driverJourneyState =>
      dbString(row['driver_journey_state']).trim().toLowerCase();

  String get lifecycleStatus {
    final activityStatus = status.trim().toLowerCase();
    final currentTourStatus = tourStatus.trim().toLowerCase();
    final currentBookingStatus = bookingStatus.trim().toLowerCase();

    if (activityStatus == 'cancelled' ||
        currentBookingStatus == 'cancelled' ||
        currentBookingStatus == 'rejected') {
      return 'cancelled';
    }
    if (activityStatus == 'completed' ||
        currentTourStatus == 'completed' ||
        currentBookingStatus == 'completed' ||
        currentBookingStatus == 'done') {
      return 'completed';
    }

    // A convoy member can finish their own assignment before the booking is
    // globally complete. Keep that state distinct so one driver cannot make
    // every participant see "Tour Completed" prematurely.
    if (bookingDriverStatus == 'completed' ||
        driverJourneyState == 'completed') {
      return 'assignment_completed';
    }

    if (bookingRow?['tracking_interrupted_at'] != null) {
      return 'interrupted';
    }

    // A booking_drivers row is the authoritative ownership record for a
    // convoy driver. In particular, the first accepted driver remains active
    // while the booking itself is still waiting for the remaining slots.
    if (bookingDriverStatus == 'accepted') {
      if (driverJourneyState == 'boarded' ||
          driverJourneyState == 'en_route_stop' ||
          driverJourneyState == 'at_stop' ||
          driverJourneyState == 'stop_done' ||
          driverJourneyState == 'en_route_dropoff' ||
          driverJourneyState == 'at_dropoff') {
        return 'ongoing';
      }
      return 'accepted';
    }

    if (activityStatus == 'ongoing' ||
        currentBookingStatus == 'on_tour' ||
        currentTourStatus == 'picked_up' ||
        currentTourStatus == 'on_tour' ||
        currentTourStatus == 'en_route_to_spot' ||
        currentTourStatus == 'at_spot' ||
        currentTourStatus == 'en_route_to_dropoff' ||
        currentTourStatus == 'ready_to_complete') {
      return 'ongoing';
    }
    if (activityStatus == 'accepted' ||
        currentBookingStatus == 'accepted' ||
        currentBookingStatus == 'confirmed' ||
        currentBookingStatus == 'driver_on_the_way' ||
        currentTourStatus == 'arrived' ||
        currentTourStatus == 'driver_accepted' ||
        currentTourStatus == 'driver_en_route' ||
        currentTourStatus == 'driver_arrived') {
      return 'accepted';
    }
    if (activityStatus == 'pending' ||
        currentBookingStatus == 'pending' ||
        currentBookingStatus == 'waiting_for_drivers') {
      return 'pending';
    }

    return activityStatus.isNotEmpty
        ? activityStatus
        : currentBookingStatus.isNotEmpty
        ? currentBookingStatus
        : currentTourStatus;
  }

  bool get isActiveLifecycle =>
      lifecycleStatus == 'accepted' || lifecycleStatus == 'ongoing';

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

/// Reconstructs the Activity view model from the persisted booking row.
///
/// `package_bookings` is the source of truth. `package_activities` supplies
/// tracking details when present, while [bookingDriver] supplies authoritative
/// convoy ownership and per-driver journey state.
PackageActivity packageActivityFromPersistedBooking(
  Json booking, {
  Json? bookingDriver,
  String? effectiveDriverId,
}) {
  final bookingCopy = Json.from(booking);
  final package = bookingCopy.remove('tour_packages');
  final relatedActivity = _singleRelatedRow(
    bookingCopy.remove('package_activities'),
  );

  final row = <String, dynamic>{
    ...?relatedActivity,
    'booking_id': dbString(booking['id']),
    'tourist_id': dbString(booking['tourist_id']),
    'package_id': booking['package_id'],
    'price': relatedActivity?['price'] ?? booking['total_amount'],
    'created_at': relatedActivity?['created_at'] ?? booking['created_at'],
    'updated_at': relatedActivity?['updated_at'] ?? booking['updated_at'],
    'status': relatedActivity?['status'] ?? booking['status'] ?? 'pending',
    'tour_status': relatedActivity?['tour_status'] ?? 'waiting_driver',
    'payment_status':
        bookingCopy['_derived_payment_status'] ??
        relatedActivity?['payment_status'] ??
        'unpaid',
    '_settled_amount': bookingCopy['_settled_amount'] ?? 0,
    'package_bookings': bookingCopy,
    ...package is Map
        ? {'tour_packages': Json.from(package)}
        : const <String, dynamic>{},
    if (effectiveDriverId != null && effectiveDriverId.isNotEmpty)
      'driver_id': effectiveDriverId,
    if (bookingDriver != null) ...{
      'booking_driver_status': bookingDriver['status'],
      'driver_journey_state': bookingDriver['journey_state'],
      'booking_driver_accepted_at': bookingDriver['accepted_at'],
      'booking_driver_completed_at': bookingDriver['completed_at'],
    },
  };

  final activity = PackageActivity(row);
  if (activity.lifecycleStatus == 'completed' ||
      activity.lifecycleStatus == 'assignment_completed' ||
      activity.lifecycleStatus == 'cancelled') {
    // Activity/history rows must never expose a driver's live coordinates for
    // a terminal trip. Live tracking performs its own active-trip checks.
    row['driver_latitude'] = null;
    row['driver_longitude'] = null;
    row['driver_last_seen'] = null;
  }

  return PackageActivity(row);
}

Json? _singleRelatedRow(dynamic value) {
  if (value is Map) return Json.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Json.from(value.first as Map);
  }
  return null;
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

  // Convoy sync fields
  ConvoyJourneyState get journeyState =>
      ConvoyJourneyState.fromDb(row['journey_state'] as String?);

  int get currentStopIndex => dbInt(row['current_stop_index']);

  int get assignedPassengers => dbInt(row['assigned_passengers']);

  DateTime get stateUpdatedAt =>
      dbDate(row['state_updated_at']) ??
      acceptedAt ??
      createdAt ??
      DateTime.now();

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
  String get accessStatus =>
      dbString(row['access_status'], fallback: 'pending');
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
    this.drivers = const [],
  });

  final List<ConvoyDriverSnapshot> drivers;
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
    // Supabase numeric fields may arrive as numbers or numeric strings.
    double? number(dynamic value) {
      final parsed = double.tryParse(value?.toString() ?? '');
      return parsed != null && parsed.isFinite ? parsed : null;
    }

    Map<String, dynamic> coordinates(
      Map<String, dynamic> row,
      String latKey,
      String lngKey,
    ) {
      final lat = number(row[latKey]);
      final lng = number(row[lngKey]);
      final valid =
          lat != null &&
          lng != null &&
          lat.abs() <= 90 &&
          lng.abs() <= 180 &&
          !(lat == 0 && lng == 0);
      return {...row, latKey: valid ? lat : null, lngKey: valid ? lng : null};
    }

    for (final prefix in ['pickup', 'dropoff', 'driver']) {
      json = coordinates(json, '${prefix}_latitude', '${prefix}_longitude');
    }
    return GuestTripDetails(
      drivers: (json['drivers'] as List? ?? const []).whereType<Map>().map((
        row,
      ) {
        final driver = coordinates(
          Map<String, dynamic>.from(row),
          'latitude',
          'longitude',
        );
        return ConvoyDriverSnapshot(
          driverId: dbString(driver['driver_id']),
          driverName: dbString(driver['driver_name'], fallback: 'Driver'),
          plateNumber: dbString(driver['plate_number']),
          todaName: dbString(driver['toda_name']),
          lastLocationAt: dbDate(driver['updated_at']),
          journeyState: ConvoyJourneyState.fromDb(
            driver['journey_state']?.toString(),
          ),
          currentStopIndex: dbInt(driver['current_stop_index']),
          stateUpdatedAt:
              DateTime.tryParse(dbString(driver['state_updated_at'])) ??
              DateTime.fromMillisecondsSinceEpoch(0),
          assignmentStatus: dbString(driver['status'], fallback: 'accepted'),
          latitude: (driver['latitude'] as num?)?.toDouble(),
          longitude: (driver['longitude'] as num?)?.toDouble(),
          heading: number(driver['heading']) ?? 0,
        );
      }).toList(),
      bookingId: json['booking_id']?.toString() ?? '',
      driverId: json['driver_id']?.toString() ?? '',
      bookingStatus: json['booking_status']?.toString() ?? '',
      tourStatus: json['tour_status']?.toString() ?? '',
      bookingStatusDetail: json['booking_status_detail']?.toString() ?? '',
      itineraryItems:
          (json['itinerary_items'] as List?)
              ?.whereType<Map>()
              .map(
                (e) => coordinates(
                  Map<String, dynamic>.from(e),
                  'latitude',
                  'longitude',
                ),
              )
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
    drivers: drivers,
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

  /// Adapt the token-scoped projection for the SAME live ETA widget used by
  /// Tourist Tracking. These models contain no payment or contact data.
  PackageBooking get trackingBooking => PackageBooking({
    'id': bookingId,
    'pickup_latitude': pickupLatitude,
    'pickup_longitude': pickupLongitude,
    'dropoff_latitude': dropoffLatitude,
    'dropoff_longitude': dropoffLongitude,
  });

  List<BookingItineraryItem> get trackingStops => itineraryItems
      .map(
        (item) => BookingItineraryItem({
          ...item,
          'destination_name': item['name'],
          'destination_order': item['order'],
          'spot_status': item['status'],
          'actual_arrival_time': item['arrived_at'],
          'actual_departure_time': item['departed_at'],
        }),
      )
      .toList(growable: false);

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
        const {
          'completed',
          'cancelled',
          'rejected',
          'done',
        }.contains(bookingStatus) ||
        const {
          'completed',
          'cancelled',
          'rejected',
          'done',
        }.contains(bookingStatusDetail);
  }
}
