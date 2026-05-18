import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:touristrike/screens/auth/login_screen.dart';
import 'package:touristrike/screens/tourist/profile/emergency_contact_screen.dart';
import 'package:touristrike/screens/tourist/profile/notifications_screen.dart';
import 'package:touristrike/screens/tourist/profile/payment_history_screen.dart';
import 'package:touristrike/screens/tourist/profile/payment_methods_screen.dart';
import 'package:touristrike/screens/tourist/profile/personal_info_screen.dart';
import 'package:touristrike/screens/tourist/profile/privacy_policy_screen.dart';
import 'package:touristrike/screens/tourist/profile/saved_places_screen.dart';
import 'package:touristrike/screens/tourist/profile/terms_screen.dart';
import 'package:touristrike/screens/tourist/tourist_saved_places_state.dart';
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
  String _language = 'English';
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  User? get _user => _supabase.auth.currentUser;

  Future<void> _loadProfile() async {
    final user = _user;
    if (user == null) {
      setState(() => _loading = false);
      return;
    }

    setState(() => _loading = true);

    try {
      final profile = await _supabase
          .from('profiles')
          .select(
            'id, full_name, first_name, middle_name, last_name, mobile, '
            'address, barangay, city, province, profile_image_url, avatar_url',
          )
          .eq('id', user.id)
          .maybeSingle()
          .timeout(const Duration(seconds: 12));

      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (e) {
      _showSnack('Unable to load profile details.', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _displayName {
    final full = (_profile?['full_name'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;

    final first = (_profile?['first_name'] ?? '').toString().trim();
    final middle = (_profile?['middle_name'] ?? '').toString().trim();
    final last = (_profile?['last_name'] ?? '').toString().trim();
    final parts = [first, middle, last].where((e) => e.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(' ');

    final metadataName = (_user?.userMetadata?['full_name'] ?? '')
        .toString()
        .trim();
    if (metadataName.isNotEmpty) return metadataName;

    return 'Tourist';
  }

  String get _email {
    final value = _user?.email?.trim() ?? '';
    return value.isEmpty ? 'No email available' : value;
  }

  String get _phone {
    final value = (_profile?['mobile'] ?? '').toString().trim();
    return value.isEmpty ? 'Add mobile number' : value;
  }

  String get _address {
    final address = (_profile?['address'] ?? '').toString().trim();
    final barangay = (_profile?['barangay'] ?? '').toString().trim();
    final city = (_profile?['city'] ?? '').toString().trim();
    final province = (_profile?['province'] ?? '').toString().trim();
    final parts = [
      address,
      barangay,
      city,
      province,
    ].where((value) => value.isNotEmpty).toList();

    return parts.isEmpty ? 'Complete your tourist profile' : parts.join(', ');
  }

  String get _imageUrl {
    final profileImage = (_profile?['profile_image_url'] ?? '')
        .toString()
        .trim();
    if (profileImage.isNotEmpty) return profileImage;

    final avatar = (_profile?['avatar_url'] ?? '').toString().trim();
    if (avatar.isNotEmpty) return avatar;

    return (_user?.userMetadata?['avatar_url'] ?? '').toString().trim();
  }

  bool get _emailVerified => _user?.emailConfirmedAt != null;

  void _showSnack(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
        ),
      );
  }

  Future<void> _openPage(Widget screen, {bool refreshAfter = false}) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (refreshAfter && mounted) _loadProfile();
  }

  Future<void> _chooseLanguage() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _LanguageSheet(current: _language),
    );

    if (selected == null || selected == _language) return;

    setState(() => _language = selected);
    _showSnack('Language set to $selected.', error: false);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text('You will need to log in again to continue.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loggingOut = true);

    try {
      await _supabase.auth.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loggingOut = false);
      _showSnack('Unable to log out. Please try again.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textMid = Color(0xFF64748B);

    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: const AppBottomNav(selectedIndex: 4),
      body: SafeArea(
        child: RefreshIndicator(
          color: blue,
          onRefresh: _loadProfile,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 118),
            children: [
              _ProfileHeader(
                loading: _loading,
                imageUrl: _imageUrl,
                name: _displayName,
                email: _email,
                phone: _phone,
                address: _address,
                emailVerified: _emailVerified,
                onEdit: () =>
                    _openPage(const PersonalInfoScreen(), refreshAfter: true),
              ),
              const SizedBox(height: 12),
              ValueListenableBuilder<List<TouristSavedPlace>>(
                valueListenable: touristSavedPlacesStore,
                builder: (context, places, _) {
                  return Row(
                    children: [
                      Expanded(
                        child: _SummaryTile(
                          icon: Icons.bookmark_rounded,
                          value: places.length.toString(),
                          label: 'Saved',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SummaryTile(
                          icon: Icons.verified_user_rounded,
                          value: _emailVerified ? 'Verified' : 'Pending',
                          label: 'Email',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _SummaryTile(
                          icon: Icons.location_on_rounded,
                          value:
                              (_profile?['city'] ?? '')
                                  .toString()
                                  .trim()
                                  .isEmpty
                              ? 'Unset'
                              : (_profile?['city'] ?? '').toString(),
                          label: 'City',
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Account',
                children: [
                  _SettingRow(
                    icon: Icons.person_outline_rounded,
                    title: 'Personal Info',
                    subtitle: 'Name, email, phone, and address',
                    onTap: () => _openPage(
                      const PersonalInfoScreen(),
                      refreshAfter: true,
                    ),
                  ),
                  _SettingRow(
                    icon: Icons.bookmark_border_rounded,
                    title: 'Saved Places',
                    subtitle: 'Spots you saved from details pages',
                    onTap: () => _openPage(const SavedPlacesScreen()),
                  ),
                  _SettingRow(
                    icon: Icons.emergency_share_rounded,
                    title: 'Emergency Contacts',
                    subtitle: 'Manage contacts for safety sharing',
                    onTap: () => _openPage(const EmergencyContactsScreen()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'Payments',
                children: [
                  _SettingRow(
                    icon: Icons.payments_outlined,
                    title: 'Payment History',
                    subtitle: 'View completed ride and tour payments',
                    onTap: () => _openPage(const PaymentHistoryScreen()),
                  ),
                  _SettingRow(
                    icon: Icons.credit_card_rounded,
                    title: 'Payment Methods',
                    subtitle: 'Cash, GCash, and card options',
                    onTap: () => _openPage(const PaymentMethodsScreen()),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _SectionCard(
                title: 'App',
                children: [
                  _SettingRow(
                    icon: Icons.notifications_none_rounded,
                    title: 'Notifications',
                    subtitle: 'Ride, tour, promo, and safety alerts',
                    onTap: () => _openPage(const NotificationsScreen()),
                  ),
                  _SettingRow(
                    icon: Icons.language_rounded,
                    title: 'Language',
                    subtitle: 'Choose app language',
                    trailing: Text(
                      _language,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textMid,
                      ),
                    ),
                    onTap: _chooseLanguage,
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
                    subtitle: 'How Touristrike handles your data',
                    onTap: () => _openPage(const PrivacyPolicyScreen()),
                  ),
                  _SettingRow(
                    icon: Icons.article_outlined,
                    title: 'Terms',
                    subtitle: 'Service rules and user responsibilities',
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

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.loading,
    required this.imageUrl,
    required this.name,
    required this.email,
    required this.phone,
    required this.address,
    required this.emailVerified,
    required this.onEdit,
  });

  final bool loading;
  final String imageUrl;
  final String name;
  final String email;
  final String phone;
  final String address;
  final bool emailVerified;
  final VoidCallback onEdit;

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
              child: Center(child: CircularProgressIndicator()),
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                    color: textDark,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              if (emailVerified)
                                const Icon(
                                  Icons.verified_rounded,
                                  color: blue,
                                  size: 19,
                                ),
                            ],
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
                              fontSize: 12.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton.filledTonal(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: line),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        color: blue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          address,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: textMid,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
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

class _Avatar extends StatelessWidget {
  const _Avatar({required this.imageUrl, required this.name});

  final String imageUrl;
  final String name;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'T' : name.trim()[0].toUpperCase();

    return Container(
      width: 76,
      height: 76,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE7EEF7), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isEmpty
          ? Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Color(0xFF2A86FF),
                  fontWeight: FontWeight.w900,
                  fontSize: 30,
                ),
              ),
            )
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Color(0xFF2A86FF),
                    fontWeight: FontWeight.w900,
                    fontSize: 30,
                  ),
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
    return Container(
      height: 92,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE7EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.045),
            blurRadius: 18,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: const Color(0xFF2A86FF), size: 21),
          const SizedBox(height: 7),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w800,
              fontSize: 11.5,
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
    const line = Color(0xFFE7EEF7);
    const textMid = Color(0xFF64748B);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: textMid,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 10),
          ..._withDividers(children),
        ],
      ),
    );
  }

  static List<Widget> _withDividers(List<Widget> kids) {
    final out = <Widget>[];
    for (var i = 0; i < kids.length; i++) {
      out.add(kids[i]);
      if (i != kids.length - 1) out.add(const _RowDivider());
    }
    return out;
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(16),
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
                      fontWeight: FontWeight.w900,
                      color: textDark,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: textMid,
                      fontSize: 12.3,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: textMid),
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
    const red = Color(0xFFDC2626);
    const line = Color(0xFFE7EEF7);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: line),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.045),
              blurRadius: 18,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: loading
                  ? const Padding(
                      padding: EdgeInsets.all(11),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.logout_rounded, color: red),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                loading ? 'Logging out...' : 'Logout',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: red,
                  fontSize: 16,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFFCA5A5)),
          ],
        ),
      ),
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(left: 56),
      child: Divider(height: 16, color: Color(0xFFE7EEF7)),
    );
  }
}

class _LanguageSheet extends StatelessWidget {
  const _LanguageSheet({required this.current});

  final String current;

  @override
  Widget build(BuildContext context) {
    const options = ['English', 'Filipino'];

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 16,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 16),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Language',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...options.map(
            (option) => ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: const Icon(Icons.language_rounded),
              title: Text(
                option,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              trailing: current == option
                  ? const Icon(
                      Icons.check_circle_rounded,
                      color: Color(0xFF2A86FF),
                    )
                  : null,
              onTap: () => Navigator.pop(context, option),
            ),
          ),
        ],
      ),
    );
  }
}
