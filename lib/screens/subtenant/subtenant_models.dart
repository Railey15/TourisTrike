import 'package:flutter/material.dart';

String stString(
  Map<String, dynamic> map,
  List<String> keys, {
  String fallback = '',
}) {
  for (final key in keys) {
    final value = map[key];
    if (value != null && value.toString().trim().isNotEmpty) {
      return value.toString().trim();
    }
  }
  return fallback;
}

double stDouble(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '').trim()) ??
      fallback;
}

int stInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().replaceAll(',', '').trim()) ?? fallback;
}

DateTime? stDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

String stId(dynamic value) => value?.toString() ?? '';

String stProfileDisplayName(
  Map<String, dynamic> map, {
  String fallback = 'Tourist',
}) {
  final fullName = stString(map, const ['full_name']);
  if (fullName.isNotEmpty) return fullName;

  final parts = [
    stString(map, const ['first_name']),
    stString(map, const ['last_name']),
  ].where((part) => part.isNotEmpty);
  final joined = parts.join(' ').trim();
  if (joined.isNotEmpty) return joined;

  final mobile = stString(map, const ['mobile']);
  if (mobile.isNotEmpty) return mobile;

  return fallback;
}

String stTitleCase(String value) {
  final normalized = value.replaceAll('_', ' ').trim();
  if (normalized.isEmpty) return 'N/A';
  return normalized
      .split(RegExp(r'\s+'))
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}

Color stStatusColor(String status) {
  switch (status.toLowerCase().trim()) {
    case 'active':
    case 'published':
    case 'visible':
    case 'confirmed':
    case 'completed':
    case 'approved':
      return const Color(0xFF16A34A);
    case 'pending':
    case 'draft':
    case 'maintenance':
      return const Color(0xFFF59E0B);
    case 'returned':
    case 'cancelled':
    case 'archived':
    case 'hidden':
    case 'suspended':
      return const Color(0xFFDC2626);
    case 'sold_out':
      return const Color(0xFF7C3AED);
    default:
      return const Color(0xFF64748B);
  }
}

class SubTenantProfile {
  const SubTenantProfile({
    required this.id,
    required this.role,
    required this.fullName,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.mobile,
    required this.address,
    required this.city,
    required this.province,
    required this.profileImageUrl,
    required this.raw,
  });

  final String id;
  final String role;
  final String fullName;
  final String firstName;
  final String lastName;
  final String email;
  final String mobile;
  final String address;
  final String city;
  final String province;
  final String profileImageUrl;
  final Map<String, dynamic> raw;

  factory SubTenantProfile.fromMap(
    Map<String, dynamic> map, {
    String email = '',
  }) {
    return SubTenantProfile(
      id: stId(map['id']),
      role: stString(map, const ['role']),
      fullName: stString(map, const ['full_name']),
      firstName: stString(map, const ['first_name']),
      lastName: stString(map, const ['last_name']),
      email: stString(map, const ['email'], fallback: email),
      mobile: stString(map, const ['mobile', 'contact_number']),
      address: stString(map, const ['address', 'office_address']),
      city: stString(map, const ['city']),
      province: stString(map, const ['province'], fallback: 'Bulacan'),
      profileImageUrl: stString(map, const ['profile_image_url', 'avatar_url']),
      raw: map,
    );
  }

  String get displayName {
    if (fullName.isNotEmpty) return fullName;
    final generated = [
      firstName,
      lastName,
    ].where((e) => e.isNotEmpty).join(' ');
    if (generated.trim().isNotEmpty) return generated.trim();
    return 'City Tourism Admin';
  }

  String get assignedCity => city;

  bool get isSubTenant => role.toLowerCase().trim() == 'subtenant';
}

String normalizeLocalGovernmentType(String value) {
  final normalized = value.trim().toLowerCase();
  return normalized == 'city' ? 'city' : 'municipality';
}

