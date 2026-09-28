import 'package:flutter/material.dart';
import 'package:touristrike/screens/main_tenant/widgets/main_tenant_section_card.dart';

class MainTenantDataTable extends StatelessWidget {
  const MainTenantDataTable({super.key, required this.child, this.minWidth = 980});

  final Widget child;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return MainTenantSectionCard(
      padding: EdgeInsets.zero,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minWidth),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
