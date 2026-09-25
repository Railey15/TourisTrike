import 'package:flutter/material.dart';
import '../core/notifications/tour_notification.dart';

/// Pure presentation: never creates events, marks history read, or takes focus.
class NotificationForegroundBanner extends StatelessWidget {
  const NotificationForegroundBanner({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDismiss,
  });
  final TourNotification item;
  final VoidCallback onTap, onDismiss;

  (IconData, Color) _category(ColorScheme colors) {
    final type = item.type;
    if (type.contains('emergency')) {
      return (Icons.emergency_outlined, colors.error);
    }
    if (type.contains('cancel') ||
        type.contains('failed') ||
        type.contains('rejected')) {
      return (Icons.warning_amber_rounded, colors.error);
    }
    if (type.contains('confirmed') || type.contains('completed')) {
      return (Icons.check_circle_outline_rounded, const Color(0xFF15803D));
    }
    if (type.contains('payment') ||
        type.contains('balance') ||
        type.contains('cash')) {
      return (Icons.account_balance_wallet_outlined, const Color(0xFFB45309));
    }
    if (type.contains('arrived') || type.contains('pickup')) {
      return (Icons.location_on_outlined, colors.primary);
    }
    if (type.contains('booking') ||
        type.contains('job') ||
        type.contains('assigned')) {
      return (Icons.event_available_outlined, colors.primary);
    }
    return (Icons.local_taxi_outlined, colors.primary);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (icon, accent) = _category(theme.colorScheme);
    final age = DateTime.now().difference(item.createdAt);
    final time = age.inMinutes < 1 ? 'Just now' : '${age.inMinutes} min ago';
    return Semantics(
      container: true,
      liveRegion: true,
      child: Dismissible(
        key: ValueKey('notification-${item.id}'),
        direction: DismissDirection.up,
        movementDuration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
        dismissThresholds: const {DismissDirection.up: 0.2},
        confirmDismiss: (_) async {
          onDismiss();
          return false;
        },
        child: Material(
          color: theme.colorScheme.surface,
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: BorderSide(color: accent.withValues(alpha: 0.18)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            canRequestFocus: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, size: 22, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          time,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 11,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      tooltip: 'Dismiss notification',
                      onPressed: onDismiss,
                      icon: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
