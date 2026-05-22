import 'package:flutter/material.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_scaffold.dart';

class DriverPlateNumberScreen extends StatefulWidget {
  const DriverPlateNumberScreen({
    super.key,
    required this.bundle,
    this.flowStep,
  });

  final DriverProfileBundle bundle;
  final DriverProfileStep? flowStep;

  @override
  State<DriverPlateNumberScreen> createState() =>
      _DriverPlateNumberScreenState();
}

class _DriverPlateNumberScreenState extends State<DriverPlateNumberScreen> {
  final DriverProfileService _service = DriverProfileService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _plateController;
  bool _saving = false;

  String get _userId => widget.bundle.profile.id;

  @override
  void initState() {
    super.initState();
    _plateController = TextEditingController(
      text: widget.bundle.details.plateNumber,
    );
  }

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      await _service.savePlateNumber(
        userId: _userId,
        plateNumber: _plateController.text,
      );

      if (!mounted) return;
      setState(() => _saving = false);
      _showSuccess('Plate number saved.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Failed to save plate number: $error');
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
      title: 'Plate Number',
      subtitle: widget.flowStep == null
          ? 'Update your tricycle plate number.'
          : 'Step 4 of 7: add your assigned plate number.',
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: DriverPrimaryButton(
          label: widget.flowStep == null ? 'Save Changes' : 'Save and Continue',
          onPressed: _save,
          loading: _saving,
          icon: Icons.directions_bike_rounded,
        ),
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          children: [
            DriverProfileCard(
              child: DriverTextField(
                controller: _plateController,
                label: 'Plate Number',
                hintText: 'Example: ABC-1234',
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