String localGovernmentDisplayName(String assignedLocation) {
  var name = assignedLocation.trim();
  name = name.replaceFirst(
    RegExp(r'^(city|municipality)\s+of\s+', caseSensitive: false),
    '',
  );
  name = name.replaceFirst(
    RegExp(r'\s+(city|municipality)$', caseSensitive: false),
    '',
  );
  return name.trim();
}

String defaultTourismOfficeName({
  required String assignedLocation,
  required String localGovernmentType,
}) {
  final location = localGovernmentDisplayName(assignedLocation);
  if (location.isEmpty) return 'Tourism Office';
  final officeType = normalizeLocalGovernmentType(localGovernmentType) == 'city'
      ? 'City'
      : 'Municipal';
  return '$location $officeType Tourism Office';
}

bool _stBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  final text = value.toString().trim().toLowerCase();
  if (text == 'true' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == '0' || text == 'no') return false;
  return fallback;
}

class SubTenantCityProfileData {
  const SubTenantCityProfileData({
    required this.city,
    required this.province,
    required this.description,
    required this.tourismOfficeName,
    required this.contactPerson,
    required this.contactNumber,
    required this.email,
    required this.officeAddress,
    required this.coverImageUrl,
    required this.logoImageUrl,
    required this.localGovernmentType,
    required this.officeNameCustomized,
    required this.detailsTableAvailable,
  });

  final String city;
  final String province;
  final String description;
  final String tourismOfficeName;
  final String contactPerson;
  final String contactNumber;
  final String email;
  final String officeAddress;
  final String coverImageUrl;
  final String logoImageUrl;
  final String localGovernmentType;
  final bool officeNameCustomized;
  final bool detailsTableAvailable;

  factory SubTenantCityProfileData.fromProfile(SubTenantProfile profile) {
    return SubTenantCityProfileData(
      city: profile.city,
      province: profile.province.isEmpty ? 'Bulacan' : profile.province,
      description: '',
      tourismOfficeName: defaultTourismOfficeName(
        assignedLocation: profile.city,
        localGovernmentType: 'municipality',
      ),
      contactPerson: profile.displayName,
      contactNumber: profile.mobile,
      email: profile.email,
      officeAddress: profile.address,
      coverImageUrl: '',
      logoImageUrl: profile.profileImageUrl,
      localGovernmentType: 'municipality',
      officeNameCustomized: false,
      detailsTableAvailable: false,
    );
  }

  factory SubTenantCityProfileData.fromMap(
    Map<String, dynamic> map,
    SubTenantProfile profile,
  ) {
    final city = stString(map, const ['city'], fallback: profile.city);
    final localGovernmentType = normalizeLocalGovernmentType(
      stString(map, const ['local_government_type']),
    );
    final storedOfficeName = stString(map, const ['office_name', 'name']);
    final officeNameCustomized = _stBool(map['office_name_customized']);
    final generatedOfficeName = defaultTourismOfficeName(
      assignedLocation: city,
      localGovernmentType: localGovernmentType,
    );
    return SubTenantCityProfileData(
      city: city,
      province: stString(map, const ['province'], fallback: profile.province),
      description: stString(map, const ['description']),
      tourismOfficeName: officeNameCustomized && storedOfficeName.isNotEmpty
          ? storedOfficeName
          : generatedOfficeName,
      contactPerson: stString(map, const [
        'contact_person',
        'full_name',
      ], fallback: profile.displayName),
      contactNumber: stString(map, const [
        'contact_number',
        'mobile',
      ], fallback: profile.mobile),
      email: stString(map, const ['email'], fallback: profile.email),
      officeAddress: stString(map, const [
        'office_address',
        'address',
      ], fallback: profile.address),
      coverImageUrl: stString(map, const ['cover_image_url', 'cover_url']),
      logoImageUrl: stString(map, const [
        'logo_url',
        'profile_image_url',
      ], fallback: profile.profileImageUrl),
      localGovernmentType: localGovernmentType,
      officeNameCustomized: officeNameCustomized,
      detailsTableAvailable: true,
    );
  }

