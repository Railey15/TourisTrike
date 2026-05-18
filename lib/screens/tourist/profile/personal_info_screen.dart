import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final _supabase = Supabase.instance.client;
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  DateTime? _birthday;
  String _gender = 'Prefer not to say';

  bool _phoneVerified = false;
  bool _emailVerified = false;

  bool _dirty = false;
  bool _saving = false;
  bool _loadingProfile = true;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_markDirty);
    _emailCtrl.addListener(_markDirty);
    _phoneCtrl.addListener(_markDirty);
    _addressCtrl.addListener(_markDirty);
    _loadProfile();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _loadProfile() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final profile = await _supabase
          .from('profiles')
          .select(
            'full_name, mobile, address, birthdate, gender, barangay, city, province',
          )
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      final parts = [
        (profile?['address'] ?? '').toString().trim(),
        (profile?['barangay'] ?? '').toString().trim(),
        (profile?['city'] ?? '').toString().trim(),
        (profile?['province'] ?? '').toString().trim(),
      ].where((e) => e.isNotEmpty).toList();

      _nameCtrl.text = (profile?['full_name'] ?? '').toString();
      _emailCtrl.text = user.email ?? '';
      _phoneCtrl.text = (profile?['mobile'] ?? '').toString();
      _addressCtrl.text = parts.join(', ');
      _birthday = DateTime.tryParse((profile?['birthdate'] ?? '').toString());
      _gender = (profile?['gender'] ?? 'Prefer not to say').toString();
      _phoneVerified = _phoneCtrl.text.trim().isNotEmpty;
      _emailVerified = user.emailConfirmedAt != null;
      _dirty = false;
    } finally {
      if (mounted) {
        setState(() => _loadingProfile = false);
      }
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickBirthday() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthday ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked != null) {
      setState(() {
        _birthday = picked;
        _dirty = true;
      });
    }
  }

  Future<void> _pickGender() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChoiceSheet(
        title: 'Gender',
        current: _gender,
        items: const [
          'Prefer not to say',
          'Male',
          'Female',
          'Non-binary',
          'Other',
        ],
      ),
    );

    if (picked != null && picked != _gender) {
      setState(() {
        _gender = picked;
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    if (!_dirty || _saving) return;
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _saving = true);

    await _supabase
        .from('profiles')
        .update({
          'full_name': _nameCtrl.text.trim(),
          'mobile': _phoneCtrl.text.trim(),
          'address': _addressCtrl.text.trim(),
          'birthdate': _birthday?.toIso8601String(),
          'gender': _gender,
        })
        .eq('id', user.id);

    if (!mounted) return;
    setState(() {
      _saving = false;
      _dirty = false;
    });

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Personal info saved')));
  }

  void _verifyPhone() {
    if (_phoneCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a phone number first')),
      );
      return;
    }

    setState(() {
      _phoneVerified = true;
      _dirty = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Phone number marked as reachable')),
    );
  }

  Future<void> _verifyEmail() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;

    await _supabase.auth.resend(type: OtpType.signup, email: email);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Verification email sent')));
  }

  Future<void> _changePassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;

    await _supabase.auth.resetPasswordForEmail(email);

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Password reset email sent')));
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);

    if (_loadingProfile) {
      return const Scaffold(
        backgroundColor: bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: bg,

      // âœ… sticky save bar only when there are changes
      bottomNavigationBar: !_dirty
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      elevation: 0,
                      textStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : const Text('Save Changes'),
                  ),
                ),
              ),
            ),

      body: SafeArea(
        child: Column(
          children: [
            // ============================================================
            // TOP BAR
            // ============================================================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  _TopCircleButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Personal Info',
                      style: TextStyle(
                        fontSize: 20.5,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  _PillButton(
                    label: _saving ? 'Saving...' : 'Save',
                    enabled: _dirty && !_saving,
                    onTap: _save,
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: [
                  // ============================================================
                  // TOP CENTER PROFILE PHOTO
                  // ============================================================
                  Column(
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              color: const Color(0xFFEAF2FF),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: const Color(0xFF2A86FF),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              size: 60,
                              color: Color(0xFF2A86FF),
                            ),
                          ),

                          Container(
                            width: 36,
                            height: 36,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2A86FF),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Profile Photo',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Managed from your account',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // ============================================================
                  // PERSONAL DETAILS CARD
                  // ============================================================
                  _Card(
                    child: Column(
                      children: [
                        _FieldTile(
                          label: 'Full Name',
                          controller: _nameCtrl,
                          hint: 'Enter your name',
                        ),
                        const _RowDivider(),

                        _FieldTile(
                          label: 'Email',
                          controller: _emailCtrl,
                          hint: 'Enter email',
                          trailing: _emailVerified
                              ? const _VerifiedChip()
                              : _VerifyChip(onTap: _verifyEmail),
                        ),
                        const _RowDivider(),

                        _FieldTile(
                          label: 'Phone Number',
                          controller: _phoneCtrl,
                          hint: 'Enter phone number',
                          trailing: _phoneVerified
                              ? const _VerifiedChip()
                              : _VerifyChip(onTap: _verifyPhone),
                        ),
                        const _RowDivider(),

                        _TapTile(
                          label: 'Birthday',
                          value: _birthday == null
                              ? 'Set birthday'
                              : _fmtDate(_birthday!),
                          onTap: _pickBirthday,
                        ),
                        const _RowDivider(),

                        _TapTile(
                          label: 'Gender',
                          value: _gender,
                          onTap: _pickGender,
                        ),
                        const _RowDivider(),

                        _FieldTile(
                          label: 'Address',
                          controller: _addressCtrl,
                          hint: 'Optional',
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ============================================================
                  // ACCOUNT ACTIONS
                  // ============================================================
                  _Card(
                    child: Column(
                      children: [
                        _NavRow(
                          icon: Icons.lock_outline_rounded,
                          title: 'Change Password',
                          subtitle: 'Send a password reset email',
                          onTap: _changePassword,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }
}

// ============================================================
// UI PIECES
// ============================================================

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE7EEF7);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF0F172A)),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const line = Color(0xFFE7EEF7);
    const textMid = Color(0xFF64748B);

    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: enabled ? const Color(0xFFEAF2FF) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: enabled ? const Color(0xFFBBD7FF) : line),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: enabled ? blue : textMid,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.label,
    required this.controller,
    required this.hint,
    this.trailing,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final Widget? trailing;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: maxLines > 1
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textMid,
                    fontSize: 12,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: maxLines,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textDark,
                    fontSize: 16,
                    letterSpacing: -0.2,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: hint,
                    hintStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF94A3B8),
                    ),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 10), trailing!],
        ],
      ),
    );
  }
}

