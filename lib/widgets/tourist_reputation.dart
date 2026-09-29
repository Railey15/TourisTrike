import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

typedef TouristReputationLoader = Future<Map<String, dynamic>> Function(String);

/// Booking-scoped reputation only; the RPC never exposes contact information.
class TouristReputation extends StatefulWidget {
  const TouristReputation({super.key, required this.bookingId, this.load});
  final String bookingId;
  final TouristReputationLoader? load;

  @override
  State<TouristReputation> createState() => _TouristReputationState();
}

class _TouristReputationState extends State<TouristReputation> {
  late Future<Map<String, dynamic>> _future;
  Future<Map<String, dynamic>> _fetch() =>
      (widget.load ?? TourisTrikeRepository().fetchTouristReputation)(
        widget.bookingId,
      );

  void _refresh() {
    final request = _fetch();
    setState(() {
      _future = request;
    });
  }

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(covariant TouristReputation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingId != widget.bookingId) _future = _fetch();
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _future,
    builder: (context, snapshot) {
      final data = snapshot.data;
      final count = (data?['total_reviews'] as num?)?.toInt() ?? 0;
      final name = data?['display_name']?.toString().trim() ?? '';
      return ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.person_outline, color: Color(0xFF2563EB)),
        title: Text(
          name.isEmpty ? 'Tourist' : name,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          snapshot.hasError
              ? 'Reputation unavailable — tap to retry'
              : data == null
              ? 'Loading reputation…'
              : count == 0
              ? 'No ratings yet'
              : '★ ${(data['average_rating'] as num).toStringAsFixed(1)} · $count review${count == 1 ? '' : 's'}',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          if (data == null) {
            _refresh();
            return;
          }
          await showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            builder: (_) => TouristRatingSheet(data: data),
          );
          if (mounted) _refresh();
        },
      );
    },
  );
}

class TouristRatingSheet extends StatelessWidget {
  const TouristRatingSheet({super.key, required this.data});
  final Map<String, dynamic> data;
  @override
  Widget build(BuildContext context) {
    final count = (data['total_reviews'] as num).toInt();
    final reviews = (data['reviews'] as List? ?? const []).whereType<Map>();
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .8,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Tourist rating',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Text(
              data['display_name']?.toString() ?? 'Tourist',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            if (count == 0)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No ratings yet'),
              )
            else ...[
              Text(
                '★ ${(data['average_rating'] as num).toStringAsFixed(1)} · $count Driver review${count == 1 ? '' : 's'}',
              ),
              const SizedBox(height: 12),
              for (var star = 5; star >= 1; star--)
                Text(
                  '$star ★  ${(data['distribution'] as Map?)?['$star'] ?? 0}',
                ),
              const Divider(height: 28),
              const Text('Recent Driver reviews'),
              for (final review in reviews)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('★ ${review['rating']} / 5'),
                      if ((review['review_text']?.toString() ?? '').isNotEmpty)
                        Text(review['review_text'].toString()),
                      if (DateTime.tryParse('${review['created_at']}')
                          case final date?)
                        Text(
                          DateFormat.yMMMd().format(date.toLocal()),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
