import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/components/tourist/ai_chatbot_floating_widget.dart';

import 'package:touristrike/screens/auth/login_screen.dart';
import 'package:touristrike/screens/tourist/profile/change_password_screen.dart';
import 'package:touristrike/screens/tourist/profile/emergency_contact_screen.dart';
import 'package:touristrike/screens/tourist/profile/personal_info_screen.dart';
import 'package:touristrike/screens/tourist/profile/privacy_policy_screen.dart';
import 'package:touristrike/screens/tourist/profile/saved_places_screen.dart';
import 'package:touristrike/screens/tourist/profile/terms_screen.dart';
import 'package:touristrike/screens/tourist/profile/widgets/developer_tools_section.dart';
import 'package:touristrike/widgets/app_bottom_nav_tourist.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _loggingOut = false;

  int _savedPlacesCount = 0;

  _TouristProfileData? _profile;
  RealtimeChannel? _profileChannel;

  User? get _user => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _profileChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = _user;

    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _profile = null;
          _savedPlacesCount = 0;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final profileRow = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      final savedPlacesRows = await _supabase
          .from('saved_places')
          .select('id')
          .eq('user_id', user.id);

      if (!mounted) return;

      setState(() {
        _profile = _TouristProfileData.fromMap(
          profileRow ?? <String, dynamic>{},
        );

        _savedPlacesCount = savedPlacesRows.length;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('ProfileScreen _loadData error: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() => _loading = false);

      _showError(
        'Unable to load your profile right now.',
      );
    }
  }

  void _subscribeToRealtime() {
    final userId = _user?.id;

    if (userId == null) return;

    _profileChannel?.unsubscribe();

    _profileChannel = _supabase
        .channel(
          'tourist_profile_$userId',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'profiles',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (payload) {
            final row = payload.newRecord;

            if (row.isEmpty) {
              _loadData();
              return;
            }

            if (!mounted) return;

            setState(() {
              _profile = _TouristProfileData.fromMap(
                Map<String, dynamic>.from(row),
              );
            });
          },
        )
        .subscribe();
  }

  void _showError(String message) {
    _showSnack(
      message,
      isError: true,
    );
  }

  void _showSnack(
    String message, {
    required bool isError,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Row(
            children: [
              Icon(
                isError
                    ? Icons.error_outline_rounded
                    : Icons.check_circle_outline_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

  Future<void> _openPage(
    Widget screen, {
    bool refreshAfter = false,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => screen,
      ),
    );

    if (refreshAfter && mounted) {
      await _loadData();
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
          titlePadding: const EdgeInsets.fromLTRB(
            24,
            24,
            24,
            0,
          ),
          contentPadding: const EdgeInsets.fromLTRB(
            24,
            12,
            24,
            0,
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16,
          ),
          title: const Row(
            children: [
              _LogoutDialogIcon(),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Log out?',
                  style: TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'You will need to sign in again to continue using your TourisTrike account.',
            style: TextStyle(
              color: Color(0xFF667085),
              fontWeight: FontWeight.w500,
              height: 1.4,
              fontSize: 13,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              style: TextButton.styleFrom(
                foregroundColor:
                    const Color(0xFF667085),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor:
                    const Color(0xFFDC2626),
                foregroundColor:
                    Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(13),
                ),
              ),
              child: const Text(
                'Log Out',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    if (mounted) {
      setState(() {
        _loggingOut = true;
      });
    }

    try {
      await clearAiChatbotHistory();
      await _supabase.auth.signOut();

      if (!mounted) return;

      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => const LoginScreen(),
        ),
        (route) => false,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'ProfileScreen _logout error: $error',
      );
      debugPrintStack(
        stackTrace: stackTrace,
      );

      if (!mounted) return;

      setState(() {
        _loggingOut = false;
      });

      _showError(
        'Unable to log out. Please try again.',
      );
    }
  }

  String get _displayName {
    final profile = _profile;

    if (profile != null &&
        profile.displayName.isNotEmpty) {
      return profile.displayName;
    }

    final metadataName =
        (_user?.userMetadata?['full_name'] ?? '')
            .toString()
            .trim();

    return metadataName.isEmpty
        ? 'Tourist'
        : metadataName;
  }

  String get _email {
    final email =
        _user?.email?.trim() ?? '';

    return email.isEmpty
        ? 'No email available'
        : email;
  }

  String get _phone {
    final phone =
        _profile?.mobile.trim() ?? '';

    return phone.isEmpty
        ? 'Add mobile number'
        : phone;
  }

  String get _address {
    final profile = _profile;

    if (profile == null) {
      return 'Complete your tourist profile';
    }

    final parts = [
      profile.address,
      profile.barangay,
      profile.city,
      profile.province,
      profile.postalCode,
    ]
        .where(
          (value) =>
              value.trim().isNotEmpty,
        )
        .toList();

    return parts.isEmpty
        ? 'Complete your tourist profile'
        : parts.join(', ');
  }

  String get _imageUrl {
    final profileImage =
        _profile?.profileImageUrl.trim() ?? '';

    if (profileImage.isNotEmpty) {
      return profileImage;
    }

    final avatarUrl =
        _profile?.avatarUrl.trim() ?? '';

    if (avatarUrl.isNotEmpty) {
      return avatarUrl;
    }

    return (_user?.userMetadata?['avatar_url'] ?? '')
        .toString()
        .trim();
  }

  bool get _isProfileComplete =>
      _profile?.isProfileComplete ?? false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor:
          const Color(0xFFF6F8FC),
      bottomNavigationBar:
          const AppBottomNav(
        selectedIndex: -1,
      ),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          color:
              const Color(0xFF2A86FF),
          backgroundColor: Colors.white,
          onRefresh: _loadData,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth: 680,
              ),
              child: ListView(
                physics:
                    const AlwaysScrollableScrollPhysics(
                  parent:
                      BouncingScrollPhysics(),
                ),
                padding:
                    const EdgeInsets.fromLTRB(
                  18,
                  12,
                  18,
                  30,
                ),
                children: [
                  _PageHeader(
                    onBack: () {
                      Navigator.pop(
                        context,
                      );
                    },
                  ),

                  const SizedBox(height: 14),

                  _ProfileHeader(
                    loading: _loading,
                    imageUrl: _imageUrl,
                    name: _displayName,
                    email: _email,
                    phone: _phone,
                    address: _address,
                    isComplete:
                        _isProfileComplete,
                  ),

                  if (!_isProfileComplete) ...[
                    const SizedBox(height: 12),

                    _ProfileCompletionBanner(
                      onTap: () {
                        _openPage(
                          const PersonalInfoScreen(),
                          refreshAfter: true,
                        );
                      },
                    ),
                  ],

                  const SizedBox(height: 14),

                  _ProfileSummaryPanel(
                    savedPlacesCount:
                        _savedPlacesCount,
                    isProfileComplete:
                        _isProfileComplete,
                    city:
                        (_profile?.city.trim().isNotEmpty ??
                                false)
                            ? _profile!.city
                            : 'Unset',
                  ),

                  const SizedBox(height: 18),

                  _SectionCard(
                    title: 'Account',
                    subtitle:
                        'Manage your personal account',
                    children: [
                      _SettingRow(
                        icon:
                            Icons.person_outline_rounded,
                        title:
                            'Personal Info',
                        subtitle:
                            'Name, contact details and address',
                        onTap: () {
                          _openPage(
                            const PersonalInfoScreen(),
                            refreshAfter: true,
                          );
                        },
                      ),

                      _SettingRow(
                        icon:
                            Icons.lock_outline_rounded,
                        title:
                            'Change Password',
                        subtitle:
                            'Update your password securely',
                        onTap: () {
                          _openPage(
                            const ChangePasswordScreen(),
                          );
                        },
                      ),

                      _SettingRow(
                        icon:
                            Icons.bookmark_border_rounded,
                        title:
                            'Saved Places',
                        subtitle:
                            'View and manage your saved destinations',
                        onTap: () {
                          _openPage(
                            const SavedPlacesScreen(),
                            refreshAfter: true,
                          );
                        },
                      ),

                      _SettingRow(
                        icon:
                            Icons.emergency_outlined,
                        title:
                            'Emergency Contacts',
                        subtitle:
                            'Manage your trusted safety contacts',
                        onTap: () {
                          _openPage(
                            const EmergencyContactsScreen(),
                          );
                        },
                        showDivider: false,
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  if (kDebugMode) ...[
                    const DeveloperToolsSection(),
                    const SizedBox(height: 14),
                  ],

                  _SectionCard(
                    title: 'Legal & Privacy',
                    subtitle:
                        'Policies and account information',
                    children: [
                      _SettingRow(
                        icon:
                            Icons.privacy_tip_outlined,
                        title:
                            'Privacy Policy',
                        subtitle:
                            'How TourisTrike handles your information',
                        onTap: () {
                          _openPage(
                            const PrivacyPolicyScreen(),
                          );
                        },
                      ),

                      _SettingRow(
                        icon:
                            Icons.description_outlined,
                        title:
                            'Terms & Conditions',
                        subtitle:
                            'Review the latest terms of service',
                        onTap: () {
                          _openPage(
                            const TermsScreen(),
                          );
                        },
                        showDivider: false,
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  _LogoutButton(
                    loading: _loggingOut,
                    onTap: _loggingOut
                        ? null
                        : _logout,
                  ),

                  const SizedBox(height: 14),

                  const Center(
                    child: Text(
                      'TourisTrike • Tourist Account',
                      style: TextStyle(
                        color:
                            Color(0xFFA0AABA),
                        fontSize: 10.5,
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// PAGE HEADER
// ============================================================================

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.onBack,
  });

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Material(
          color: Colors.white,
          borderRadius:
              BorderRadius.circular(13),
          child: InkWell(
            onTap: onBack,
            borderRadius:
                BorderRadius.circular(13),
            child: Container(
              width: 42,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius:
                    BorderRadius.circular(
                  13,
                ),
                border: Border.all(
                  color:
                      const Color(
                    0xFFE5EBF3,
                  ),
                ),
              ),
              child: const Icon(
                Icons
                    .arrow_back_ios_new_rounded,
                size: 18,
                color:
                    Color(0xFF344054),
              ),
            ),
          ),
        ),

        const SizedBox(width: 12),

        const Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                'Profile & Settings',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight:
                      FontWeight.w900,
                  color:
                      Color(0xFF111827),
                  letterSpacing: -0.5,
                  height: 1.05,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Manage your account and preferences',
                style: TextStyle(
                  color:
                      Color(0xFF8391A4),
                  fontSize: 11.5,
                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// PROFILE HEADER
// ============================================================================

class _ProfileHeader
    extends StatelessWidget {
  const _ProfileHeader({
    required this.loading,
    required this.imageUrl,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.isComplete,
  });

  final bool loading;
  final String imageUrl;
  final String name;
  final String email;
  final String phone;
  final String address;
  final bool isComplete;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const _ProfileHeaderLoading();
    }

    return Container(
      padding:
          const EdgeInsets.fromLTRB(
        16,
        17,
        16,
        15,
      ),
      decoration: BoxDecoration(
        gradient:
            const LinearGradient(
          begin: Alignment.topLeft,
          end:
              Alignment.bottomRight,
          colors: [
            Color(0xFFFFFFFF),
            Color(0xFFF9FBFF),
          ],
        ),
        borderRadius:
            BorderRadius.circular(24),
        border: Border.all(
          color:
              const Color(
            0xFFE5ECF5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(
              0xFF0F172A,
            ).withValues(
              alpha: 0.055,
            ),
            blurRadius: 24,
            offset:
                const Offset(0, 11),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment:
                CrossAxisAlignment.center,
            children: [
              _Avatar(
                imageUrl: imageUrl,
                name: name,
              ),

              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow:
                          TextOverflow
                              .ellipsis,
                      style:
                          const TextStyle(
                        fontSize: 19,
                        fontWeight:
                            FontWeight
                                .w900,
                        color:
                            Color(
                          0xFF111827,
                        ),
                        letterSpacing:
                            -0.35,
                        height: 1.12,
                      ),
                    ),

                    const SizedBox(
                      height: 7,
                    ),

                    _ProfileInfoLine(
                      icon:
                          Icons.email_outlined,
                      text: email,
                    ),

                    const SizedBox(
                      height: 5,
                    ),

                    _ProfileInfoLine(
                      icon:
                          Icons.phone_outlined,
                      text: phone,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Container(
                padding:
                    const EdgeInsets
                        .symmetric(
                  horizontal: 9,
                  vertical: 5,
                ),
                decoration:
                    BoxDecoration(
                  color: isComplete
                      ? const Color(
                          0xFFECFDF3,
                        )
                      : const Color(
                          0xFFFFF7E6,
                        ),
                  borderRadius:
                      BorderRadius
                          .circular(999),
                ),
                child: Row(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    Icon(
                      isComplete
                          ? Icons
                              .check_circle_rounded
                          : Icons
                              .pending_outlined,
                      size: 12,
                      color: isComplete
                          ? const Color(
                              0xFF16A34A,
                            )
                          : const Color(
                              0xFFD97706,
                            ),
                    ),
                    const SizedBox(
                      width: 4,
                    ),
                    Text(
                      isComplete
                          ? 'Complete'
                          : 'Pending',
                      style: TextStyle(
                        color: isComplete
                            ? const Color(
                                0xFF15803D,
                              )
                            : const Color(
                                0xFFB45309,
                              ),
                        fontWeight:
                            FontWeight
                                .w800,
                        fontSize: 9.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 15),

          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.fromLTRB(
              12,
              10,
              12,
              10,
            ),
            decoration: BoxDecoration(
              color:
                  const Color(
                0xFFF5F8FC,
              ),
              borderRadius:
                  BorderRadius.circular(
                14,
              ),
              border: Border.all(
                color:
                    const Color(
                  0xFFE9EEF5,
                ),
              ),
            ),
            child: Row(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xFFEAF3FF,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      9,
                    ),
                  ),
                  child: const Icon(
                    Icons
                        .location_on_outlined,
                    color:
                        Color(
                      0xFF2A86FF,
                    ),
                    size: 16,
                  ),
                ),

                const SizedBox(width: 9),

                Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.only(
                      top: 4,
                    ),
                    child: Text(
                      address,
                      style:
                          const TextStyle(
                        color:
                            Color(
                          0xFF667085,
                        ),
                        fontWeight:
                            FontWeight
                                .w600,
                        fontSize: 11.5,
                        height: 1.35,
                      ),
                    ),
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

class _ProfileInfoLine
    extends StatelessWidget {
  const _ProfileInfoLine({
    required this.icon,
    required this.text,
  });

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 13,
          color:
              const Color(
            0xFF8A98AA,
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style:
                const TextStyle(
              color:
                  Color(
                0xFF667085,
              ),
              fontSize: 11.5,
              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProfileHeaderLoading
    extends StatelessWidget {
  const _ProfileHeaderLoading();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 155,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(24),
        border: Border.all(
          color:
              const Color(
            0xFFE5ECF5,
          ),
        ),
      ),
      child: const Center(
        child: SizedBox(
          width: 30,
          height: 30,
          child:
              CircularProgressIndicator(
            strokeWidth: 3,
            color:
                Color(0xFF2A86FF),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// AVATAR
// ============================================================================

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.imageUrl,
    required this.name,
  });

  final String imageUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials =
        name.trim().isEmpty
            ? 'T'
            : name
                .trim()
                .split(
                  RegExp(r'\s+'),
                )
                .where(
                  (part) =>
                      part.isNotEmpty,
                )
                .take(2)
                .map(
                  (part) =>
                      part[0]
                          .toUpperCase(),
                )
                .join();

    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient:
            const LinearGradient(
          begin: Alignment.topLeft,
          end:
              Alignment.bottomRight,
          colors: [
            Color(0xFF2A86FF),
            Color(0xFF5EA9FF),
          ],
        ),
        border: Border.all(
          color: Colors.white,
          width: 3,
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(
              0xFF2A86FF,
            ).withValues(
              alpha: 0.22,
            ),
            blurRadius: 16,
            offset:
                const Offset(0, 7),
          ),
        ],
        image: imageUrl.trim().isEmpty
            ? null
            : DecorationImage(
                image:
                    NetworkImage(
                  imageUrl,
                ),
                fit: BoxFit.cover,
              ),
      ),
      child: imageUrl.trim().isNotEmpty
          ? null
          : Center(
              child: Text(
                initials,
                style:
                    const TextStyle(
                  color: Colors.white,
                  fontWeight:
                      FontWeight
                          .w900,
                  fontSize: 23,
                ),
              ),
            ),
    );
  }
}

// ============================================================================
// PROFILE COMPLETION BANNER
// ============================================================================

class _ProfileCompletionBanner
    extends StatelessWidget {
  const _ProfileCompletionBanner({
    required this.onTap,
  });

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(18),
        child: Ink(
          padding:
              const EdgeInsets.fromLTRB(
            13,
            12,
            12,
            12,
          ),
          decoration: BoxDecoration(
            gradient:
                const LinearGradient(
              begin:
                  Alignment.centerLeft,
              end:
                  Alignment.centerRight,
              colors: [
                Color(0xFFFFF8E7),
                Color(0xFFFFF3CE),
              ],
            ),
            borderRadius:
                BorderRadius.circular(
              18,
            ),
            border: Border.all(
              color:
                  const Color(
                0xFFF9D56E,
              ),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 39,
                height: 39,
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xFFFFE9AD,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    12,
                  ),
                ),
                child: const Icon(
                  Icons
                      .person_add_alt_1_rounded,
                  color:
                      Color(
                    0xFFB45309,
                  ),
                  size: 19,
                ),
              ),

              const SizedBox(width: 10),

              const Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Complete your profile',
                      style:
                          TextStyle(
                        color:
                            Color(
                          0xFF92400E,
                        ),
                        fontWeight:
                            FontWeight
                                .w900,
                        fontSize:
                            12.5,
                      ),
                    ),
                    SizedBox(
                      height: 2,
                    ),
                    Text(
                      'Add your information for smoother bookings and better matches.',
                      style:
                          TextStyle(
                        color:
                            Color(
                          0xFFA16207,
                        ),
                        fontWeight:
                            FontWeight
                                .w600,
                        fontSize:
                            10.5,
                        height:
                            1.3,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              const Icon(
                Icons
                    .chevron_right_rounded,
                color:
                    Color(
                  0xFFB45309,
                ),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// SUMMARY
// ============================================================================

class _ProfileSummaryPanel
    extends StatelessWidget {
  const _ProfileSummaryPanel({
    required this.savedPlacesCount,
    required this.isProfileComplete,
    required this.city,
  });

  final int savedPlacesCount;
  final bool isProfileComplete;
  final String city;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 8,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(22),
        border: Border.all(
          color:
              const Color(
            0xFFE5ECF5,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _SummaryItem(
              icon:
                  Icons.bookmark_outline_rounded,
              value:
                  savedPlacesCount.toString(),
              label: 'Saved',
            ),
          ),

          const _SummaryVerticalDivider(),

          Expanded(
            child: _SummaryItem(
              icon:
                  Icons.verified_user_outlined,
              value: isProfileComplete
                  ? 'Done'
                  : 'Pending',
              label: 'Profile',
            ),
          ),

          const _SummaryVerticalDivider(),

          Expanded(
            child: _SummaryItem(
              icon:
                  Icons.location_on_outlined,
              value: city,
              label: 'City',
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryItem
    extends StatelessWidget {
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
      children: [
        Container(
          width: 35,
          height: 35,
          decoration: BoxDecoration(
            color:
                const Color(
              0xFFEAF3FF,
            ),
            borderRadius:
                BorderRadius.circular(
              11,
            ),
          ),
          child: Icon(
            icon,
            color:
                const Color(
              0xFF2A86FF,
            ),
            size: 18,
          ),
        ),

        const SizedBox(height: 8),

        Text(
          value,
          maxLines: 1,
          overflow:
              TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style:
              const TextStyle(
            color:
                Color(
              0xFF111827,
            ),
            fontWeight:
                FontWeight.w900,
            fontSize: 14,
          ),
        ),

        const SizedBox(height: 2),

        Text(
          label,
          style:
              const TextStyle(
            color:
                Color(
              0xFF8492A6,
            ),
            fontWeight:
                FontWeight.w600,
            fontSize: 10.5,
          ),
        ),
      ],
    );
  }
}

class _SummaryVerticalDivider
    extends StatelessWidget {
  const _SummaryVerticalDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 52,
      color:
          const Color(
        0xFFE9EEF5,
      ),
    );
  }
}

// ============================================================================
// SECTION CARD
// ============================================================================

class _SectionCard
    extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.fromLTRB(
        14,
        15,
        14,
        5,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(22),
        border: Border.all(
          color:
              const Color(
            0xFFE5ECF5,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(
              0xFF0F172A,
            ).withValues(
              alpha: 0.025,
            ),
            blurRadius: 16,
            offset:
                const Offset(0, 7),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 2,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style:
                      const TextStyle(
                    color:
                        Color(
                      0xFF111827,
                    ),
                    fontWeight:
                        FontWeight
                            .w900,
                    fontSize: 15,
                  ),
                ),

                const SizedBox(
                  height: 3,
                ),

                Text(
                  subtitle,
                  style:
                      const TextStyle(
                    color:
                        Color(
                      0xFF96A2B3,
                    ),
                    fontWeight:
                        FontWeight
                            .w500,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          ...children,
        ],
      ),
    );
  }
}

// ============================================================================
// SETTING ROW
// ============================================================================

class _SettingRow
    extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.showDivider = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(15),
        child: Padding(
          padding:
              const EdgeInsets.fromLTRB(
            2,
            9,
            2,
            0,
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 39,
                    height: 39,
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xFFEAF3FF,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                    ),
                    child: Icon(
                      icon,
                      color:
                          const Color(
                        0xFF2A86FF,
                      ),
                      size: 19,
                    ),
                  ),

                  const SizedBox(width: 11),

                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style:
                              const TextStyle(
                            color:
                                Color(
                              0xFF1F2937,
                            ),
                            fontWeight:
                                FontWeight
                                    .w800,
                            fontSize:
                                13.5,
                          ),
                        ),

                        const SizedBox(
                          height: 3,
                        ),

                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              const TextStyle(
                            color:
                                Color(
                              0xFF78869A,
                            ),
                            fontWeight:
                                FontWeight
                                    .w500,
                            fontSize:
                                10.8,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: 6),

                  Container(
                    width: 28,
                    height: 28,
                    decoration:
                        BoxDecoration(
                      color:
                          const Color(
                        0xFFF5F7FA,
                      ),
                      borderRadius:
                          BorderRadius.circular(
                        9,
                      ),
                    ),
                    child: const Icon(
                      Icons
                          .chevron_right_rounded,
                      color:
                          Color(
                        0xFF9AA6B6,
                      ),
                      size: 18,
                    ),
                  ),
                ],
              ),

              if (showDivider) ...[
                const SizedBox(height: 9),

                const Padding(
                  padding:
                      EdgeInsets.only(
                    left: 50,
                  ),
                  child: Divider(
                    height: 1,
                    color:
                        Color(
                      0xFFEDF1F6,
                    ),
                  ),
                ),
              ] else
                const SizedBox(height: 9),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// LOGOUT
// ============================================================================

class _LogoutButton
    extends StatelessWidget {
  const _LogoutButton({
    required this.loading,
    required this.onTap,
  });

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color:
          const Color(
        0xFFFEF2F2,
      ),
      borderRadius:
          BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(17),
        child: Container(
          height: 52,
          padding:
              const EdgeInsets.symmetric(
            horizontal: 15,
          ),
          decoration: BoxDecoration(
            borderRadius:
                BorderRadius.circular(
              17,
            ),
            border: Border.all(
              color:
                  const Color(
                0xFFFACACA,
              ),
            ),
          ),
          child: loading
              ? const Center(
                  child: SizedBox(
                    width: 21,
                    height: 21,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2.3,
                      color:
                          Color(
                        0xFFDC2626,
                      ),
                    ),
                  ),
                )
              : const Row(
                  mainAxisAlignment:
                      MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.logout_rounded,
                      color:
                          Color(
                        0xFFDC2626,
                      ),
                      size: 19,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Log Out',
                      style: TextStyle(
                        color:
                            Color(
                          0xFFDC2626,
                        ),
                        fontWeight:
                            FontWeight
                                .w800,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _LogoutDialogIcon
    extends StatelessWidget {
  const _LogoutDialogIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color:
            const Color(
          0xFFFEF2F2,
        ),
        borderRadius:
            BorderRadius.circular(13),
      ),
      child: const Icon(
        Icons.logout_rounded,
        color:
            Color(0xFFDC2626),
        size: 20,
      ),
    );
  }
}

// ============================================================================
// DATA MODEL
// ============================================================================

class _TouristProfileData {
  const _TouristProfileData({
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.fullName,
    required this.mobile,
    required this.profileImageUrl,
    required this.avatarUrl,
    required this.address,
    required this.barangay,
    required this.city,
    required this.province,
    required this.postalCode,
    required this.isProfileComplete,
  });

  factory _TouristProfileData.fromMap(
    Map<String, dynamic> map,
  ) {
    return _TouristProfileData(
      firstName:
          (map['first_name'] ?? '')
              .toString(),
      middleName:
          (map['middle_name'] ?? '')
              .toString(),
      lastName:
          (map['last_name'] ?? '')
              .toString(),
      fullName:
          (map['full_name'] ?? '')
              .toString(),
      mobile:
          (map['mobile'] ?? '')
              .toString(),
      profileImageUrl:
          (map['profile_image_url'] ?? '')
              .toString(),
      avatarUrl:
          (map['avatar_url'] ?? '')
              .toString(),
      address:
          (map['address'] ?? '')
              .toString(),
      barangay:
          (map['barangay'] ?? '')
              .toString(),
      city:
          (map['city'] ?? '')
              .toString(),
      province:
          (map['province'] ?? '')
              .toString(),
      postalCode:
          (map['postal_code'] ?? '')
              .toString(),
      isProfileComplete:
          map['is_profile_complete'] ==
              true,
    );
  }

  final String firstName;
  final String middleName;
  final String lastName;
  final String fullName;

  final String mobile;

  final String profileImageUrl;
  final String avatarUrl;

  final String address;
  final String barangay;
  final String city;
  final String province;
  final String postalCode;

  final bool isProfileComplete;

  String get displayName {
    final normalized =
        fullName.trim();

    if (normalized.isNotEmpty) {
      return normalized;
    }

    final parts = [
      firstName.trim(),
      middleName.trim(),
      lastName.trim(),
    ]
        .where(
          (value) =>
              value.isNotEmpty,
        )
        .toList();

    return parts.join(' ');
  }
}
