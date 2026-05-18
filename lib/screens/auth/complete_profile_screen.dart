import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../tourist/tourist_home_screen.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final supabase = Supabase.instance.client;

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  String? _gender;
  ImageProvider? _profileImage; // UI-only

  bool _saving = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _mobileCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  bool _isValidMobile(String s) {
    final v = s.trim();
    // simple PH mobile check (adjust if needed)
    return v.length >= 10;
  }

  Future<void> _saveProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showSnack('No active session. Please log in again.');
      return;
    }

    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final mobile = _mobileCtrl.text.trim();
    final address = _addressCtrl.text.trim();
    final gender = _gender;

    if (firstName.isEmpty || lastName.isEmpty) {
      _showSnack('Please enter your first and last name.');
      return;
    }
    if (mobile.isEmpty || !_isValidMobile(mobile)) {
      _showSnack('Please enter a valid mobile number.');
      return;
    }
    if (gender == null || gender.isEmpty) {
      _showSnack('Please select your gender.');
      return;
    }
    if (address.isEmpty) {
      _showSnack('Please enter your address.');
      return;
    }

    setState(() => _saving = true);

    try {
      await supabase.from('profiles').update({
        'first_name': firstName,
        'last_name': lastName,
        // full_name will be auto-set by trigger (if you added it),
        // but we also send it just in case you skip the trigger:
        'full_name': '$firstName $lastName'.trim(),
        'mobile': mobile,
        'gender': gender,
        'address': address,
      }).eq('id', user.id);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const TouristHomeScreen()),
      );
    } on PostgrestException catch (e) {
      _showSnack('Save failed: ${e.message}');
    } catch (e) {
      _showSnack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final headerH = (size.height * 0.14).clamp(96.0, 120.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: headerH,
              width: double.infinity,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ),
            _AvatarHeader(
              image: _profileImage,
              onUploadTap: () {
                // UI only
              },
            ),
            const SizedBox(height: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const Text(
                      'Complete your profile',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        height: 1.05,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This helps drivers and tourists identify you easily.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _GlassCard(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  children: [
                                    const _Label(text: 'First Name'),
                                    const SizedBox(height: 8),
                                    _FancyInputField(
                                      controller: _firstNameCtrl,
                                      hintText: 'Juan',
                                      prefixIcon: Icons.badge_outlined,
                                      keyboardType: TextInputType.name,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  children: [
                                    const _Label(text: 'Last Name'),
                                    const SizedBox(height: 8),
                                    _FancyInputField(
                                      controller: _lastNameCtrl,
                                      hintText: 'Dela Cruz',
                                      prefixIcon: Icons.badge_outlined,
                                      keyboardType: TextInputType.name,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const _Label(text: 'Mobile Number'),
                          const SizedBox(height: 8),
                          _FancyInputField(
                            controller: _mobileCtrl,
                            hintText: '09XXXXXXXXX',
                            prefixIcon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                          ),
                          const SizedBox(height: 12),
                          const _Label(text: 'Gender'),
                          const SizedBox(height: 8),
                          _DropdownField(
                            value: _gender,
                            hintText: 'Select gender',
                            items: const ['Male', 'Female', 'Prefer not to say'],
                            prefixIcon: Icons.wc_outlined,
                            onChanged: (v) => setState(() => _gender = v),
                          ),
                          const SizedBox(height: 12),
                          const _Label(text: 'Address'),
                          const SizedBox(height: 8),
                          _FancyInputField(
                            controller: _addressCtrl,
                            hintText: 'Street, Barangay, Bustos, Bulacan',
                            prefixIcon: Icons.location_on_outlined,
                            keyboardType: TextInputType.streetAddress,
                          ),
                          const SizedBox(height: 14),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: _GradientButton(
                              text: _saving ? 'Saving...' : 'Save Profile',
                              onPressed: _saving ? () {} : _saveProfile,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'You can edit these details later in Settings.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: const Color(0xFF64748B).withOpacity(0.95),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Avatar (unchanged)
class _AvatarHeader extends StatelessWidget {
  const _AvatarHeader({required this.image, required this.onUploadTap});

  final ImageProvider? image;
  final VoidCallback onUploadTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2A86FF).withOpacity(0.28),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          padding: const EdgeInsets.all(3),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF5F7FB),
              border: Border.all(color: Colors.white.withOpacity(0.75), width: 1),
            ),
            child: ClipOval(
              child: image != null
                  ? Image(image: image!, fit: BoxFit.cover)
                  : Container(
                      color: const Color(0xFFEAF1FF),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        color: Color(0xFF2A86FF),
                        size: 42,
                      ),
                    ),
            ),
          ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: InkWell(
            onTap: onUploadTap,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2A86FF),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 18),
            ),
          ),
        ),
      ],
    );
  }
}

/// --- UI components (unchanged from your file) ---
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.text, required this.onPressed});
  final String text;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A86FF).withOpacity(0.30),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w900,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }
}

class _FancyInputField extends StatefulWidget {
  const _FancyInputField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;

  @override
  State<_FancyInputField> createState() => _FancyInputFieldState();
}

class _FancyInputFieldState extends State<_FancyInputField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
        border: Border.all(
          color: focused ? const Color(0xFF2A86FF) : const Color(0xFFE2E8F0),
          width: focused ? 1.5 : 1,
        ),
        boxShadow: [
          if (focused)
            BoxShadow(
              color: const Color(0xFF2A86FF).withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, 10),
            )
          else
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: TextField(
        focusNode: _focus,
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        obscureText: widget.obscureText,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF94A3B8),
          ),
          prefixIcon: Icon(widget.prefixIcon, color: const Color(0xFF94A3B8)),
          suffixIcon: widget.suffix,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}

class _DropdownField extends StatelessWidget {
  const _DropdownField({
    required this.value,
    required this.hintText,
    required this.items,
    required this.prefixIcon,
    required this.onChanged,
  });

  final String? value;
  final String hintText;
  final List<String> items;
  final IconData prefixIcon;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          icon: const Padding(
            padding: EdgeInsets.only(right: 10),
            child: Icon(Icons.expand_more_rounded, color: Color(0xFF94A3B8)),
          ),
          hint: Row(
            children: [
              const SizedBox(width: 12),
              Icon(prefixIcon, color: const Color(0xFF94A3B8)),
              const SizedBox(width: 12),
              Text(
                hintText,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF94A3B8),
                ),
              ),
            ],
          ),
          items: items
              .map(
                (g) => DropdownMenuItem(
                  value: g,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(
                      children: [
                        Icon(prefixIcon, color: const Color(0xFF94A3B8)),
                        const SizedBox(width: 12),
                        Text(
                          g,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}