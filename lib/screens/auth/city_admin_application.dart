class CityAdminApplicationDraft {
  const CityAdminApplicationDraft({
    required this.email,
    required this.password,
    required this.city,
    required this.officeName,
    required this.contactPerson,
    required this.contactNumber,
    required this.officeAddress,
  });

  final String email;
  final String password;
  final String city;
  final String officeName;
  final String contactPerson;
  final String contactNumber;
  final String officeAddress;

  String get displayOffice =>
      officeName.trim().isEmpty ? '$city Tourism Office' : officeName.trim();

  String get normalizedCity => city.trim();

  String get normalizedEmail => email.trim().toLowerCase();

  Map<String, String> get contactNameParts {
    final parts = contactPerson.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return const {'first_name': '', 'last_name': ''};
    }
    if (parts.length == 1) {
      return {'first_name': parts.first, 'last_name': ''};
    }
    return {'first_name': parts.first, 'last_name': parts.sublist(1).join(' ')};
  }

  Map<String, dynamic> profileInsertPayload(String userId) {
    final nameParts = contactNameParts;
    return {
      'id': userId,
      'role': 'tourist',
      'first_name': nameParts['first_name'],
      'last_name': nameParts['last_name'],
      'full_name': contactPerson.trim(),
      'mobile': contactNumber.trim(),
      'address': officeAddress.trim(),
      'city': normalizedCity,
      'province': 'Bulacan',
    };
  }

  Map<String, dynamic> profileUpdatePayload() {
    final payload = profileInsertPayload('');
    payload.remove('id');
    payload.remove('role');
    return payload;
  }

  Map<String, dynamic> registrationPayload(String userId) {
    return {
      'user_id': userId,
      'city': normalizedCity,
      'office_name': displayOffice,
      'contact_person': contactPerson.trim(),
      'contact_number': contactNumber.trim(),
      'email': normalizedEmail,
      'office_address': officeAddress.trim(),
      'status': 'pending',
    };
  }
}
