import 'package:flutter/material.dart';

enum DriverProfileStep {
  personalInfo,
  licenseInformation,
  todaAssignment,
  plateNumber,
  gcashPayment,
  roleSelection,
  documentsUpload,
  onlineStatus,
}

extension DriverProfileStepX on DriverProfileStep {
  String get title {
    switch (this) {
      case DriverProfileStep.personalInfo:
        return 'Personal Info';
      case DriverProfileStep.licenseInformation:
        return 'License Information';
      case DriverProfileStep.todaAssignment:
        return 'TODA Assignment';
      case DriverProfileStep.plateNumber:
        return 'Plate Number';
      case DriverProfileStep.gcashPayment:
        return 'GCash Payment Details';
      case DriverProfileStep.roleSelection:
        return 'Role Selection';
      case DriverProfileStep.documentsUpload:
        return 'Documents Upload';
      case DriverProfileStep.onlineStatus:
        return 'Online Status';
    }
  }

  String get subtitle {
    switch (this) {
      case DriverProfileStep.personalInfo:
        return 'Basic identity, contact details, municipality, barangay, and photo.';
      case DriverProfileStep.licenseInformation:
        return 'Your license number and expiry date.';
      case DriverProfileStep.todaAssignment:
        return 'Your TODA name and operator code.';
      case DriverProfileStep.plateNumber:
        return 'The tricycle plate number assigned to you.';
      case DriverProfileStep.gcashPayment:
        return 'Your GCash QR code and details so tourists can pay you directly.';
      case DriverProfileStep.roleSelection:
        return 'Confirm the driver role linked to your profile.';
      case DriverProfileStep.documentsUpload:
        return 'Upload the required driver documents to Supabase Storage.';
      case DriverProfileStep.onlineStatus:
        return 'Choose your online availability status.';
    }
  }

  IconData get icon {
    switch (this) {
      case DriverProfileStep.personalInfo:
        return Icons.person_outline_rounded;
      case DriverProfileStep.licenseInformation:
        return Icons.badge_outlined;
      case DriverProfileStep.todaAssignment:
        return Icons.groups_2_outlined;
      case DriverProfileStep.plateNumber:
        return Icons.directions_bike_outlined;
      case DriverProfileStep.gcashPayment:
        return Icons.qr_code_2_rounded;
      case DriverProfileStep.roleSelection:
        return Icons.verified_user_outlined;
      case DriverProfileStep.documentsUpload:
        return Icons.folder_open_outlined;
      case DriverProfileStep.onlineStatus:
        return Icons.circle_outlined;
    }
  }
}

enum DriverDocumentType {
  selfie,
  licenseFront,
  licenseBack,
  policeClearance,
  mtop,
  vehicleFront,
  vehicleBack,
  vehicleLeft,
  vehicleRight,
  orDocument,
  crDocument,
}

extension DriverDocumentTypeX on DriverDocumentType {
  String get label {
    switch (this) {
      case DriverDocumentType.selfie:
        return 'Selfie';
      case DriverDocumentType.licenseFront:
        return 'License Front';
      case DriverDocumentType.licenseBack:
        return 'License Back';
      case DriverDocumentType.policeClearance:
        return 'Police Clearance';
      case DriverDocumentType.mtop:
        return 'MTOP';
      case DriverDocumentType.vehicleFront:
        return 'Vehicle Front';
      case DriverDocumentType.vehicleBack:
        return 'Vehicle Back';
      case DriverDocumentType.vehicleLeft:
        return 'Vehicle Left';
      case DriverDocumentType.vehicleRight:
        return 'Vehicle Right';
      case DriverDocumentType.orDocument:
        return 'OR';
      case DriverDocumentType.crDocument:
        return 'CR';
    }
  }

  String get columnName {
    switch (this) {
      case DriverDocumentType.selfie:
        return 'selfie_url';
      case DriverDocumentType.licenseFront:
        return 'license_front_url';
      case DriverDocumentType.licenseBack:
        return 'license_back_url';
      case DriverDocumentType.policeClearance:
        return 'police_clearance_url';
      case DriverDocumentType.mtop:
        return 'mtop_url';
      case DriverDocumentType.vehicleFront:
        return 'vehicle_front_url';
      case DriverDocumentType.vehicleBack:
        return 'vehicle_back_url';
      case DriverDocumentType.vehicleLeft:
        return 'vehicle_left_url';
      case DriverDocumentType.vehicleRight:
        return 'vehicle_right_url';
      case DriverDocumentType.orDocument:
        return 'or_url';
      case DriverDocumentType.crDocument:
        return 'cr_url';
    }
  }

