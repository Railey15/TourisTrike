import 'package:flutter/material.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';
import 'package:touristrike/screens/driver/profile/driver_documents_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_gcash_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_license_expiry_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_online_status_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_personal_info_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_plate_number_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_role_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_toda_assignment_screen.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_scaffold.dart';
import 'package:touristrike/screens/driver/driver_home_screen.dart';

class DriverProfileCompletionScreen extends StatefulWidget {
  const DriverProfileCompletionScreen({super.key, this.finishToHome = true});

  final bool finishToHome;

  @override
  State<DriverProfileCompletionScreen> createState() =>
      _DriverProfileCompletionScreenState();
}

class _DriverProfileCompletionScreenState
    extends State<DriverProfileCompletionScreen> {
  final DriverProfileService _service = DriverProfileService();
  bool _navigating = false;

  String? get _userId => _service.currentUserId;

  Future<void> _openStep(
    DriverProfileStep step,
    DriverProfileBundle bundle,
  ) async {
    if (_navigating) return;
    setState(() => _navigating = true);

    final screen = _screenForStep(step, bundle);

    final completed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => screen),
    );

    if (!mounted) return;
    setState(() => _navigating = false);

    final userId = _userId;
    if (userId == null || completed != true) return;

    final refreshed = await _service.fetchProfileBundle(userId);
    if (!mounted) return;

    if (refreshed.isFullyComplete) {
      if (widget.finishToHome) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
          (route) => false,
        );
      }
      return;
    }

    if (!refreshed.isStepComplete(step)) return;

    final nextStep = refreshed.nextIncompleteStep;
    if (nextStep.index <= step.index) return;

    await _openStep(nextStep, refreshed);
  }

  Widget _screenForStep(DriverProfileStep step, DriverProfileBundle bundle) {
    switch (step) {
      case DriverProfileStep.personalInfo:
        return DriverPersonalInfoScreen(bundle: bundle, flowStep: step);
      case DriverProfileStep.licenseInformation:
        return DriverLicenseExpiryScreen(bundle: bundle, flowStep: step);
      case DriverProfileStep.todaAssignment:
        return DriverTodaAssignmentScreen(bundle: bundle, flowStep: step);
      case DriverProfileStep.plateNumber:
        return DriverPlateNumberScreen(bundle: bundle, flowStep: step);
      case DriverProfileStep.gcashPayment:
        return DriverGcashScreen(bundle: bundle, flowStep: step);
      case DriverProfileStep.roleSelection:
        return DriverRoleScreen(bundle: bundle, flowStep: step);
      case DriverProfileStep.documentsUpload:
        return DriverDocumentsScreen(bundle: bundle, flowStep: step);
      case DriverProfileStep.onlineStatus:
        return DriverOnlineStatusScreen(bundle: bundle, flowStep: step);
    }
  }

  bool _canOpenStep(DriverProfileBundle bundle, DriverProfileStep step) {
    final currentIndex = bundle.nextIncompleteStep.index;
    return step.index <= currentIndex;
  }

  @override
  Widget build(BuildContext context) {
    final userId = _userId;
    if (userId == null) {
      return DriverProfilePageScaffold(
        title: 'Driver Profile Setup',
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DriverEmptyState(
            icon: Icons.lock_outline_rounded,
            title: 'Session Expired',
            message:
                'Please log in again to continue your driver profile setup.',
            action: DriverPrimaryButton(
              label: 'Back to Login',
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
        ),
      );
    }

    return DriverProfilePageScaffold(
      title: 'Driver Profile Setup',
      subtitle: 'Complete each step to finish your driver profile.',
      child: StreamBuilder<DriverProfileBundle>(
        stream: _service.watchProfileBundle(userId),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: DriverEmptyState(
                icon: Icons.error_outline_rounded,
                title: 'Unable to load setup flow',
                message: '${snapshot.error}',
                action: DriverPrimaryButton(
                  label: 'Retry',
                  onPressed: () => setState(() {}),
                ),
              ),
            );
          }

          if (!snapshot.hasData) {
            return const DriverLoadingView(message: 'Loading driver setup...');
          }

          final bundle = snapshot.data!;
          final nextStep = bundle.nextIncompleteStep;

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
            children: [
              DriverProfileSummaryCard(
                name: bundle.profile.displayName,
                subtitle: bundle.profile.locationSummary,
                photoUrl: bundle.profile.effectivePhotoUrl,
                completionPercent: bundle.completionPercent,
                progressLabel: bundle.isFullyComplete
                    ? 'Profile setup complete'
                    : 'Complete all 8 driver profile steps',
              ),
              const SizedBox(height: 14),
              DriverProfileCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DriverSectionTitle('Setup Steps'),
                    const SizedBox(height: 10),
                    ...DriverProfileStep.values.asMap().entries.map((entry) {
                      final step = entry.value;
                      final enabled = _canOpenStep(bundle, step);
                      return Column(
                        children: [
                          Opacity(
                            opacity: enabled ? 1 : 0.45,
                            child: DriverStepTile(
                              step: step,
                              isComplete: bundle.isStepComplete(step),
                              isCurrent:
                                  !bundle.isStepComplete(step) &&
                                  step == nextStep,
                              onTap: enabled
                                  ? () => _openStep(step, bundle)
                                  : () {},
                            ),
                          ),
                          if (entry.key != DriverProfileStep.values.length - 1)
                            const Divider(height: 1, color: Color(0xFFEFF4FA)),
                        ],
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              DriverProfileCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const DriverSectionTitle('Next Action'),
                    const SizedBox(height: 10),
                    Text(
                      bundle.isFullyComplete
                          ? 'Your driver profile is ready. You can go to the driver home screen now.'
                          : 'Continue with ${nextStep.title}. You need to finish the current step before moving forward.',
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    DriverPrimaryButton(
                      label: bundle.isFullyComplete
                          ? 'Open Driver Home'
                          : 'Continue Setup',
                      onPressed: () {
                        if (bundle.isFullyComplete) {
                          Navigator.of(context).pushAndRemoveUntil(
                            MaterialPageRoute(
                              builder: (_) => const DriverHomeScreen(),
                            ),
                            (route) => false,
                          );
                          return;
                        }
                        _openStep(nextStep, bundle);
                      },
                      loading: _navigating,
                      icon: bundle.isFullyComplete
                          ? Icons.home_rounded
                          : Icons.arrow_forward_rounded,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}


