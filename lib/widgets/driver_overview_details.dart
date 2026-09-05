import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/supabase/touristrike_models.dart';
import '../screens/driver/driver_package_tracking_screen.dart';

class DriverOverviewDetails extends StatelessWidget {
  const DriverOverviewDetails({
    super.key,
    required this.data,
    required this.onRefresh,
    this.assignmentsOnly = false,
    this.upcoming,
  });
  final Json data;
  final VoidCallback onRefresh;
  final bool assignmentsOnly;
  final bool? upcoming;
  @override
  Widget build(BuildContext context) {
    final assignments = (data['assignments'] as List? ?? [])
        .whereType<Map>()
        .where((a) {
          if (upcoming == null) return true;
          final isUpcoming =
              a['journey_state'] == 'assigned' &&
              dbDate(a['scheduled_start_at'])?.isAfter(DateTime.now()) == true;
          return upcoming == isUpcoming;
        });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (assignmentsOnly) ...[
          for (final assignment in assignments)
            Card(
              child: ListTile(
                leading: const Icon(Icons.route_outlined),
                title: Text(
                  dbString(assignment['title'], fallback: 'Tour assignment'),
                ),
                subtitle: Text(
                  [
                    dbString(assignment['journey_state']).replaceAll('_', ' '),
                    if (dbDate(assignment['scheduled_start_at'])
                        case final start?)
                      DateFormat('MMM d, h:mm a').format(start.toLocal()),
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: assignment['activity_id'] == null
                    ? null
                    : () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DriverPackageTrackingScreen(
                              activityId: assignment['activity_id'].toString(),
                            ),
                          ),
                        );
                        onRefresh();
                      },
              ),
            ),
          if (assignments.isEmpty)
            ListTile(
              title: Text(
                upcoming == true
                    ? 'No upcoming tour assignments'
                    : 'No active tour assignments',
              ),
            ),
        ] else ...[
          const SizedBox(height: 12),
          Text(
            '${dbInt(data['active_trips'])} active · ${dbInt(data['upcoming_trips'])} upcoming',
          ),
          const SizedBox(height: 8),
          Text(
            '${dbInt(data['review_count'])} driver reviews',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final review
              in (data['recent_reviews'] as List? ?? []).whereType<Map>())
            Card(
              child: ListTile(
                leading: const Icon(Icons.star, color: Colors.amber),
                title: Text('${dbInt(review['rating'])}/5'),
                subtitle: Text(
                  dbString(review['review_text'], fallback: 'Rating submitted'),
                ),
              ),
            ),
        ],
      ],
    );
  }
}
