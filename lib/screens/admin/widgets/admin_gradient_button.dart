import 'package:flutter/material.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class AdminGradientButton extends StatelessWidget {
  const AdminGradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: ProvincialAdminColors.gradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: ProvincialAdminColors.blue.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: loading ? null : onPressed,
        icon: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(icon ?? Icons.check_rounded, color: Colors.white),
        label: Text(
          loading ? 'Saving...' : label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14.5,
            fontWeight: FontWeight.w900,
          ),
        ),
        style: ElevatedButton.styleFrom(
          minimumSize: const Size.fromHeight(50),
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}
