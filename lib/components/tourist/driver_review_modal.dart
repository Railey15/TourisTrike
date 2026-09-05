import 'package:flutter/material.dart';
import 'package:touristrike/core/models/booking_feedback.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

class DriverReviewModal extends StatefulWidget {
  const DriverReviewModal({super.key, required this.feedback, this.repository});
  final BookingFeedback feedback;
  final TourisTrikeRepository? repository;
  static Future<bool> show(
    BuildContext context, {
    required BookingFeedback feedback,
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
        builder: (_) => DriverReviewModal(feedback: feedback),
      ) ??
      false;
  @override
  State<DriverReviewModal> createState() => _DriverReviewModalState();
}

class _DriverReviewModalState extends State<DriverReviewModal> {
  late final TourisTrikeRepository _repo;
  final _packageComment = TextEditingController();
  final _comments = <String, TextEditingController>{};
  final _ratings = <String, int>{};
  int _packageRating = 0;
  bool _submitting = false;
  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? TourisTrikeRepository();
    for (final driver in widget.feedback.drivers.where(
      (d) => d['review'] == null,
    )) {
      final id = driver['driver_id'].toString();
      _comments[id] = TextEditingController();
      _ratings[id] = 0;
    }
  }

  @override
  void dispose() {
    _packageComment.dispose();
    for (final controller in _comments.values) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _canSubmit =>
      !_submitting &&
      (widget.feedback.packageReview != null || _packageRating > 0) &&
      _ratings.values.every((rating) => rating > 0);
  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    try {
      final result = BookingFeedback(
        await _repo.submitBookingFeedback(
          bookingId: widget.feedback.bookingId,
          packageRating: widget.feedback.packageReview == null
              ? _packageRating
              : null,
          packageComment: _packageComment.text,
          driverReviews: _ratings.entries
              .map(
                (entry) => <String, dynamic>{
                  'driver_id': entry.key,
                  'rating': entry.value,
                  'review_text': _comments[entry.key]!.text,
                },
              )
              .toList(),
        ),
      );
      if (!result.complete) throw StateError('Incomplete feedback');
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Feedback was not completed. Your entries are kept; please retry.',
          ),
        ),
      );
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
              'Rate Your Tour',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'One feedback session for this booking. Rate your package and each driver, then submit together.',
            ),
            const SizedBox(height: 20),
            if (widget.feedback.packageReview == null)
              _ReviewSection(
                icon: Icons.explore_rounded,
                title: 'Package Rating',
                subtitle: widget.feedback.packageName,
                accentColor: const Color(0xFF2F6FFF),
                rating: _packageRating,
                ratingLabel: _packageRating == 0
                    ? 'Tap a star to rate'
                    : '$_packageRating/5',
                controller: _packageComment,
                hintText: 'Optional package feedback',
                onRatingChanged: (value) =>
                    setState(() => _packageRating = value),
              )
            else
              const Text('Package feedback already saved'),
            for (final driver in widget.feedback.drivers) ...[
              const SizedBox(height: 16),
              if (driver['review'] != null)
                Text('${driver['name']}: feedback already saved')
              else
                _ReviewSection(
                  icon: Icons.person_rounded,
                  title: 'Driver Rating',
                  subtitle: driver['name'].toString(),
                  avatarUrl: driver['avatar_url']?.toString() ?? '',
                  accentColor: const Color(0xFF16A34A),
                  rating: _ratings[driver['driver_id']]!,
                  ratingLabel: 'Rate this driver',
                  controller: _comments[driver['driver_id']]!,
                  hintText: 'Optional driver feedback',
                  onRatingChanged: (value) => setState(
                    () => _ratings[driver['driver_id'].toString()] = value,
                  ),
                ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _canSubmit ? _submit : null,
              child: Text(_submitting ? 'Submitting...' : 'Submit Feedback'),
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

class _ReviewSection extends StatelessWidget {
  const _ReviewSection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.rating,
    required this.ratingLabel,
    required this.controller,
    required this.hintText,
    required this.onRatingChanged,
    this.avatarUrl = '',
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final int rating;
  final String ratingLabel;
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<int> onRatingChanged;
  final String avatarUrl;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = avatarUrl.trim().isNotEmpty;
    return Container(
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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  image: hasAvatar
                      ? DecorationImage(
                          image: NetworkImage(avatarUrl),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: hasAvatar
                    ? null
                    : Icon(icon, color: accentColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _StarRow(selected: rating, onSelect: onRatingChanged),
          const SizedBox(height: 8),
          Center(
            child: Text(
              ratingLabel,
              style: TextStyle(
                color: accentColor,
                fontWeight: FontWeight.w900,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: controller,
            maxLines: 3,
            maxLength: 300,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.all(14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: accentColor, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StarRow extends StatelessWidget {
  const _StarRow({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final value = index + 1;
        return Expanded(
          child: IconButton(
            onPressed: () => onSelect(value),
            tooltip: '$value ${value == 1 ? 'star' : 'stars'}',
            padding: EdgeInsets.zero,
            iconSize: 38,
            splashRadius: 24,
            icon: Icon(
              value <= selected
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              color: value <= selected
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFCBD5E1),
            ),
          ),
        );
      }),
    );
  }
}
