import 'package:flutter/material.dart';

String adminString(
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

int adminInt(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString().replaceAll(',', '').trim()) ?? fallback;
}

double adminDouble(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '').trim()) ??
      fallback;
}

DateTime? adminDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

String adminId(dynamic value) => value?.toString() ?? '';

String adminTitleCase(String value) {
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

Color adminStatusColor(String status) {
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

class ProvincialAdminProfile {
  const ProvincialAdminProfile({
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

  factory ProvincialAdminProfile.fromMap(
    Map<String, dynamic> map, {
    String email = '',
  }) {
    return ProvincialAdminProfile(
      id: adminId(map['id']),
      role: adminString(map, const ['role']),
      fullName: adminString(map, const ['full_name']),
      firstName: adminString(map, const ['first_name']),
      lastName: adminString(map, const ['last_name']),
      email: adminString(map, const ['email'], fallback: email),
      mobile: adminString(map, const ['mobile', 'contact_number']),
      city: adminString(map, const ['city']),
      province: adminString(map, const ['province'], fallback: 'Bulacan'),
      profileImageUrl: adminString(map, const [
        'profile_image_url',
        'avatar_url',
      ]),
      raw: map,
    );
  }

  bool get isAdmin => role.toLowerCase().trim() == 'admin';

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
  final Map<String, dynamic> raw;

  factory CityTenant.fromProfile(
    Map<String, dynamic> map, {
    int spotsCount = 0,
    int packagesCount = 0,
    int bookingsCount = 0,
    int driversCount = 0,
  }) {
    final city = adminString(map, const ['city', 'assigned_city']);
    final firstName = adminString(map, const ['first_name']);
    final lastName = adminString(map, const ['last_name']);
    final generatedName = [
      firstName,
      lastName,
    ].where((value) => value.isNotEmpty).join(' ');
    final detailsStatus = adminString(map, const ['verification_status']);
    final active = map['is_active'];
    final status = active is bool
        ? (active ? 'active' : 'inactive')
        : adminString(map, const [
            'status',
            'account_status',
            'tenant_status',
          ], fallback: detailsStatus.isEmpty ? 'active' : detailsStatus);
    return CityTenant(
      id: adminId(map['id']),
      city: city.isEmpty ? 'Unassigned City' : city,
      province: adminString(map, const ['province'], fallback: 'Bulacan'),
      adminName: adminString(map, const [
        'full_name',
        'contact_person',
        'office_name',
        'name',
      ], fallback: generatedName.isEmpty ? 'City Admin' : generatedName),
      email: adminString(map, const [
        'email',
        'contact_email',
        'office_email',
      ]),
      mobile: adminString(map, const ['mobile', 'contact_number']),
      address: adminString(map, const ['address', 'office_address']),
      status: status,
      createdAt: adminDate(map['created_at']),
      spotsCount: spotsCount,
      packagesCount: packagesCount,
      bookingsCount: bookingsCount,
      driversCount: driversCount,
      verified:
          map['verified'] == true ||
          map['is_verified'] == true ||
          detailsStatus == 'approved' ||
          detailsStatus == 'verified',
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
      raw: raw,
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
      title: adminString(map, const ['title', 'name'], fallback: 'Untitled'),
      subtitle: adminString(map, const ['subtitle', 'tagline']),
      description: adminString(map, const ['description', 'details']),
      city: adminString(map, const ['city'], fallback: 'Unassigned'),
      status: adminString(map, const ['status'], fallback: 'draft'),
      visibilityStatus: adminString(map, const [
        'visibility_status',
        'visibility',
      ], fallback: 'visible'),
      priceText: adminString(map, const ['price_text', 'price']),
      durationText: adminString(map, const ['duration_text', 'duration']),
      imageUrl: adminString(map, const ['cover_image_url', 'image_url']),
      createdAt: adminDate(map['created_at']),
      estimatedBudget: adminDouble(map['estimated_budget']),
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
      title: adminString(map, const ['title', 'name'], fallback: 'Untitled'),
      description: adminString(map, const ['description']),
      city: adminString(map, const ['city'], fallback: 'Unassigned'),
      barangay: adminString(map, const ['barangay']),
      status: adminString(map, const ['status'], fallback: 'active'),
      verificationStatus: adminString(map, const [
        'verification_status',
      ], fallback: map['verified_at'] != null ? 'verified' : 'unverified'),
      rating: adminDouble(map['rating']),
      imageUrl: adminString(map, const ['image_url', 'cover_image_url']),
      createdAt: adminDate(map['created_at']),
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
          adminString(nested ?? const {}, const ['title'], fallback: 'Package'),
      city:
          package?.city ??
          adminString(nested ?? const {}, const ['city'], fallback: 'Unknown'),
      touristName: adminString(map, const [
        'tourist_name',
        'full_name',
        'customer_name',
      ], fallback: 'Tourist'),
      status: adminString(map, const ['status'], fallback: 'pending'),
      totalAmount: adminDouble(map['total_amount']),
      travelDate: adminDate(map['travel_date']),
      createdAt: adminDate(map['created_at']),
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
      city: adminString(map, const ['city'], fallback: city),
      rating: adminDouble(map['rating'], fallback: adminDouble(map['score'])),
      comment: adminString(map, const [
        'comment',
        'review_text',
        'feedback',
        'message',
        'body',
        'content',
      ]),
      reviewerName: adminString(map, const [
        'tourist_name',
        'reviewer',
        'reviewer_name',
        'customer_name',
        'user_name',
      ], fallback: 'Tourist'),
      subjectName: adminString(map, const [
        'driver_name',
        'subject_name',
        'package_title',
        'spot_title',
        'related_title',
      ], fallback: 'Transport service'),
      createdAt: adminDate(map['created_at']),
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
      userId: adminId(map['user_id']),
      city: adminString(map, const ['city'], fallback: 'Unassigned'),
      officeName: adminString(map, const ['office_name']),
      contactPerson: adminString(map, const ['contact_person']),
      contactNumber: adminString(map, const ['contact_number', 'mobile']),
      email: adminString(map, const ['email']),
      address: adminString(map, const ['office_address', 'address']),
      status: adminString(map, const ['status'], fallback: 'pending')
          .toLowerCase(),
      submittedAt: adminDate(map['submitted_at'] ?? map['created_at']),
      reviewedAt: adminDate(map['reviewed_at']),
      reviewedBy: adminId(map['reviewed_by']),
      rejectionReason: adminString(map, const ['rejection_reason']),
      raw: map,
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}

class AdminPolicy {
  const AdminPolicy({
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

  factory AdminPolicy.fromMap(Map<String, dynamic> map) {
    return AdminPolicy(
      id: map['id'],
      title: adminString(map, const ['title'], fallback: 'Untitled Policy'),
      content: adminString(map, const ['content', 'body', 'description']),
      status: adminString(map, const ['status'], fallback: 'draft'),
      createdAt: adminDate(map['created_at']),
      raw: map,
    );
  }
}

class AdminCategory {
  const AdminCategory({
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

  factory AdminCategory.fromMap(Map<String, dynamic> map) {
    return AdminCategory(
      id: map['id'],
      name: adminString(map, const ['name'], fallback: 'Unnamed Category'),
      description: adminString(map, const ['description']),
      icon: adminString(map, const ['icon']),
      status: adminString(map, const ['status'], fallback: 'active'),
      createdAt: adminDate(map['created_at']),
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

class AdminDashboardData {
  const AdminDashboardData({
    required this.profile,
    required this.tenants,
    required this.packages,
    required this.spots,
    required this.bookings,
    required this.feedback,
    required this.registrations,
    required this.registrationsTableAvailable,
  });

  final ProvincialAdminProfile profile;
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

class AdminReportData {
  const AdminReportData({
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

class AdminSettingsData {
  const AdminSettingsData({
    required this.available,
    required this.notifications,
    required this.packageAlerts,
    required this.touristSpotAlerts,
    required this.performanceReports,
    required this.systemNotices,
    required this.language,
    required this.dashboardWidgets,
  });

  final bool available;
  final bool notifications;
  final bool packageAlerts;
  final bool touristSpotAlerts;
  final bool performanceReports;
  final bool systemNotices;
  final String language;
  final Map<String, bool> dashboardWidgets;

  factory AdminSettingsData.defaults({bool available = true}) {
    return AdminSettingsData(
      available: available,
      notifications: true,
      packageAlerts: true,
      touristSpotAlerts: true,
      performanceReports: true,
      systemNotices: true,
      language: 'English',
      dashboardWidgets: const {
        'Total Views': true,
        'Bookings': true,
        'Popular Destinations': true,
        'Top Packages': true,
      },
    );
  }

  factory AdminSettingsData.fromMap(Map<String, dynamic> map) {
    final widgets = <String, bool>{
      'Total Views': map['show_total_views'] != false,
      'Bookings': map['show_bookings'] != false,
      'Popular Destinations': map['show_popular_destinations'] != false,
      'Top Packages': map['show_top_packages'] != false,
    };

    return AdminSettingsData(
      available: true,
      notifications: map['notifications_enabled'] != false,
      packageAlerts: map['package_alerts'] != false,
      touristSpotAlerts: map['tourist_spot_alerts'] != false,
      performanceReports: map['performance_reports'] != false,
      systemNotices: map['system_notices'] != false,
      language: adminString(map, const ['language'], fallback: 'English'),
      dashboardWidgets: widgets,
    );
  }

  AdminSettingsData copyWith({
    bool? available,
    bool? notifications,
    bool? packageAlerts,
    bool? touristSpotAlerts,
    bool? performanceReports,
    bool? systemNotices,
    String? language,
    Map<String, bool>? dashboardWidgets,
  }) {
    return AdminSettingsData(
      available: available ?? this.available,
      notifications: notifications ?? this.notifications,
      packageAlerts: packageAlerts ?? this.packageAlerts,
      touristSpotAlerts: touristSpotAlerts ?? this.touristSpotAlerts,
      performanceReports: performanceReports ?? this.performanceReports,
      systemNotices: systemNotices ?? this.systemNotices,
      language: language ?? this.language,
      dashboardWidgets: dashboardWidgets ?? Map<String, bool>.from(this.dashboardWidgets),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'notifications_enabled': notifications,
      'package_alerts': packageAlerts,
      'tourist_spot_alerts': touristSpotAlerts,
      'performance_reports': performanceReports,
      'system_notices': systemNotices,
      'language': language,
      'show_total_views': dashboardWidgets['Total Views'] ?? true,
      'show_bookings': dashboardWidgets['Bookings'] ?? true,
      'show_popular_destinations':
          dashboardWidgets['Popular Destinations'] ?? true,
      'show_top_packages': dashboardWidgets['Top Packages'] ?? true,
    };
  }
}
