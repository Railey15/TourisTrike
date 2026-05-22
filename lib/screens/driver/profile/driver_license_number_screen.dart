import 'package:flutter/material.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_scaffold.dart';

class DriverLicenseNumberScreen extends StatefulWidget {
  const DriverLicenseNumberScreen({super.key, required this.bundle});

  final DriverProfileBundle bundle;

  @override
  State<DriverLicenseNumberScreen> createState() =>
      _DriverLicenseNumberScreenState();
}

class _DriverLicenseNumberScreenState extends State<DriverLicenseNumberScreen> {
  final DriverProfileService _service = DriverProfileService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _licenseController;
  bool _saving = false;

  String get _userId => widget.bundle.profile.id;

  @override
  void initState() {
    super.initState();
    _licenseController = TextEditingController(
      text: widget.bundle.details.licenseNumber,
    );
  }

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      await _service.saveLicenseNumber(
        userId: _userId,
        licenseNumber: _licenseController.text,
      );

      if (!mounted) return;
      setState(() => _saving = false);
      _showSuccess('License number saved.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Failed to save license number: $error');
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
      title: 'License Number',
      subtitle: 'Update the driver license number linked to your profile.',
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: DriverPrimaryButton(
          label: 'Save Changes',
          onPressed: _save,
          loading: _saving,
          icon: Icons.badge_rounded,
        ),
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            DriverProfileCard(
              child: DriverTextField(
                controller: _licenseController,
                label: 'License Number',
                validator: _requiredValidator,
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
}


