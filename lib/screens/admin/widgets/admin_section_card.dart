import 'package:flutter/material.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class AdminSectionCard extends StatelessWidget {
  const AdminSectionCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: margin,
      padding:
          padding ??
          Responsive.responsiveValue<EdgeInsets>(
            context,
            mobile: const EdgeInsets.all(16),
            tablet: const EdgeInsets.all(18),
            desktop: const EdgeInsets.all(20),
          ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: ProvincialAdminColors.line),
        boxShadow: [provincialAdminShadow()],
      ),
      child: child,
    );
  }
}