  SubTenantCityProfileData copyWith({
    String? city,
    String? province,
    String? description,
    String? tourismOfficeName,
    String? contactPerson,
    String? contactNumber,
    String? email,
    String? officeAddress,
    String? coverImageUrl,
    String? logoImageUrl,
    String? localGovernmentType,
    bool? officeNameCustomized,
    bool? detailsTableAvailable,
  }) {
    return SubTenantCityProfileData(
      city: city ?? this.city,
      province: province ?? this.province,
      description: description ?? this.description,
      tourismOfficeName: tourismOfficeName ?? this.tourismOfficeName,
      contactPerson: contactPerson ?? this.contactPerson,
      contactNumber: contactNumber ?? this.contactNumber,
      email: email ?? this.email,
      officeAddress: officeAddress ?? this.officeAddress,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      logoImageUrl: logoImageUrl ?? this.logoImageUrl,
      localGovernmentType: localGovernmentType ?? this.localGovernmentType,
      officeNameCustomized: officeNameCustomized ?? this.officeNameCustomized,
      detailsTableAvailable:
          detailsTableAvailable ?? this.detailsTableAvailable,
    );
  }

  Map<String, dynamic> toPersistenceMap() {
    return {
      'description': description,
      'office_name': tourismOfficeName,
      'contact_person': contactPerson,
      'contact_number': contactNumber,
      'email': email,
      'office_address': officeAddress,
      'cover_image_url': coverImageUrl,
      'logo_url': logoImageUrl,
      'office_name_customized': officeNameCustomized,
    };
  }
}

class SubTenantFareSettings {
  const SubTenantFareSettings({
    this.id,
    required this.subtenantId,
    required this.city,
    this.baseFare = 50,
    this.farePerKm = 50,
    this.minimumFare = 0,
    this.waitingFee = 0,
    this.isActive = true,
  });

  final dynamic id;
  final String subtenantId;
  final String city;
  final double baseFare;
  final double farePerKm;
  final double minimumFare;
  final double waitingFee;
  final bool isActive;

  factory SubTenantFareSettings.defaults(SubTenantProfile profile) {
    return SubTenantFareSettings(
      subtenantId: profile.id,
      city: profile.assignedCity,
    );
  }

