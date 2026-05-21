import 'package:flutter/material.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

class DriverReviewModal extends StatefulWidget {
  const DriverReviewModal({
    super.key,
    required this.bookingId,
    required this.driverId,
    required this.driverName,
    required this.driverAvatarUrl,
  });

  final String bookingId;
  final String driverId;
  final String driverName;
  final String driverAvatarUrl;

  static Future<void> show(
    BuildContext context, {
    required String bookingId,
    required String driverId,
    required String driverName,
    required String driverAvatarUrl,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => DriverReviewModal(
        bookingId: bookingId,
        driverId: driverId,
        driverName: driverName,
        driverAvatarUrl: driverAvatarUrl,
      ),
    );
  }

  @override
  State<DriverReviewModal> createState() => _DriverReviewModalState();
}

class _DriverReviewModalState extends State<DriverReviewModal> {
  final _repo = TourisTrikeRepository();
  final _reviewCtrl = TextEditingController();

  int _rating = 0;
  bool _submitting = false;
  bool _submitted = false;

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) return;
    setState(() => _submitting = true);
    try {
      await _repo.submitDriverReview(
        bookingId: widget.bookingId,
        driverId: widget.driverId,
        rating: _rating,
        reviewText: _reviewCtrl.text,
      );
      if (mounted) setState(() => _submitted = true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to submit review. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.all(Radius.circular(28)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 20, 24, 24 + bottom),
        child: _submitted ? _buildThankYou() : _buildForm(),
      ),
    );
  }

  Widget _buildThankYou() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),
        Container(
          width: 68,
          height: 68,
          decoration: const BoxDecoration(
            color: Color(0xFFECFDF5),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.star_rounded, color: Color(0xFF16A34A), size: 38),
        ),
        const SizedBox(height: 16),
        const Text(
          'Thank you for your feedback!',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Your review helps improve the experience for all tourists.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text(
              'Done',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle bar
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Header
        const Text(
          'Rate Your Experience',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'How was your tour?',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 20),

        // Driver avatar + name
        Row(
          children: [
            _DriverAvatar(url: widget.driverAvatarUrl, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.driverName.isEmpty ? 'Your Driver' : widget.driverName,
                    style: const TextStyle(
                      color: Color(0xFF0F172A),
                      fontWeight: FontWeight.w900,
                      fontSize: 15.5,
                    ),
                  ),
                  const Text(
                    'Tour driver',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Star rating
        _StarRow(selected: _rating, onSelect: (v) => setState(() => _rating = v)),
        const SizedBox(height: 6),
        Text(
          _ratingLabel(_rating),
          style: const TextStyle(
            color: Color(0xFFF59E0B),
            fontWeight: FontWeight.w900,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 20),

        // Review text field
        TextField(
          controller: _reviewCtrl,
          maxLines: 3,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: 'Share your experience (optional)…',
            hintStyle: const TextStyle(color: Color(0xFFCBD5E1)),
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFF2F6FFF), width: 1.5),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text(
                  'Skip',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: (_rating == 0 || _submitting) ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF2F6FFF),
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.star_rounded, size: 18),
                label: Text(
                  _submitting ? 'Submitting…' : 'Submit Review',
                  style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _ratingLabel(int r) => switch (r) {
        1 => 'Poor',
        2 => 'Fair',
        3 => 'Good',
        4 => 'Great',
        5 => 'Excellent!',
        _ => 'Tap a star to rate',
      };
}

class _StarRow extends StatelessWidget {
  const _StarRow({required this.selected, required this.onSelect});

  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (i) {
        final star = i + 1;
        return GestureDetector(
          onTap: () => onSelect(star),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              star <= selected ? Icons.star_rounded : Icons.star_outline_rounded,
              color: star <= selected ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1),
              size: 42,
            ),
          ),
        );
      }),
    );
  }
}

class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar({required this.url, required this.size});

  final String url;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hasUrl = url.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        shape: BoxShape.circle,
        image: hasUrl
            ? DecorationImage(image: NetworkImage(url), fit: BoxFit.cover)
            : null,
      ),
      child: hasUrl
          ? null
          : const Icon(Icons.person_rounded, color: Color(0xFF2F6FFF), size: 28),
    );
  }
}
