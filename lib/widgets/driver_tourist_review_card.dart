import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverTouristReviewCard extends StatefulWidget {
  const DriverTouristReviewCard({super.key, required this.bookingId});

  final String bookingId;

  @override
  State<DriverTouristReviewCard> createState() =>
      _DriverTouristReviewCardState();
}

class _DriverTouristReviewCardState extends State<DriverTouristReviewCard> {
  final _reviewController = TextEditingController();
  int _rating = 0;
  int? _submittedRating;
  String? _submittedText;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DriverTouristReviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bookingId != widget.bookingId) _load();
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final row = await Supabase.instance.client
          .from('tourist_reviews')
          .select('rating,review_text')
          .eq('booking_id', widget.bookingId)
          .eq('driver_id', userId)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _submittedRating = (row?['rating'] as num?)?.toInt();
        _submittedText = row?['review_text']?.toString();
        _error = null;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load your review.');
    }
  }

  Future<void> _submit() async {
    if (_busy || _rating == 0) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'submit_tourist_review',
        params: {
          'p_booking_id': widget.bookingId,
          'p_rating': _rating,
          'p_review_text': _reviewController.text.trim(),
        },
      );
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Review could not be submitted.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rate your tourist',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Completed booking ${widget.bookingId.substring(0, 8)}'),
            if (_submittedRating != null) ...[
              const SizedBox(height: 8),
              Text('Your rating: $_submittedRating / 5'),
              if ((_submittedText ?? '').isNotEmpty) Text(_submittedText!),
            ] else ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  for (var star = 1; star <= 5; star++)
                    IconButton(
                      tooltip: '$star stars',
                      onPressed: _busy
                          ? null
                          : () => setState(() => _rating = star),
                      icon: Icon(
                        star <= _rating ? Icons.star : Icons.star_border,
                      ),
                      color: Colors.amber.shade700,
                    ),
                ],
              ),
              TextField(
                controller: _reviewController,
                maxLength: 2000,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Share feedback about this tour (optional)',
                ),
              ),
              FilledButton(
                onPressed: _busy || _rating == 0 ? null : _submit,
                child: Text(_busy ? 'Submitting…' : 'Submit Review'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
