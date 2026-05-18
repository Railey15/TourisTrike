import 'package:flutter/material.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/widgets/admin_section_card.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class AdminMetricCard extends StatefulWidget {
  const AdminMetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.color = ProvincialAdminColors.blue,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  State<AdminMetricCard> createState() => _AdminMetricCardState();
}

class _AdminMetricCardState extends State<AdminMetricCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered && !Responsive.isMobile(context) ? 1.015 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(22),
            child: AdminSectionCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              widget.color.withValues(alpha: 0.86),
                              widget.color,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: widget.color.withValues(alpha: 0.18),
                              blurRadius: 14,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Icon(widget.icon, color: Colors.white, size: 22),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.trending_up_rounded,
                        color: widget.color.withValues(alpha: 0.55),
                        size: 20,
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    widget.value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: ProvincialAdminColors.text,
                      fontSize: Responsive.isMobile(context) ? 24 : 28,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ProvincialAdminColors.muted,
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (widget.subtitle != null &&
                      widget.subtitle!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProvincialAdminColors.lightMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
