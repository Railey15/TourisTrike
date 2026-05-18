import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';

class DriverPlateNumberScreen extends StatefulWidget {
  const DriverPlateNumberScreen({
    super.key,
    required this.details,
  });

  final DriverDetails details;

  @override
  State<DriverPlateNumberScreen> createState() =>
      _DriverPlateNumberScreenState();
}

class _DriverPlateNumberScreenState extends State<DriverPlateNumberScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late final TextEditingController _plateController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _plateController = TextEditingController(text: widget.details.plateNumber);
  }

  @override
  void dispose() {
    _plateController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      setState(() => _isSaving = true);

      await _supabase.from('driver_details').upsert({
        'driver_id': widget.details.driverId,
        'plate_number':
            _plateController.text.trim().isEmpty ? null : _plateController.text.trim(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Plate number updated'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF16A34A),
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update plate number: $e'),
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
    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Plate Number'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: TextField(
              controller: _plateController,
              decoration: InputDecoration(
                labelText: 'Plate Number',
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
                  borderSide:
                      const BorderSide(color: Color(0xFF2F6FFF), width: 1.3),
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