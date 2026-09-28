import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/reports/tour_operations_report.dart';

class TourOperationsReportSection extends StatefulWidget {
  const TourOperationsReportSection({
    super.key,
    required this.start,
    required this.end,
    this.city,
  });

  final DateTime start;
  final DateTime end;
  final String? city;

  @override
  State<TourOperationsReportSection> createState() =>
      _TourOperationsReportSectionState();
}

class _TourOperationsReportSectionState
    extends State<TourOperationsReportSection> {
  late Future<TourOperationsReport> _future;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TourOperationsReportSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.start != widget.start ||
        oldWidget.end != widget.end ||
        oldWidget.city != widget.city) {
      _load();
    }
  }

  void _load() {
    _future = TourOperationsReport.fetch(
      start: widget.start,
      end: widget.end.add(const Duration(milliseconds: 1)),
      city: widget.city,
    );
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(symbol: 'PHP ', decimalDigits: 2);
    return FutureBuilder<TourOperationsReport>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          );
        }
        if (snapshot.hasError) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Tour operations report is unavailable.'),
          );
        }
        final report = snapshot.data!;
        final distribution = Map<String, dynamic>.from(
          report.data['rating_distribution'] as Map? ?? const {},
        );
        final distributionLabel = [
          1,
          2,
          3,
          4,
          5,
        ].map((star) => '$star★ ${distribution['$star'] ?? 0}').join('  ·  ');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'TOUR OPERATIONS',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _metric(
                  'Completed tours',
                  '${report.count('completed_tours')}',
                ),
                _metric(
                  'Tours with overtime',
                  '${report.count('tours_with_overtime')}',
                ),
                _metric(
                  'Overtime minutes',
                  '${report.amount('total_overtime_minutes')}',
                ),
                _metric(
                  '15-minute intervals',
                  '${report.count('chargeable_intervals')}',
                ),
                _metric(
                  'Additional waiting fees',
                  money.format(report.amount('additional_waiting_fees')),
                ),
                _metric(
                  'Confirmed payments collected',
                  money.format(report.amount('confirmed_collections')),
                ),
                _metric(
                  'Average overtime per affected tour',
                  '${report.amount('average_overtime_per_affected_tour')} min',
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'TOURIST FEEDBACK',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 20,
              runSpacing: 8,
              children: [
                _metric(
                  'Tourists reviewed',
                  '${report.count('tourists_reviewed')}',
                ),
                _metric('Driver reviews', '${report.count('tourist_reviews')}'),
                _metric(
                  'Average tourist rating',
                  report.amount('average_tourist_rating').toStringAsFixed(2),
                ),
                _metric(
                  'Low ratings (1–2 stars)',
                  '${(distribution['1'] as num? ?? 0) + (distribution['2'] as num? ?? 0)}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Ratings: $distributionLabel'),
            if (report.rows('municipalities').isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'BY MUNICIPALITY',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final row in report.rows('municipalities'))
                Text(
                  '${row['municipality']}: ${row['affected_bookings']} bookings, '
                  '${row['overtime_minutes']} min, '
                  '${money.format(row['additional_amount'])}',
                ),
            ],
            if (report.rows('destinations').isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                'DESTINATIONS WITH OVERTIME',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              for (final row in report.rows('destinations'))
                Text(
                  '${row['destination']}: ${row['overtime_minutes']} min, '
                  '${money.format(row['additional_amount'])}',
                ),
            ],
          ],
        );
      },
    );
  }

  Widget _metric(String label, String value) => SizedBox(
    width: 170,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    ),
  );
}
