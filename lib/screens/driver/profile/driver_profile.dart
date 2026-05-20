import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/auth/login_screen.dart';

import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';
import 'package:touristrike/screens/driver/profile/driver_personal_info_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_details_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_toda_assignment_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_plate_number_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_license_number_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_license_expiry_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_documents_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_online_status_screen.dart';
import 'package:touristrike/screens/driver/profile/driver_role_screen.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() => _DriverProfileScreenState();
}

class _DriverProfileScreenState extends State<DriverProfileScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  bool _isSigningOut = false;

  Stream<DriverProfileData> _profileDataStream(String userId) {
    final profileStream = _supabase
        .from('profiles')
        .stream(primaryKey: const ['id'])
        .eq('id', userId)
        .map(
          (rows) => rows.isNotEmpty
              ? DriverProfile.fromMap(rows.first)
              : DriverProfile.empty(userId),
        );

    final detailsStream = _supabase
        .from('driver_details')
        .stream(primaryKey: const ['driver_id'])
        .eq('driver_id', userId)
        .map(
          (rows) => rows.isNotEmpty
              ? DriverDetails.fromMap(rows.first)
              : DriverDetails.empty(userId),
        );

    final docsStream = _supabase
        .from('driver_documents')
        .stream(primaryKey: const ['driver_id'])
        .eq('driver_id', userId)
        .map(
          (rows) => rows.isNotEmpty
              ? DriverDocuments.fromMap(rows.first)
              : DriverDocuments.empty(userId),
        );

    return Stream<DriverProfileData>.multi((controller) {
      DriverProfile latestProfile = DriverProfile.empty(userId);
      DriverDetails latestDetails = DriverDetails.empty(userId);
      DriverDocuments latestDocs = DriverDocuments.empty(userId);

      late final StreamSubscription profileSub;
      late final StreamSubscription detailsSub;
      late final StreamSubscription docsSub;

      void emit() {
        controller.add(
          DriverProfileData(
            profile: latestProfile,
            details: latestDetails,
            documents: latestDocs,
          ),
        );
      }

      profileSub = profileStream.listen((value) {
        latestProfile = value;
        emit();
      }, onError: controller.addError);

      detailsSub = detailsStream.listen((value) {
        latestDetails = value;
        emit();
      }, onError: controller.addError);

      docsSub = docsStream.listen((value) {
        latestDocs = value;
        emit();
      }, onError: controller.addError);

      controller.onCancel = () async {
        await profileSub.cancel();
        await detailsSub.cancel();
        await docsSub.cancel();
      };
    });
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'Logout',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'Are you sure you want to log out of your driver account?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFEF4444),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    try {
      setState(() => _isSigningOut = true);

      await _supabase.auth.signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to logout: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSigningOut = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F6FA),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'No authenticated driver found. Please sign in again.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      body: SafeArea(
        child: StreamBuilder<DriverProfileData>(
          stream: _profileDataStream(user.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _ErrorState(
                message: 'Failed to load profile.\n${snapshot.error}',
                onRetry: () => setState(() {}),
              );
            }

            if (!snapshot.hasData) {
              return const _LoadingState();
            }

            final data = snapshot.data!;
            final profile = data.profile;
            final details = data.details;
            final documents = data.documents;

            return Stack(
              children: [
                CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: _ProfileHeaderCard(
                          fullName: profile.displayName,
                          subtitle: profile.mobile.isNotEmpty
                              ? profile.mobile
                              : (user.email ?? 'No email available'),
                          profileImageUrl: profile.profileImageUrl,
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: _SectionCard(
                          title: 'ACCOUNT',
                          children: [
                            _SettingsTile(
                              icon: Icons.person_outline_rounded,
                              title: 'Personal Info',
                              subtitle: profile.personalInfoSubtitle,
                              onTap: () => _push(
                                DriverPersonalInfoScreen(profile: profile),
                              ),
                            ),
                            _SettingsTile(
                              icon: Icons.badge_outlined,
                              title: 'Driver Details',
                              subtitle: details.driverDetailsSubtitle,
                              onTap: () => _push(
                                DriverDetailsScreen(
                                  profile: profile,
                                  details: details,
                                ),
                              ),
                            ),
                            _SettingsTile(
                              icon: Icons.storefront_outlined,
                              title: 'TODA Assignment',
                              subtitle: details.todaSubtitle,
                              showDivider: false,
                              onTap: () => _push(
                                DriverTodaAssignmentScreen(details: details),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: _SectionCard(
                          title: 'TRICYCLE',
                          children: [
                            _SettingsTile(
                              icon: Icons.directions_bike_outlined,
                              title: 'Plate Number',
                              trailingText: details.plateNumber.isEmpty
                                  ? 'Not set'
                                  : details.plateNumber,
                              onTap: () => _push(
                                DriverPlateNumberScreen(details: details),
                              ),
                            ),
                            _SettingsTile(
                              icon: Icons.credit_card_outlined,
                              title: 'License Number',
                              trailingText: details.licenseNumber.isEmpty
                                  ? 'Not set'
                                  : details.licenseNumber,
                              onTap: () => _push(
                                DriverLicenseNumberScreen(details: details),
                              ),
                            ),
                            _SettingsTile(
                              icon: Icons.event_note_outlined,
                              title: 'License Expiry',
                              trailingText: details.licenseExpiry == null
                                  ? 'Not set'
                                  : DateFormat(
                                      'MMM dd, yyyy',
                                    ).format(details.licenseExpiry!),
                              showDivider: false,
                              onTap: () => _push(
                                DriverLicenseExpiryScreen(details: details),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: _SectionCard(
                          title: 'STATUS',
                          children: [
                            _SettingsTile(
                              icon: Icons.folder_open_outlined,
                              title: 'Driver Documents',
                              subtitle:
                                  '${documents.uploadedCount} uploaded of ${documents.totalCount}',
                              onTap: () => _push(
                                DriverDocumentsScreen(documents: documents),
                              ),
                            ),
                            _SettingsTile(
                              icon: Icons.circle_outlined,
                              title: 'Online Status',
                              trailingText: profile.isOnline
                                  ? 'Online'
                                  : 'Offline',
                              trailingColor: profile.isOnline
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFF6B7280),
                              onTap: () => _push(
                                DriverOnlineStatusScreen(profile: profile),
                              ),
                            ),
                            _SettingsTile(
                              icon: Icons.verified_user_outlined,
                              title: 'Role',
                              trailingText: profile.role.isEmpty
                                  ? 'driver'
                                  : profile.role,
                              showDivider: false,
                              onTap: () =>
                                  _push(DriverRoleScreen(profile: profile)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 120),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: const Color(0xFFF0F2F6)),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x08000000),
                                blurRadius: 14,
                                offset: Offset(0, 6),
                              ),
                            ],
                          ),
                          child: _LogoutTile(
                            onTap: _isSigningOut ? null : _logout,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isSigningOut)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.08),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  const _ProfileHeaderCard({
    required this.fullName,
    required this.subtitle,
    required this.profileImageUrl,
  });

  final String fullName;
  final String subtitle;
  final String profileImageUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0F2F6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(31),
            ),
            clipBehavior: Clip.antiAlias,
            child: profileImageUrl.isNotEmpty
                ? Image.network(
                    profileImageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.person_rounded,
                      color: Color(0xFF2F6FFF),
                      size: 28,
                    ),
                  )
                : const Icon(
                    Icons.person_rounded,
                    color: Color(0xFF2F6FFF),
                    size: 28,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFF0F2F6)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 14,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 2, bottom: 6),
              child: Text(
                title,
                style: const TextStyle(
                  color: Color(0xFF7B8794),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailingText,
    this.trailingColor,
    required this.onTap,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? trailingText;
  final Color? trailingColor;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;

    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(21),
                  ),
                  child: Icon(icon, color: const Color(0xFF2F6FFF), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: Color(0xFF172033),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF8A94A6),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (trailingText != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      trailingText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: trailingColor ?? const Color(0xFF6B7280),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else
                  const SizedBox(width: 8),
                Icon(
                  enabled ? Icons.chevron_right_rounded : Icons.remove_rounded,
                  color: const Color(0xFF94A3B8),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
        if (showDivider) const Divider(height: 1, color: Color(0xFFF1F5F9)),
      ],
    );
  }
}

class _LogoutTile extends StatelessWidget {
  const _LogoutTile({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(21),
              ),
              child: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFEF4444),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Logout',
                style: TextStyle(
                  color: Color(0xFFEF4444),
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFF87171),
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 42,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF344054),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
