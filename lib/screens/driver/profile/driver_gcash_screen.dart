import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_scaffold.dart';

// TourisTrike does NOT custody funds — GCash-to-GCash direct. Outside AMLA covered-person scope (RA 9160).
// Tourists pay this driver's personal GCash account directly; TourisTrike only
// displays the QR/number and records the payment trail.
class DriverGcashScreen extends StatefulWidget {
  const DriverGcashScreen({super.key, required this.bundle, this.flowStep});

  final DriverProfileBundle bundle;
  final DriverProfileStep? flowStep;

  @override
  State<DriverGcashScreen> createState() => _DriverGcashScreenState();
}

class _DriverGcashScreenState extends State<DriverGcashScreen> {
  final DriverProfileService _service = DriverProfileService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _numberController;
  late final TextEditingController _nameController;
  late String _qrUrl;

  bool _saving = false;
  bool _uploadingQr = false;

  String get _userId => widget.bundle.profile.id;

  @override
  void initState() {
    super.initState();
    final details = widget.bundle.details;
    _numberController = TextEditingController(text: details.gcashNumber);
    _nameController = TextEditingController(text: details.gcashName);
    _qrUrl = details.gcashQrUrl;
  }

  @override
  void dispose() {
    _numberController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _pickQr() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => _QrSourceSheet(hasExisting: _qrUrl.trim().isNotEmpty),
    );
    if (source == null) return;

    final file = await _service.pickImage(source: source);
    if (file == null) return;

    if (mounted) setState(() => _uploadingQr = true);
    try {
      final url = await _service.uploadGcashQr(
        userId: _userId,
        file: file,
        previousUrl: _qrUrl,
      );
      if (!mounted) return;
      setState(() {
        _qrUrl = url;
        _uploadingQr = false;
      });
      _showSuccess('GCash QR uploaded.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingQr = false);
      _showError('Failed to upload QR code: $error');
    }
  }

  Future<void> _removeQr() async {
    if (_qrUrl.trim().isEmpty) return;
    if (mounted) setState(() => _uploadingQr = true);
    try {
      await _service.removeGcashQr(userId: _userId, existingUrl: _qrUrl);
      if (!mounted) return;
      setState(() {
        _qrUrl = '';
        _uploadingQr = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _uploadingQr = false);
      _showError('Failed to remove QR code: $error');
    }
  }

  bool get _hasGcashDetails =>
      _qrUrl.trim().isNotEmpty ||
      (_numberController.text.trim().isNotEmpty &&
          _nameController.text.trim().isNotEmpty);

  Future<void> _save() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;
    if (!_hasGcashDetails) {
      _showError(
        'Upload your GCash QR, or fill in both your GCash number and name.',
      );
      return;
    }

    if (mounted) setState(() => _saving = true);
    try {
      await _service.saveGcashDetails(
        userId: _userId,
        gcashNumber: _numberController.text,
        gcashName: _nameController.text,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      _showSuccess('GCash payment details saved.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Failed to save GCash details: $error');
    }
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
      title: 'GCash Payment Details',
      subtitle: widget.flowStep == null
          ? 'Manage the GCash QR and details tourists use to pay you directly.'
          : 'Step 5 of 8: add your GCash QR and details.',
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: DriverPrimaryButton(
          label: widget.flowStep == null ? 'Save Changes' : 'Save and Continue',
          onPressed: _save,
          loading: _saving,
          icon: Icons.save_rounded,
        ),
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            DriverProfileCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DriverSectionTitle('Your GCash QR Code'),
                  const SizedBox(height: 6),
                  const Text(
                    'Tourists scan this to pay you directly in the GCash app. '
                    'TourisTrike never holds or moves this money.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (_qrUrl.trim().isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(18),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Image.network(
                          _qrUrl,
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
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: DriverPrimaryButton(
                      label: _uploadingQr
                          ? 'Working...'
                          : _qrUrl.trim().isEmpty
                          ? 'Upload QR from GCash App'
                          : 'Replace QR Code',
                      onPressed: _uploadingQr ? null : _pickQr,
                      loading: _uploadingQr,
                      icon: Icons.qr_code_2_rounded,
                    ),
                  ),
                  if (_qrUrl.trim().isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: DriverSecondaryButton(
                        label: 'Remove QR Code',
                        onPressed: _uploadingQr ? null : _removeQr,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            DriverProfileCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DriverSectionTitle('GCash Account Details'),
                  const SizedBox(height: 6),
                  const Text(
                    'Optional if you already uploaded a QR code, but useful as '
                    'a backup so tourists can pay by GCash number too.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DriverTextField(
                    controller: _numberController,
                    label: 'GCash Number',
                    keyboardType: TextInputType.phone,
                    validator: _gcashNumberValidator,
                  ),
                  const SizedBox(height: 12),
                  DriverTextField(
                    controller: _nameController,
                    label: 'GCash Account Name',
                    hintText: 'As shown in your GCash app',
                    validator: _gcashNameValidator,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _gcashNumberValidator(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) return null;
    if (!RegExp(r'^(09|\+639)\d{9}$').hasMatch(normalized)) {
      return 'Use an 11-digit number starting with 09.';
    }
    return null;
  }

  String? _gcashNameValidator(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) return null;
    if (normalized.length < 2) return 'Enter the full account name.';
    return null;
  }
}

class _QrSourceSheet extends StatelessWidget {
  const _QrSourceSheet({required this.hasExisting});

  final bool hasExisting;

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
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: const Icon(Icons.photo_library_rounded),
            title: Text(hasExisting ? 'Replace from gallery' : 'Choose from gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
          ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: const Icon(Icons.camera_alt_rounded),
            title: Text(hasExisting ? 'Retake using camera' : 'Take a photo'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
        ],
      ),
    );
  }
}