  IconData get icon {
    switch (this) {
      case DriverDocumentType.selfie:
        return Icons.portrait_outlined;
      case DriverDocumentType.licenseFront:
      case DriverDocumentType.licenseBack:
        return Icons.badge_outlined;
      case DriverDocumentType.policeClearance:
        return Icons.gavel_outlined;
      case DriverDocumentType.mtop:
        return Icons.description_outlined;
      case DriverDocumentType.vehicleFront:
      case DriverDocumentType.vehicleBack:
      case DriverDocumentType.vehicleLeft:
      case DriverDocumentType.vehicleRight:
        return Icons.directions_bike_outlined;
      case DriverDocumentType.orDocument:
      case DriverDocumentType.crDocument:
        return Icons.article_outlined;
    }
  }
}

class DriverProfileBundle {
  const DriverProfileBundle({
    required this.profile,
    required this.details,
    required this.documents,
  });

  final DriverProfileRecord profile;
  final DriverDetailsRecord details;
  final DriverDocumentsRecord documents;

  bool isStepComplete(DriverProfileStep step) {
    switch (step) {
      case DriverProfileStep.personalInfo:
        return profile.isPersonalInfoComplete;
      case DriverProfileStep.licenseInformation:
        return details.isLicenseInformationComplete;
      case DriverProfileStep.todaAssignment:
        return details.isTodaAssignmentComplete;
      case DriverProfileStep.plateNumber:
        return details.isPlateNumberComplete;
      case DriverProfileStep.gcashPayment:
        return details.isGcashPaymentComplete;
      case DriverProfileStep.roleSelection:
        return profile.isRoleSelectionComplete;
      case DriverProfileStep.documentsUpload:
        return documents.isDocumentsStepComplete;
      case DriverProfileStep.onlineStatus:
        return profile.isOnlineStatusConfigured;
    }
  }

  List<DriverProfileStep> get completedSteps {
    return DriverProfileStep.values.where(isStepComplete).toList();
  }

  int get completionPercent {
    return ((completedSteps.length / DriverProfileStep.values.length) * 100)
        .round();
  }

  DriverProfileStep get nextIncompleteStep {
    return DriverProfileStep.values.firstWhere(
      (step) => !isStepComplete(step),
      orElse: () => DriverProfileStep.onlineStatus,
    );
  }

  bool get isFullyComplete =>
      completedSteps.length == DriverProfileStep.values.length;
}

class DriverProfileRecord {
  const DriverProfileRecord({
    required this.id,
    required this.role,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.fullName,
    required this.mobile,
    required this.gender,
    required this.address,
    required this.barangay,
    required this.city,
    required this.municipality,
    required this.province,
    required this.postalCode,
    required this.profileImageUrl,
    required this.avatarUrl,
    required this.birthdate,
    required this.isOnline,
    required this.hasOnlineStatusValue,
  });

  factory DriverProfileRecord.fromMap(Map<String, dynamic> map, String userId) {
    return DriverProfileRecord(
      id: _stringValue(map['id'], fallback: userId),
      role: _stringValue(map['role'], fallback: 'driver'),
      firstName: _stringValue(map['first_name']),
      middleName: _stringValue(map['middle_name']),
      lastName: _stringValue(map['last_name']),
      fullName: _stringValue(map['full_name']),
      mobile: _stringValue(map['mobile']),
      gender: _stringValue(map['gender']),
      address: _stringValue(map['address']),
      barangay: _stringValue(map['barangay']),
      city: _stringValue(map['city']),
      municipality: _stringValue(
        map['municipality'],
        fallback: _stringValue(map['city']),
      ),
      province: _stringValue(map['province'], fallback: 'Bulacan'),
      postalCode: _stringValue(map['postal_code']),
      profileImageUrl: _stringValue(map['profile_image_url']),
      avatarUrl: _stringValue(map['avatar_url']),
      birthdate: _dateValue(map['birthdate']),
      isOnline: _boolValue(map['is_online']),
      hasOnlineStatusValue:
          map.containsKey('is_online') && map['is_online'] != null,
    );
  }

  factory DriverProfileRecord.empty(String userId) {
    return DriverProfileRecord(
      id: userId,
      role: 'driver',
      firstName: '',
      middleName: '',
      lastName: '',
      fullName: '',
      mobile: '',
      gender: '',
      address: '',
      barangay: '',
      city: '',
      municipality: '',
      province: 'Bulacan',
      postalCode: '',
      profileImageUrl: '',
      avatarUrl: '',
      birthdate: null,
      isOnline: false,
      hasOnlineStatusValue: false,
    );
  }

