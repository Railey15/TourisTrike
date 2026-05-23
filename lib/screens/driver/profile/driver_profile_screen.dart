import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';
import 'package:touristrike/screens/driver/profile/driver_documents_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_license_expiry_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_online_status_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_personal_info_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_plate_number_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_profile_completion_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_role_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_toda_assignment_screen.dart';
import 'package:touristrike/screens/driver/profile/services/driver_profile_service.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_scaffold.dart';
import 'package:touristrike/screens/auth/login_screen.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final DriverProfileService _service = DriverProfileService();

  bool _loggingOut = false;
  bool _navigating = false;

  String? get _userId => _service.currentUserId;

  Future<void> _navigateTo(Widget screen) async {
    if (_navigating) return;
    setState(() => _navigating = true);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    setState(() => _navigating = false);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text('Log out?'),
        content: const Text('You will need to log in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );

      await Supabase.instance.client.auth.signOut();
    } catch (error) {
      // Optional: ignore logout navigation errors
    }
  }

  @override
  Widget build(BuildContext context) {
    final userId = _userId;
    if (userId == null) {
      return DriverProfilePageScaffold(
        title: 'Driver Profile',
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DriverEmptyState(
            icon: Icons.lock_outline_rounded,
            title: 'Session Expired',
            message: 'Please sign in again to access your driver profile.',
            action: DriverPrimaryButton(
              label: 'Back to Login',
              onPressed: () {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
          ),
        ),
      );
    }

    return DriverProfilePageScaffold(
      title: 'Driver Profile',
      subtitle: 'Manage your driver information and onboarding progress.',
      child: Stack(
        children: [
          StreamBuilder<DriverProfileBundle>(
            stream: _service.watchProfileBundle(userId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: DriverEmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Unable to load driver profile',
                    message: '${snapshot.error}',
                    action: DriverPrimaryButton(
                      label: 'Retry',
                      onPressed: () => setState(() {}),
                    ),
                  ),
                );
              }

              if (!snapshot.hasData) {
                return const DriverLoadingView(
                  message: 'Loading driver profile...',
                );
              }

              final bundle = snapshot.data!;
              final profile = bundle.profile;
              final details = bundle.details;
              final documents = bundle.documents;

              return RefreshIndicator(
                color: const Color(0xFF2A86FF),
                onRefresh: () => _service.fetchProfileBundle(userId),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  children: [
                    DriverProfileSummaryCard(
                      name: profile.displayName,
                      subtitle: profile.mobile.trim().isNotEmpty
                          ? profile.mobile
                          : profile.locationSummary,
                      photoUrl: profile.effectivePhotoUrl,
                      completionPercent: bundle.completionPercent,
                      progressLabel: bundle.isFullyComplete
                          ? 'Driver profile complete'
                          : 'Complete your remaining driver profile steps',
                    ),
                    const SizedBox(height: 14),
                    DriverProfileCard(
                      child: Row(
                        children: [
                          Expanded(
                            child: _SummaryItem(
                              icon: Icons.assignment_turned_in_outlined,
                              value: '${bundle.completedSteps.length}/7',
                              label: 'Steps Done',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SummaryItem(
                              icon: Icons.folder_outlined,
                              value:
                                  '${documents.uploadedCount}/${documents.totalCount}',
                              label: 'Documents',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SummaryItem(
                              icon: Icons.circle_rounded,
                              value: profile.isOnline ? 'Online' : 'Offline',
                              label: 'Status',
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!bundle.isFullyComplete) ...[
                      const SizedBox(height: 14),
                      DriverProfileCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const DriverSectionTitle('Finish Setup'),
                            const SizedBox(height: 8),
                            Text(
                              'Your driver onboarding is not complete yet. Continue the guided setup to finish every required step without missing any fields.',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w700,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 14),
                            DriverPrimaryButton(
                              label: 'Continue Profile Setup',
                              onPressed: () => _navigateTo(
                                const DriverProfileCompletionScreen(
                                  finishToHome: false,
                                ),
                              ),
                              icon: Icons.flag_rounded,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 14),
                    DriverSectionCard(
                      title: 'Account',
                      children: [
                        DriverSettingsTile(
                          icon: Icons.person_outline_rounded,
                          title: 'Personal Info',
                          subtitle: profile.locationSummary,
                          onTap: () => _navigateTo(
                            DriverPersonalInfoScreen(bundle: bundle),
                          ),
                        ),
                        DriverSettingsTile(
                          icon: Icons.badge_outlined,
                          title: 'License Information',
                          subtitle: details.licenseNumber.trim().isEmpty
                              ? 'Add your license number and expiry'
                              : details.licenseExpiry == null
                              ? details.licenseNumber
                              : '${details.licenseNumber} / Exp ${DateFormat('MMM dd, yyyy').format(details.licenseExpiry!)}',
                          onTap: () => _navigateTo(
                            DriverLicenseExpiryScreen(bundle: bundle),
                          ),
                        ),
                        DriverSettingsTile(
                          icon: Icons.groups_2_outlined,
                          title: 'TODA Assignment',
                          subtitle: details.todaName.trim().isEmpty
                              ? 'Add your TODA and operator code'
                              : '${details.todaName} / ${details.operatorCode}',
                          onTap: () => _navigateTo(
                            DriverTodaAssignmentScreen(bundle: bundle),
                          ),
                          showDivider: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DriverSectionCard(
                      title: 'Vehicle & Status',
                      children: [
                        DriverSettingsTile(
                          icon: Icons.directions_bike_outlined,
                          title: 'Plate Number',
                          trailingText: details.plateNumber.trim().isEmpty
                              ? 'Not set'
                              : details.plateNumber,
                          onTap: () => _navigateTo(
                            DriverPlateNumberScreen(bundle: bundle),
                          ),
                        ),
                        DriverSettingsTile(
                          icon: Icons.folder_open_outlined,
                          title: 'Driver Documents',
                          subtitle:
                              '${documents.uploadedCount} uploaded of ${documents.totalCount}',
                          onTap: () => _navigateTo(
                            DriverDocumentsScreen(bundle: bundle),
                          ),
                        ),
                        DriverSettingsTile(
                          icon: Icons.circle_outlined,
                          title: 'Online Status',
                          trailingText: profile.isOnline ? 'Online' : 'Offline',
                          trailingColor: profile.isOnline
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF64748B),
                          onTap: () => _navigateTo(
                            DriverOnlineStatusScreen(bundle: bundle),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    DriverProfileCard(
                      child: InkWell(
                        onTap: _loggingOut ? null : _logout,
                        borderRadius: BorderRadius.circular(18),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEF2F2),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.logout_rounded,
                                color: Color(0xFFDC2626),
                              ),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Log Out',
                                style: TextStyle(
                                  color: Color(0xFFDC2626),
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            if (_loggingOut)
                              const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: Color(0xFFDC2626),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          if (_navigating)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black.withValues(alpha: 0.04),
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF2A86FF)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  const _SummaryItem({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFF2A86FF)),
        const SizedBox(height: 10),
        Text(
          value,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}


