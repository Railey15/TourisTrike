import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';

class DriverTodaAssignmentScreen extends StatefulWidget {
  const DriverTodaAssignmentScreen({
    super.key,
    required this.details,
  });

  final DriverDetails details;

  @override
  State<DriverTodaAssignmentScreen> createState() =>
      _DriverTodaAssignmentScreenState();
}

class _DriverTodaAssignmentScreenState
    extends State<DriverTodaAssignmentScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  late final TextEditingController _todaController;
  late final TextEditingController _operatorController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _todaController = TextEditingController(text: widget.details.todaName);
    _operatorController =
        TextEditingController(text: widget.details.operatorCode);
  }

  @override
  void dispose() {
    _todaController.dispose();
    _operatorController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    try {
      setState(() => _isSaving = true);

      await _supabase.from('driver_details').upsert({
        'driver_id': widget.details.driverId,
        'toda_name':
            _todaController.text.trim().isEmpty ? null : _todaController.text.trim(),
        'operator_code': _operatorController.text.trim().isEmpty
            ? null
            : _operatorController.text.trim(),
      });

      if (!mounted) return;
      _showSnack('TODA assignment updated', error: false);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      _showSnack('Failed to update TODA assignment: $e');
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

  Widget _field(String label, TextEditingController controller) {
    return TextField(
      controller: controller,
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
        title: const Text('TODA Assignment'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Card(
            child: Column(
              children: [
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