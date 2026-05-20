import 'package:flutter/material.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class ResponsivePageContainer extends StatelessWidget {
  const ResponsivePageContainer({
    super.key,
    this.children,
    this.child,
    this.padding,
    this.maxWidth = double.infinity,
    this.physics,
    this.controller,
  }) : assert(
         child != null || children != null,
         'Provide either child or children.',
       );

  final List<Widget>? children;
  final Widget? child;
  final EdgeInsetsGeometry? padding;
  final double maxWidth;
  final ScrollPhysics? physics;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final content =
        child ??
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children!,
        );
    final pageContent = maxWidth.isFinite
        ? Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: content,
            ),
          )
        : content;

    return ListView(
      controller: controller,
      physics:
          physics ??
          AlwaysScrollableScrollPhysics(
            parent: Responsive.isMobile(context)
                ? const BouncingScrollPhysics()
                : const ClampingScrollPhysics(),
          ),
      padding: padding ?? _subTenantPagePadding(context),
      children: [pageContent],
    );
  }
}

EdgeInsets _subTenantPagePadding(BuildContext context) {
  return Responsive.responsiveValue<EdgeInsets>(
    context,
    mobile: const EdgeInsets.fromLTRB(16, 12, 16, 112),
    tablet: const EdgeInsets.fromLTRB(16, 18, 16, 28),
    desktop: const EdgeInsets.fromLTRB(16, 24, 16, 34),
  );
}

class ResponsiveGrid extends StatelessWidget {
  const ResponsiveGrid({
    super.key,
    required this.children,
    this.minItemWidth = 220,
    this.minColumns = 1,
    this.maxColumns = 4,
    this.spacing = 14,
    this.runSpacing = 14,
    this.mobileAspectRatio = 1.55,
    this.tabletAspectRatio = 1.35,
    this.desktopAspectRatio = 1.45,
  });

  final List<Widget> children;
  final double minItemWidth;
  final int minColumns;
  final int maxColumns;
  final double spacing;
  final double runSpacing;
  final double mobileAspectRatio;
  final double tabletAspectRatio;
  final double desktopAspectRatio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        var columns = constraints.maxWidth ~/ minItemWidth;
        if (columns < minColumns) columns = minColumns;
        if (columns > maxColumns) columns = maxColumns;
        if (children.length < columns && children.isNotEmpty) {
          columns = children.length;
        }

        final aspectRatio = Responsive.responsiveValue<double>(
          context,
          mobile: mobileAspectRatio,
          tablet: tabletAspectRatio,
          desktop: desktopAspectRatio,
        );

        return GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: columns,
          crossAxisSpacing: spacing,
          mainAxisSpacing: runSpacing,
          childAspectRatio: aspectRatio,
          children: children,
        );
      },
    );
  }
}

class DashboardSectionCard extends StatelessWidget {
  const DashboardSectionCard({
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
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: SubTenantColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.055),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class DashboardMetricCard extends StatefulWidget {
  const DashboardMetricCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    this.color = SubTenantColors.blue,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  State<DashboardMetricCard> createState() => _DashboardMetricCardState();
}

class _DashboardMetricCardState extends State<DashboardMetricCard> {
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
            child: DashboardSectionCard(
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
                      color: SubTenantColors.text,
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
                      color: SubTenantColors.muted,
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
                        color: SubTenantColors.lightMuted,
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

class ResponsiveTableWrapper extends StatelessWidget {
  const ResponsiveTableWrapper({
    super.key,
    required this.child,
    this.minWidth = 900,
  });

  final Widget child;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
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

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({
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
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5DB4FF), Color(0xFF2A86FF), Color(0xFF1E63E9)],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: SubTenantColors.blue.withValues(alpha: 0.24),
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
              child: _DashboardHeaderCopy(
                eyebrow: eyebrow,
                title: title,
                subtitle: subtitle,
                desktop: desktop,
              ),
            )
          else
            _DashboardHeaderCopy(
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

class _DashboardHeaderCopy extends StatelessWidget {
  const _DashboardHeaderCopy({
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

class PageTitleBar extends StatelessWidget {
  const PageTitleBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final compact = !Responsive.isDesktop(context);

    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 12)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 4),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: SubTenantColors.text,
                  fontSize: compact ? 20 : 24,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SubTenantColors.muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actions.isNotEmpty) ...[
          const SizedBox(width: 14),
          Flexible(
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 10,
              runSpacing: 8,
              children: actions,
            ),
          ),
        ],
      ],
    );
  }
}

class EmptyStateCard extends StatelessWidget {
  const EmptyStateCard({
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
    return DashboardSectionCard(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: SubTenantColors.blue.withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, color: SubTenantColors.blue, size: 30),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SubTenantColors.text,
              fontSize: 17,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SubTenantColors.muted,
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 18),
            SubTenantGradientButton(
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