  factory SubTenantFareSettings.fromMap(
    Map<String, dynamic> map,
    SubTenantProfile profile,
  ) {
    final defaults = SubTenantFareSettings.defaults(profile);
    return SubTenantFareSettings(
      id: map['id'],
      subtenantId: stString(map, const [
        'subtenant_id',
      ], fallback: defaults.subtenantId),
      city: stString(map, const ['city'], fallback: defaults.city),
      baseFare: stDouble(map['base_fare'], fallback: defaults.baseFare),
      farePerKm: stDouble(map['fare_per_km'], fallback: defaults.farePerKm),
      minimumFare: stDouble(
        map['minimum_fare'],
        fallback: defaults.minimumFare,
      ),
      waitingFee: stDouble(map['waiting_fee'], fallback: defaults.waitingFee),
      isActive: _stBool(map['is_active'], fallback: defaults.isActive),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'subtenant_id': subtenantId,
      'city': city,
      'base_fare': baseFare,
      'fare_per_km': farePerKm,
      'minimum_fare': minimumFare,
      'waiting_fee': waitingFee,
      'is_active': isActive,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  FareCalculation calculate({
    required double routeDistanceKm,
    double waitingHours = 1.0,
  }) {
    final normalizedDistance = routeDistanceKm < 0 ? 0.0 : routeDistanceKm;
    final distanceFee = farePerKm * normalizedDistance;
    final waitingTotal = waitingFee * (waitingHours < 0 ? 0 : waitingHours);
    final rawTotal = baseFare + distanceFee + waitingTotal;
    final total = minimumFare > 0 && rawTotal < minimumFare
        ? minimumFare
        : rawTotal;
    return FareCalculation(
      baseFare: baseFare,
      distanceFee: distanceFee,
      waitingFee: waitingTotal,
      minimumFareAdjustment: total - rawTotal,
      total: total,
    );
  }
}

class FareCalculation {
  const FareCalculation({
    required this.baseFare,
    required this.distanceFee,
    required this.waitingFee,
    required this.minimumFareAdjustment,
    required this.total,
  });

  final double baseFare;
  final double distanceFee;
  final double waitingFee;
  final double minimumFareAdjustment;
  final double total;
}

class SubTenantSpot {
  const SubTenantSpot({
    required this.id,
    required this.title,
    required this.description,
    required this.address,
    required this.barangay,
    required this.city,
    required this.municipality,
    required this.province,
    required this.latitude,
    required this.longitude,
    required this.rating,
    required this.imageUrl,
    required this.status,
    required this.createdAt,
    this.categoryId,
    this.verificationStatus = '',
    this.sourceType = 'manual',
    this.googlePlaceId = '',
  });

  final dynamic id;
  final String title;
  final String description;
  final String address;
  final String barangay;
  final String city;
  final String municipality;
  final String province;
  final double latitude;
  final double longitude;
  final double rating;
  final String imageUrl;
  final String status;
  final DateTime? createdAt;
  final dynamic categoryId;
  final String verificationStatus;
  final String sourceType;
  final String googlePlaceId;

  factory SubTenantSpot.fromMap(Map<String, dynamic> map) {
    return SubTenantSpot(
      id: map['id'],
      title: stString(map, const ['title', 'name']),
      description: stString(map, const ['description']),
      address: stString(map, const ['address']),
      barangay: stString(map, const ['barangay']),
      city: stString(map, const ['city']),
      municipality: stString(map, const ['municipality', 'city']),
      province: stString(map, const ['province'], fallback: 'Bulacan'),
      latitude: stDouble(map['latitude']),
      longitude: stDouble(map['longitude']),
      rating: stDouble(map['rating']),
      imageUrl: stString(map, const ['image_url', 'cover_image_url']),
      status: stString(map, const ['status'], fallback: 'active').toLowerCase(),
      createdAt: stDate(map['created_at']),
      categoryId: map['category_id'],
      verificationStatus: stString(map, const ['verification_status']),
      sourceType: stString(map, const ['source_type'], fallback: 'manual'),
      googlePlaceId: stString(map, const ['google_place_id']),
    );
  }
}

class SubTenantPackage {
  const SubTenantPackage({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.city,
    required this.priceText,
    required this.durationText,
    required this.estimatedBudget,
    required this.groupSize,
    required this.routeDistanceKm,
    required this.imageUrl,
    required this.coverImageUrl,
    required this.status,
    required this.visibilityStatus,
    required this.submittedBy,
    required this.submittedByName,
    required this.createdAt,
  });

  final dynamic id;
  final String title;
  final String subtitle;
  final String description;
  final String city;
  final String priceText;
  final String durationText;
  final double estimatedBudget;
  final int groupSize;
  final double routeDistanceKm;
  final String imageUrl;
  final String coverImageUrl;
  final String status;
  final String visibilityStatus;
  final String submittedBy;
  final String submittedByName;
  final DateTime? createdAt;

  factory SubTenantPackage.fromMap(Map<String, dynamic> map) {
    return SubTenantPackage(
      id: map['id'],
      title: stString(map, const ['title']),
      subtitle: stString(map, const ['subtitle']),
      description: stString(map, const ['description']),
      city: stString(map, const ['city']),
      priceText: stString(map, const ['price_text'], fallback: 'From PHP 0'),
      durationText: stString(map, const ['duration_text'], fallback: 'N/A'),
      estimatedBudget: stDouble(map['estimated_budget']),
      groupSize: stInt(map['group_size']),
      routeDistanceKm: stDouble(map['route_distance_km']),
      imageUrl: stString(map, const ['image_url', 'cover_image_url']),
      coverImageUrl: stString(map, const ['cover_image_url', 'image_url']),
      status: stString(map, const ['status'], fallback: 'draft').toLowerCase(),
      visibilityStatus: stString(map, const [
        'visibility_status',
      ], fallback: 'visible').toLowerCase(),
      submittedBy: stString(map, const ['submitted_by']),
      submittedByName: stString(map, const ['submitted_by_name']),
      createdAt: stDate(map['created_at']),
    );
  }
}

class SubTenantBooking {
  const SubTenantBooking({
    required this.raw,
    required this.package,
    required this.tourist,
  });

  final Map<String, dynamic> raw;
  final SubTenantPackage? package;
  final Map<String, dynamic>? tourist;

  dynamic get id => raw['id'];
  dynamic get packageId => raw['package_id'];
  String get touristId => stString(raw, const ['tourist_id', 'user_id']);
  String get assignedDriverId => stString(raw, const ['assigned_driver_id']);
  String get status =>
      stString(raw, const ['status'], fallback: 'pending').toLowerCase();
  String get paymentMethod => stString(raw, const ['payment_method']);
  String get notes => stString(raw, const ['notes', 'special_requests']);
  DateTime? get travelDate => stDate(raw['travel_date'] ?? raw['date']);
  DateTime? get createdAt => stDate(raw['created_at']);
  int get adults => stInt(raw['adults'] ?? raw['adult_count'] ?? raw['pax']);
  double get totalAmount =>
      stDouble(raw['total_amount'] ?? raw['amount'] ?? raw['total']);

  String get touristName {
    if (tourist == null) return 'Tourist';
    return stString(tourist!, const [
      'full_name',
      'first_name',
      'email',
    ], fallback: 'Tourist');
  }

  String get touristMobile {
    if (tourist == null) return '';
    return stString(tourist!, const ['mobile', 'phone']);
  }

  String get packageTitle => package?.title ?? 'Tour package';
}

class SubTenantDriver {
  const SubTenantDriver({
    required this.profile,
    required this.details,
    required this.documents,
  });

  final Map<String, dynamic> profile;
  final Map<String, dynamic>? details;
  final Map<String, dynamic>? documents;

  String get id => stId(profile['id']);
  String get fullName =>
      stString(profile, const ['full_name', 'first_name'], fallback: 'Driver');
  String get mobile => stString(profile, const [
    'mobile',
  ], fallback: stString(details ?? const {}, const ['mobile']));
  String get address => stString(profile, const ['address']);
  String get barangay => stString(profile, const ['barangay']);
  String get city => stString(profile, const ['city']);
  bool get isOnline => profile['is_online'] == true;
  String get status => stString(details ?? profile, const [
    'status',
  ], fallback: 'pending').toLowerCase();
  String get licenseNumber =>
      stString(details ?? const {}, const ['license_number']);
  String get plateNumber =>
      stString(details ?? const {}, const ['plate_number']);
  String get todaName => stString(details ?? const {}, const ['toda_name']);
  String get operatorCode =>
      stString(details ?? const {}, const ['operator_code']);
  String get gcashNumber =>
      stString(details ?? const {}, const ['gcash_number']);
  String get gcashName => stString(details ?? const {}, const ['gcash_name']);
  String get gcashQrUrl =>
      stString(details ?? const {}, const ['gcash_qr_url']);
  bool get hasGcashDetails =>
      gcashQrUrl.isNotEmpty || (gcashNumber.isNotEmpty && gcashName.isNotEmpty);
  int get uploadedDocumentCount => documentLinks.length;
  int get requiredDocumentCount => 11;
  String get documentCompleteness =>
      '$uploadedDocumentCount/$requiredDocumentCount';
  double get averageRating => stDouble(profile['average_rating']);
  int get totalReviews => stInt(profile['total_reviews']);

  List<SubTenantDocumentLink> get documentLinks {
    final docs = documents;
    if (docs == null) return const [];
    const labels = {
      'selfie_url': 'Selfie',
      'license_front_url': 'License Front',
      'license_back_url': 'License Back',
      'police_clearance_url': 'Police Clearance',
      'mtop_url': 'MTOP',
      'vehicle_front_url': 'Vehicle Front',
      'vehicle_back_url': 'Vehicle Back',
      'vehicle_left_url': 'Vehicle Left',
      'vehicle_right_url': 'Vehicle Right',
      'or_url': 'OR',
      'cr_url': 'CR',
    };

    return labels.entries
        .map(
          (entry) => SubTenantDocumentLink(
            label: entry.value,
            url: stString(docs, [entry.key]),
          ),
        )
        .where((link) => link.url.isNotEmpty)
        .toList(growable: false);
  }
}

class SubTenantDocumentLink {
  const SubTenantDocumentLink({required this.label, required this.url});

  final String label;
  final String url;
}

class SubTenantDriverReview {
  const SubTenantDriverReview({
    required this.id,
    required this.bookingId,
    required this.driverId,
    required this.touristId,
    required this.touristName,
    required this.rating,
    required this.reviewText,
    this.createdAt,
  });

  final String id;
  final String bookingId;
  final String driverId;
  final String touristId;
  final String touristName;
  final int rating;
  final String reviewText;
  final DateTime? createdAt;
}

class SubTenantDashboardData {
  const SubTenantDashboardData({
    required this.profile,
    required this.totalSpots,
    required this.totalPackages,
    required this.totalDrivers,
    required this.pendingBookings,
    required this.activeTours,
    required this.recentBookings,
    required this.announcementsTableAvailable,
    required this.announcements,
    this.packageIds = const [],
  });

  final SubTenantProfile profile;
  final int totalSpots;
  final int totalPackages;
  final int totalDrivers;
  final int pendingBookings;
  final int activeTours;
  final List<SubTenantBooking> recentBookings;
  final bool announcementsTableAvailable;
  final List<SubTenantAnnouncement> announcements;
  final List<dynamic> packageIds;
}

class PackageItineraryDay {
  const PackageItineraryDay({
    required this.id,
    required this.dayNumber,
    required this.title,
    required this.items,
  });

  final dynamic id;
  final int dayNumber;
  final String title;
  final List<PackageItineraryItem> items;

  factory PackageItineraryDay.fromMap(
    Map<String, dynamic> map,
    List<PackageItineraryItem> items,
  ) {
    return PackageItineraryDay(
      id: map['id'],
      dayNumber: stInt(map['day_number']),
      title: stString(map, const ['title'], fallback: 'Day'),
      items: items,
    );
  }
}

class PackageItineraryItem {
  const PackageItineraryItem({
    required this.id,
    required this.dayId,
    required this.spotId,
    required this.spotTitle,
    required this.spotImageUrl,
    required this.timeLabel,
    required this.note,
    required this.sortOrder,
  });

  final dynamic id;
  final dynamic dayId;
  final dynamic spotId;
  final String spotTitle;
  final String spotImageUrl;
  final String timeLabel;
  final String note;
  final int sortOrder;

  factory PackageItineraryItem.fromMap(
    Map<String, dynamic> map,
    SubTenantSpot? spot,
  ) {
    return PackageItineraryItem(
      id: map['id'],
      dayId: map['day_id'],
      spotId: map['spot_id'],
      spotTitle: spot?.title ?? 'Tourist spot',
      spotImageUrl: spot?.imageUrl ?? '',
      timeLabel: stString(map, const ['time_label']),
      note: stString(map, const ['note']),
      sortOrder: stInt(map['sort_order']),
    );
  }
}

class SubTenantReportData {
  const SubTenantReportData({
    required this.rangeLabel,
    required this.totalSpots,
    required this.totalPackages,
    required this.totalBookings,
    required this.totalDrivers,
    required this.completedBookings,
    required this.cancelledBookings,
    required this.estimatedRevenue,
    required this.topPackages,
    required this.topSpots,
    required this.averageRating,
    required this.feedbackCount,
    this.bookings = const [],
    this.feedback = const [],
    this.allPackages = const [],
    this.allSpots = const [],
    this.allDrivers = const [],
  });

  final String rangeLabel;
  final int totalSpots;
  final int totalPackages;
  final int totalBookings;
  final int totalDrivers;
  final int completedBookings;
  final int cancelledBookings;
  final double estimatedRevenue;
  final List<SubTenantReportRow> topPackages;
  final List<SubTenantReportRow> topSpots;
  final double averageRating;
  final int feedbackCount;

  final List<SubTenantBooking> bookings;
  final List<SubTenantFeedback> feedback;
  final List<SubTenantPackage> allPackages;
  final List<SubTenantSpot> allSpots;
  final List<SubTenantDriver> allDrivers;
}

class SubTenantReportRange {
  const SubTenantReportRange({
    required this.label,
    required this.start,
    required this.end,
  });

  final String label;
  final DateTime start;
  final DateTime end;

  static SubTenantReportRange currentMonth() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month);
    final end = DateTime(
      now.year,
      now.month + 1,
    ).subtract(const Duration(milliseconds: 1));
    return SubTenantReportRange(label: 'Current Month', start: start, end: end);
  }