  final String id;
  final String role;
  final String firstName;
  final String middleName;
  final String lastName;
  final String fullName;
  final String mobile;
  final String gender;
  final String address;
  final String barangay;
  final String city;
  final String municipality;
  final String province;
  final String postalCode;
  final String profileImageUrl;
  final String avatarUrl;
  final DateTime? birthdate;
  final bool isOnline;
  final bool hasOnlineStatusValue;

  String get displayName {
    final explicit = fullName.trim();
    if (explicit.isNotEmpty) return explicit;
    final computed = [
      firstName,
      middleName,
      lastName,
    ].where((value) => value.trim().isNotEmpty).join(' ').trim();
    return computed.isEmpty ? 'Driver' : computed;
  }

  String get effectiveMunicipality {
    final normalized = municipality.trim();
    if (normalized.isNotEmpty) return normalized;
    return city.trim();
  }

  String get effectivePhotoUrl {
    final primary = profileImageUrl.trim();
    if (primary.isNotEmpty) return primary;
    return avatarUrl.trim();
  }

  String get locationSummary {
    final parts = [
      barangay.trim(),
      effectiveMunicipality.trim(),
      province.trim(),
    ].where((value) => value.isNotEmpty).toList();
    return parts.isEmpty ? 'Add municipality and barangay' : parts.join(' / ');
  }

  bool get isPersonalInfoComplete {
    return firstName.trim().isNotEmpty &&
        lastName.trim().isNotEmpty &&
        displayName.trim().isNotEmpty &&
        mobile.trim().isNotEmpty &&
        address.trim().isNotEmpty &&
        barangay.trim().isNotEmpty &&
        effectiveMunicipality.trim().isNotEmpty &&
        province.trim().isNotEmpty &&
        birthdate != null &&
        effectivePhotoUrl.trim().isNotEmpty;
  }

  bool get isRoleSelectionComplete => role.trim().toLowerCase() == 'driver';

  bool get isOnlineStatusConfigured => hasOnlineStatusValue;
}

class DriverDetailsRecord {
  const DriverDetailsRecord({
    required this.driverId,
    required this.mobile,
    required this.licenseNumber,
    required this.plateNumber,
    required this.licenseExpiry,
    required this.todaName,
    required this.operatorCode,
    required this.status,
    required this.approvedAt,
    required this.gcashNumber,
    required this.gcashName,
    required this.gcashQrUrl,
  });

  factory DriverDetailsRecord.fromMap(Map<String, dynamic> map, String userId) {
    return DriverDetailsRecord(
      driverId: _stringValue(map['driver_id'], fallback: userId),
      mobile: _stringValue(map['mobile']),
      licenseNumber: _stringValue(map['license_number']),
      plateNumber: _stringValue(map['plate_number']),
      licenseExpiry: _dateValue(map['license_expiry']),
      todaName: _stringValue(map['toda_name']),
      operatorCode: _stringValue(map['operator_code']),
      status: _stringValue(map['status'], fallback: 'pending'),
      approvedAt: _dateValue(map['approved_at']),
      gcashNumber: _stringValue(map['gcash_number']),
      gcashName: _stringValue(map['gcash_name']),
      gcashQrUrl: _stringValue(map['gcash_qr_url']),
    );
  }

  factory DriverDetailsRecord.empty(String userId) {
    return DriverDetailsRecord(
      driverId: userId,
      mobile: '',
      licenseNumber: '',
      plateNumber: '',
      licenseExpiry: null,
      todaName: '',
      operatorCode: '',
      status: 'pending',
      approvedAt: null,
      gcashNumber: '',
      gcashName: '',
      gcashQrUrl: '',
    );
  }

  final String driverId;
  final String mobile;
  final String licenseNumber;
  final String plateNumber;
  final DateTime? licenseExpiry;
  final String todaName;
  final String operatorCode;
  final String status;
  final DateTime? approvedAt;
  final String gcashNumber;
  final String gcashName;
  final String gcashQrUrl;

  bool get isLicenseInformationComplete {
    return licenseNumber.trim().isNotEmpty && licenseExpiry != null;
  }

  bool get isTodaAssignmentComplete {
    return todaName.trim().isNotEmpty && operatorCode.trim().isNotEmpty;
  }

  bool get isPlateNumberComplete => plateNumber.trim().isNotEmpty;

  // TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
  bool get isGcashPaymentComplete {
    return gcashQrUrl.trim().isNotEmpty ||
        (gcashNumber.trim().isNotEmpty && gcashName.trim().isNotEmpty);
  }
}

class DriverDocumentsRecord {
  const DriverDocumentsRecord({
    required this.driverId,
    required this.selfieUrl,
    required this.licenseFrontUrl,
    required this.licenseBackUrl,
    required this.policeClearanceUrl,
    required this.mtopUrl,
    required this.vehicleFrontUrl,
    required this.vehicleBackUrl,
    required this.vehicleLeftUrl,
    required this.vehicleRightUrl,
    required this.orUrl,
    required this.crUrl,
  });

  factory DriverDocumentsRecord.fromMap(
    Map<String, dynamic> map,
    String userId,
  ) {
    return DriverDocumentsRecord(
      driverId: _stringValue(map['driver_id'], fallback: userId),
      selfieUrl: _stringValue(map['selfie_url']),
      licenseFrontUrl: _stringValue(map['license_front_url']),
      licenseBackUrl: _stringValue(map['license_back_url']),
      policeClearanceUrl: _stringValue(map['police_clearance_url']),
      mtopUrl: _stringValue(map['mtop_url']),
      vehicleFrontUrl: _stringValue(map['vehicle_front_url']),
      vehicleBackUrl: _stringValue(map['vehicle_back_url']),
      vehicleLeftUrl: _stringValue(map['vehicle_left_url']),
      vehicleRightUrl: _stringValue(map['vehicle_right_url']),
      orUrl: _stringValue(map['or_url']),
      crUrl: _stringValue(map['cr_url']),
    );
  }

  factory DriverDocumentsRecord.empty(String userId) {
    return DriverDocumentsRecord(
      driverId: userId,
      selfieUrl: '',
      licenseFrontUrl: '',
      licenseBackUrl: '',
      policeClearanceUrl: '',
      mtopUrl: '',
      vehicleFrontUrl: '',
      vehicleBackUrl: '',
      vehicleLeftUrl: '',
      vehicleRightUrl: '',
      orUrl: '',
      crUrl: '',
    );
  }

  final String driverId;
  final String selfieUrl;
  final String licenseFrontUrl;
  final String licenseBackUrl;
  final String policeClearanceUrl;
  final String mtopUrl;
  final String vehicleFrontUrl;
  final String vehicleBackUrl;
  final String vehicleLeftUrl;
  final String vehicleRightUrl;
  final String orUrl;
  final String crUrl;

  List<DriverDocumentType> get uploadedTypes {
    return DriverDocumentType.values
        .where((type) => urlFor(type).trim().isNotEmpty)
        .toList();
  }

  int get uploadedCount => uploadedTypes.length;

  int get totalCount => DriverDocumentType.values.length;

  bool get isDocumentsStepComplete => uploadedCount == totalCount;

  String urlFor(DriverDocumentType type) {
    switch (type) {
      case DriverDocumentType.selfie:
        return selfieUrl;
      case DriverDocumentType.licenseFront:
        return licenseFrontUrl;
      case DriverDocumentType.licenseBack:
        return licenseBackUrl;
      case DriverDocumentType.policeClearance:
        return policeClearanceUrl;
      case DriverDocumentType.mtop:
        return mtopUrl;
      case DriverDocumentType.vehicleFront:
        return vehicleFrontUrl;
      case DriverDocumentType.vehicleBack:
        return vehicleBackUrl;
      case DriverDocumentType.vehicleLeft:
        return vehicleLeftUrl;
      case DriverDocumentType.vehicleRight:
        return vehicleRightUrl;
      case DriverDocumentType.orDocument:
        return orUrl;
      case DriverDocumentType.crDocument:
        return crUrl;
    }
  }
}

String _stringValue(dynamic value, {String fallback = ''}) {
  if (value == null) return fallback;
  final text = value.toString().trim();
  return text.isEmpty ? fallback : text;
}

bool _boolValue(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  final normalized = value.toString().trim().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return fallback;
}

DateTime? _dateValue(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;

  final text = value.toString().trim();
  if (text.isEmpty) return null;

  final dateOnly = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
  if (dateOnly != null) {
    return DateTime(
      int.parse(dateOnly.group(1)!),
      int.parse(dateOnly.group(2)!),
      int.parse(dateOnly.group(3)!),
    );
  }

  return DateTime.tryParse(text)?.toLocal();
}
