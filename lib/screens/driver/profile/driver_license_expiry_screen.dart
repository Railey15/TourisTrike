import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';

class DriverLicenseExpiryScreen extends StatefulWidget {
  const DriverLicenseExpiryScreen({
    super.key,
    required this.details,
  });

  final DriverDetails details;

  @override
  State<DriverLicenseExpiryScreen> createState() =>
      _DriverLicenseExpiryScreenState();
}

class _DriverLicenseExpiryScreenState extends State<DriverLicenseExpiryScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  DateTime? _selectedExpiry;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedExpiry = widget.details.licenseExpiry;
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
        'license_expiry': _selectedExpiry?.toIso8601String().split('T').first,
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('License expiry updated'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF16A34A),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update license expiry: $e'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFFDC2626),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _selectedExpiry == null
        ? 'Select expiry date'
        : DateFormat('MMMM dd, yyyy').format(_selectedExpiry!);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('License Expiry'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InkWell(
            onTap: _pickExpiry,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
              ),
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'License Expiry',
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
              ),
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