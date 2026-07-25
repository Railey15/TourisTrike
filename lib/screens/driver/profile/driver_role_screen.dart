import 'package:flutter/material.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_scaffold.dart';

class DriverRoleScreen extends StatefulWidget {
  const DriverRoleScreen({super.key, required this.bundle, this.flowStep});

  final DriverProfileBundle bundle;
  final DriverProfileStep? flowStep;

  @override
  State<DriverRoleScreen> createState() => _DriverRoleScreenState();
}

class _DriverRoleScreenState extends State<DriverRoleScreen> {
  final DriverProfileService _service = DriverProfileService();
  bool _saving = false;

  String get _userId => widget.bundle.profile.id;

  Future<void> _save() async {
    if (_saving) return;

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      await _service.saveRoleSelection(_userId);

      if (!mounted) return;
      setState(() => _saving = false);
      _showSuccess('Driver role confirmed.');
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Failed to confirm driver role: $error');
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
      title: 'Role Selection',
      subtitle: widget.flowStep == null
          ? 'Review the role attached to your driver account.'
          : 'Step 6 of 8: confirm your driver role.',
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: DriverPrimaryButton(
          label: widget.flowStep == null ? 'Confirm Role' : 'Save and Continue',
          onPressed: _save,
          loading: _saving,
          icon: Icons.verified_user_rounded,
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          DriverProfileCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.verified_user_rounded,
                    color: Color(0xFF2A86FF),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Driver Account',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'This flow is intended for drivers. Confirming this step saves the role as driver in your profile record.',
                        style: TextStyle(
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
          ),
        ],
      ),
    );
  }
}


