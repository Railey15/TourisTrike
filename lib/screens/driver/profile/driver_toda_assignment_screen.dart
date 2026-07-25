import 'package:flutter/material.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_scaffold.dart';

class DriverTodaAssignmentScreen extends StatefulWidget {
  const DriverTodaAssignmentScreen({
    super.key,
    required this.bundle,
    this.flowStep,
  });

  final DriverProfileBundle bundle;
  final DriverProfileStep? flowStep;

  @override
  State<DriverTodaAssignmentScreen> createState() =>
      _DriverTodaAssignmentScreenState();
}

class _DriverTodaAssignmentScreenState
    extends State<DriverTodaAssignmentScreen> {
  final DriverProfileService _service = DriverProfileService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late final TextEditingController _todaController;
  late final TextEditingController _operatorController;
  bool _saving = false;

  String get _userId => widget.bundle.profile.id;

  @override
  void initState() {
    super.initState();
    _todaController = TextEditingController(
      text: widget.bundle.details.todaName,
    );
    _operatorController = TextEditingController(
      text: widget.bundle.details.operatorCode,
    );
  }

  @override
  void dispose() {
    _todaController.dispose();
    _operatorController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      await _service.saveTodaAssignment(
        userId: _userId,
        todaName: _todaController.text,
        operatorCode: _operatorController.text,
      );

      if (!mounted) return;
      setState(() => _saving = false);
      _showSuccess('TODA assignment saved.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Failed to save TODA assignment: $error');
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
      title: 'TODA Assignment',
      subtitle: widget.flowStep == null
          ? 'Update your TODA name and operator code.'
          : 'Step 3 of 8: add your TODA assignment details.',
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: DriverPrimaryButton(
          label: widget.flowStep == null ? 'Save Changes' : 'Save and Continue',
          onPressed: _save,
          loading: _saving,
          icon: Icons.groups_2_rounded,
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
                  const DriverSectionTitle('TODA Details'),
                  const SizedBox(height: 14),
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
}


