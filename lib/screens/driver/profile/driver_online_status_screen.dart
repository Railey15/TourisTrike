import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';

class DriverOnlineStatusScreen extends StatefulWidget {
  const DriverOnlineStatusScreen({
    super.key,
    required this.profile,
  });

  final DriverProfile profile;

  @override
  State<DriverOnlineStatusScreen> createState() =>
      _DriverOnlineStatusScreenState();
}

class _DriverOnlineStatusScreenState extends State<DriverOnlineStatusScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late bool _isOnline;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _isOnline = widget.profile.isOnline;
  }

  Future<void> _toggle(bool value) async {
    try {
      setState(() {
        _isOnline = value;
        _isSaving = true;
      });

      await _supabase.from('profiles').update({
        'is_online': value,
      }).eq('id', widget.profile.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'Driver is now online' : 'Driver is now offline'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isOnline = !_isOnline);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update online status: $e'),
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
    final statusText = _isOnline ? 'Online' : 'Offline';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Online Status'),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(23),
                  ),
                  child: Icon(
                    Icons.circle_outlined,
                    color: _isOnline
                        ? const Color(0xFF16A34A)
                        : const Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current Driver Status',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          color: Color(0xFF172033),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: _isOnline
                              ? const Color(0xFF16A34A)
                              : const Color(0xFF6B7280),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _isOnline,
                  onChanged: _isSaving ? null : _toggle,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}