  static SubTenantReportRange weekly() {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final end = start
        .add(const Duration(days: 7))
        .subtract(const Duration(milliseconds: 1));
    return SubTenantReportRange(label: 'This Week', start: start, end: end);
  }

  static SubTenantReportRange yearly() {
    final now = DateTime.now();
    final start = DateTime(now.year);
    final end = DateTime(
      now.year + 1,
    ).subtract(const Duration(milliseconds: 1));
    return SubTenantReportRange(label: 'This Year', start: start, end: end);
  }

  static SubTenantReportRange custom(DateTime start, DateTime end) {
    return SubTenantReportRange(label: 'Custom Range', start: start, end: end);
  }

  bool contains(DateTime? value) {
    if (value == null) return false;
    return !value.isBefore(start) && !value.isAfter(end);
  }
}

class SubTenantReportRow {
  const SubTenantReportRow({
    required this.title,
    required this.value,
    this.subtitle = '',
  });

  final String title;
  final String subtitle;
  final String value;
}

class SubTenantFeedback {
  const SubTenantFeedback({
    required this.id,
    required this.rating,
    required this.comment,
    required this.touristName,
    required this.driverName,
    required this.relatedLabel,
    required this.createdAt,
  });

  final dynamic id;
  final double rating;
  final String comment;
  final String touristName;
  final String driverName;
  final String relatedLabel;
  final DateTime? createdAt;
}

