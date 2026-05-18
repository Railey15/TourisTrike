import 'package:flutter/material.dart';
import 'package:touristrike/screens/admin/admin_models.dart';

class AdminStatusPill extends StatelessWidget {
  const AdminStatusPill({super.key, required this.status, this.icon});

  final String status;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final color = adminStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? Icons.circle, color: color, size: icon == null ? 8 : 13),
          const SizedBox(width: 6),
          Text(
            adminTitleCase(status),
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
