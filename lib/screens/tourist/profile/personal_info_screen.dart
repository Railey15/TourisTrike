import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PersonalInfoScreen extends StatefulWidget {
  const PersonalInfoScreen({super.key});

  @override
  State<PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends State<PersonalInfoScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _postalCodeCtrl = TextEditingController();

  String _imageUrl = '';
  File? _imageFile;
  bool _uploadingImage = false;

  bool _loading = true;
  bool _saving = false;
  DateTime? _birthdate;

  User? get _user => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _barangayCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    _postalCodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final user = _user;
    if (user == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final row = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      _firstNameCtrl.text = (row?['first_name'] ?? '').toString();
      _middleNameCtrl.text = (row?['middle_name'] ?? '').toString();
      _lastNameCtrl.text = (row?['last_name'] ?? '').toString();
      _fullNameCtrl.text = (row?['full_name'] ?? '').toString();
      _phoneCtrl.text = (row?['mobile'] ?? '').toString();
      _addressCtrl.text = (row?['address'] ?? '').toString();
      _barangayCtrl.text = (row?['barangay'] ?? '').toString();
      _cityCtrl.text = (row?['city'] ?? '').toString();
      _provinceCtrl.text = (row?['province'] ?? '').toString();
      _postalCodeCtrl.text = (row?['postal_code'] ?? '').toString();
      _birthdate = _parseDate(row?['birthdate']);
      _imageUrl = (row?['profile_image_url'] ?? row?['avatar_url'] ?? '').toString();
      if (_imageUrl.trim().isEmpty) {
        _imageUrl = (_user?.userMetadata?['avatar_url'] ?? '').toString();
      }

      setState(() => _loading = false);
    } catch (error, stackTrace) {
      debugPrint('PersonalInfoScreen _loadData error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Unable to load your personal information.');
    }
  }

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
    } catch (error) {
      _showError('Could not pick image: $error');
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

      await _supabase.storage.from('public-assets').upload(
            path,
            _imageFile!,
            fileOptions: FileOptions(
              contentType: 'image/$ext',
              upsert: true,
            ),
          );

      final publicUrl = _supabase.storage.from('public-assets').getPublicUrl(path);
      return publicUrl;
    } catch (error) {
      final msg = error.toString();
      if (msg.contains('row-level security') || msg.contains('statusCode: 403') || msg.contains('Unauthorized')) {
        _showError('Image upload failed: Unauthorized. Check your Supabase storage bucket permissions and RLS policy.');
      } else {
        _showError('Image upload failed: $error');
      }
      return null;
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _saveData() async {
    final user = _user;
    if (user == null) {
      _showError('No active session found. Please log in again.');
      return;
    }
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final fullName = _fullNameCtrl.text.trim().isNotEmpty
        ? _fullNameCtrl.text.trim()
        : _composeFullName();

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      final imageUrl = _imageFile != null ? await _uploadProfileImage(user.id) : null;
      final updateData = {
        'first_name': _firstNameCtrl.text.trim(),
        'middle_name': _middleNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'full_name': fullName,
        'mobile': _phoneCtrl.text.trim(),
        'birthdate': _birthdate == null
            ? null
            : DateFormat('yyyy-MM-dd').format(_birthdate!),
        'updated_at': DateTime.now().toIso8601String(),
      };

      final addressValue = _addressCtrl.text.trim();
      if (addressValue.isNotEmpty) {
        updateData['address'] = addressValue;
      }

      final barangayValue = _barangayCtrl.text.trim();
      if (barangayValue.isNotEmpty) {
        updateData['barangay'] = barangayValue;
      }

      final cityValue = _cityCtrl.text.trim();
      if (cityValue.isNotEmpty) {
        updateData['city'] = cityValue;
      }

      final provinceValue = _provinceCtrl.text.trim();
      if (provinceValue.isNotEmpty) {
        updateData['province'] = provinceValue;
      }

      final postalValue = _postalCodeCtrl.text.trim();
      if (postalValue.isNotEmpty) {
        updateData['postal_code'] = postalValue;
      }

      if (imageUrl != null) {
        updateData['profile_image_url'] = imageUrl;
        updateData['avatar_url'] = imageUrl;
      }

      await _supabase
          .from('profiles')
          .update(updateData)
          .eq('id', user.id);

      if (!mounted) return;
      setState(() => _saving = false);
      _showSuccess('Personal information updated.');
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      debugPrint('PersonalInfoScreen _saveData error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _saving = false);
      _showError('Unable to save your changes.');
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

  Future<void> _pickBirthdate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthdate ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: DateTime(1900, 1, 1),
      lastDate: DateTime(now.year, now.month, now.day),
    );

    if (picked == null || !mounted) return;
    setState(() => _birthdate = picked);
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _composeFullName() {
    return [
      _firstNameCtrl.text.trim(),
      _middleNameCtrl.text.trim(),
      _lastNameCtrl.text.trim(),
    ].where((value) => value.isNotEmpty).join(' ');
  }

  String get _birthdateLabel {
    if (_birthdate == null) return 'Select birthdate';
    return DateFormat.yMMMMd().format(_birthdate!);
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);

    if (_loading) {
      return const Scaffold(
        backgroundColor: bg,
        body: Center(child: CircularProgressIndicator(color: blue)),
      );
    }

    return Scaffold(
      backgroundColor: bg,
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            height: 54,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveData,
              style: ElevatedButton.styleFrom(
                backgroundColor: blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text(
                      'Save Changes',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
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
                        color: textDark,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Center(
                child: GestureDetector(
                  onTap: _showImageSourceSheet,
                  child: Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFEAF2FF),
                          image: _imageFile != null
                              ? DecorationImage(
                                  image: FileImage(_imageFile!),
                                  fit: BoxFit.cover,
                                )
                              : _imageUrl.trim().isNotEmpty
                                  ? DecorationImage(
                                      image: NetworkImage(_imageUrl),
                                      fit: BoxFit.cover,
                                    )
                                  : null,
                        ),
                        child: _imageFile == null && _imageUrl.trim().isEmpty
                            ? const Center(
                                child: Icon(
                                  Icons.person_outline_rounded,
                                  size: 40,
                                  color: Color(0xFF2A86FF),
                                ),
                              )
                            : null,
                      ),
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A86FF),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.camera_alt_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_uploadingImage)
                const SizedBox(
                  height: 32,
                  child: Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Color(0xFF2A86FF),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              const Center(
                child: Text(
                  'Tap the photo to change your profile picture.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _SectionCard(
                title: 'Basic Details',
                children: [
                  _AppTextField(
                    controller: _firstNameCtrl,
                    label: 'First Name',
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  _AppTextField(
                    controller: _middleNameCtrl,
                    label: 'Middle Name',
                  ),
                  const SizedBox(height: 12),
                  _AppTextField(
                    controller: _lastNameCtrl,
                    label: 'Last Name',
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  _ReadOnlyField(
                    label: 'Email',
                    value: _user?.email ?? 'No email available',
                  ),
                  const SizedBox(height: 12),
                  _AppTextField(
                    controller: _phoneCtrl,
                    label: 'Mobile Number',
                    keyboardType: TextInputType.phone,
                    validator: _requiredValidator,
                  ),
                  const SizedBox(height: 12),
                  _DateField(
                    label: 'Birthdate',
                    value: _birthdateLabel,
                    onTap: _pickBirthdate,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE7EEF7);
    const textDark = Color(0xFF0F172A);

    return Container(
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _AppTextField extends StatelessWidget {
  const _AppTextField({
    required this.controller,
    required this.label,
    this.validator,
    this.keyboardType,
    this.hintText,
  });

  final TextEditingController controller;
  final String label;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      maxLines: 1,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF2A86FF)),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            const Icon(Icons.calendar_month_rounded),
          ],
        ),
      ),
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
        ),
      ),
      child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
