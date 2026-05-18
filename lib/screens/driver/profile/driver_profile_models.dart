import 'package:intl/intl.dart';

class DriverProfileData {
  final DriverProfile profile;
  final DriverDetails details;
  final DriverDocuments documents;

  DriverProfileData({
    required this.profile,
    required this.details,
    required this.documents,
  });
}

class DriverProfile {
  final String id;
  final String role;
  final String firstName;
  final String lastName;
  final String fullName;
  final String mobile;
  final String gender;
  final String address;
  final String profileImageUrl;
  final bool isOnline;
  final String middleName;
  final DateTime? birthdate;
  final String barangay;
  final String city;
  final String province;
  final String postalCode;

  DriverProfile({
    required this.id,
    required this.role,
    required this.firstName,
    required this.lastName,
    required this.fullName,
    required this.mobile,
    required this.gender,
    required this.address,
    required this.profileImageUrl,
    required this.isOnline,
    required this.middleName,
    required this.birthdate,
    required this.barangay,
    required this.city,
    required this.province,
    required this.postalCode,
  });

  factory DriverProfile.fromMap(Map<String, dynamic> map) {
    return DriverProfile(
      id: map['id'].toString(),
      role: (map['role'] ?? '').toString(),
      firstName: (map['first_name'] ?? '').toString(),
      lastName: (map['last_name'] ?? '').toString(),
      fullName: (map['full_name'] ?? '').toString(),
      mobile: (map['mobile'] ?? '').toString(),
      gender: (map['gender'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      profileImageUrl: (map['profile_image_url'] ?? '').toString(),
      isOnline: map['is_online'] == true,
      middleName: (map['middle_name'] ?? '').toString(),
      birthdate: _toDate(map['birthdate']),
      barangay: (map['barangay'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      province: (map['province'] ?? '').toString(),
      postalCode: (map['postal_code'] ?? '').toString(),
    );
  }

  factory DriverProfile.empty(String userId) {
    return DriverProfile(
      id: userId,
      role: 'driver',
      firstName: '',
      lastName: '',
      fullName: '',
      mobile: '',
      gender: '',
      address: '',
      profileImageUrl: '',
      isOnline: false,
      middleName: '',
      birthdate: null,
      barangay: '',
      city: '',
      province: '',
      postalCode: '',
    );
  }

  String get displayName {
    if (fullName.trim().isNotEmpty) return fullName.trim();

    final generated = [firstName, middleName, lastName]
        .where((e) => e.trim().isNotEmpty)
        .join(' ')
        .trim();

    return generated.isEmpty ? 'Driver' : generated;
  }

  String get personalInfoSubtitle {
    final parts = <String>[
      if (barangay.isNotEmpty) barangay,
      if (city.isNotEmpty) city,
      if (province.isNotEmpty) province,
    ];
    return parts.isEmpty ? 'Tap to add personal details' : parts.join(' • ');
  }

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

class DriverDetails {
  final String driverId;
  final String mobile;
  final String licenseNumber;
  final String plateNumber;
  final DateTime? licenseExpiry;
  final String todaName;
  final String operatorCode;

  DriverDetails({
    required this.driverId,
    required this.mobile,
    required this.licenseNumber,
    required this.plateNumber,
    required this.licenseExpiry,
    required this.todaName,
    required this.operatorCode,
  });

  factory DriverDetails.fromMap(Map<String, dynamic> map) {
    return DriverDetails(
      driverId: map['driver_id'].toString(),
      mobile: (map['mobile'] ?? '').toString(),
      licenseNumber: (map['license_number'] ?? '').toString(),
      plateNumber: (map['plate_number'] ?? '').toString(),
      licenseExpiry: _toDate(map['license_expiry']),
      todaName: (map['toda_name'] ?? '').toString(),
      operatorCode: (map['operator_code'] ?? '').toString(),
    );
  }

  factory DriverDetails.empty(String userId) {
    return DriverDetails(
      driverId: userId,
      mobile: '',
      licenseNumber: '',
      plateNumber: '',
      licenseExpiry: null,
      todaName: '',
      operatorCode: '',
    );
  }

  String get driverDetailsSubtitle {
    final parts = <String>[
      if (licenseNumber.isNotEmpty) 'License saved',
      if (plateNumber.isNotEmpty) plateNumber,
      if (licenseExpiry != null)
        'Exp ${DateFormat('MMM yyyy').format(licenseExpiry!)}',
    ];
    return parts.isEmpty ? 'Tap to add driver details' : parts.join(' • ');
  }

  String get todaSubtitle {
    final parts = <String>[
      if (todaName.isNotEmpty) todaName,
      if (operatorCode.isNotEmpty) operatorCode,
    ];
    return parts.isEmpty ? 'Tap to set TODA assignment' : parts.join(' • ');
  }

  static DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

class DriverDocuments {
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

  DriverDocuments({
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

  factory DriverDocuments.fromMap(Map<String, dynamic> map) {
    return DriverDocuments(
      driverId: map['driver_id'].toString(),
      selfieUrl: (map['selfie_url'] ?? '').toString(),
      licenseFrontUrl: (map['license_front_url'] ?? '').toString(),
      licenseBackUrl: (map['license_back_url'] ?? '').toString(),
      policeClearanceUrl: (map['police_clearance_url'] ?? '').toString(),
      mtopUrl: (map['mtop_url'] ?? '').toString(),
      vehicleFrontUrl: (map['vehicle_front_url'] ?? '').toString(),
      vehicleBackUrl: (map['vehicle_back_url'] ?? '').toString(),
      vehicleLeftUrl: (map['vehicle_left_url'] ?? '').toString(),
      vehicleRightUrl: (map['vehicle_right_url'] ?? '').toString(),
      orUrl: (map['or_url'] ?? '').toString(),
      crUrl: (map['cr_url'] ?? '').toString(),
    );
  }

  factory DriverDocuments.empty(String userId) {
    return DriverDocuments(
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

  int get uploadedCount {
    final list = [
      selfieUrl,
      licenseFrontUrl,
      licenseBackUrl,
      policeClearanceUrl,
      mtopUrl,
      vehicleFrontUrl,
      vehicleBackUrl,
      vehicleLeftUrl,
      vehicleRightUrl,
      orUrl,
      crUrl,
    ];
    return list.where((e) => e.trim().isNotEmpty).length;
  }

  int get totalCount => 11;
}