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
    required this.contactNumber,
    required this.email,
    required this.officeAddress,
    required this.coverImageUrl,
    required this.logoImageUrl,
    required this.detailsTableAvailable,
  });

  final String city;
  final String province;
  final String description;
  final String tourismOfficeName;
  final String contactNumber;
  final String email;
  final String officeAddress;
  final String coverImageUrl;
  final String logoImageUrl;
  final bool detailsTableAvailable;

  factory SubTenantCityProfileData.fromProfile(SubTenantProfile profile) {
    return SubTenantCityProfileData(
      city: profile.city,
      province: profile.province.isEmpty ? 'Bulacan' : profile.province,
      description: '',
      tourismOfficeName: profile.displayName,
      contactNumber: profile.mobile,
      email: profile.email,
      officeAddress: profile.address,
      coverImageUrl: '',
      logoImageUrl: profile.profileImageUrl,
      detailsTableAvailable: false,
    );
  }

  factory SubTenantCityProfileData.fromMap(
    Map<String, dynamic> map,
    SubTenantProfile profile,
  ) {
    return SubTenantCityProfileData(
      city: stString(map, const ['city'], fallback: profile.city),
      province: stString(map, const ['province'], fallback: profile.province),
      description: stString(map, const ['description']),
      tourismOfficeName: stString(map, const [
        'office_name',
        'name',
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
      detailsTableAvailable: true,
    );
  }

  SubTenantCityProfileData copyWith({
    String? city,
    String? province,
    String? description,
    String? tourismOfficeName,
    String? contactNumber,
    String? email,
    String? officeAddress,
    String? coverImageUrl,
    String? logoImageUrl,
    bool? detailsTableAvailable,
  }) {
    return SubTenantCityProfileData(
      city: city ?? this.city,
      province: province ?? this.province,
      description: description ?? this.description,
      tourismOfficeName: tourismOfficeName ?? this.tourismOfficeName,
      contactNumber: contactNumber ?? this.contactNumber,
      email: email ?? this.email,
      officeAddress: officeAddress ?? this.officeAddress,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      logoImageUrl: logoImageUrl ?? this.logoImageUrl,
      detailsTableAvailable:
          detailsTableAvailable ?? this.detailsTableAvailable,
    );
  }
}

class SubTenantSettingsData {
  const SubTenantSettingsData({
    this.notificationsEnabled = true,
    this.packageAlerts = true,
    this.touristSpotAlerts = true,
    this.performanceReports = true,
    this.systemNotices = true,
    this.language = 'English',
    this.showTotalViews = true,
    this.showBookings = true,
    this.showPopularDestinations = true,
    this.showTopPackages = true,
    this.defaultPackageVisibility = 'visible',
    this.defaultSpotStatus = 'active',
    this.requirePackageReview = true,
    this.allowMultiDayPackages = true,
    this.allowInstantBooking = false,
    this.manualBookingConfirmation = true,
    this.allowCancellation = true,
    this.driverAutoApproval = false,
    this.requireDriverDocuments = true,
    this.requireTodaVerification = true,
    this.requireSpotVerification = true,
    this.requireMapPin = true,
    this.requireCoverImage = true,
    this.autoPublishSpots = false,
    this.enableAiSuggestions = true,
    this.diversePlaceTypes = true,
    this.prioritizePopular = true,
    this.prioritizeNearby = true,
    this.prioritizeFood = true,
    this.prioritizeNature = true,
    this.prioritizeHistorical = true,
    this.bookingNotifications = true,
    this.driverNotifications = true,
    this.reviewNotifications = true,
    this.emailNotifications = true,
    this.revenueTracking = true,
    this.spotPopularityTracking = true,
    this.driverAnalytics = true,
    this.monthlyReports = true,
  });

  final bool notificationsEnabled;
  final bool packageAlerts;
  final bool touristSpotAlerts;
  final bool performanceReports;
  final bool systemNotices;
  final String language;
  final bool showTotalViews;
  final bool showBookings;
  final bool showPopularDestinations;
  final bool showTopPackages;
  final String defaultPackageVisibility;
  final String defaultSpotStatus;
  final bool requirePackageReview;
  final bool allowMultiDayPackages;
  final bool allowInstantBooking;
  final bool manualBookingConfirmation;
  final bool allowCancellation;
  final bool driverAutoApproval;
  final bool requireDriverDocuments;
  final bool requireTodaVerification;
  final bool requireSpotVerification;
  final bool requireMapPin;
  final bool requireCoverImage;
  final bool autoPublishSpots;
  final bool enableAiSuggestions;
  final bool diversePlaceTypes;
  final bool prioritizePopular;
  final bool prioritizeNearby;
  final bool prioritizeFood;
  final bool prioritizeNature;
  final bool prioritizeHistorical;
  final bool bookingNotifications;
  final bool driverNotifications;
  final bool reviewNotifications;
  final bool emailNotifications;
  final bool revenueTracking;
  final bool spotPopularityTracking;
  final bool driverAnalytics;
  final bool monthlyReports;

  factory SubTenantSettingsData.fromMap(Map<String, dynamic> map) {
    const defaults = SubTenantSettingsData();
    return SubTenantSettingsData(
      notificationsEnabled: _stBool(
        map['notifications_enabled'],
        fallback: defaults.notificationsEnabled,
      ),
      packageAlerts: _stBool(
        map['package_alerts'],
        fallback: defaults.packageAlerts,
      ),
      touristSpotAlerts: _stBool(
        map['tourist_spot_alerts'],
        fallback: defaults.touristSpotAlerts,
      ),
      performanceReports: _stBool(
        map['performance_reports'],
        fallback: defaults.performanceReports,
      ),
      systemNotices: _stBool(
        map['system_notices'],
        fallback: defaults.systemNotices,
      ),
      language: stString(map, const ['language'], fallback: defaults.language),
      showTotalViews: _stBool(
        map['show_total_views'],
        fallback: defaults.showTotalViews,
      ),
      showBookings: _stBool(
        map['show_bookings'],
        fallback: defaults.showBookings,
      ),
      showPopularDestinations: _stBool(
        map['show_popular_destinations'],
        fallback: defaults.showPopularDestinations,
      ),
      showTopPackages: _stBool(
        map['show_top_packages'],
        fallback: defaults.showTopPackages,
      ),
      defaultPackageVisibility: stString(map, const [
        'default_package_visibility',
      ], fallback: defaults.defaultPackageVisibility),
      defaultSpotStatus: stString(map, const [
        'default_spot_status',
      ], fallback: defaults.defaultSpotStatus),
      requirePackageReview: _stBool(
        map['require_package_review'],
        fallback: defaults.requirePackageReview,
      ),
      allowMultiDayPackages: _stBool(
        map['allow_multi_day_packages'],
        fallback: defaults.allowMultiDayPackages,
      ),
      allowInstantBooking: _stBool(
        map['allow_instant_booking'],
        fallback: defaults.allowInstantBooking,
      ),
      manualBookingConfirmation: _stBool(
        map['manual_booking_confirmation'],
        fallback: defaults.manualBookingConfirmation,
      ),
      allowCancellation: _stBool(
        map['allow_cancellation'],
        fallback: defaults.allowCancellation,
      ),
      driverAutoApproval: _stBool(
        map['driver_auto_approval'],
        fallback: defaults.driverAutoApproval,
      ),
      requireDriverDocuments: _stBool(
        map['require_driver_documents'],
        fallback: defaults.requireDriverDocuments,
      ),
      requireTodaVerification: _stBool(
        map['require_toda_verification'],
        fallback: defaults.requireTodaVerification,
      ),
      requireSpotVerification: _stBool(
        map['require_spot_verification'],
        fallback: defaults.requireSpotVerification,
      ),
      requireMapPin: _stBool(
        map['require_map_pin'],
        fallback: defaults.requireMapPin,
      ),
      requireCoverImage: _stBool(
        map['require_cover_image'],
        fallback: defaults.requireCoverImage,
      ),
      autoPublishSpots: _stBool(
        map['auto_publish_spots'],
        fallback: defaults.autoPublishSpots,
      ),
      enableAiSuggestions: _stBool(
        map['enable_ai_suggestions'],
        fallback: defaults.enableAiSuggestions,
      ),
      diversePlaceTypes: _stBool(
        map['diverse_place_types'],
        fallback: defaults.diversePlaceTypes,
      ),
      prioritizePopular: _stBool(
        map['prioritize_popular'],
        fallback: defaults.prioritizePopular,
      ),
      prioritizeNearby: _stBool(
        map['prioritize_nearby'],
        fallback: defaults.prioritizeNearby,
      ),
      prioritizeFood: _stBool(
        map['prioritize_food'],
        fallback: defaults.prioritizeFood,
      ),
      prioritizeNature: _stBool(
        map['prioritize_nature'],
        fallback: defaults.prioritizeNature,
      ),
      prioritizeHistorical: _stBool(
        map['prioritize_historical'],
        fallback: defaults.prioritizeHistorical,
      ),
      bookingNotifications: _stBool(
        map['booking_notifications'],
        fallback: _stBool(
          map['package_alerts'],
          fallback: defaults.bookingNotifications,
        ),
      ),
      driverNotifications: _stBool(
        map['driver_notifications'],
        fallback: defaults.driverNotifications,
      ),
      reviewNotifications: _stBool(
        map['review_notifications'],
        fallback: _stBool(
          map['tourist_spot_alerts'],
          fallback: defaults.reviewNotifications,
        ),
      ),
      emailNotifications: _stBool(
        map['email_notifications'],
        fallback: defaults.emailNotifications,
      ),
      revenueTracking: _stBool(
        map['revenue_tracking'],
        fallback: defaults.revenueTracking,
      ),
      spotPopularityTracking: _stBool(
        map['spot_popularity_tracking'],
        fallback: defaults.spotPopularityTracking,
      ),
      driverAnalytics: _stBool(
        map['driver_analytics'],
        fallback: defaults.driverAnalytics,
      ),
      monthlyReports: _stBool(
        map['monthly_reports'],
        fallback: _stBool(
          map['performance_reports'],
          fallback: defaults.monthlyReports,
        ),
      ),
    );
  }

  Map<String, dynamic> toMap(String userId) {
    return {
      'user_id': userId,
      'notifications_enabled': notificationsEnabled,
      'package_alerts': packageAlerts,
      'tourist_spot_alerts': touristSpotAlerts,
      'performance_reports': performanceReports,
      'system_notices': systemNotices,
      'language': language,
      'show_total_views': showTotalViews,
      'show_bookings': showBookings,
      'show_popular_destinations': showPopularDestinations,
      'show_top_packages': showTopPackages,
      'default_package_visibility': defaultPackageVisibility,
      'default_spot_status': defaultSpotStatus,
      'require_package_review': requirePackageReview,
      'allow_multi_day_packages': allowMultiDayPackages,
      'allow_instant_booking': allowInstantBooking,
      'manual_booking_confirmation': manualBookingConfirmation,
      'allow_cancellation': allowCancellation,
      'driver_auto_approval': driverAutoApproval,
      'require_driver_documents': requireDriverDocuments,
      'require_toda_verification': requireTodaVerification,
      'require_spot_verification': requireSpotVerification,
      'require_map_pin': requireMapPin,
      'require_cover_image': requireCoverImage,
      'auto_publish_spots': autoPublishSpots,
      'enable_ai_suggestions': enableAiSuggestions,
      'diverse_place_types': diversePlaceTypes,
      'prioritize_popular': prioritizePopular,
      'prioritize_nearby': prioritizeNearby,
      'prioritize_food': prioritizeFood,
      'prioritize_nature': prioritizeNature,
      'prioritize_historical': prioritizeHistorical,
      'booking_notifications': bookingNotifications,
      'driver_notifications': driverNotifications,
      'review_notifications': reviewNotifications,
      'email_notifications': emailNotifications,
      'revenue_tracking': revenueTracking,
      'spot_popularity_tracking': spotPopularityTracking,
      'driver_analytics': driverAnalytics,
      'monthly_reports': monthlyReports,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
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
    this.additionalPassengerFee = 0,
    this.waitingFee = 0,
    this.guideFee = 0,
    this.weekendSurcharge = 0,
    this.isActive = true,
  });

  final dynamic id;
  final String subtenantId;
  final String city;
  final double baseFare;
  final double farePerKm;
  final double minimumFare;
  final double additionalPassengerFee;
  final double waitingFee;
  final double guideFee;
  final double weekendSurcharge;
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
      additionalPassengerFee: stDouble(
        map['additional_passenger_fee'],
        fallback: defaults.additionalPassengerFee,
      ),
      waitingFee: stDouble(map['waiting_fee'], fallback: defaults.waitingFee),
      guideFee: stDouble(map['guide_fee'], fallback: defaults.guideFee),
      weekendSurcharge: stDouble(
        map['weekend_surcharge'],
        fallback: defaults.weekendSurcharge,
      ),
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
      'additional_passenger_fee': additionalPassengerFee,
      'waiting_fee': waitingFee,
      'guide_fee': guideFee,
      'weekend_surcharge': weekendSurcharge,
      'is_active': isActive,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    };
  }

  FareCalculation calculate({
    required double routeDistanceKm,
    required int groupSize,
    bool includeWeekendSurcharge = false,
  }) {
    final normalizedGroupSize = groupSize < 1 ? 1 : groupSize;
    final normalizedDistance = routeDistanceKm < 0 ? 0.0 : routeDistanceKm;
    final extraPassengers = normalizedGroupSize > 1
        ? normalizedGroupSize - 1
        : 0;
    final distanceFee = farePerKm * normalizedDistance;
    final passengerFee = additionalPassengerFee * extraPassengers;
    final surcharge = includeWeekendSurcharge ? weekendSurcharge : 0.0;
    final rawTotal =
        baseFare +
        distanceFee +
        passengerFee +
        waitingFee +
        guideFee +
        surcharge;
    final total = minimumFare > 0 && rawTotal < minimumFare
        ? minimumFare
        : rawTotal;
    return FareCalculation(
      baseFare: baseFare,
      distanceFee: distanceFee,
      passengerFee: passengerFee,
      waitingFee: waitingFee,
      guideFee: guideFee,
      weekendSurcharge: surcharge,
      minimumFareAdjustment: total - rawTotal,
      total: total,
    );
  }
}

class FareCalculation {
  const FareCalculation({
    required this.baseFare,
    required this.distanceFee,
    required this.passengerFee,
    required this.waitingFee,
    required this.guideFee,
    required this.weekendSurcharge,
    required this.minimumFareAdjustment,
    required this.total,
  });

  final double baseFare;
  final double distanceFee;
  final double passengerFee;
  final double waitingFee;
  final double guideFee;
  final double weekendSurcharge;
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
  int get uploadedDocumentCount => documentLinks.length;
  int get requiredDocumentCount => 11;
  String get documentCompleteness =>
      '$uploadedDocumentCount/$requiredDocumentCount';

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