class SubTenantAnnouncement {
  const SubTenantAnnouncement({
    required this.id,
    required this.title,
    required this.body,
    required this.status,
    required this.createdAt,
  });

  final dynamic id;
  final String title;
  final String body;
  final String status;
  final DateTime? createdAt;

  factory SubTenantAnnouncement.fromMap(Map<String, dynamic> map) {
    return SubTenantAnnouncement(
      id: map['id'],
      title: stString(map, const ['title']),
      body: stString(map, const ['body', 'description']),
      status: stString(map, const ['status'], fallback: 'draft').toLowerCase(),
      createdAt: stDate(map['created_at']),
    );
  }
}

class SubTenantAnnouncementsResult {
  const SubTenantAnnouncementsResult({
    required this.tableAvailable,
    required this.items,
  });

  final bool tableAvailable;
  final List<SubTenantAnnouncement> items;
}

class SubTenantCategory {
  const SubTenantCategory({
    required this.id,
    required this.name,
    this.iconUrl = '',
  });

  final dynamic id;
  final String name;
  final String iconUrl;

  factory SubTenantCategory.fromMap(Map<String, dynamic> map) {
    return SubTenantCategory(
      id: map['id'],
      name: stString(map, const ['name', 'title', 'label']),
      iconUrl: stString(map, const ['icon_url', 'image_url']),
    );
  }
}

class SelectedPackageSpot {
  SelectedPackageSpot({
    required this.spot,
    required this.sortOrder,
    this.openingTime = '',
    this.closingTime = '',
    this.estimatedArrivalTime = '',
    this.estimatedDurationMinutes = 0,
    this.recommendedVisitDurationMinutes = 0,
  });

  final SubTenantSpot spot;
  int sortOrder;
  String openingTime;
  String closingTime;
  String estimatedArrivalTime;
  int estimatedDurationMinutes;
  int recommendedVisitDurationMinutes;
}
