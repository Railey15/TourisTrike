import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_scaffold.dart';

class DriverLicenseExpiryScreen extends StatefulWidget {
  const DriverLicenseExpiryScreen({
    super.key,
    required this.bundle,
    this.flowStep,
  });

  final DriverProfileBundle bundle;
  final DriverProfileStep? flowStep;

  @override
  State<DriverLicenseExpiryScreen> createState() =>
      _DriverLicenseExpiryScreenState();
}

class _DriverLicenseExpiryScreenState extends State<DriverLicenseExpiryScreen> {
  final DriverProfileService _service = DriverProfileService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _licenseController;

  DateTime? _selectedExpiry;
  bool _saving = false;

  String get _userId => widget.bundle.profile.id;

  @override
  void initState() {
    super.initState();
    _licenseController = TextEditingController(
      text: widget.bundle.details.licenseNumber,
    );
    _selectedExpiry = widget.bundle.details.licenseExpiry;
  }

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 1, 1, 1),
      lastDate: DateTime(now.year + 20, 12, 31),
      initialDate:
          _selectedExpiry ?? DateTime(now.year + 1, now.month, now.day),
    );

    if (picked == null || !mounted) return;
    setState(() => _selectedExpiry = picked);
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    if (_selectedExpiry == null) {
      _showError('Please select your license expiry date.');
      return;
    }

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      await _service.saveDriverDetails(
        userId: _userId,
        licenseNumber: _licenseController.text,
        licenseExpiry: _selectedExpiry,
      );

      if (!mounted) return;
      setState(() => _saving = false);
      _showSuccess('License information saved.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Failed to save license information: $error');
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
    final expiryLabel = _selectedExpiry == null
        ? 'Select expiry date'
        : DateFormat('MMMM dd, yyyy').format(_selectedExpiry!);

    return DriverProfilePageScaffold(
      title: 'License Information',
      subtitle: widget.flowStep == null
          ? 'Update your driver license number and expiry date.'
          : 'Step 2 of 7: add your license information.',
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: DriverPrimaryButton(
          label: widget.flowStep == null ? 'Save Changes' : 'Save and Continue',
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const DriverSectionTitle('License Details'),
                  const SizedBox(height: 14),
                  DriverTextField(
                    controller: _licenseController,
                    label: 'License Number',
                    hintText: 'Enter your driver license number',
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  DriverReadOnlyField(
                    label: 'License Expiry',
                    value: expiryLabel,
                    onTap: _pickExpiry,
                    trailingIcon: Icons.calendar_month_rounded,
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
}


