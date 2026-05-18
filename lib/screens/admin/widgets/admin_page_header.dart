import 'package:flutter/material.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class AdminPageHeader extends StatelessWidget {
  const AdminPageHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.eyebrow,
    this.icon = Icons.admin_panel_settings_rounded,
    this.trailing,
  });

  final String? eyebrow;
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(desktop ? 26 : 20),
      decoration: BoxDecoration(
        gradient: ProvincialAdminColors.gradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: ProvincialAdminColors.blue.withValues(alpha: 0.24),
            blurRadius: 28,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Flex(
        direction: desktop ? Axis.horizontal : Axis.vertical,
        crossAxisAlignment: desktop
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          SizedBox(width: desktop ? 16 : 0, height: desktop ? 0 : 14),
          if (desktop)
            Expanded(
              child: _HeaderCopy(
                eyebrow: eyebrow,
                title: title,
                subtitle: subtitle,
                desktop: desktop,
              ),
            )
          else
            _HeaderCopy(
              eyebrow: eyebrow,
              title: title,
              subtitle: subtitle,
              desktop: desktop,
            ),
          if (trailing != null) ...[
            SizedBox(width: desktop ? 18 : 0, height: desktop ? 0 : 18),
            trailing!,
          ],
        ],
      ),
    );
  }
}

class _HeaderCopy extends StatelessWidget {
  const _HeaderCopy({
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.desktop,
  });

  final String? eyebrow;
  final String title;
  final String subtitle;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (eyebrow != null && eyebrow!.isNotEmpty) ...[
          Text(
            eyebrow!.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.78),
              fontSize: 11,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 7),
        ],
        Text(
          title,
          maxLines: desktop ? 1 : 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white,
            fontSize: desktop ? 30 : 22,
            height: 1.05,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          maxLines: desktop ? 2 : 4,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.88),
            fontSize: desktop ? 14 : 13,
            height: 1.45,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