class _TapTile extends StatelessWidget {
  const _TapTile({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label.toUpperCase(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: textMid,
                      fontSize: 12,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    value,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: textDark,
                      fontSize: 16,
                      letterSpacing: -0.2,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: textMid),
          ],
        ),
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
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
              width: 42,
              height: 42,
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
                  const SizedBox(height: 5),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textMid,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: textMid),
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
    const line = Color(0xFFE7EEF7);
    return const Padding(
      padding: EdgeInsets.only(left: 54),
      child: Divider(height: 16, color: line),
    );
  }
}

class _VerifyChip extends StatelessWidget {
  const _VerifyChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFBBD7FF)),
        ),
        child: const Text(
          'Verify',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: blue,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

class _VerifiedChip extends StatelessWidget {
  const _VerifiedChip();

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF16A34A);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: const Text(
        'Verified',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: green,
          fontSize: 12.5,
        ),
      ),
    );
  }
}

class _ChoiceSheet extends StatelessWidget {
  const _ChoiceSheet({
    required this.title,
    required this.current,
    required this.items,
  });

  final String title;
  final String current;
  final List<String> items;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE7EEF7);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const blue = Color(0xFF2A86FF);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textDark,
                  fontSize: 16,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Divider(height: 1, color: line),
          const SizedBox(height: 6),
          ...items.map((e) {
            final selected = e == current;
            return InkWell(
              onTap: () => Navigator.pop(context, e),
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFEAF2FF)
                      : const Color(0xFFF8FAFF),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: selected ? blue : line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        e,
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          color: selected ? blue : textMid,
                        ),
                      ),
                    ),
                    if (selected) const Icon(Icons.check_rounded, color: blue),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
