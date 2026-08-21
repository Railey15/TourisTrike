import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';

const _cancelBlue = Color(0xFF2563EB);
const _cancelInk = Color(0xFF0F172A);
const _cancelMuted = Color(0xFF64748B);
const _cancelBorder = Color(0xFFE5EBF3);
const _cancelDanger = Color(0xFFDC2626);

const packageCancellationReasons = <String>[
  'Change of plans',
  'Booked by mistake',
  'Wrong date or time',
  'Wrong pickup location',
  'Found another transportation option',
  'Driver is taking too long',
  'Driver asked me to cancel',
  'Safety concern',
  'Payment issue',
  'Weather / emergency',
  'Other',
];

String humanizeCancellationError(Object error) {
  final value = error.toString().toUpperCase();
  const messages = <String, String>{
    'BOOKING_NOT_FOUND': 'This booking could not be found.',
    'NOT_BOOKING_OWNER': 'You are not allowed to cancel this booking.',
    'BOOKING_ALREADY_CANCELLED': 'This booking has already been cancelled.',
    'TOUR_ALREADY_COMPLETED': 'Completed tours can no longer be cancelled.',
    'TOUR_ALREADY_STARTED':
        'This tour can no longer be cancelled because it has started.',
    'DRIVER_ALREADY_ARRIVED':
        'This tour can no longer be cancelled because the driver has arrived.',
    'PAYMENT_DISPUTE_ACTIVE':
        'Cancellation is unavailable while a payment dispute is under review.',
    'CANCELLATION_REASON_REQUIRED': 'Please select a cancellation reason.',
    'CANCELLATION_NOT_ALLOWED': 'This booking is not in a cancellable state.',
  };
  for (final entry in messages.entries) {
    if (value.contains(entry.key)) return entry.value;
  }
  return 'We could not cancel this booking. Please refresh and try again.';
}

Future<BookingCancellationResult?> showPackageBookingCancellationFlow(
  BuildContext context, {
  required String bookingId,
  required String packageTitle,
  required DateTime? travelDate,
  TourisTrikeRepository? repository,
}) async {
  final repo = repository ?? TourisTrikeRepository();
  _showBlockingProgress(context, 'Checking cancellation policy…');

  late CancellationEligibility eligibility;
  try {
    eligibility = await repo.getPackageBookingCancellationEligibility(
      bookingId,
    );
  } catch (error) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (context.mounted) _showError(context, humanizeCancellationError(error));
    return null;
  }
  if (!context.mounted) return null;
  Navigator.of(context, rootNavigator: true).pop();

  if (!eligibility.canCancel) {
    await _showUnavailableSheet(context, eligibility.displayMessage);
    return null;
  }

  final choice = await _showReasonSheet(context, eligibility);
  if (choice == null || !context.mounted) return null;

  final confirmed = await _showConfirmationSheet(
    context,
    eligibility: eligibility,
    packageTitle: packageTitle,
    travelDate: travelDate,
    reason: choice.$1,
  );
  if (!confirmed || !context.mounted) return null;

  _showBlockingProgress(context, 'Cancelling booking…');
  try {
    final result = await repo.cancelPackageBooking(
      bookingId: bookingId,
      reason: choice.$1,
      note: choice.$2,
      category: _categoryFor(choice.$1),
    );
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    return result;
  } catch (error) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    if (context.mounted) _showError(context, humanizeCancellationError(error));
    return null;
  }
}

String _categoryFor(String reason) {
  if (reason == 'Safety concern') return 'safety';
  if (reason == 'Driver asked me to cancel') return 'driver_requested';
  if (reason == 'Payment issue') return 'payment';
  if (reason == 'Weather / emergency') return 'emergency';
  return 'general';
}

