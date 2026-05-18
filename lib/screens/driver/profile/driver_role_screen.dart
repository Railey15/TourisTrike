import 'package:flutter/material.dart';
import 'package:touristrike/screens/driver/profile/driver_profile_models.dart';

class DriverRoleScreen extends StatelessWidget {
  const DriverRoleScreen({
    super.key,
    required this.profile,
  });

  final DriverProfile profile;

  @override
  Widget build(BuildContext context) {
    final role = profile.role.isEmpty ? 'driver' : profile.role;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6FA),
      appBar: AppBar(
        title: const Text('Role'),
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
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    color: Color(0xFF2F6FFF),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    role,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF172033),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Text(
              'Your role is controlled by the system and cannot be changed from this screen.',
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}