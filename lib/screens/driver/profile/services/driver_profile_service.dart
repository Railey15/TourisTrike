import 'dart:async';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';

class DriverProfileService {
  DriverProfileService({SupabaseClient? client, ImagePicker? imagePicker})
    : _supabase = client ?? Supabase.instance.client,
      _imagePicker = imagePicker ?? ImagePicker();

  final SupabaseClient _supabase;
  final ImagePicker _imagePicker;

  static const String storageBucket = 'public-assets';
  static const String storageFolder = 'driver-documents';
  static const String gcashPaymentFolder = 'driver-payment';

  User? get currentUser => _supabase.auth.currentUser;

  String? get currentUserId => currentUser?.id;

  Future<DriverProfileBundle> fetchProfileBundle(String userId) async {
    final profileRow = await _supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .maybeSingle();
    final detailsRow = await _supabase
        .from('driver_details')
        .select()
        .eq('driver_id', userId)
        .maybeSingle();
    final documentsRow = await _supabase
        .from('driver_documents')
        .select()
        .eq('driver_id', userId)
        .maybeSingle();

    return DriverProfileBundle(
      profile: DriverProfileRecord.fromMap(
        profileRow ?? <String, dynamic>{},
        userId,
      ),
      details: DriverDetailsRecord.fromMap(
        detailsRow ?? <String, dynamic>{},
        userId,
      ),
      documents: DriverDocumentsRecord.fromMap(
        documentsRow ?? <String, dynamic>{},
        userId,
      ),
    );
  }

  Stream<DriverProfileBundle> watchProfileBundle(String userId) {
    final profileStream = _supabase
        .from('profiles')
        .stream(primaryKey: const ['id'])
        .eq('id', userId)
        .map(
          (rows) => rows.isNotEmpty
              ? DriverProfileRecord.fromMap(rows.first, userId)
              : DriverProfileRecord.empty(userId),
        );

    final detailsStream = _supabase
        .from('driver_details')
        .stream(primaryKey: const ['driver_id'])
        .eq('driver_id', userId)
        .map(
          (rows) => rows.isNotEmpty
              ? DriverDetailsRecord.fromMap(rows.first, userId)
              : DriverDetailsRecord.empty(userId),
        );

    final documentsStream = _supabase
        .from('driver_documents')
        .stream(primaryKey: const ['driver_id'])
        .eq('driver_id', userId)
        .map(
          (rows) => rows.isNotEmpty
              ? DriverDocumentsRecord.fromMap(rows.first, userId)
              : DriverDocumentsRecord.empty(userId),
        );

    return Stream<DriverProfileBundle>.multi((controller) {
      DriverProfileRecord latestProfile = DriverProfileRecord.empty(userId);
      DriverDetailsRecord latestDetails = DriverDetailsRecord.empty(userId);
      DriverDocumentsRecord latestDocuments = DriverDocumentsRecord.empty(
        userId,
      );

      late final StreamSubscription<dynamic> profileSub;
      late final StreamSubscription<dynamic> detailsSub;
      late final StreamSubscription<dynamic> documentsSub;

      void emit() {
        controller.add(
          DriverProfileBundle(
            profile: latestProfile,
            details: latestDetails,
            documents: latestDocuments,
          ),
        );
      }

      profileSub = profileStream.listen((profile) {
        latestProfile = profile;
        emit();
      }, onError: controller.addError);

      detailsSub = detailsStream.listen((details) {
        final hadPersistedDetails =
            latestDetails.licenseNumber.trim().isNotEmpty ||
            latestDetails.licenseExpiry != null ||
            latestDetails.todaName.trim().isNotEmpty ||
            latestDetails.operatorCode.trim().isNotEmpty ||
            latestDetails.plateNumber.trim().isNotEmpty;
        final incomingLooksEmpty =
            details.licenseNumber.trim().isEmpty &&
            details.licenseExpiry == null &&
            details.todaName.trim().isEmpty &&
            details.operatorCode.trim().isEmpty &&
            details.plateNumber.trim().isEmpty;

        // Realtime can briefly emit an empty placeholder row between writes.
        if (hadPersistedDetails && incomingLooksEmpty) {
          return;
        }

        latestDetails = details;
        emit();
      }, onError: controller.addError);

      documentsSub = documentsStream.listen((documents) {
        latestDocuments = documents;
        emit();
      }, onError: controller.addError);

      controller.onCancel = () async {
        await profileSub.cancel();
        await detailsSub.cancel();
        await documentsSub.cancel();
      };
    });
  }

