class DriverIdentityStatus {
  const DriverIdentityStatus(
    this.value, {
    this.verifiedAt,
    this.verifiedDocumentType,
  });

  final String value;
  final DateTime? verifiedAt;
  final String? verifiedDocumentType;

  String get verifiedIdLabel => value != 'approved'
      ? 'Government-issued ID'
      : switch (verifiedDocumentType) {
          "Driver's License" ||
          'Identity Card' ||
          'Passport' ||
          'Residence Permit' => verifiedDocumentType!,
          _ => 'Government-issued ID',
        };

  bool get canStart =>
      value == 'not_verified' ||
      value == 'declined' ||
      value == 'expired' ||
      value == 'creating' ||
      value == 'not_started' ||
      value == 'in_progress';

  String get label => switch (value) {
    'creating' => 'Preparing verification',
    'not_started' => 'Ready to verify',
    'in_progress' => 'Verification in progress',
    'in_review' => 'Under review',
    'approved' => 'Identity verified',
    'declined' => 'Verification unsuccessful',
    'expired' => 'Verification expired',
    _ => 'Not verified',
  };

  String get description => switch (value) {
    'approved' =>
      'Your identity was verified. Your Driver application still requires MTO approval.',
    'in_review' => 'Your result is being reviewed. Refresh this status later.',
    'declined' => 'The identity check was unsuccessful. You can try again.',
    'expired' => 'The verification session expired. You can start a new check.',
    'in_progress' =>
      'Complete the Didit steps, then return here to check the result.',
    'not_started' => 'Your verification session is ready.',
    'creating' => 'Your verification session is being prepared.',
    _ => 'Verify your identity as part of Driver registration.',
  };
}
