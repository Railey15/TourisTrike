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
    this.initialStep = 1,
  });

  final String bookingId;
  final String driverId;
  final String driverName;
  final String driverAvatarUrl;
  final dynamic packageId;
  final String? packageName;
  final int initialStep;

  static Future<void> show(
    BuildContext context, {
    required String bookingId,
    required String driverId,
    required String driverName,
    required String driverAvatarUrl,
    dynamic packageId,
    String? packageName,
    int initialStep = 1,
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
        packageId: packageId,
        packageName: packageName,
        initialStep: initialStep,
      ),
    );
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
  late int _step; // 1 = driver, 2 = package, 3 = thank you

  @override
  void initState() {
    super.initState();
    _step = widget.initialStep;
  }

  @override
  void dispose() {
    _driverReviewCtrl.dispose();
    _packageReviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _submitDriverReview() async {
    if (_driverRating == 0) return;
    setState(() => _submitting = true);
    try {
      await _repo.submitDriverReview(
        bookingId: widget.bookingId,
        driverId: widget.driverId,
        rating: _driverRating,
        reviewText: _driverReviewCtrl.text,
      );
      if (mounted) {
        setState(() {
          _submitting = false;
          _step = widget.packageId != null ? 2 : 3;
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to submit review. Please try again.'),
        ),
      );
      setState(() => _submitting = false);
    }
  }

  Future<void> _submitPackageReview() async {
    if (_packageRating == 0) return;
    setState(() => _submitting = true);
    try {
      await _repo.submitPackageReview(
        bookingId: widget.bookingId,
        rating: _packageRating,
        reviewText: _packageReviewCtrl.text,
        packageId: widget.packageId,
      );
      if (mounted) {
        setState(() {
          _submitting = false;
          _step = 3;
        });
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to submit review. Please try again.'),
        ),
      );
      setState(() => _submitting = false);
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
        child: switch (_step) {
          2 => _buildPackageForm(),
          3 => _buildThankYou(),
          _ => _buildDriverForm(),
        },
      ),
    );
  }

  // ── Thank you ──────────────────────────────────────────────────
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
          child: const Icon(
            Icons.star_rounded,
            color: Color(0xFF16A34A),
            size: 38,
          ),
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
          'Your reviews help improve the experience for all tourists.',
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
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

  // ── Driver form (step 1) ───────────────────────────────────────
  Widget _buildDriverForm() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHandle(),
        const SizedBox(height: 20),
        _buildStepIndicator(current: 1),
        const SizedBox(height: 16),
        const Text(
          'Rate Your Driver',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'How was your driver?',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
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
        _StarRow(
          selected: _driverRating,
          onSelect: (v) => setState(() => _driverRating = v),
        ),
        const SizedBox(height: 6),
        Text(
          _ratingLabel(_driverRating),
          style: const TextStyle(
            color: Color(0xFFF59E0B),
            fontWeight: FontWeight.w900,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _driverReviewCtrl,
          maxLines: 3,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          decoration: _textFieldDecor('Share your experience with the driver (optional)…'),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting ? null : () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
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
                onPressed: (_driverRating == 0 || _submitting)
                    ? null
                    : _submitDriverReview,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF2F6FFF),
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.star_rounded, size: 18),
                label: Text(
                  _submitting ? 'Submitting…' : 'Rate Driver',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Package form (step 2) ──────────────────────────────────────
  Widget _buildPackageForm() {
    final pkgName = widget.packageName?.isNotEmpty == true
        ? widget.packageName!
        : 'Tour Package';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHandle(),
        const SizedBox(height: 20),
        _buildStepIndicator(current: 2),
        const SizedBox(height: 16),
        const Text(
          'Rate the Package',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontWeight: FontWeight.w900,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'How was the tour package?',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF2F6FFF).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.explore_rounded,
                  color: Color(0xFF2F6FFF),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  pkgName,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _StarRow(
          selected: _packageRating,
          onSelect: (v) => setState(() => _packageRating = v),
        ),
        const SizedBox(height: 6),
        Text(
          _ratingLabel(_packageRating),
          style: const TextStyle(
            color: Color(0xFFF59E0B),
            fontWeight: FontWeight.w900,
            fontSize: 13.5,
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _packageReviewCtrl,
          maxLines: 3,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          decoration: _textFieldDecor('Share your thoughts about the package (optional)…'),
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() => _step = 3),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
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
                onPressed: (_packageRating == 0 || _submitting)
                    ? null
                    : _submitPackageReview,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  backgroundColor: const Color(0xFF16A34A),
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: _submitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.verified_rounded, size: 18),
                label: Text(
                  _submitting ? 'Submitting…' : 'Rate Package',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────
  Widget _buildHandle() {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }

  Widget _buildStepIndicator({required int current}) {
    final hasPackage = widget.packageId != null;
    final total = hasPackage ? 2 : 1;
    if (total == 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Step $current of $total',
          style: const TextStyle(
            color: Color(0xFF94A3B8),
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 8),
        ...List.generate(total, (i) {
          final active = i + 1 == current;
          return Container(
            margin: const EdgeInsets.only(right: 4),
            width: active ? 18 : 6,
            height: 6,
            decoration: BoxDecoration(
              color: active
                  ? const Color(0xFF2F6FFF)
                  : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(99),
            ),
          );
        }),
      ],
    );
  }

  InputDecoration _textFieldDecor(String hint) {
    return InputDecoration(
      hintText: hint,
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

// ── Star row ────────────────────────────────────────────────────
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
              color: star <= selected
                  ? const Color(0xFFF59E0B)
                  : const Color(0xFFCBD5E1),
              size: 42,
            ),
          ),
        );
      }),
    );
  }
}

// ── Driver avatar ───────────────────────────────────────────────
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
          : const Icon(
              Icons.person_rounded,
              color: Color(0xFF2F6FFF),
              size: 28,
            ),
    );
  }
}
