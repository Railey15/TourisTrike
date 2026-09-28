import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// One deliberate, handle-only slide for each persisted driver tour action.
/// Keep [actionId] stable until the backend stage/stop changes.
class DriverTourSlideAction extends StatefulWidget {
  const DriverTourSlideAction({
    super.key,
    required this.actionId,
    required this.label,
    required this.onConfirmed,
    this.busy = false,
    this.enabled = true,
  });

  final String actionId;
  final String label;
  final Future<void> Function() onConfirmed;
  final bool busy;
  final bool enabled;

  @override
  State<DriverTourSlideAction> createState() => _DriverTourSlideActionState();
}

class _DriverTourSlideActionState extends State<DriverTourSlideAction>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  bool _submitting = false;
  bool _confirmed = false;
  bool _dragging = false;
  bool get _locked =>
      !widget.enabled || widget.busy || _submitting || _confirmed;

  @override
  void didUpdateWidget(covariant DriverTourSlideAction oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionId != widget.actionId) {
      _progress.value = 0;
      _confirmed = false;
      _dragging = false;
    } else if (_locked && !_submitting && !_confirmed) {
      _dragging = false;
      _progress.animateBack(0, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_locked) return;
    final submittedAction = widget.actionId;
    setState(() {
      _submitting = true;
      _dragging = false;
      _progress.value = 1;
    });
    HapticFeedback.mediumImpact();
    try {
      await widget.onConfirmed();
      if (mounted && widget.actionId == submittedAction) {
        setState(() => _confirmed = true);
      }
    } catch (_) {
      // The owning screen displays the authoritative domain error.
      if (mounted && widget.actionId == submittedAction) {
        _progress.animateBack(0, curve: Curves.easeOutCubic);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _returnToStart() {
    _dragging = false;
    _progress.animateBack(0, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2563EB);
    final loading = widget.busy || _submitting;
    final label = loading
        ? 'UPDATING TOUR…'
        : _confirmed
        ? 'ACTION CONFIRMED'
        : widget.label;
    return Semantics(
      excludeSemantics: true,
      label: widget.label,
      hint: _locked
          ? loading
                ? 'Waiting for the server'
                : _confirmed
                ? 'Action confirmed'
                : 'Action unavailable'
          : 'Drag the arrow handle all the way to the right to confirm',
      enabled: !_locked,
      // Accessibility users can deliberately complete the same action without
      // changing the physical track into a tappable button.
      onIncrease: _locked ? null : _confirm,
      child: SizedBox(
        width: double.infinity,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const inset = 6.0;
            const handle = 56.0;
            final travel = (constraints.maxWidth - handle - inset * 2).clamp(
              1.0,
              double.infinity,
            );
            final textWidth = (constraints.maxWidth - handle - 32).clamp(
              1.0,
              double.infinity,
            );
            final painter = TextPainter(
              text: TextSpan(
                text: label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
            )..layout(maxWidth: textWidth);
            final height = (painter.height + 28).clamp(72.0, double.infinity);
            painter.dispose();
            return AnimatedBuilder(
              animation: _progress,
              builder: (context, _) => ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  height: height,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: widget.enabled
                        ? const Color(0xFFEAF3FF)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: widget.enabled ? blue : const Color(0xFFCBD5E1),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        right: travel * (1 - _progress.value),
                        child: ColoredBox(color: blue.withValues(alpha: .14)),
                      ),
                      Positioned.fill(
                        left: (loading || _confirmed) && _progress.value >= .5
                            ? 16
                            : handle + 16,
                        right: (loading || _confirmed) && _progress.value >= .5
                            ? handle + 16
                            : 16,
                        child: Center(
                          child: Opacity(
                            opacity: loading || _confirmed
                                ? 1
                                : 1 - _progress.value * .85,
                            child: Text(
                              label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: widget.enabled
                                    ? blue
                                    : const Color(0xFF64748B),
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: inset + travel * _progress.value,
                        top: (height - handle) / 2,
                        child: GestureDetector(
                          key: const ValueKey('driver-tour-slide-handle'),
                          behavior: HitTestBehavior.opaque,
                          onHorizontalDragStart: _locked
                              ? null
                              : (_) {
                                  _progress.stop();
                                  _dragging = true;
                                },
                          onHorizontalDragUpdate: _locked
                              ? null
                              : (details) {
                                  if (!_dragging) return;
                                  _progress.value =
                                      (_progress.value +
                                              details.delta.dx / travel)
                                          .clamp(0.0, 1.0);
                                },
                          onHorizontalDragEnd: _locked
                              ? null
                              : (_) {
                                  if (!_dragging) return;
                                  if (_progress.value >= .92) {
                                    _confirm();
                                  } else {
                                    _returnToStart();
                                  }
                                },
                          onHorizontalDragCancel: _returnToStart,
                          child: Container(
                            width: handle,
                            height: handle,
                            decoration: BoxDecoration(
                              color: widget.enabled
                                  ? blue
                                  : const Color(0xFF94A3B8),
                              borderRadius: BorderRadius.circular(15),
                            ),
                            child: loading
                                ? const Padding(
                                    padding: EdgeInsets.all(17),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Icon(
                                    _confirmed
                                        ? Icons.check_rounded
                                        : !widget.enabled
                                        ? Icons.lock_outline_rounded
                                        : Icons
                                              .keyboard_double_arrow_right_rounded,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
