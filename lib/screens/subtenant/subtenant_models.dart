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
    required this.totalSpots,
    required this.totalPackages,
    required this.totalBookings,
    required this.completedBookings,
    required this.cancelledBookings,
    required this.estimatedRevenue,
    required this.topPackages,
    required this.topSpots,
    required this.averageRating,
    required this.feedbackCount,
  });

  final int totalSpots;
  final int totalPackages;
  final int totalBookings;
  final int completedBookings;
  final int cancelledBookings;
  final double estimatedRevenue;
  final List<SubTenantReportRow> topPackages;
  final List<SubTenantReportRow> topSpots;
  final double averageRating;
  final int feedbackCount;
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
