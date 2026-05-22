import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_scaffold.dart';

class DriverDocumentsScreen extends StatefulWidget {
  const DriverDocumentsScreen({super.key, required this.bundle, this.flowStep});

  final DriverProfileBundle bundle;
  final DriverProfileStep? flowStep;

  @override
  State<DriverDocumentsScreen> createState() => _DriverDocumentsScreenState();
}

class _DriverDocumentsScreenState extends State<DriverDocumentsScreen> {
  final DriverProfileService _service = DriverProfileService();

  late DriverDocumentsRecord _documents;
  DriverDocumentType? _busyType;
  bool _working = false;

  String get _userId => widget.bundle.profile.id;

  @override
  void initState() {
    super.initState();
    _documents = widget.bundle.documents;
  }

  Future<void> _handleDocument(DriverDocumentType type) async {
    final currentUrl = _documents.urlFor(type);
    final action = await showModalBottomSheet<_DocumentAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _DocumentActionSheet(hasExistingFile: currentUrl.trim().isNotEmpty),
    );

    if (action == null) return;

    if (action == _DocumentAction.preview && currentUrl.trim().isNotEmpty) {
      await _showPreview(type.label, currentUrl);
      return;
    }

    if (action == _DocumentAction.remove && currentUrl.trim().isNotEmpty) {
      await _deleteDocument(type, currentUrl);
      return;
    }

    final source = action == _DocumentAction.camera
        ? ImageSource.camera
        : ImageSource.gallery;
    final file = await _service.pickImage(source: source);
    if (file == null) return;

    if (mounted) {
      setState(() {
        _busyType = type;
        _working = true;
      });
    }

