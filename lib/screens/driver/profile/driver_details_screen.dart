import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_scaffold.dart';

class DriverDetailsScreen extends StatefulWidget {
  const DriverDetailsScreen({super.key, required this.bundle, this.flowStep});

  final DriverProfileBundle bundle;
  final DriverProfileStep? flowStep;

  @override
  State<DriverDetailsScreen> createState() => _DriverDetailsScreenState();
}

class _DriverDetailsScreenState extends State<DriverDetailsScreen> {
  final DriverProfileService _service = DriverProfileService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _mobileController;
  late final TextEditingController _licenseController;
  late final TextEditingController _plateController;
  late final TextEditingController _todaController;
  late final TextEditingController _operatorController;

  DateTime? _selectedExpiry;
  bool _saving = false;

  String get _userId => widget.bundle.profile.id;

  @override
  void initState() {
    super.initState();
    final details = widget.bundle.details;
    _mobileController = TextEditingController(
      text: details.mobile.isNotEmpty
          ? details.mobile
          : widget.bundle.profile.mobile,
    );
    _licenseController = TextEditingController(text: details.licenseNumber);
    _plateController = TextEditingController(text: details.plateNumber);
    _todaController = TextEditingController(text: details.todaName);
    _operatorController = TextEditingController(text: details.operatorCode);
    _selectedExpiry = details.licenseExpiry;
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _licenseController.dispose();
    _plateController.dispose();
    _todaController.dispose();
    _operatorController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
      initialDate: _selectedExpiry ?? DateTime.now(),
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
        mobile: _mobileController.text,
        licenseNumber: _licenseController.text,
        licenseExpiry: _selectedExpiry,
        todaName: _todaController.text,
        operatorCode: _operatorController.text,
        plateNumber: _plateController.text,
      );

      if (!mounted) return;
      setState(() => _saving = false);
      _showSuccess('Driver details saved.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Failed to save driver details: $error');
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
      title: 'Driver Details',
      subtitle: widget.flowStep == null
          ? 'Manage your mobile number, license, plate, and TODA details.'
          : 'Fill out all driver details before proceeding.',
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
                  const DriverSectionTitle('Driver Details'),
                  const SizedBox(height: 14),
                  DriverTextField(
                    controller: _mobileController,
                    label: 'Phone Number',
                    keyboardType: TextInputType.phone,
                    validator: _phoneValidator,
                  ),
                  const SizedBox(height: 12),
                  DriverTextField(
                    controller: _licenseController,
                    label: 'License Number',
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  DriverReadOnlyField(
                    label: 'License Expiry',
                    value: _selectedExpiry == null
                        ? 'Select expiry date'
                        : DateFormat('MMMM dd, yyyy').format(_selectedExpiry!),
                    onTap: _pickExpiry,
                    trailingIcon: Icons.calendar_month_rounded,
                  ),
                  const SizedBox(height: 12),
                  DriverTextField(
                    controller: _plateController,
                    label: 'Plate Number',
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  DriverTextField(
                    controller: _todaController,
                    label: 'TODA Assignment',
                    hintText: 'Example: San Miguel TODA',
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  DriverTextField(
                    controller: _operatorController,
                    label: 'Operator Code',
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


