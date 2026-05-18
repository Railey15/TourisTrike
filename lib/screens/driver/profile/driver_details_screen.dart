import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';

class DriverDetailsScreen extends StatefulWidget {
  const DriverDetailsScreen({
    super.key,
    required this.profile,
    required this.details,
  });

  final DriverProfile profile;
  final DriverDetails details;

  @override
  State<DriverDetailsScreen> createState() => _DriverDetailsScreenState();
}

class _DriverDetailsScreenState extends State<DriverDetailsScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  late final TextEditingController _mobileController;
  late final TextEditingController _licenseController;
  late final TextEditingController _plateController;
  late final TextEditingController _todaController;
  late final TextEditingController _operatorController;

  DateTime? _selectedExpiry;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _mobileController = TextEditingController(text: widget.details.mobile);
    _licenseController = TextEditingController(text: widget.details.licenseNumber);
    _plateController = TextEditingController(text: widget.details.plateNumber);
    _todaController = TextEditingController(text: widget.details.todaName);
    _operatorController = TextEditingController(text: widget.details.operatorCode);
    _selectedExpiry = widget.details.licenseExpiry;
  }

  @override
  void dispose() {
    _mobileController.dispose();
    _licenseController.dispose();
    _plateController.dispose();
    _todaController.dispose();
    _operatorController.dispose();
    super.dispose();
  }

  Future<void> _pickExpiry() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: _selectedExpiry ?? DateTime.now(),
    );

    if (picked != null) {
      setState(() => _selectedExpiry = picked);
    }
  }

  Future<void> _save() async {
    try {
      setState(() => _isSaving = true);

      await _supabase.from('driver_details').upsert({
        'driver_id': widget.details.driverId,
        'mobile':
            _mobileController.text.trim().isEmpty ? null : _mobileController.text.trim(),
        'license_number': _licenseController.text.trim().isEmpty
            ? null
            : _licenseController.text.trim(),
        'plate_number':
            _plateController.text.trim().isEmpty ? null : _plateController.text.trim(),
        'license_expiry': _selectedExpiry?.toIso8601String().split('T').first,
        'toda_name':
            _todaController.text.trim().isEmpty ? null : _todaController.text.trim(),
        'operator_code': _operatorController.text.trim().isEmpty
            ? null
            : _operatorController.text.trim(),
      });

      if (!mounted) return;
      _showSnack('Driver details updated', error: false);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to update driver details: $e');
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

  Widget _field(String label, TextEditingController controller,
      {TextInputType? keyboardType}) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Driver Details'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            child: Column(
              children: [
                _field('Driver Mobile', _mobileController,
                    keyboardType: TextInputType.phone),
                const SizedBox(height: 12),
                _field('License Number', _licenseController),
                const SizedBox(height: 12),
                _field('Plate Number', _plateController),
                const SizedBox(height: 12),
                InkWell(
                  onTap: _pickExpiry,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'License Expiry',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5EAF1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide:
                            const BorderSide(color: Color(0xFFE5EAF1)),
                      ),
                    ),
                    child: Text(
                      _selectedExpiry == null
                          ? 'Select expiry date'
                          : DateFormat('MMMM dd, yyyy').format(_selectedExpiry!),
                      style: const TextStyle(
                        color: Color(0xFF172033),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _field('TODA Name', _todaController),
                const SizedBox(height: 12),
                _field('Operator Code', _operatorController),
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