  Future<XFile?> pickImage({
    required ImageSource source,
    int imageQuality = 78,
    double maxWidth = 1600,
    double maxHeight = 1600,
  }) {
    return _imagePicker.pickImage(
      source: source,
      imageQuality: imageQuality,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
    );
  }

  Future<void> savePersonalInfo({
    required String userId,
    required String firstName,
    required String middleName,
    required String lastName,
    required String fullName,
    required String mobile,
    required String address,
    required String barangay,
    required String municipality,
    required String province,
    required DateTime? birthdate,
  }) async {
    final normalizedFullName = fullName.trim().isNotEmpty
        ? fullName.trim()
        : [firstName, middleName, lastName]
              .where((value) => value.trim().isNotEmpty)
              .join(' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();

    await _upsertProfile(userId, <String, dynamic>{
      'role': 'driver',
      'first_name': _nullableText(firstName),
      'middle_name': _nullableText(middleName),
      'last_name': _nullableText(lastName),
      'full_name': _nullableText(normalizedFullName),
      'mobile': _nullableText(mobile),
      'birthdate': _dateOnlyString(birthdate),
      'address': _nullableText(address),
      'barangay': _nullableText(barangay),
      // `city` is the stable column in this repo. We also try `municipality`
      // if the deployment has already added it.
      'city': _nullableText(municipality),
      'municipality': _nullableText(municipality),
      'province': _nullableText(province),
      'updated_at': DateTime.now().toIso8601String(),
    });

    await _upsertDriverDetails(userId, <String, dynamic>{
      'mobile': _nullableText(mobile),
    });
  }

  Future<void> saveDriverDetails({
    required String userId,
    String? mobile,
    String? licenseNumber,
    DateTime? licenseExpiry,
    String? todaName,
    String? operatorCode,
    String? plateNumber,
  }) async {
    // Only include keys that were explicitly provided so that unrelated fields
    // already saved in the DB are never overwritten with null.
    final payload = <String, dynamic>{};
    if (mobile != null) payload['mobile'] = _nullableText(mobile);
    if (licenseNumber != null) payload['license_number'] = _nullableText(licenseNumber);
    if (licenseExpiry != null) payload['license_expiry'] = _dateOnlyString(licenseExpiry);
    if (todaName != null) payload['toda_name'] = _nullableText(todaName);
    if (operatorCode != null) payload['operator_code'] = _nullableText(operatorCode);
    if (plateNumber != null) payload['plate_number'] = _nullableText(plateNumber);

    await _upsertDriverDetails(userId, payload);

    if (mobile != null) {
      await _upsertProfile(userId, <String, dynamic>{
        'mobile': _nullableText(mobile),
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> saveLicenseNumber({
    required String userId,
    required String licenseNumber,
  }) {
    return saveDriverDetails(userId: userId, licenseNumber: licenseNumber);
  }

  Future<void> saveLicenseExpiry({
    required String userId,
    required DateTime? licenseExpiry,
  }) {
    return saveDriverDetails(userId: userId, licenseExpiry: licenseExpiry);
  }

  Future<void> savePlateNumber({
    required String userId,
    required String plateNumber,
  }) {
    return saveDriverDetails(userId: userId, plateNumber: plateNumber);
  }

  Future<void> saveTodaAssignment({
    required String userId,
    required String todaName,
    required String operatorCode,
  }) {
    return saveDriverDetails(
      userId: userId,
      todaName: todaName,
      operatorCode: operatorCode,
    );
  }

  Future<void> saveRoleSelection(String userId) {
    return _upsertProfile(userId, <String, dynamic>{
      'role': 'driver',
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> saveOnlineStatus({
    required String userId,
    required bool isOnline,
  }) {
    return _upsertProfile(userId, <String, dynamic>{
      'is_online': isOnline,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<String> uploadProfilePhoto({
    required String userId,
    required XFile file,
    String? previousUrl,
  }) async {
    final upload = await _uploadFile(
      userId: userId,
      baseName: 'profile_photo',
      file: file,
    );

    await _upsertProfile(userId, <String, dynamic>{
      'role': 'driver',
      'profile_image_url': upload.publicUrl,
      'avatar_url': upload.publicUrl,
      'updated_at': DateTime.now().toIso8601String(),
    });

    if (previousUrl != null && previousUrl.trim().isNotEmpty) {
      unawaited(_deleteStorageObjectIfPossible(previousUrl));
    }

    return upload.publicUrl;
  }

  Future<void> removeProfilePhoto({
    required String userId,
    required String previousUrl,
  }) async {
    await _upsertProfile(userId, <String, dynamic>{
      'role': 'driver',
      'profile_image_url': null,
      'avatar_url': null,
      'updated_at': DateTime.now().toIso8601String(),
    });
    await _deleteStorageObjectIfPossible(previousUrl);
  }

  Future<String> uploadDocument({
    required String userId,
    required DriverDocumentType type,
    required XFile file,
    String? previousUrl,
  }) async {
    final upload = await _uploadFile(
      userId: userId,
      baseName: type.columnName,
      file: file,
    );

    await _upsertDriverDocuments(userId, <String, dynamic>{
      type.columnName: upload.publicUrl,
    });

    if (previousUrl != null && previousUrl.trim().isNotEmpty) {
      unawaited(_deleteStorageObjectIfPossible(previousUrl));
    }

    return upload.publicUrl;
  }

  Future<void> deleteDocument({
    required String userId,
    required DriverDocumentType type,
    required String existingUrl,
  }) async {
    await _upsertDriverDocuments(userId, <String, dynamic>{
      type.columnName: null,
    });
    await _deleteStorageObjectIfPossible(existingUrl);
  }

  /// GCash-to-GCash direct payment setup — the driver's own QR code, uploaded
  /// under the `driver-payment/` folder (a distinct storage RLS policy from
  /// `driver-documents/`, see the payment-trail migration).
  Future<String> uploadGcashQr({
    required String userId,
    required XFile file,
    String? previousUrl,
  }) async {
    final upload = await _uploadFile(
      userId: userId,
      baseName: 'gcash_qr',
      file: file,
      folder: gcashPaymentFolder,
    );

    await _upsertDriverDetails(userId, <String, dynamic>{
      'gcash_qr_url': upload.publicUrl,
    });

    if (previousUrl != null && previousUrl.trim().isNotEmpty) {
      unawaited(_deleteStorageObjectIfPossible(previousUrl));
    }

    return upload.publicUrl;
  }

  Future<void> removeGcashQr({
    required String userId,
    required String existingUrl,
  }) async {
    await _upsertDriverDetails(userId, <String, dynamic>{
      'gcash_qr_url': null,
    });
    await _deleteStorageObjectIfPossible(existingUrl);
  }

  Future<void> saveGcashDetails({
    required String userId,
    String? gcashNumber,
    String? gcashName,
  }) async {
    final payload = <String, dynamic>{};
    if (gcashNumber != null) payload['gcash_number'] = _nullableText(gcashNumber);
    if (gcashName != null) payload['gcash_name'] = _nullableText(gcashName);
    await _upsertDriverDetails(userId, payload);
  }

  Future<void> ensureDriverRows(String userId) async {
    await _upsertDriverDetails(userId, const <String, dynamic>{});
    await _upsertDriverDocuments(userId, const <String, dynamic>{});
  }

  /// Patches only the provided columns. Uses UPDATE when a row exists so
  /// earlier onboarding fields (license, TODA, plate, etc.) are never cleared.
  Future<void> _patchDriverDetails(
    String userId,
    Map<String, dynamic> payload,
  ) async {
    if (payload.isEmpty) return;

    final existing = await _supabase
        .from('driver_details')
        .select('driver_id')
        .eq('driver_id', userId)
        .maybeSingle();

    if (existing != null) {
      await _supabase
          .from('driver_details')
          .update(payload)
          .eq('driver_id', userId);
      return;
    }

    await _supabase.from('driver_details').insert(<String, dynamic>{
      'driver_id': userId,
      ...payload,
    });
  }

  Future<void> _upsertDriverDetails(
    String userId,
    Map<String, dynamic> payload,
  ) {
    return _patchDriverDetails(userId, payload);
  }

  Future<void> _upsertDriverDocuments(
    String userId,
    Map<String, dynamic> payload,
  ) {
    return _supabase.from('driver_documents').upsert(<String, dynamic>{
      'driver_id': userId,
      ...payload,
    });
  }

  Future<void> _upsertProfile(
    String userId,
    Map<String, dynamic> payload,
  ) async {
    final mutable = <String, dynamic>{'id': userId, ...payload};
    final optionalColumns = <String>[
      'avatar_url',
      'municipality',
      'is_profile_complete',
      'updated_at',
    ];

    while (true) {
      try {
        await _supabase.from('profiles').upsert(mutable);
        return;
      } on PostgrestException catch (error) {
        final normalizedMessage = error.message.toLowerCase();
        String? removableColumn;
        for (final column in optionalColumns) {
          if (mutable.containsKey(column) &&
              normalizedMessage.contains(column.toLowerCase())) {
            removableColumn = column;
            break;
          }
        }
        if (removableColumn == null) rethrow;
        mutable.remove(removableColumn);
      }
    }
  }

  Future<_UploadedAsset> _uploadFile({
    required String userId,
    required String baseName,
    required XFile file,
    String? folder,
  }) async {
    final bytes = await file.readAsBytes();
    final ext = _extensionFromPath(file.path);
    final storagePath =
        '${folder ?? storageFolder}/$userId/${baseName}_${DateTime.now().millisecondsSinceEpoch}.$ext';

    await _supabase.storage
        .from(storageBucket)
        .uploadBinary(
          storagePath,
          Uint8List.fromList(bytes),
          fileOptions: FileOptions(
            contentType: _contentTypeForExtension(ext),
            upsert: true,
          ),
        );

    final publicUrl = _supabase.storage
        .from(storageBucket)
        .getPublicUrl(storagePath);
    return _UploadedAsset(storagePath: storagePath, publicUrl: publicUrl);
  }

  Future<void> _deleteStorageObjectIfPossible(String publicUrl) async {
    final storagePath = _extractStoragePath(publicUrl);
    if (storagePath == null || storagePath.isEmpty) return;
    try {
      await _supabase.storage.from(storageBucket).remove([storagePath]);
    } catch (_) {
      // Best-effort cleanup only.
    }
  }

  String? _extractStoragePath(String publicUrl) {
    final marker = '/object/public/$storageBucket/';
    final index = publicUrl.indexOf(marker);
    if (index == -1) return null;
    return publicUrl.substring(index + marker.length);
  }

  String _extensionFromPath(String path) {
    final segments = path.split('.');
    if (segments.length < 2) return 'jpg';
    final ext = segments.last.trim().toLowerCase();
    if (ext.isEmpty) return 'jpg';
    return ext;
  }

  String _contentTypeForExtension(String ext) {
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'pdf':
        return 'application/pdf';
      default:
        return 'image/jpeg';
    }
  }

  String? _nullableText(String? value) {
    final trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String? _dateOnlyString(DateTime? value) {
    if (value == null) return null;
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }
}

class _UploadedAsset {
  const _UploadedAsset({required this.storagePath, required this.publicUrl});

  final String storagePath;
  final String publicUrl;
}


