import 'package:flutter/material.dart';
import 'package:touristrike/screens/admin/widgets/admin_gradient_button.dart';
import 'package:touristrike/screens/admin/widgets/admin_section_card.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class AdminEmptyState extends StatelessWidget {
  const AdminEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: ProvincialAdminColors.blue.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: ProvincialAdminColors.blue, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ProvincialAdminColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: ProvincialAdminColors.muted,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            AdminGradientButton(
              label: actionLabel!,
              icon: Icons.add_rounded,
              onPressed: onAction,
            ),
          ],
        ],
      ),
    );
  }
}
