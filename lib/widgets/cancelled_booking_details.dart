import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/presentation/cancellation_display.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';

class CancelledBookingDetails extends StatelessWidget {
  const CancelledBookingDetails({
    super.key,
    required this.packageName,
    required this.municipality,
    required this.province,
    required this.travelDate,
    required this.scheduledStartAt,
    required this.estimatedEndAt,
    required this.touristCount,
    required this.spots,
    required this.cancelledAt,
    required this.cancellationReason,
    required this.refund,
    required this.onBack,
    this.headerMessage = 'This booking remains in your history for reference.',
  });

  final String packageName;
  final String municipality;
  final String province;
  final DateTime? travelDate;
  final DateTime? scheduledStartAt;
  final DateTime? estimatedEndAt;
  final int touristCount;
  final List<BookingItineraryItem> spots;
  final DateTime? cancelledAt;
  final String cancellationReason;
  final CancellationRefundDisplay refund;
  final VoidCallback onBack;
  final String headerMessage;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'en_PH',
      symbol: '₱',
      decimalDigits: 2,
    );
    final start = scheduledStartAt?.toLocal();
    final end = estimatedEndAt?.toLocal();
    final displayDate = start ?? travelDate?.toLocal();
    final place = [
      municipality.trim(),
      province.trim(),
    ].where((value) => value.isNotEmpty).toSet().join(', ');
    final schedule = switch ((start, end)) {
      (final DateTime start, final DateTime end) =>
        '${DateFormat('h:mm a').format(start)} – ${DateFormat('h:mm a').format(end)}',
      (final DateTime start, null) => DateFormat('h:mm a').format(start),
      _ => 'Time unavailable',
    };

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      children: [
        _CancelledHeader(message: headerMessage),
        const SizedBox(height: 14),
        _SectionCard(
          eyebrow: 'BOOKED PACKAGE',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                packageName.trim().isEmpty ? 'Tour Package' : packageName,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 13),
              if (place.isNotEmpty)
                _PackageLine(icon: Icons.place_outlined, text: place),
              _PackageLine(
                icon: Icons.calendar_today_outlined,
                text: displayDate == null
                    ? 'Date unavailable'
                    : DateFormat('MMM d, yyyy').format(displayDate),
              ),
              _PackageLine(icon: Icons.schedule_rounded, text: schedule),
              _PackageLine(
                icon: Icons.route_outlined,
                text:
                    '${spots.length} Destination${spots.length == 1 ? '' : 's'}',
              ),
              if (touristCount > 0)
                _PackageLine(
                  icon: Icons.groups_2_outlined,
                  text: '$touristCount Tourist${touristCount == 1 ? '' : 's'}',
                  isLast: true,
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          eyebrow: 'TOUR DESTINATIONS',
          child: spots.isEmpty
              ? const _EmptyDestinations()
              : Column(
                  children: [
                    for (var index = 0; index < spots.length; index++)
                      _DestinationRow(
                        number: index + 1,
                        spot: spots[index],
                        isLast: index == spots.length - 1,
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        _SectionCard(
          eyebrow: 'CANCELLATION DETAILS',
          child: Column(
            children: [
              _DetailBlock(
                label: 'Cancelled',
                value: cancelledAt == null
                    ? 'Date unavailable'
                    : DateFormat(
                        'MMM d, yyyy • h:mm a',
                      ).format(cancelledAt!.toLocal()),
              ),
              _DetailBlock(
                label: 'Reason',
                value: cancellationReasonLabel(cancellationReason),
              ),
              _DetailBlock(
                label: 'Refund',
                value: money.format(refund.amount),
                supportingText: refund.status,
                isLast: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to Bookings'),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            backgroundColor: const Color(0xFF2563EB),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
      ],
    );
  }
}

class _CancelledHeader extends StatelessWidget {
  const _CancelledHeader({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: const Color(0xFFFECACA)),
    ),
    child: Column(
      children: [
        const CircleAvatar(
          radius: 28,
          backgroundColor: Color(0xFFFEF2F2),
          child: Icon(
            Icons.event_busy_rounded,
            color: Color(0xFFDC2626),
            size: 29,
          ),
        ),
        const SizedBox(height: 14),
        const Text(
          'Booking Cancelled',
          style: TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 21,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF64748B), height: 1.4),
        ),
      ],
    ),
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.eyebrow, required this.child});

  final String eyebrow;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE5EBF3)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A0F172A),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            color: Color(0xFF2563EB),
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _PackageLine extends StatelessWidget {
  const _PackageLine({
    required this.icon,
    required this.text,
    this.isLast = false,
  });

  final IconData icon;
  final String text;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: isLast ? 0 : 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 17, color: const Color(0xFF64748B)),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF475569),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _DestinationRow extends StatelessWidget {
  const _DestinationRow({
    required this.number,
    required this.spot,
    required this.isLast,
  });

  final int number;
  final BookingItineraryItem spot;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.only(
      bottom: isLast ? 0 : 12,
      top: number == 1 ? 0 : 12,
    ),
    decoration: isLast
        ? null
        : const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE9EEF5))),
          ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              color: Color(0xFF2563EB),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spot.destinationName.trim().isEmpty
                    ? 'Destination $number'
                    : spot.destinationName,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (spot.destinationAddress.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  spot.destinationAddress,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 10.5,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _EmptyDestinations extends StatelessWidget {
  const _EmptyDestinations();

  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Icon(Icons.info_outline_rounded, color: Color(0xFF64748B), size: 18),
      SizedBox(width: 9),
      Expanded(
        child: Text(
          'No destination snapshot is available for this booking.',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 11.5),
        ),
      ),
    ],
  );
}

class _DetailBlock extends StatelessWidget {
  const _DetailBlock({
    required this.label,
    required this.value,
    this.supportingText,
    this.isLast = false,
  });

  final String label;
  final String value;
  final String? supportingText;
  final bool isLast;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.only(
      bottom: isLast ? 0 : 13,
      top: label == 'Cancelled' ? 0 : 13,
    ),
    decoration: isLast
        ? null
        : const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE9EEF5))),
          ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: label == 'Refund'
                ? const Color(0xFF0F172A)
                : const Color(0xFF1E293B),
            fontSize: label == 'Refund' ? 18 : 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (supportingText != null) ...[
          const SizedBox(height: 3),
          Text(
            supportingText!,
            style: TextStyle(
              color: supportingText == 'Refunded'
                  ? const Color(0xFF15803D)
                  : const Color(0xFF64748B),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    ),
  );
}
