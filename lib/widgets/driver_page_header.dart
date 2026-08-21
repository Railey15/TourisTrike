import 'package:flutter/material.dart';

/// A single summary item displayed in [DriverPageHeader].
class DriverHeaderStat {
  const DriverHeaderStat({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;
}

/// Shared blue header shell for the main driver navigation screens.
///
/// The widget owns the top safe-area inset so its parent must not add another
/// top inset. Use [DriverPageHeader.custom] when a page needs a richer title
/// row, such as the driver profile shown on the home screen.
class DriverPageHeader extends StatelessWidget {
  const DriverPageHeader({
    super.key,
    required IconData this.icon,
    required String this.title,
    this.subtitle,
    this.action,
    this.onRefresh,
    this.stats = const [],
    this.customContent,
  }) : headerContent = null;

  const DriverPageHeader.custom({
    super.key,
    required Widget this.headerContent,
    this.stats = const [],
    this.customContent,
  }) : icon = null,
       title = null,
       subtitle = null,
       action = null,
       onRefresh = null;

  final IconData? icon;
  final String? title;
  final String? subtitle;
  final Widget? action;
  final VoidCallback? onRefresh;
  final List<DriverHeaderStat> stats;
  final Widget? customContent;
  final Widget? headerContent;

  /// Height of the blue header below the device's top safe-area inset.
  static const double standardHeight = 184;
  static const EdgeInsets contentPadding = EdgeInsets.fromLTRB(18, 14, 18, 16);
  static const double outerRadius = 28;
  static const double iconBoxSize = 42;
  static const double actionSize = 42;
  static const double statPanelHeight = 74;
  static const double profileAvatarSize = 50;

  static const LinearGradient gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2563EB), Color(0xFF3188FF), Color(0xFF49B8F7)],
    stops: [0, 0.58, 1],
  );

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;

    return Container(
      width: double.infinity,
      height: topInset + standardHeight,
      padding: contentPadding.copyWith(top: topInset + contentPadding.top),
      decoration: const BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(outerRadius),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          headerContent ?? _buildStandardHeader(),
          if (customContent != null || stats.isNotEmpty)
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (customContent != null)
                    Flexible(
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: customContent!,
                      ),
                    ),
                  if (customContent != null && stats.isNotEmpty)
                    const SizedBox(height: 8),
                  if (stats.isNotEmpty) _DriverHeaderStats(stats: stats),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStandardHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: iconBoxSize,
          height: iconBoxSize,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Icon(icon, color: Colors.white, size: 21),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  letterSpacing: -0.35,
                  height: 1.1,
                ),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFDCEAFF),
                    fontWeight: FontWeight.w600,
                    fontSize: 11.5,
                    height: 1.25,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null || onRefresh != null) ...[
          const SizedBox(width: 10),
          action ??
              DriverHeaderActionButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Refresh',
                onPressed: onRefresh!,
              ),
        ],
      ],
    );
  }
}

/// Standard compact icon action used on a driver header.
class DriverHeaderActionButton extends StatelessWidget {
  const DriverHeaderActionButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.white.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: DriverPageHeader.actionSize,
          height: DriverPageHeader.actionSize,
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// Standard pill treatment for short non-interactive header labels.
class DriverHeaderBadge extends StatelessWidget {
  const DriverHeaderBadge({super.key, required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 13),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            maxLines: 1,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverHeaderStats extends StatelessWidget {
  const _DriverHeaderStats({required this.stats});

  final List<DriverHeaderStat> stats;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DriverPageHeader.statPanelHeight,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (var index = 0; index < stats.length; index++) ...[
            if (index > 0) const _DriverHeaderStatDivider(),
            Expanded(child: _DriverHeaderStat(stat: stats[index])),
          ],
        ],
      ),
    );
  }
}

class _DriverHeaderStat extends StatelessWidget {
  const _DriverHeaderStat({required this.stat});

  final DriverHeaderStat stat;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(stat.icon, color: Colors.white, size: 17),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: 15,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                stat.value,
                maxLines: 1,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                  height: 1,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            stat.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontWeight: FontWeight.w600,
              fontSize: 9.5,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _DriverHeaderStatDivider extends StatelessWidget {
  const _DriverHeaderStatDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 42,
      color: Colors.white.withValues(alpha: 0.17),
    );
  }
}
