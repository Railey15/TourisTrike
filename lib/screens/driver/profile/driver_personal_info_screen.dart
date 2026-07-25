import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_scaffold.dart';

class DriverPersonalInfoScreen extends StatefulWidget {
  const DriverPersonalInfoScreen({
    super.key,
    required this.bundle,
    this.flowStep,
  });

  final DriverProfileBundle bundle;
  final DriverProfileStep? flowStep;

  @override
  State<DriverPersonalInfoScreen> createState() =>
      _DriverPersonalInfoScreenState();
}

class _DriverPersonalInfoScreenState extends State<DriverPersonalInfoScreen> {
  final DriverProfileService _service = DriverProfileService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _fullNameController;
  late final TextEditingController _mobileController;
  late final TextEditingController _addressController;
  late final TextEditingController _barangayController;
  late final TextEditingController _municipalityController;
  late final TextEditingController _provinceController;

  DateTime? _selectedBirthdate;
  bool _saving = false;
  bool _uploadingPhoto = false;
  String _photoUrl = '';

  String get _userId => widget.bundle.profile.id;

  @override
  void initState() {
    super.initState();
    final profile = widget.bundle.profile;
    _firstNameController = TextEditingController(text: profile.firstName);
    _middleNameController = TextEditingController(text: profile.middleName);
    _lastNameController = TextEditingController(text: profile.lastName);
    _fullNameController = TextEditingController(text: profile.fullName);
    _mobileController = TextEditingController(text: profile.mobile);
    _addressController = TextEditingController(text: profile.address);
    _barangayController = TextEditingController(text: profile.barangay);
    _municipalityController = TextEditingController(
      text: profile.effectiveMunicipality,
    );
    _provinceController = TextEditingController(text: profile.province);
    _selectedBirthdate = profile.birthdate;
    _photoUrl = profile.effectivePhotoUrl;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _fullNameController.dispose();
    _mobileController.dispose();
    _addressController.dispose();
    _barangayController.dispose();
    _municipalityController.dispose();
    _provinceController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate:
          _selectedBirthdate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1950, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
    );

