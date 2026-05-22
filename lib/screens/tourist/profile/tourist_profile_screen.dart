import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/screens/auth/login_screen.dart';
import 'package:touristrike/screens/tourist/profile/change_password_screen.dart';
import 'package:touristrike/screens/tourist/profile/emergency_contact_screen.dart';
import 'package:touristrike/screens/tourist/profile/notifications_screen.dart';
import 'package:touristrike/screens/tourist/profile/personal_info_screen.dart';
import 'package:touristrike/screens/tourist/profile/privacy_policy_screen.dart';
import 'package:touristrike/screens/tourist/profile/saved_places_screen.dart';
import 'package:touristrike/screens/tourist/profile/terms_screen.dart';
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
      _showError('Unable to load your profile right now.');
    }
  }

  void _subscribeToRealtime() {
    final userId = _user?.id;
    if (userId == null) return;

    _profileChannel?.unsubscribe();
    _profileChannel = _supabase
        .channel('tourist_profile_$userId')
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
  }

  Future<void> _openPage(Widget screen, {bool refreshAfter = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (refreshAfter && mounted) {
      await _loadData();
    }
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

    if (confirmed != true) return;

    if (mounted) {
      setState(() => _loggingOut = true);
    }

    try {
      await _supabase.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (error, stackTrace) {
      debugPrint('ProfileScreen _logout error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _loggingOut = false);
      _showError('Unable to log out. Please try again.');
    }
  }

  String get _displayName {
    final profile = _profile;
    if (profile != null && profile.displayName.isNotEmpty) {
      return profile.displayName;
    }
    final metadataName = (_user?.userMetadata?['full_name'] ?? '')
        .toString()
        .trim();
    return metadataName.isEmpty ? 'Tourist' : metadataName;
  }

  String get _email {
    final email = _user?.email?.trim() ?? '';
    return email.isEmpty ? 'No email available' : email;
  }

  String get _phone {
    final phone = _profile?.mobile.trim() ?? '';
    return phone.isEmpty ? 'Add mobile number' : phone;
  }

  String get _address {
    final profile = _profile;
    if (profile == null) return 'Complete your tourist profile';
    final parts = [
      profile.address,
      profile.barangay,
      profile.city,
      profile.province,
      profile.postalCode,
    ].where((value) => value.trim().isNotEmpty).toList();
    return parts.isEmpty ? 'Complete your tourist profile' : parts.join(', ');
  }

  String get _imageUrl {
    final profileImage = _profile?.profileImageUrl.trim() ?? '';
    if (profileImage.isNotEmpty) return profileImage;
    final avatarUrl = _profile?.avatarUrl.trim() ?? '';
    if (avatarUrl.isNotEmpty) return avatarUrl;
    return (_user?.userMetadata?['avatar_url'] ?? '').toString().trim();
  }

  bool get _isProfileComplete => _profile?.isProfileComplete ?? false;

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const textDark = Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: const AppBottomNav(selectedIndex: -1),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF2A86FF),
          onRefresh: _loadData,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
            children: [
              Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, color: textDark),
                  ),
                  const Expanded(
                    child: Text(
                      'Profile & Settings',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _ProfileHeader(
                loading: _loading,
                imageUrl: _imageUrl,
                name: _displayName,
                email: _email,
                phone: _phone,
                address: _address,
              ),
              if (!_isProfileComplete) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFB45309),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Complete your tourist profile to unlock better matches and faster service.',
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _SummaryTile(
                      icon: Icons.bookmark_rounded,
                      value: _savedPlacesCount.toString(),
                      label: 'Saved',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummaryTile(
                      icon: Icons.verified_user_rounded,
                      value: _isProfileComplete ? 'Complete' : 'Pending',
                      label: 'Profile',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _SummaryTile(
                      icon: Icons.location_on_rounded,
                      value: (_profile?.city.trim().isNotEmpty ?? false)
                          ? _profile!.city
                          : 'Unset',
                      label: 'City',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Account',
                children: [
                  _SettingRow(
                    icon: Icons.person_outline_rounded,
                    title: 'Personal Info',
                    subtitle: 'Name, mobile number, birthdate, and address',
                    onTap: () => _openPage(
                      const PersonalInfoScreen(),
                      refreshAfter: true,
                    ),
                  ),
                  _SettingRow(
                    icon: Icons.lock_reset_rounded,
                    title: 'Change Password',
                    subtitle: 'Update your account password securely',
                    onTap: () => _openPage(const ChangePasswordScreen()),
                  ),
                  _SettingRow(
                    icon: Icons.bookmark_border_rounded,
                    title: 'Saved Places',
                    subtitle: 'Manage places saved to your account',
                    onTap: () => _openPage(
                      const SavedPlacesScreen(),
                      refreshAfter: true,
                    ),
                  ),
                  _SettingRow(
                    icon: Icons.emergency_share_rounded,
                    title: 'Emergency Contacts',
                    subtitle: 'Manage safety contacts with realtime sync',
                    onTap: () => _openPage(const EmergencyContactsScreen()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Legal',
                children: [
                  _SettingRow(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy Policy',
                    subtitle: 'Latest published privacy policy',
                    onTap: () => _openPage(const PrivacyPolicyScreen()),
                  ),
                  _SettingRow(
                    icon: Icons.article_outlined,
                    title: 'Terms',
                    subtitle: 'Latest published terms and conditions',
                    onTap: () => _openPage(const TermsScreen()),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _LogoutButton(
                loading: _loggingOut,
                onTap: _loggingOut ? null : _logout,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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

  factory _TouristProfileData.fromMap(Map<String, dynamic> map) {
    return _TouristProfileData(
      firstName: (map['first_name'] ?? '').toString(),
      middleName: (map['middle_name'] ?? '').toString(),
      lastName: (map['last_name'] ?? '').toString(),
      fullName: (map['full_name'] ?? '').toString(),
      mobile: (map['mobile'] ?? '').toString(),
      profileImageUrl: (map['profile_image_url'] ?? '').toString(),
      avatarUrl: (map['avatar_url'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      barangay: (map['barangay'] ?? '').toString(),
      city: (map['city'] ?? '').toString(),
      province: (map['province'] ?? '').toString(),
      postalCode: (map['postal_code'] ?? '').toString(),
      isProfileComplete: map['is_profile_complete'] == true,
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
    final normalizedFullName = fullName.trim();
    if (normalizedFullName.isNotEmpty) return normalizedFullName;

    final parts = [
      firstName.trim(),
      middleName.trim(),
      lastName.trim(),
    ].where((value) => value.isNotEmpty).toList();
    return parts.join(' ');
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.loading,
    required this.imageUrl,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
  });

  final bool loading;
  final String imageUrl;
  final String name;
  final String email;
  final String phone;
  final String address;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const line = Color(0xFFE7EEF7);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: loading
          ? const SizedBox(
              height: 104,
              child: Center(child: CircularProgressIndicator(color: blue)),
            )
          : Column(
              children: [
                Row(
                  children: [
                    _Avatar(imageUrl: imageUrl, name: name),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: textDark,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            email,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: textMid,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            phone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: textMid,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    const Icon(
                      Icons.location_on_outlined,
                      color: textMid,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        address,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: textMid,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.imageUrl, required this.name});

  final String imageUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? 'T'
        : name
              .trim()
              .split(RegExp(r'\s+'))
              .where((part) => part.isNotEmpty)
              .take(2)
              .map((part) => part[0].toUpperCase())
              .join();

    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [Color(0xFF2A86FF), Color(0xFF60A5FA)],
        ),
        image: imageUrl.trim().isEmpty
            ? null
            : DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover),
      ),
      child: imageUrl.trim().isNotEmpty
          ? null
          : Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                ),
              ),
            ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: blue),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: textMid, fontWeight: FontWeight.w800),
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
    const line = Color(0xFFE7EEF7);
    const textDark = Color(0xFF0F172A);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: textDark,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const line = Color(0xFFE7EEF7);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: textDark,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: textMid,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: textMid),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1, color: line),
          ],
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFDC2626),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        child: loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Text(
                'Log Out',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
      ),
    );
  }
}