Future<(String, String?)?> _showReasonSheet(
  BuildContext context,
  CancellationEligibility eligibility,
) async {
  String? selected;
  final noteController = TextEditingController();
  final result = await showModalBottomSheet<(String, String?)>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            20 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .86,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 12),
                const Text(
                  'Cancel this booking?',
                  style: TextStyle(
                    color: _cancelInk,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Please tell us why you need to cancel.',
                  style: TextStyle(color: _cancelMuted, fontSize: 14),
                ),
                const SizedBox(height: 14),
                _PolicyCard(eligibility: eligibility),
                const SizedBox(height: 14),
                const Text(
                  'Why are you cancelling?',
                  style: TextStyle(
                    color: _cancelInk,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: packageCancellationReasons.length,
                    itemBuilder: (context, index) {
                      final reason = packageCancellationReasons[index];
                      return RadioListTile<String>(
                        value: reason,
                        groupValue: selected,
                        activeColor: _cancelBlue,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          reason,
                          style: const TextStyle(fontSize: 14),
                        ),
                        onChanged: (value) => setSheetState(() {
                          selected = value;
                        }),
                      );
                    },
                  ),
                ),
                if (selected == 'Other') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteController,
                    onChanged: (_) => setSheetState(() {}),
                    maxLength: 240,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Tell us what happened',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: _cancelBorder),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: FilledButton(
                    onPressed:
                        selected == null ||
                            (selected == 'Other' &&
                                noteController.text.trim().isEmpty)
                        ? null
                        : () => Navigator.pop(sheetContext, (
                            selected!,
                            noteController.text.trim().isEmpty
                                ? null
                                : noteController.text.trim(),
                          )),
                    style: FilledButton.styleFrom(
                      backgroundColor: _cancelBlue,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Continue'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  noteController.dispose();
  return result;
}

Future<bool> _showConfirmationSheet(
  BuildContext context, {
  required CancellationEligibility eligibility,
  required String packageTitle,
  required DateTime? travelDate,
  required String reason,
}) async {
  final dateText = travelDate == null
      ? 'Schedule unavailable'
      : DateFormat('MMM d, yyyy • h:mm a').format(travelDate);
  return await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SheetHandle(),
                const SizedBox(height: 12),
                const Text(
                  'Confirm cancellation',
                  style: TextStyle(
                    color: _cancelInk,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 14),
                _SummaryRow(label: 'Booking', value: packageTitle),
                _SummaryRow(label: 'Tour date', value: dateText),
                _SummaryRow(label: 'Reason', value: reason),
                const Divider(height: 25, color: _cancelBorder),
                Text(
                  eligibility.displayMessage,
                  style: const TextStyle(color: _cancelMuted, height: 1.35),
                ),
                const SizedBox(height: 14),
                _MoneyRow(label: 'Amount paid', value: eligibility.amountPaid),
                _MoneyRow(
                  label: 'Estimated refundable amount',
                  value: eligibility.refundableAmount,
                  color: const Color(0xFF15803D),
                ),
                _MoneyRow(
                  label: 'Non-refundable amount',
                  value: eligibility.nonRefundableAmount,
                ),
                if (eligibility.hasAssignedDrivers) ...[
                  const SizedBox(height: 12),
                  const _Notice(
                    text:
                        'Your assigned driver will be notified and released from this booking.',
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          side: const BorderSide(color: _cancelBorder),
                        ),
                        child: const Text('Keep Booking'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          backgroundColor: _cancelDanger,
                        ),
                        child: const Text('Confirm Cancellation'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;
}

Future<void> _showUnavailableSheet(BuildContext context, String message) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetHandle(),
            const SizedBox(height: 18),
            const Icon(
              Icons.info_outline_rounded,
              color: _cancelBlue,
              size: 40,
            ),
            const SizedBox(height: 12),
            const Text(
              'Cancellation unavailable',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _cancelMuted, height: 1.4),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void _showBlockingProgress(BuildContext context, String label) {
  showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    ),
  );
}

void _showError(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

String _money(double value) =>
    NumberFormat.currency(locale: 'en_PH', symbol: '₱').format(value);

class _PolicyCard extends StatelessWidget {
  const _PolicyCard({required this.eligibility});

  final CancellationEligibility eligibility;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cancellation policy',
            style: TextStyle(color: _cancelInk, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            eligibility.displayMessage,
            style: const TextStyle(color: _cancelMuted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            'Estimated refund: ${_money(eligibility.refundableAmount)}',
            style: const TextStyle(
              color: _cancelBlue,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(label, style: const TextStyle(color: _cancelMuted)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: _cancelInk,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({required this.label, required this.value, this.color});
  final String label;
  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: _cancelMuted)),
        ),
        Text(
          _money(value),
          style: TextStyle(
            color: color ?? _cancelInk,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706)),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(color: _cancelInk, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 42,
      height: 4,
      decoration: BoxDecoration(
        color: const Color(0xFFCBD5E1),
        borderRadius: BorderRadius.circular(20),
      ),
    ),
  );
}
