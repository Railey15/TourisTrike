import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';

class DriverPersonalInfoScreen extends StatefulWidget {
  const DriverPersonalInfoScreen({
    super.key,
    required this.profile,
  });

  final DriverProfile profile;

  @override
  State<DriverPersonalInfoScreen> createState() =>
      _DriverPersonalInfoScreenState();
}

class _DriverPersonalInfoScreenState extends State<DriverPersonalInfoScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _firstNameController;
  late final TextEditingController _middleNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _mobileController;
  late final TextEditingController _genderController;
  late final TextEditingController _addressController;
  late final TextEditingController _barangayController;
  late final TextEditingController _cityController;
  late final TextEditingController _provinceController;
  late final TextEditingController _postalCodeController;

  DateTime? _selectedBirthdate;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    _firstNameController = TextEditingController(text: p.firstName);
    _middleNameController = TextEditingController(text: p.middleName);
    _lastNameController = TextEditingController(text: p.lastName);
    _mobileController = TextEditingController(text: p.mobile);
    _genderController = TextEditingController(text: p.gender);
    _addressController = TextEditingController(text: p.address);
    _barangayController = TextEditingController(text: p.barangay);
    _cityController = TextEditingController(text: p.city);
    _provinceController = TextEditingController(text: p.province);
    _postalCodeController = TextEditingController(text: p.postalCode);
    _selectedBirthdate = p.birthdate;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _mobileController.dispose();
    _genderController.dispose();
    _addressController.dispose();
    _barangayController.dispose();
    _cityController.dispose();
    _provinceController.dispose();
    _postalCodeController.dispose();
    super.dispose();
  }

  Future<void> _pickBirthdate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
      initialDate: _selectedBirthdate ?? DateTime(2000, 1, 1),
    );

    if (picked != null) {
      setState(() => _selectedBirthdate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      setState(() => _isSaving = true);

      final firstName = _firstNameController.text.trim();
      final middleName = _middleNameController.text.trim();
      final lastName = _lastNameController.text.trim();

      final fullName = [firstName, middleName, lastName]
          .where((e) => e.isNotEmpty)
          .join(' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      await _supabase.from('profiles').upsert({
        'id': widget.profile.id,
        'role': widget.profile.role.isEmpty ? 'driver' : widget.profile.role,
        'first_name': firstName.isEmpty ? null : firstName,
        'middle_name': middleName.isEmpty ? null : middleName,
        'last_name': lastName.isEmpty ? null : lastName,
        'full_name': fullName.isEmpty ? null : fullName,
        'mobile': _mobileController.text.trim().isEmpty
            ? null
            : _mobileController.text.trim(),
        'gender': _genderController.text.trim().isEmpty
            ? null
            : _genderController.text.trim(),
        'birthdate': _selectedBirthdate?.toIso8601String().split('T').first,
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'barangay': _barangayController.text.trim().isEmpty
            ? null
            : _barangayController.text.trim(),
        'city': _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        'province': _provinceController.text.trim().isEmpty
            ? null
            : _provinceController.text.trim(),
        'postal_code': _postalCodeController.text.trim().isEmpty
            ? null
            : _postalCodeController.text.trim(),
      });

      if (!mounted) return;
      _showSnack('Personal info updated', error: false);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to update personal info: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnack(String message, {bool error = true}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            error ? const Color(0xFFDC2626) : const Color(0xFF16A34A),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE5EAF1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE5EAF1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFF2F6FFF), width: 1.3),
        ),
      ),
    );
  }

  Widget _readOnlyField(String label, String value) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE5EAF1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE5EAF1)),
        ),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: Color(0xFF172033),
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final email = _supabase.auth.currentUser?.email ?? 'No email available';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Personal Info'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Card(
              child: Column(
                children: [
                  _readOnlyField('Email', email),
                  const SizedBox(height: 12),
                  _readOnlyField(
                    'Role',
                    widget.profile.role.isEmpty ? 'driver' : widget.profile.role,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Card(
              child: Column(
                children: [
                  _field(
                    'First Name',
                    _firstNameController,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  _field('Middle Name', _middleNameController),
                  const SizedBox(height: 12),
                  _field(
                    'Last Name',
                    _lastNameController,
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 12),
                  _field('Mobile', _mobileController,
                      keyboardType: TextInputType.phone),
                  const SizedBox(height: 12),
                  _field('Gender', _genderController),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: _pickBirthdate,
                    child: _readOnlyField(
                      'Birthdate',
                      _selectedBirthdate == null
                          ? 'Select birthdate'
                          : DateFormat('MMMM dd, yyyy')
                              .format(_selectedBirthdate!),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _Card(
              child: Column(
                children: [
                  _field('Address', _addressController, maxLines: 2),
                  const SizedBox(height: 12),
                  _field('Barangay', _barangayController),
                  const SizedBox(height: 12),
                  _field('City', _cityController),
                  const SizedBox(height: 12),
                  _field('Province', _provinceController),
                  const SizedBox(height: 12),
                  _field('Postal Code', _postalCodeController,
                      keyboardType: TextInputType.number),
                ],
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2F6FFF),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
      ),
      child: child,
    );
  }
}