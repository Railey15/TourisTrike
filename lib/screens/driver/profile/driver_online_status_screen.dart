import 'package:flutter/material.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_scaffold.dart';

class DriverOnlineStatusScreen extends StatefulWidget {
  const DriverOnlineStatusScreen({
    super.key,
    required this.bundle,
    this.flowStep,
  });

  final DriverProfileBundle bundle;
  final DriverProfileStep? flowStep;

  @override
  State<DriverOnlineStatusScreen> createState() =>
      _DriverOnlineStatusScreenState();
}

class _DriverOnlineStatusScreenState extends State<DriverOnlineStatusScreen> {
  final DriverProfileService _service = DriverProfileService();

  late bool _isOnline;
  bool _saving = false;

  String get _userId => widget.bundle.profile.id;

  @override
  void initState() {
    super.initState();
    _isOnline = widget.bundle.profile.isOnline;
  }

  Future<void> _save() async {
    if (_saving) return;

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      await _service.saveOnlineStatus(userId: _userId, isOnline: _isOnline);

      if (!mounted) return;
      setState(() => _saving = false);
      _showSuccess(
        _isOnline
            ? 'Driver status set to online.'
            : 'Driver status set to offline.',
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Failed to update online status: $error');
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
    final statusColor = _isOnline
        ? const Color(0xFF16A34A)
        : const Color(0xFF64748B);

    return DriverProfilePageScaffold(
      title: 'Online Status',
      subtitle: widget.flowStep == null
          ? 'Choose whether you are currently available for bookings.'
          : 'Step 7 of 7: choose your online availability.',
      bottomBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: DriverPrimaryButton(
          label: widget.flowStep == null ? 'Save Changes' : 'Finish Setup',
          onPressed: _save,
          loading: _saving,
          icon: Icons.circle_rounded,
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
        children: [
          DriverProfileCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const DriverSectionTitle('Availability'),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Icon(Icons.circle_rounded, color: statusColor),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isOnline ? 'You are online' : 'You are offline',
                            style: const TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Online drivers can receive work when the rest of their account is approved.',
                            style: TextStyle(
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isOnline,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _isOnline = value),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}