    try {
      final newUrl = await _service.uploadDocument(
        userId: _userId,
        type: type,
        file: file,
        previousUrl: currentUrl,
      );

      if (!mounted) return;
      setState(() {
        _documents = _replaceDocumentUrl(_documents, type, newUrl);
        _busyType = null;
        _working = false;
      });
      _showSuccess('${type.label} uploaded successfully.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyType = null;
        _working = false;
      });
      _showError('Failed to upload ${type.label.toLowerCase()}: $error');
    }
  }

  Future<void> _deleteDocument(
    DriverDocumentType type,
    String currentUrl,
  ) async {
    if (mounted) {
      setState(() {
        _busyType = type;
        _working = true;
      });
    }

    try {
      await _service.deleteDocument(
        userId: _userId,
        type: type,
        existingUrl: currentUrl,
      );

      if (!mounted) return;
      setState(() {
        _documents = _replaceDocumentUrl(_documents, type, '');
        _busyType = null;
        _working = false;
      });
      _showSuccess('${type.label} removed.');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busyType = null;
        _working = false;
      });
      _showError('Failed to remove ${type.label.toLowerCase()}: $error');
    }
  }

  DriverDocumentsRecord _replaceDocumentUrl(
    DriverDocumentsRecord record,
    DriverDocumentType type,
    String newUrl,
  ) {
    switch (type) {
      case DriverDocumentType.selfie:
        return DriverDocumentsRecord(
          driverId: record.driverId,
          selfieUrl: newUrl,
          licenseFrontUrl: record.licenseFrontUrl,
          licenseBackUrl: record.licenseBackUrl,
          policeClearanceUrl: record.policeClearanceUrl,
          mtopUrl: record.mtopUrl,
          vehicleFrontUrl: record.vehicleFrontUrl,
          vehicleBackUrl: record.vehicleBackUrl,
          vehicleLeftUrl: record.vehicleLeftUrl,
          vehicleRightUrl: record.vehicleRightUrl,
          orUrl: record.orUrl,
          crUrl: record.crUrl,
        );
      case DriverDocumentType.licenseFront:
        return DriverDocumentsRecord(
          driverId: record.driverId,
          selfieUrl: record.selfieUrl,
          licenseFrontUrl: newUrl,
          licenseBackUrl: record.licenseBackUrl,
          policeClearanceUrl: record.policeClearanceUrl,
          mtopUrl: record.mtopUrl,
          vehicleFrontUrl: record.vehicleFrontUrl,
          vehicleBackUrl: record.vehicleBackUrl,
          vehicleLeftUrl: record.vehicleLeftUrl,
          vehicleRightUrl: record.vehicleRightUrl,
          orUrl: record.orUrl,
          crUrl: record.crUrl,
        );
      case DriverDocumentType.licenseBack:
        return DriverDocumentsRecord(
          driverId: record.driverId,
          selfieUrl: record.selfieUrl,
          licenseFrontUrl: record.licenseFrontUrl,
          licenseBackUrl: newUrl,
          policeClearanceUrl: record.policeClearanceUrl,
          mtopUrl: record.mtopUrl,
          vehicleFrontUrl: record.vehicleFrontUrl,
          vehicleBackUrl: record.vehicleBackUrl,
          vehicleLeftUrl: record.vehicleLeftUrl,
          vehicleRightUrl: record.vehicleRightUrl,
          orUrl: record.orUrl,
          crUrl: record.crUrl,
        );
      case DriverDocumentType.policeClearance:
        return DriverDocumentsRecord(
          driverId: record.driverId,
          selfieUrl: record.selfieUrl,
          licenseFrontUrl: record.licenseFrontUrl,
          licenseBackUrl: record.licenseBackUrl,
          policeClearanceUrl: newUrl,
          mtopUrl: record.mtopUrl,
          vehicleFrontUrl: record.vehicleFrontUrl,
          vehicleBackUrl: record.vehicleBackUrl,
          vehicleLeftUrl: record.vehicleLeftUrl,
          vehicleRightUrl: record.vehicleRightUrl,
          orUrl: record.orUrl,
          crUrl: record.crUrl,
        );
      case DriverDocumentType.mtop:
        return DriverDocumentsRecord(
          driverId: record.driverId,
          selfieUrl: record.selfieUrl,
          licenseFrontUrl: record.licenseFrontUrl,
          licenseBackUrl: record.licenseBackUrl,
          policeClearanceUrl: record.policeClearanceUrl,
          mtopUrl: newUrl,
          vehicleFrontUrl: record.vehicleFrontUrl,
          vehicleBackUrl: record.vehicleBackUrl,
          vehicleLeftUrl: record.vehicleLeftUrl,
          vehicleRightUrl: record.vehicleRightUrl,
          orUrl: record.orUrl,
          crUrl: record.crUrl,
        );
      case DriverDocumentType.vehicleFront:
        return DriverDocumentsRecord(
          driverId: record.driverId,
          selfieUrl: record.selfieUrl,
          licenseFrontUrl: record.licenseFrontUrl,
          licenseBackUrl: record.licenseBackUrl,
          policeClearanceUrl: record.policeClearanceUrl,
          mtopUrl: record.mtopUrl,
          vehicleFrontUrl: newUrl,
          vehicleBackUrl: record.vehicleBackUrl,
          vehicleLeftUrl: record.vehicleLeftUrl,
          vehicleRightUrl: record.vehicleRightUrl,
          orUrl: record.orUrl,
          crUrl: record.crUrl,
        );
      case DriverDocumentType.vehicleBack:
        return DriverDocumentsRecord(
          driverId: record.driverId,
          selfieUrl: record.selfieUrl,
          licenseFrontUrl: record.licenseFrontUrl,
          licenseBackUrl: record.licenseBackUrl,
          policeClearanceUrl: record.policeClearanceUrl,
          mtopUrl: record.mtopUrl,
          vehicleFrontUrl: record.vehicleFrontUrl,
          vehicleBackUrl: newUrl,
          vehicleLeftUrl: record.vehicleLeftUrl,
          vehicleRightUrl: record.vehicleRightUrl,
          orUrl: record.orUrl,
          crUrl: record.crUrl,
        );
      case DriverDocumentType.vehicleLeft:
        return DriverDocumentsRecord(
          driverId: record.driverId,
          selfieUrl: record.selfieUrl,
          licenseFrontUrl: record.licenseFrontUrl,
          licenseBackUrl: record.licenseBackUrl,
          policeClearanceUrl: record.policeClearanceUrl,
          mtopUrl: record.mtopUrl,
          vehicleFrontUrl: record.vehicleFrontUrl,
          vehicleBackUrl: record.vehicleBackUrl,
          vehicleLeftUrl: newUrl,
          vehicleRightUrl: record.vehicleRightUrl,
          orUrl: record.orUrl,
          crUrl: record.crUrl,
        );
      case DriverDocumentType.vehicleRight:
        return DriverDocumentsRecord(
          driverId: record.driverId,
          selfieUrl: record.selfieUrl,
          licenseFrontUrl: record.licenseFrontUrl,
          licenseBackUrl: record.licenseBackUrl,
          policeClearanceUrl: record.policeClearanceUrl,
          mtopUrl: record.mtopUrl,
          vehicleFrontUrl: record.vehicleFrontUrl,
          vehicleBackUrl: record.vehicleBackUrl,
          vehicleLeftUrl: record.vehicleLeftUrl,
          vehicleRightUrl: newUrl,
          orUrl: record.orUrl,
          crUrl: record.crUrl,
        );
      case DriverDocumentType.orDocument:
        return DriverDocumentsRecord(
          driverId: record.driverId,
          selfieUrl: record.selfieUrl,
          licenseFrontUrl: record.licenseFrontUrl,
          licenseBackUrl: record.licenseBackUrl,
          policeClearanceUrl: record.policeClearanceUrl,
          mtopUrl: record.mtopUrl,
          vehicleFrontUrl: record.vehicleFrontUrl,
          vehicleBackUrl: record.vehicleBackUrl,
          vehicleLeftUrl: record.vehicleLeftUrl,
          vehicleRightUrl: record.vehicleRightUrl,
          orUrl: newUrl,
          crUrl: record.crUrl,
        );
      case DriverDocumentType.crDocument:
        return DriverDocumentsRecord(
          driverId: record.driverId,
          selfieUrl: record.selfieUrl,
          licenseFrontUrl: record.licenseFrontUrl,
          licenseBackUrl: record.licenseBackUrl,
          policeClearanceUrl: record.policeClearanceUrl,
          mtopUrl: record.mtopUrl,
          vehicleFrontUrl: record.vehicleFrontUrl,
          vehicleBackUrl: record.vehicleBackUrl,
          vehicleLeftUrl: record.vehicleLeftUrl,
          vehicleRightUrl: record.vehicleRightUrl,
          orUrl: record.orUrl,
          crUrl: newUrl,
        );
    }
  }

  Future<void> _showPreview(String title, String url) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Image.network(
                      url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                        color: const Color(0xFFF8FAFC),
                        alignment: Alignment.center,
                        child: const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            'Preview unavailable for this file.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: DriverSecondaryButton(
                    label: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSuccess(String message) => _showSnack(message, isError: false);

  void _showError(String message) => _showSnack(message, isError: true);

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return DriverProfilePageScaffold(
      title: 'Driver Documents',
      subtitle: widget.flowStep == null
          ? 'Upload and manage the required driver documents.'
          : 'Step 6 of 7: upload all required driver documents.',
      bottomBar: widget.flowStep == null
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: DriverPrimaryButton(
                label: _documents.isDocumentsStepComplete
                    ? 'Continue to Final Step'
                    : 'Upload Required Documents',
                onPressed: _documents.isDocumentsStepComplete
                    ? () => Navigator.of(context).pop(true)
                    : null,
                icon: Icons.folder_open_rounded,
              ),
            ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          DriverProfileCard(
            child: DriverProgressBar(
              progress: _documents.totalCount == 0
                  ? 0
                  : _documents.uploadedCount / _documents.totalCount,
              label: 'Documents uploaded',
              trailing: '${_documents.uploadedCount}/${_documents.totalCount}',
            ),
          ),
          const SizedBox(height: 14),
          ...DriverDocumentType.values.map((type) {
            final url = _documents.urlFor(type);
            final uploaded = url.trim().isNotEmpty;
            final busy = _working && _busyType == type;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DriverProfileCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: uploaded
                                ? const Color(0xFFDCFCE7)
                                : const Color(0xFFEAF2FF),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Icon(
                            uploaded ? Icons.check_circle_rounded : type.icon,
                            color: uploaded
                                ? const Color(0xFF16A34A)
                                : const Color(0xFF2A86FF),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                type.label,
                                style: const TextStyle(
                                  color: Color(0xFF0F172A),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                uploaded
                                    ? 'Uploaded to Supabase Storage. You can preview, replace, or delete this file.'
                                    : 'No file uploaded yet. Add this document to complete the driver profile.',
                                style: const TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w700,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (uploaded) ...[
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: AspectRatio(
                          aspectRatio: 16 / 9,
                          child: Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Container(
                              color: const Color(0xFFF8FAFC),
                              alignment: Alignment.center,
                              child: const Text(
                                'Preview unavailable',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: DriverPrimaryButton(
                        label: busy
                            ? 'Working...'
                            : uploaded
                            ? 'Manage File'
                            : 'Upload File',
                        onPressed: busy ? null : () => _handleDocument(type),
                        loading: busy,
                        icon: uploaded
                            ? Icons.refresh_rounded
                            : Icons.upload_rounded,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

enum _DocumentAction { gallery, camera, preview, remove }

class _DocumentActionSheet extends StatelessWidget {
  const _DocumentActionSheet({required this.hasExistingFile});

  final bool hasExistingFile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 14),
          if (hasExistingFile)
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: const Icon(Icons.visibility_outlined),
              title: const Text('Preview file'),
              onTap: () => Navigator.pop(context, _DocumentAction.preview),
            ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: const Icon(Icons.photo_library_rounded),
            title: Text(
              hasExistingFile ? 'Replace from gallery' : 'Choose from gallery',
            ),
            onTap: () => Navigator.pop(context, _DocumentAction.gallery),
          ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: const Icon(Icons.camera_alt_rounded),
            title: Text(
              hasExistingFile ? 'Retake using camera' : 'Take a photo',
            ),
            onTap: () => Navigator.pop(context, _DocumentAction.camera),
          ),
          if (hasExistingFile)
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFDC2626),
              ),
              title: const Text(
                'Delete current file',
                style: TextStyle(color: Color(0xFFDC2626)),
              ),
              onTap: () => Navigator.pop(context, _DocumentAction.remove),
            ),
        ],
      ),
    );
  }
}