    if (picked == null || !mounted) return;
    setState(() => _selectedBirthdate = picked);
  }

  Future<void> _pickProfilePhoto() async {
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) =>
          _ImageSourceSheet(allowRemove: _photoUrl.trim().isNotEmpty),
    );

    if (action == null) return;
    if (action == _PhotoAction.gallery || action == _PhotoAction.camera) {
      final file = await _service.pickImage(
        source: action == _PhotoAction.gallery
            ? ImageSource.gallery
            : ImageSource.camera,
      );
      if (file == null) return;

      if (mounted) {
        setState(() => _uploadingPhoto = true);
      }

      try {
        final newUrl = await _service.uploadProfilePhoto(
          userId: _userId,
          file: file,
          previousUrl: _photoUrl,
        );
        if (!mounted) return;
        setState(() {
          _photoUrl = newUrl;
          _uploadingPhoto = false;
        });
        _showSuccess('Profile photo updated.');
      } catch (error) {
        if (!mounted) return;
        setState(() => _uploadingPhoto = false);
        _showError('Failed to upload profile photo: $error');
      }
      return;
    }

    if (action == _PhotoAction.remove) {
      if (mounted) {
        setState(() => _uploadingPhoto = true);
      }
      try {
        await _service.removeProfilePhoto(
          userId: _userId,
          previousUrl: _photoUrl,
        );
        if (!mounted) return;
        setState(() {
          _photoUrl = '';
          _uploadingPhoto = false;
        });
        _showSuccess('Profile photo removed.');
      } catch (error) {
        if (!mounted) return;
        setState(() => _uploadingPhoto = false);
        _showError('Failed to remove profile photo: $error');
      }
    }
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    if (_selectedBirthdate == null) {
      _showError('Please select your birthdate.');
      return;
    }
    if (_photoUrl.trim().isEmpty) {
      _showError('Please upload a profile photo before continuing.');
      return;
    }

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      await _service.savePersonalInfo(
        userId: _userId,
        firstName: _firstNameController.text,
        middleName: _middleNameController.text,
        lastName: _lastNameController.text,
        fullName: _fullNameController.text,
        mobile: _mobileController.text,
        address: _addressController.text,
        barangay: _barangayController.text,
        municipality: _municipalityController.text,
        province: _provinceController.text,
        birthdate: _selectedBirthdate,
      );

      if (!mounted) return;
      setState(() => _saving = false);
      _showSuccess('Personal information saved.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Failed to save personal information: $error');
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

  String get _birthdateLabel {
    if (_selectedBirthdate == null) return 'Select birthdate';
    return DateFormat.yMMMMd().format(_selectedBirthdate!);
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.bundle.profile;

    return DriverProfilePageScaffold(
      title: 'Personal Info',
      subtitle: widget.flowStep == null
          ? 'Update your driver identity, contact details, and address.'
          : 'Step 1 of 8: complete your personal information.',
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
              child: Row(
                children: [
                  _PhotoPreview(
                    photoUrl: _photoUrl,
                    name: profile.displayName,
                    uploading: _uploadingPhoto,
                    onTap: _pickProfilePhoto,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Profile Photo',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Upload a clear photo for your driver profile. This is required to complete onboarding.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DriverSecondaryButton(
                          label: _photoUrl.trim().isEmpty
                              ? 'Upload Photo'
                              : 'Change Photo',
                          onPressed: _uploadingPhoto ? null : _pickProfilePhoto,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            DriverProfileCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DriverSectionTitle('Account'),
                  const SizedBox(height: 14),
                  DriverReadOnlyField(
                    label: 'Email',
                    value: _service.currentUser?.email ?? 'No email available',
                  ),
                  const SizedBox(height: 12),
                  DriverReadOnlyField(label: 'Role', value: profile.role),
                ],
              ),
            ),
            const SizedBox(height: 14),
            DriverProfileCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DriverSectionTitle('Basic Details'),
                  const SizedBox(height: 14),
                  DriverTextField(
                    controller: _firstNameController,
                    label: 'First Name',
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  DriverTextField(
                    controller: _middleNameController,
                    label: 'Middle Name',
                  ),
                  const SizedBox(height: 12),
                  DriverTextField(
                    controller: _lastNameController,
                    label: 'Last Name',
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  DriverTextField(
                    controller: _fullNameController,
                    label: 'Full Name',
                    hintText: 'Leave blank to auto-build from your name fields',
                  ),
                  const SizedBox(height: 12),
                  DriverTextField(
                    controller: _mobileController,
                    label: 'Phone Number',
                    keyboardType: TextInputType.phone,
                    validator: _phoneValidator,
                  ),
                  const SizedBox(height: 12),
                  DriverReadOnlyField(
                    label: 'Birthdate',
                    value: _birthdateLabel,
                    onTap: _pickBirthdate,
                    trailingIcon: Icons.calendar_month_rounded,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            DriverProfileCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DriverSectionTitle('Address'),
                  const SizedBox(height: 14),
                  DriverTextField(
                    controller: _addressController,
                    label: 'Street Address',
                    maxLines: 2,
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  DriverTextField(
                    controller: _barangayController,
                    label: 'Barangay',
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  DriverTextField(
                    controller: _municipalityController,
                    label: 'Municipality',
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  DriverTextField(
                    controller: _provinceController,
                    label: 'Province',
                    validator: _requiredValidator,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  String? _phoneValidator(String? value) {
    final normalized = (value ?? '').trim();
    if (normalized.isEmpty) return 'This field is required.';
    if (!RegExp(r'^09\d{9}$').hasMatch(normalized)) {
      return 'Use an 11-digit number starting with 09.';
    }
    return null;
  }
}

class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({
    required this.photoUrl,
    required this.name,
    required this.uploading,
    required this.onTap,
  });

  final String photoUrl;
  final String name;
  final bool uploading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0].toUpperCase())
        .join();

    return InkWell(
      onTap: uploading ? null : onTap,
      borderRadius: BorderRadius.circular(24),
      child: Container(
        width: 92,
        height: 92,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(
            colors: [Color(0xFF2A86FF), Color(0xFF60A5FA)],
          ),
          image: photoUrl.trim().isEmpty
              ? null
              : DecorationImage(
                  image: NetworkImage(photoUrl),
                  fit: BoxFit.cover,
                ),
        ),
        child: uploading
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : photoUrl.trim().isNotEmpty
            ? Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    size: 18,
                    color: Color(0xFF2A86FF),
                  ),
                ),
              )
            : Center(
                child: Text(
                  initials.isEmpty ? 'D' : initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 30,
                  ),
                ),
              ),
      ),
    );
  }
}

class _ImageSourceSheet extends StatelessWidget {
  const _ImageSourceSheet({required this.allowRemove});

  final bool allowRemove;

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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: const Icon(Icons.photo_library_rounded),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(context, _PhotoAction.gallery),
          ),
          ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: const Icon(Icons.camera_alt_rounded),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(context, _PhotoAction.camera),
          ),
          if (allowRemove)
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Color(0xFFDC2626),
              ),
              title: const Text(
                'Remove current photo',
                style: TextStyle(color: Color(0xFFDC2626)),
              ),
              onTap: () => Navigator.pop(context, _PhotoAction.remove),
            ),
        ],
      ),
    );
  }
}

enum _PhotoAction { gallery, camera, remove }


