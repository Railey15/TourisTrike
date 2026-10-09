import 'package:flutter/material.dart';
import 'package:touristrike/core/presentation/cancellation_display.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/widgets/cancelled_booking_details.dart';

class BookingCancellationResultScreen extends StatefulWidget {
  const BookingCancellationResultScreen({
    super.key,
    required this.result,
    required this.packageTitle,
    required this.travelDate,
  });

  final BookingCancellationResult result;
  final String packageTitle;
  final DateTime? travelDate;

  @override
  State<BookingCancellationResultScreen> createState() =>
      _BookingCancellationResultScreenState();
}

class _BookingCancellationResultScreenState
    extends State<BookingCancellationResultScreen> {
  final TourisTrikeRepository _repo = TourisTrikeRepository();
  PackageBooking? _booking;
  List<BookingItineraryItem> _spots = const [];
  List<PaymentRecord> _payments = const [];
  List<RefundRequest> _refunds = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPersistedDetails();
  }

  Future<T> _withFallback<T>(Future<T> request, T fallback) async {
    try {
      return await request;
    } catch (_) {
      return fallback;
    }
  }

  Future<void> _loadPersistedDetails() async {
    final results = await Future.wait<dynamic>([
      _withFallback<PackageBooking?>(
        _repo.fetchPackageBookingDetails(widget.result.bookingId),
        null,
      ),
      _withFallback<List<BookingItineraryItem>>(
        _repo.fetchBookingItinerary(widget.result.bookingId),
        const [],
      ),
      _withFallback<List<PaymentRecord>>(
        _repo.fetchPaymentRecordsFor(bookingId: widget.result.bookingId),
        const [],
      ),
      _withFallback<List<RefundRequest>>(
        _repo.fetchBookingRefundRequests(widget.result.bookingId),
        const [],
      ),
    ]);
    if (!mounted) return;
    setState(() {
      _booking = results[0] as PackageBooking?;
      _spots = results[1] as List<BookingItineraryItem>;
      _payments = results[2] as List<PaymentRecord>;
      _refunds = results[3] as List<RefundRequest>;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final booking = _booking;
    final refund = booking == null
        ? CancellationRefundDisplay.fromResult(widget.result)
        : CancellationRefundDisplay.fromBooking(
            booking: booking,
            payments: _payments,
            refunds: _refunds,
          );
    final reason = booking?.cancelledReason.trim().isNotEmpty == true
        ? booking!.cancelledReason
        : widget.result.reason;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(color: Color(0xFF2563EB)),
                  )
                : CancelledBookingDetails(
                    packageName: booking?.packageTitle ?? widget.packageTitle,
                    municipality: booking?.municipality ?? '',
                    province: booking?.province ?? '',
                    travelDate: booking?.travelDate ?? widget.travelDate,
                    scheduledStartAt:
                        booking?.scheduledStartAt ??
                        widget.result.eligibility.scheduledAt,
                    estimatedEndAt: booking?.estimatedEndAt,
                    touristCount: booking?.totalPassengers ?? 0,
                    spots: _spots,
                    cancelledAt:
                        booking?.cancelledAt ?? widget.result.cancelledAt,
                    cancellationReason: reason,
                    refund: refund,
                    headerMessage:
                        'Your booking was cancelled successfully and remains in your history.',
                    onBack: () => Navigator.of(context).pop(),
                  ),
          ),
        ),
      ),
    );
  }
}
