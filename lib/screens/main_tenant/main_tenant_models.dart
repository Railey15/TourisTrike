import 'package:flutter/material.dart';
import 'package:touristrike/core/auth/app_role.dart';

String mainTenantString(
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

int mainTenantInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().replaceAll(',', '').trim()) ?? fallback;
}

double mainTenantDouble(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '').trim()) ??
      fallback;
}

DateTime? mainTenantDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

String mainTenantId(dynamic value) => value?.toString() ?? '';

String mainTenantTitleCase(String value) {
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

Color mainTenantStatusColor(String status) {
  switch (status.toLowerCase().trim()) {
    case 'active':
    case 'approved':
    case 'verified':
    case 'published':
    case 'visible':
    case 'completed':
    case 'confirmed':
      return const Color(0xFF16A34A);
    case 'pending':
    case 'draft':
    case 'review':
    case 'submitted':
    case 'maintenance':
      return const Color(0xFFF59E0B);
    case 'inactive':
    case 'disabled':
    case 'deactivated':
    case 'rejected':
    case 'returned':
    case 'cancelled':
    case 'archived':
    case 'hidden':
    case 'flagged':
    case 'suspended':
      return const Color(0xFFDC2626);
    case 'sold_out':
      return const Color(0xFF7C3AED);
    default:
      return const Color(0xFF64748B);
  }
}

class MainTenantProfile {
  const MainTenantProfile({
    required this.id,
    required this.role,
    required this.fullName,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.mobile,
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
  final String city;
  final String province;
  final String profileImageUrl;
  final Map<String, dynamic> raw;

  factory MainTenantProfile.fromMap(
    Map<String, dynamic> map, {
    String email = '',
  }) {
    return MainTenantProfile(
      id: mainTenantId(map['id']),
      role: mainTenantString(map, const ['role']),
      fullName: mainTenantString(map, const ['full_name']),
      firstName: mainTenantString(map, const ['first_name']),
      lastName: mainTenantString(map, const ['last_name']),
      email: mainTenantString(map, const ['email'], fallback: email),
      mobile: mainTenantString(map, const ['mobile', 'contact_number']),
      city: mainTenantString(map, const ['city']),
      province: mainTenantString(map, const ['province'], fallback: 'Bulacan'),
      profileImageUrl: mainTenantString(map, const [
        'profile_image_url',
        'avatar_url',
      ]),
      raw: map,
    );
  }

  bool get isMainTenant => AppRole.tryParse(role) == AppRole.mainTenant;

  String get displayName {
    if (fullName.isNotEmpty) return fullName;
    final name = [
      firstName,
      lastName,
    ].where((value) => value.trim().isNotEmpty).join(' ');
    if (name.trim().isNotEmpty) return name.trim();
    return 'Bulacan Provincial Tourism Office';
  }
}

class ProvincialOfficeSettings {
  const ProvincialOfficeSettings({
    required this.officeName,
    required this.officeAddress,
    required this.contactPerson,
    required this.contactNumber,
    required this.officialEmail,
    required this.displayName,
    required this.logoUrl,
    required this.coverImageUrl,
  });

  final String officeName;
  final String officeAddress;
  final String contactPerson;
  final String contactNumber;
  final String officialEmail;
  final String displayName;
  final String logoUrl;
  final String coverImageUrl;

  factory ProvincialOfficeSettings.fromMap(
    Map<String, dynamic> map,
    MainTenantProfile profile,
  ) {
    final defaultOfficeName = profile.province.trim().isEmpty
        ? 'Provincial Tourism Office'
        : 'Provincial Tourism Office of ${profile.province.trim()}';
    final officeName = mainTenantString(map, const [
      'office_name',
    ], fallback: defaultOfficeName);
    return ProvincialOfficeSettings(
      officeName: officeName,
      officeAddress: mainTenantString(map, const [
        'office_address',
      ], fallback: mainTenantString(profile.raw, const ['address'])),
      contactPerson: mainTenantString(map, const [
        'contact_person',
      ], fallback: profile.displayName),
      contactNumber: mainTenantString(map, const [
        'contact_number',
      ], fallback: profile.mobile),
      officialEmail: mainTenantString(map, const [
        'official_email',
      ], fallback: profile.email),
      displayName: mainTenantString(map, const [
        'display_name',
      ], fallback: officeName),
      logoUrl: mainTenantString(map, const ['logo_url']),
      coverImageUrl: mainTenantString(map, const ['cover_image_url']),
    );
  }
}

class ProvincialBookingPolicySettings {
  const ProvincialBookingPolicySettings({
    required this.freeCancellationHours,
    required this.termsAndConditions,
    required this.cancellationPolicy,
    required this.dataPrivacyNotice,
    this.termsPolicyId,
    this.cancellationPolicyId,
    this.privacyPolicyId,
  });

  final int freeCancellationHours;
  final String termsAndConditions;
  final String cancellationPolicy;
  final String dataPrivacyNotice;
  final dynamic termsPolicyId;
  final dynamic cancellationPolicyId;
  final dynamic privacyPolicyId;
}

class ProvincialNotificationPreferences {
  const ProvincialNotificationPreferences({
    required this.cityApplications,
    required this.driverStatusUpdates,
    required this.bookingIssues,
    required this.paymentDisputes,
  });

  final bool cityApplications;
  final bool driverStatusUpdates;
  final bool bookingIssues;
  final bool paymentDisputes;

  factory ProvincialNotificationPreferences.fromMap(Map<String, dynamic> map) {
    bool read(String key) => map[key] is bool ? map[key] as bool : true;
    return ProvincialNotificationPreferences(
      cityApplications: read('city_application_notifications'),
      driverStatusUpdates: read('driver_status_notifications'),
      bookingIssues: read('booking_issue_notifications'),
      paymentDisputes: read('payment_dispute_notifications'),
    );
  }
}

class MainTenantSettingsData {
  const MainTenantSettingsData({
    required this.profile,
    required this.office,
    required this.bookingPolicies,
    required this.notifications,
  });

  final MainTenantProfile profile;
  final ProvincialOfficeSettings office;
  final ProvincialBookingPolicySettings bookingPolicies;
  final ProvincialNotificationPreferences notifications;
}

class CityTenant {
  const CityTenant({
    required this.id,
    required this.city,
    required this.province,
    required this.adminName,
    required this.email,
    required this.mobile,
    required this.address,
    required this.status,
    required this.createdAt,
    required this.spotsCount,
    required this.packagesCount,
    required this.bookingsCount,
    required this.driversCount,
    required this.verified,
    required this.localGovernmentType,
    required this.localGovernmentTypeReviewed,
    required this.raw,
  });

  final String id;
  final String city;
  final String province;
  final String adminName;
  final String email;
  final String mobile;
  final String address;
  final String status;
  final DateTime? createdAt;
  final int spotsCount;
  final int packagesCount;
  final int bookingsCount;
  final int driversCount;
  final bool verified;
  final String localGovernmentType;
  final bool localGovernmentTypeReviewed;
  final Map<String, dynamic> raw;

  factory CityTenant.fromProfile(
    Map<String, dynamic> map, {
    int spotsCount = 0,
    int packagesCount = 0,
    int bookingsCount = 0,
    int driversCount = 0,
  }) {
    final city = mainTenantString(map, const ['city', 'assigned_city']);
    final firstName = mainTenantString(map, const ['first_name']);
    final lastName = mainTenantString(map, const ['last_name']);
    final generatedName = [
      firstName,
      lastName,
    ].where((value) => value.isNotEmpty).join(' ');
    final detailsStatus = mainTenantString(map, const ['verification_status']);
    final active = map['is_active'];
    final status = active is bool
        ? (active ? 'active' : 'inactive')
        : mainTenantString(map, const [
            'status',
            'account_status',
            'tenant_status',
          ], fallback: detailsStatus.isEmpty ? 'active' : detailsStatus);
    return CityTenant(
      id: mainTenantId(map['id']),
      city: city.isEmpty ? 'Unassigned City' : city,
      province: mainTenantString(map, const ['province'], fallback: 'Bulacan'),
      adminName: mainTenantString(map, const [
        'full_name',
        'contact_person',
        'office_name',
        'name',
      ], fallback: generatedName.isEmpty ? 'Subtenant Admin' : generatedName),
      email: mainTenantString(map, const ['email', 'contact_email', 'office_email']),
      mobile: mainTenantString(map, const ['mobile', 'contact_number']),
      address: mainTenantString(map, const ['address', 'office_address']),
      status: status,
      createdAt: mainTenantDate(map['created_at']),
      spotsCount: spotsCount,
      packagesCount: packagesCount,
      bookingsCount: bookingsCount,
      driversCount: driversCount,
      verified:
          map['verified'] == true ||
          map['is_verified'] == true ||
          detailsStatus == 'approved' ||
          detailsStatus == 'verified',
      localGovernmentType: mainTenantString(map, const [
        'local_government_type',
      ], fallback: 'municipality'),
      localGovernmentTypeReviewed:
          map['local_government_type_reviewed'] == true,
      raw: map,
    );
  }

  CityTenant copyWith({
    int? spotsCount,
    int? packagesCount,
    int? bookingsCount,
    int? driversCount,
    String? status,
  }) {
    return CityTenant(
      id: id,
      city: city,
      province: province,
      adminName: adminName,
      email: email,
      mobile: mobile,
      address: address,
      status: status ?? this.status,
      createdAt: createdAt,
      spotsCount: spotsCount ?? this.spotsCount,
      packagesCount: packagesCount ?? this.packagesCount,
      bookingsCount: bookingsCount ?? this.bookingsCount,
      driversCount: driversCount ?? this.driversCount,
      verified: verified,
      localGovernmentType: localGovernmentType,
      localGovernmentTypeReviewed: localGovernmentTypeReviewed,
      raw: raw,
    );
  }
}

enum MainTenantSearchResultType { tenant, spot, package, driver, booking }

class MainTenantSearchResult {
  const MainTenantSearchResult({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    required this.raw,
  });

  final MainTenantSearchResultType type;
  final String id;
  final String title;
  final String subtitle;
  final Map<String, dynamic> raw;
}

class MainTenantNotification {
  const MainTenantNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.type,
    required this.isRead,
    required this.createdAt,
  });

  final dynamic id;
  final String title;
  final String body;
  final String type;
  final bool isRead;
  final DateTime? createdAt;

  factory MainTenantNotification.fromMap(Map<String, dynamic> map) {
    return MainTenantNotification(
      id: map['id'],
      title: mainTenantString(map, const ['title'], fallback: 'Notification'),
      body: mainTenantString(map, const ['body']),
      type: mainTenantString(map, const ['type']),
      isRead: map['is_read'] == true,
      createdAt: mainTenantDate(map['created_at']),
    );
  }

  MainTenantNotification copyWith({bool? isRead}) {
    return MainTenantNotification(
      id: id,
      title: title,
      body: body,
      type: type,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}

class ProvincePackage {
  const ProvincePackage({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.description,
    required this.city,
    required this.status,
    required this.visibilityStatus,
    required this.priceText,
    required this.durationText,
    required this.imageUrl,
    required this.createdAt,
    required this.estimatedBudget,
    required this.bookingsCount,
    required this.revenue,
    required this.raw,
  });

  final dynamic id;
  final String title;
  final String subtitle;
  final String description;
  final String city;
  final String status;
  final String visibilityStatus;
  final String priceText;
  final String durationText;
  final String imageUrl;
  final DateTime? createdAt;
  final double estimatedBudget;
  final int bookingsCount;
  final double revenue;
  final Map<String, dynamic> raw;

  factory ProvincePackage.fromMap(
    Map<String, dynamic> map, {
    int bookingsCount = 0,
    double revenue = 0,
  }) {
    return ProvincePackage(
      id: map['id'],
      title: mainTenantString(map, const ['title', 'name'], fallback: 'Untitled'),
      subtitle: mainTenantString(map, const ['subtitle', 'tagline']),
      description: mainTenantString(map, const ['description', 'details']),
      city: mainTenantString(map, const ['city'], fallback: 'Unassigned'),
      status: mainTenantString(map, const ['status'], fallback: 'draft'),
      visibilityStatus: mainTenantString(map, const [
        'visibility_status',
        'visibility',
      ], fallback: 'visible'),
      priceText: mainTenantString(map, const ['price_text', 'price']),
      durationText: mainTenantString(map, const ['duration_text', 'duration']),
      imageUrl: mainTenantString(map, const ['cover_image_url', 'image_url']),
      createdAt: mainTenantDate(map['created_at']),
      estimatedBudget: mainTenantDouble(map['estimated_budget']),
      bookingsCount: bookingsCount,
      revenue: revenue,
      raw: map,
    );
  }
}

class ProvinceSpot {
  const ProvinceSpot({
    required this.id,
    required this.title,
    required this.description,
    required this.city,
    required this.barangay,
    required this.status,
    required this.verificationStatus,
    required this.rating,
    required this.imageUrl,
    required this.createdAt,
    required this.raw,
  });

  final dynamic id;
  final String title;
  final String description;
  final String city;
  final String barangay;
  final String status;
  final String verificationStatus;
  final double rating;
  final String imageUrl;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  factory ProvinceSpot.fromMap(Map<String, dynamic> map) {
    return ProvinceSpot(
      id: map['id'],
      title: mainTenantString(map, const ['title', 'name'], fallback: 'Untitled'),
      description: mainTenantString(map, const ['description']),
      city: mainTenantString(map, const ['city'], fallback: 'Unassigned'),
      barangay: mainTenantString(map, const ['barangay']),
      status: mainTenantString(map, const ['status'], fallback: 'active'),
      verificationStatus: mainTenantString(map, const [
        'verification_status',
      ], fallback: map['verified_at'] != null ? 'verified' : 'unverified'),
      rating: mainTenantDouble(map['rating']),
      imageUrl: mainTenantString(map, const ['image_url', 'cover_image_url']),
      createdAt: mainTenantDate(map['created_at']),
      raw: map,
    );
  }
}

class ProvinceBooking {
  const ProvinceBooking({
    required this.id,
    required this.packageId,
    required this.packageTitle,
    required this.city,
    required this.touristName,
    required this.status,
    required this.totalAmount,
    required this.travelDate,
    required this.createdAt,
    required this.raw,
  });

  final dynamic id;
  final dynamic packageId;
  final String packageTitle;
  final String city;
  final String touristName;
  final String status;
  final double totalAmount;
  final DateTime? travelDate;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  factory ProvinceBooking.fromMap(
    Map<String, dynamic> map, {
    ProvincePackage? package,
  }) {
    final nestedPackage = map['tour_packages'];
    final nested = nestedPackage is Map
        ? Map<String, dynamic>.from(nestedPackage)
        : null;
    return ProvinceBooking(
      id: map['id'],
      packageId: map['package_id'] ?? package?.id,
      packageTitle:
          package?.title ??
          mainTenantString(nested ?? const {}, const ['title'], fallback: 'Package'),
      city:
          package?.city ??
          mainTenantString(nested ?? const {}, const ['city'], fallback: 'Unknown'),
      touristName: mainTenantString(map, const [
        'tourist_name',
        'full_name',
        'customer_name',
      ], fallback: 'Tourist'),
      status: mainTenantString(map, const ['status'], fallback: 'pending'),
      totalAmount: mainTenantDouble(map['total_amount']),
      travelDate: mainTenantDate(map['travel_date']),
      createdAt: mainTenantDate(map['created_at']),
      raw: map,
    );
  }
}

class ProvinceFeedback {
  const ProvinceFeedback({
    required this.id,
    required this.source,
    required this.city,
    required this.rating,
    required this.comment,
    required this.reviewerName,
    required this.subjectName,
    required this.createdAt,
    required this.raw,
  });

  final dynamic id;
  final String source;
  final String city;
  final double rating;
  final String comment;
  final String reviewerName;
  final String subjectName;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  factory ProvinceFeedback.fromMap(
    Map<String, dynamic> map, {
    String source = 'ride_reviews',
    String city = 'Unknown',
  }) {
    return ProvinceFeedback(
      id: map['id'],
      source: source,
      city: mainTenantString(map, const ['city'], fallback: city),
      rating: mainTenantDouble(map['rating'], fallback: mainTenantDouble(map['score'])),
      comment: mainTenantString(map, const [
        'comment',
        'review_text',
        'feedback',
        'message',
        'body',
        'content',
      ]),
      reviewerName: mainTenantString(map, const [
        'tourist_name',
        'reviewer',
        'reviewer_name',
        'customer_name',
        'user_name',
      ], fallback: 'Tourist'),
      subjectName: mainTenantString(map, const [
        'driver_name',
        'subject_name',
        'package_title',
        'spot_title',
        'related_title',
      ], fallback: 'Transport service'),
      createdAt: mainTenantDate(map['created_at']),
      raw: map,
    );
  }
}

class CityRegistration {
  const CityRegistration({
    required this.id,
    required this.userId,
    required this.city,
    required this.officeName,
    required this.contactPerson,
    required this.contactNumber,
    required this.email,
    required this.address,
    required this.status,
    required this.submittedAt,
    required this.reviewedAt,
    required this.reviewedBy,
    required this.rejectionReason,
    required this.raw,
  });

  final dynamic id;
  final String userId;
  final String city;
  final String officeName;
  final String contactPerson;
  final String contactNumber;
  final String email;
  final String address;
  final String status;
  final DateTime? submittedAt;
  final DateTime? reviewedAt;
  final String reviewedBy;
  final String rejectionReason;
  final Map<String, dynamic> raw;

  factory CityRegistration.fromMap(Map<String, dynamic> map) {
    return CityRegistration(
      id: map['id'],
      userId: mainTenantId(map['user_id']),
      city: mainTenantString(map, const ['city'], fallback: 'Unassigned'),
      officeName: mainTenantString(map, const ['office_name']),
      contactPerson: mainTenantString(map, const ['contact_person']),
      contactNumber: mainTenantString(map, const ['contact_number', 'mobile']),
      email: mainTenantString(map, const ['email']),
      address: mainTenantString(map, const ['office_address', 'address']),
      status: mainTenantString(map, const [
        'status',
      ], fallback: 'pending').toLowerCase(),
      submittedAt: mainTenantDate(map['submitted_at'] ?? map['created_at']),
      reviewedAt: mainTenantDate(map['reviewed_at']),
      reviewedBy: mainTenantId(map['reviewed_by']),
      rejectionReason: mainTenantString(map, const ['rejection_reason']),
      raw: map,
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

class MainTenantPolicy {
  const MainTenantPolicy({
    required this.id,
    required this.title,
    required this.content,
    required this.status,
    required this.createdAt,
    required this.raw,
  });

  final dynamic id;
  final String title;
  final String content;
  final String status;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  factory MainTenantPolicy.fromMap(Map<String, dynamic> map) {
    return MainTenantPolicy(
      id: map['id'],
      title: mainTenantString(map, const ['title'], fallback: 'Untitled Policy'),
      content: mainTenantString(map, const ['content', 'body', 'description']),
      status: mainTenantString(map, const ['status'], fallback: 'draft'),
      createdAt: mainTenantDate(map['created_at']),
      raw: map,
    );
  }
}

class MainTenantCategory {
  const MainTenantCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.status,
    required this.createdAt,
    required this.raw,
  });

  final dynamic id;
  final String name;
  final String description;
  final String icon;
  final String status;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

  factory MainTenantCategory.fromMap(Map<String, dynamic> map) {
    return MainTenantCategory(
      id: map['id'],
      name: mainTenantString(map, const ['name'], fallback: 'Unnamed Category'),
      description: mainTenantString(map, const ['description']),
      icon: mainTenantString(map, const ['icon']),
      status: mainTenantString(map, const ['status'], fallback: 'active'),
      createdAt: mainTenantDate(map['created_at']),
      raw: map,
    );
  }
}

class TableResult<T> {
  const TableResult({required this.available, required this.items});

  final bool available;
  final List<T> items;
}

class CityMetricRow {
  const CityMetricRow({
    required this.city,
    required this.value,
    this.subtitle = '',
    this.amount = 0,
  });

  final String city;
  final int value;
  final String subtitle;
  final double amount;
}

class MainTenantDashboardData {
  const MainTenantDashboardData({
    required this.profile,
    required this.tenants,
    required this.packages,
    required this.spots,
    required this.bookings,
    required this.feedback,
    required this.registrations,
    required this.registrationsTableAvailable,
  });

  final MainTenantProfile profile;
  final List<CityTenant> tenants;
  final List<ProvincePackage> packages;
  final List<ProvinceSpot> spots;
  final List<ProvinceBooking> bookings;
  final List<ProvinceFeedback> feedback;
  final List<CityRegistration> registrations;
  final bool registrationsTableAvailable;

  int get activeCities => tenants.where((tenant) {
    final status = tenant.status.toLowerCase();
    return status == 'active' || status == 'approved' || status == 'verified';
  }).length;

  int get pendingRegistrations => registrations
      .where((item) => item.status.toLowerCase() == 'pending')
      .length;

  double get totalRevenue => bookings.fold<double>(
    0,
    (sum, booking) => booking.status.toLowerCase() == 'completed'
        ? sum + booking.totalAmount
        : sum,
  );

  List<CityMetricRow> get bookingsByCity {
    final counts = <String, int>{};
    for (final booking in bookings) {
      counts.update(booking.city, (value) => value + 1, ifAbsent: () => 1);
    }
    final rows = counts.entries
        .map((entry) => CityMetricRow(city: entry.key, value: entry.value))
        .toList();
    rows.sort((a, b) => b.value.compareTo(a.value));
    return rows;
  }

  List<ProvincePackage> get topPackages {
    final rows = [...packages];
    rows.sort((a, b) => b.bookingsCount.compareTo(a.bookingsCount));
    return rows.take(5).toList(growable: false);
  }
}

class MainTenantReportData {
  const MainTenantReportData({
    required this.tenants,
    required this.packages,
    required this.spots,
    required this.bookings,
    required this.feedback,
  });

  final List<CityTenant> tenants;
  final List<ProvincePackage> packages;
  final List<ProvinceSpot> spots;
  final List<ProvinceBooking> bookings;
  final List<ProvinceFeedback> feedback;

  int get completedTours =>
      bookings.where((item) => item.status.toLowerCase() == 'completed').length;

  int get cancelledBookings =>
      bookings.where((item) => item.status.toLowerCase() == 'cancelled').length;
}

class RevenueSummaryData {
  const RevenueSummaryData({required this.packages, required this.bookings});

  final List<ProvincePackage> packages;
  final List<ProvinceBooking> bookings;

  double get completedRevenue => bookings.fold<double>(
    0,
    (sum, booking) => booking.status.toLowerCase() == 'completed'
        ? sum + booking.totalAmount
        : sum,
  );

  double get pendingValue => bookings.fold<double>(
    0,
    (sum, booking) => booking.status.toLowerCase() == 'pending'
        ? sum + booking.totalAmount
        : sum,
  );
}

class FeedbackTrendData {
  const FeedbackTrendData({required this.feedback});

  final List<ProvinceFeedback> feedback;

  double get averageRating {
    final rated = feedback.where((item) => item.rating > 0).toList();
    if (rated.isEmpty) return 0;
    return rated.fold<double>(0, (sum, item) => sum + item.rating) /
        rated.length;
  }

  List<ProvinceFeedback> get lowRated {
    final rows = feedback.where((item) => item.rating > 0 && item.rating < 3);
    return rows.take(10).toList(growable: false);
  }
}
