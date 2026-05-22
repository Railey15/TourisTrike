import 'package:flutter/material.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

class DriverReviewModal extends StatefulWidget {
  const DriverReviewModal({
    super.key,
    required this.bookingId,
    required this.driverId,
    required this.driverName,
    required this.driverAvatarUrl,
    this.packageId,
    this.packageName,
    this.includeDriverReview = true,
    this.includePackageReview = true,
  });

  final String bookingId;
  final String driverId;
  final String driverName;
  final String driverAvatarUrl;
  final dynamic packageId;
  final String? packageName;
  final bool includeDriverReview;
  final bool includePackageReview;

  static Future<bool> show(
    BuildContext context, {
    required String bookingId,
    required String driverId,
    required String driverName,
    required String driverAvatarUrl,
    dynamic packageId,
    String? packageName,
    bool includeDriverReview = true,
    bool includePackageReview = true,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (_) => DriverReviewModal(
        bookingId: bookingId,
        driverId: driverId,
        driverName: driverName,
        driverAvatarUrl: driverAvatarUrl,
        packageId: packageId,
        packageName: packageName,
        includeDriverReview: includeDriverReview,
        includePackageReview: includePackageReview,
      ),
    );
    return result ?? false;
  }

  @override
  State<DriverReviewModal> createState() => _DriverReviewModalState();
}

class _DriverReviewModalState extends State<DriverReviewModal> {
  final _repo = TourisTrikeRepository();
  final _driverReviewCtrl = TextEditingController();
  final _packageReviewCtrl = TextEditingController();

  int _driverRating = 0;
  int _packageRating = 0;
  bool _submitting = false;

  @override
  void dispose() {
    _driverReviewCtrl.dispose();
    _packageReviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (widget.includeDriverReview && _driverRating == 0) return;
    if (widget.includePackageReview && _packageRating == 0) return;

    setState(() => _submitting = true);
    try {
      if (widget.includeDriverReview) {
        await _repo.submitDriverReview(
          bookingId: widget.bookingId,
          driverId: widget.driverId,
          rating: _driverRating,
          reviewText: _driverReviewCtrl.text,
        );
      }
      if (widget.includePackageReview) {
        await _repo.submitPackageReview(
          bookingId: widget.bookingId,
          rating: _packageRating,
          reviewText: _packageReviewCtrl.text,
          packageId: widget.packageId,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to submit feedback. Please try again.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final pkgName = widget.packageName?.trim().isNotEmpty == true
        ? widget.packageName!.trim()
        : 'Tour Package';

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.all(Radius.circular(30)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(22, 18, 22, 22 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Rate Your Tour',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                  fontSize: 24,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Share your feedback for the package and driver before closing this trip.',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 20),
              if (widget.includePackageReview) ...[
                _ReviewSection(
                  icon: Icons.explore_rounded,
                  title: 'Package Rating',
                  subtitle: pkgName,
                  accentColor: const Color(0xFF2F6FFF),
                  rating: _packageRating,
                  ratingLabel: _ratingLabel(_packageRating),
                  controller: _packageReviewCtrl,
                  hintText: 'Tell us about the package experience...',
                  onRatingChanged: (value) {
                    setState(() => _packageRating = value);
                  },
                ),
                const SizedBox(height: 16),
              ],
              if (widget.includeDriverReview) ...[
                _ReviewSection(
                  icon: Icons.person_rounded,
                  title: 'Driver Rating',
                  subtitle: widget.driverName.trim().isEmpty
                      ? 'Your driver'
                      : widget.driverName.trim(),
                  accentColor: const Color(0xFF16A34A),
                  rating: _driverRating,
                  ratingLabel: _ratingLabel(_driverRating),
                  controller: _driverReviewCtrl,
                  hintText: 'Tell us about your driver...',
                  avatarUrl: widget.driverAvatarUrl,
                  onRatingChanged: (value) {
                    setState(() => _driverRating = value);
                  },
                ),
              ],
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _canSubmit ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.star_rounded, size: 18),
                  label: Text(
                    _submitting ? 'Submitting...' : 'Submit Feedback',
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _canSubmit {
    final driverReady = !widget.includeDriverReview || _driverRating > 0;
    final packageReady = !widget.includePackageReview || _packageRating > 0;
    return !_submitting && driverReady && packageReady;
  }

  String _ratingLabel(int rating) => switch (rating) {
    1 => 'Poor',
    2 => 'Fair',
    3 => 'Good',
    4 => 'Great',
    5 => 'Excellent',
    _ => 'Tap a star to rate',
  };
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
        return IconButton(
          onPressed: () => onSelect(value),
          iconSize: 38,
          splashRadius: 24,
          icon: Icon(
            value <= selected ? Icons.star_rounded : Icons.star_outline_rounded,
            color: value <= selected
                ? const Color(0xFFF59E0B)
                : const Color(0xFFCBD5E1),
          ),
        );
      }),
    );
  }
}
