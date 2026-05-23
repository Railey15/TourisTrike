import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../tourist/tourist_home_screen.dart';

class CompleteProfileScreen extends StatefulWidget {
  const CompleteProfileScreen({super.key});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final supabase = Supabase.instance.client;
  final _picker = ImagePicker();

  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _mobileCtrl = TextEditingController();

  File? _imageFile;
  bool _saving = false;
  bool _uploadingImage = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _mobileCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(msg),
          behavior: SnackBarBehavior.floating,
          backgroundColor:
              isError ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );
  }
  bool _isValidMobile(String s) => RegExp(r'^09\d{9}$').hasMatch(s.trim());

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 800,
        maxHeight: 800,
      );
      if (picked == null) return;
      setState(() => _imageFile = File(picked.path));
    } catch (e) {
      _showSnack('Could not pick image: $e');
    }
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
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
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Profile Photo',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: const Icon(
                Icons.camera_alt_rounded,
                color: Color(0xFF2A86FF),
              ),
              title: const Text(
                'Take Photo',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: const Icon(
                Icons.photo_library_rounded,
                color: Color(0xFF2A86FF),
              ),
              title: const Text(
                'Choose from Gallery',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _uploadProfileImage(String userId) async {
    if (_imageFile == null) return null;

    setState(() => _uploadingImage = true);
    try {
      final ext = _imageFile!.path.split('.').last.toLowerCase();
      final path = 'avatars/$userId.$ext';
      // prefer the multi-part upload which works with client-side File
      await supabase.storage.from('public-assets').upload(
            path,
            _imageFile!,
            fileOptions: FileOptions(
              contentType: 'image/$ext',
              upsert: true,
            ),
          );

      final publicUrl = supabase.storage.from('public-assets').getPublicUrl(path);
      return publicUrl;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('row-level security') || msg.contains('statusCode: 403') || msg.contains('Unauthorized')) {
        _showSnack('Image upload failed: Unauthorized. Check your Supabase storage bucket permissions and RLS policy.');
      } else {
        _showSnack('Image upload failed: $e');
      }
      return null;
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
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

    if (firstName.isEmpty || lastName.isEmpty) {
      _showSnack('Please enter your first and last name.');
      return;
    }
    if (mobile.isEmpty || !_isValidMobile(mobile)) {
      _showSnack('Please enter a valid mobile number starting with 09 and 11 digits long.');
      return;
    }
    if (_imageFile == null) {
      _showSnack('Please upload a profile photo.');
      return;
    }

    setState(() => _saving = true);

    try {
      final imageUrl = await _uploadProfileImage(user.id);

      final updateData = <String, dynamic>{
        'first_name': firstName,
        'last_name': lastName,
        'full_name': '$firstName $lastName'.trim(),
        'mobile': mobile,
        'is_profile_complete': true,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (imageUrl != null) {
        updateData['profile_image_url'] = imageUrl;
        updateData['avatar_url'] = imageUrl;
      }

      await supabase.from('profiles').update(updateData).eq('id', user.id);

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
    final headerH = (size.height * 0.12).clamp(80.0, 110.0);

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
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: Column(
                      children: [
                    _AvatarHeader(
                      imageFile: _imageFile,
                      uploading: _uploadingImage,
                      onUploadTap: _showImageSourceSheet,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Complete your profile',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        height: 1.05,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'A profile photo helps drivers and fellow tourists identify you.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _GlassCard(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const _Label(text: 'First Name'),
                                    const SizedBox(height: 8),
                                    _FancyInputField(
                                      controller: _firstNameCtrl,
                                      hintText: 'Juan',
                                      prefixIcon: Icons.badge_outlined,
                                      keyboardType: TextInputType.name,
                                      textInputAction: TextInputAction.next,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const _Label(text: 'Last Name'),
                                    const SizedBox(height: 8),
                                    _FancyInputField(
                                      controller: _lastNameCtrl,
                                      hintText: 'Dela Cruz',
                                      prefixIcon: Icons.badge_outlined,
                                      keyboardType: TextInputType.name,
                                      textInputAction: TextInputAction.next,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          const _Label(text: 'Mobile Number'),
                          const SizedBox(height: 8),
                          _FancyInputField(
                            controller: _mobileCtrl,
                            hintText: '09XXXXXXXXX',
                            prefixIcon: Icons.phone_outlined,
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.done,
                          ),
                          const SizedBox(height: 18),
                          if (_imageFile == null)
                            _PhotoRequiredBanner(
                              onTap: _showImageSourceSheet,
                            ),
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            height: 54,
                            child: _GradientButton(
                              text: _saving
                                  ? 'Saving...'
                                  : _uploadingImage
                                      ? 'Uploading photo...'
                                      : 'Save Profile',
                              onPressed:
                                  (_saving || _uploadingImage)
                                      ? () {}
                                      : _saveProfile,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'You can update these details later in Settings.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.3,
                          color: const Color(0xFF64748B).withValues(alpha: 0.9),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Avatar header â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AvatarHeader extends StatelessWidget {
  const _AvatarHeader({
    required this.imageFile,
    required this.uploading,
    required this.onUploadTap,
  });

  final File? imageFile;
  final bool uploading;
  final VoidCallback onUploadTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.center,
      children: [
        Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF)],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF2A86FF).withValues(alpha: 0.28),
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
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.75),
                width: 1,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: uploading
                ? const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Color(0xFF2A86FF),
                      ),
                    ),
                  )
                : imageFile != null
                    ? Image.file(imageFile!, fit: BoxFit.cover)
                    : Container(
                        color: const Color(0xFFEAF1FF),
                        child: const Icon(
                          Icons.person_outline_rounded,
                          color: Color(0xFF2A86FF),
                          size: 48,
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
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF2A86FF),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// â”€â”€ Photo required banner â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _PhotoRequiredBanner extends StatelessWidget {
  const _PhotoRequiredBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Profile photo required',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF92400E),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Tap here or the camera icon above to add one.',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF92400E).withValues(alpha: 0.8),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// â”€â”€ Glass card â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

// â”€â”€ Gradient button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A86FF).withValues(alpha: 0.30),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
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
    );
  }
}

// â”€â”€ Label â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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

// â”€â”€ Fancy input field â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _FancyInputField extends StatefulWidget {
  const _FancyInputField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.keyboardType,
    this.obscureText = false,
    this.suffix,
    this.textInputAction,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? suffix;
  final TextInputAction? textInputAction;

  @override
  State<_FancyInputField> createState() => _FancyInputFieldState();
}

class _FancyInputFieldState extends State<_FancyInputField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
  }

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
          color: focused
              ? const Color(0xFF2A86FF)
              : const Color(0xFFE2E8F0),
          width: focused ? 1.5 : 1,
        ),
        boxShadow: [
          if (focused)
            BoxShadow(
              color: const Color(0xFF2A86FF).withValues(alpha: 0.15),
              blurRadius: 18,
              offset: const Offset(0, 10),
            )
          else
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: TextField(
        focusNode: _focus,
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        obscureText: widget.obscureText,
        textInputAction: widget.textInputAction,
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
          prefixIcon: Icon(
            widget.prefixIcon,
            color: focused
                ? const Color(0xFF2A86FF)
                : const Color(0xFF94A3B8),
          ),
          suffixIcon: widget.suffix,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}























































































