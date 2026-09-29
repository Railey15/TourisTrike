import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

typedef SubmitTouristReview =
    Future<void> Function(String bookingId, int rating, String comment);

/// Reserves one automatic prompt per booking for this screen visit.
class DriverTouristReviewPromptGate {
  final Set<String> _promptedBookingIds = {};

  bool hasPrompted(String bookingId) => _promptedBookingIds.contains(bookingId);

  bool reserve(String bookingId) => _promptedBookingIds.add(bookingId);
}

/// Mirrors the tourist's review bottom sheet; review eligibility is checked
/// against the saved driver review by the tracking screen before this opens.
class DriverTouristReviewModal extends StatefulWidget {
  const DriverTouristReviewModal({
    super.key,
    required this.bookingId,
    required this.touristName,
    this.submitReview,
  });

  final String bookingId;
  final String touristName;
  final SubmitTouristReview? submitReview;

  static Future<bool> show(
    BuildContext context, {
    required String bookingId,
    required String touristName,
  }) async =>
      await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .92,
          maxWidth: 640,
        ),
        builder: (_) => DriverTouristReviewModal(
          bookingId: bookingId,
          touristName: touristName,
        ),
      ) ??
      false;

  @override
  State<DriverTouristReviewModal> createState() =>
      _DriverTouristReviewModalState();
}

class _DriverTouristReviewModalState extends State<DriverTouristReviewModal> {
  final _comment = TextEditingController();
  int _rating = 0;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting || _rating < 1 || _rating > 5) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      if (widget.submitReview != null) {
        await widget.submitReview!(
          widget.bookingId,
          _rating,
          _comment.text.trim(),
        );
      } else {
        await Supabase.instance.client.rpc(
          'submit_tourist_review',
          params: {
            'p_booking_id': widget.bookingId,
            'p_rating': _rating,
            'p_review_text': _comment.text.trim(),
          },
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Review could not be submitted. Please try again.';
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Rate your tourist',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'How was your completed tour? Your feedback is optional.',
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.person_rounded,
                        color: Color(0xFF16A34A),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.touristName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      for (var value = 1; value <= 5; value++)
                        Expanded(
                          child: IconButton(
                            onPressed: _submitting
                                ? null
                                : () => setState(() => _rating = value),
                            tooltip: '$value ${value == 1 ? 'star' : 'stars'}',
                            padding: EdgeInsets.zero,
                            iconSize: 38,
                            icon: Icon(
                              value <= _rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              color: value <= _rating
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFFCBD5E1),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _comment,
                    enabled: !_submitting,
                    maxLines: 3,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Optional tourist feedback',
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submitting || _rating == 0 ? null : _submit,
              child: Text(_submitting ? 'Submitting...' : 'Submit Review'),
            ),
            TextButton(
              onPressed: _submitting
                  ? null
                  : () => Navigator.pop(context, false),
              child: const Text('Later'),
            ),
          ],
        ),
      ),
    ),
  );
}
