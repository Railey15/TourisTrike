import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_booking_details_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantBookingsScreen extends StatefulWidget {
  const SubTenantBookingsScreen({super.key});

  @override
  State<SubTenantBookingsScreen> createState() =>
      _SubTenantBookingsScreenState();
}

class _SubTenantBookingsScreenState extends State<SubTenantBookingsScreen> {
  final SubTenantService _service = SubTenantService();
  late Future<_BookingListLoad> _future;
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_BookingListLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final bookings = await _service.fetchBookings(profile, status: _status);
    return _BookingListLoad(profile: profile, bookings: bookings);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _openDetails(SubTenantBooking booking) async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SubTenantBookingDetailsScreen(bookingId: booking.id),
      ),
    );
    if (!mounted) return;
    if (changed == true) _reload();
  }

  Future<void> _setStatus(
    SubTenantProfile profile,
    SubTenantBooking booking,
    String status,
  ) async {
    try {
      await _service.updateBookingStatus(profile, booking, status);
      if (!mounted) return;
      showSubTenantSnack(context, 'Booking updated.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to update booking: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final mobile = Responsive.isMobile(context);

    return SubTenantAdminShell(
      currentIndex: 3,
      title: 'Bookings',
      subtitle: 'Review package requests and keep tour status current.',
      child: FutureBuilder<_BookingListLoad>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SubTenantLoadingView();
          }
          if (snapshot.hasError) {
            return SubTenantErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final load = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ResponsivePageContainer(
              children: [
                DashboardSectionCard(
                  child: SubTenantFilterChips(
                    values: const [
                      'all',
                      'pending',
                      'confirmed',
                      'cancelled',
                      'completed',
                    ],
                    selected: _status,
                    onSelected: (value) {
                      setState(() {
                        _status = value;
                        _future = _load();
                      });
                    },
                  ),
                ),
                const SizedBox(height: 16),
                if (load.bookings.isEmpty)
                  EmptyStateCard(
                    icon: Icons.receipt_long_outlined,
                    title: 'No bookings found',
                    message:
                        'Bookings are filtered through tour packages in ${load.profile.assignedCity}.',
                  )
                else if (mobile)
                  ...load.bookings.map(
                    (booking) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _BookingCard(
                        booking: booking,
                        onTap: () => _openDetails(booking),
                        onConfirm: () =>
                            _setStatus(load.profile, booking, 'confirmed'),
                        onCancel: () =>
                            _setStatus(load.profile, booking, 'cancelled'),
                        onComplete: () =>
                            _setStatus(load.profile, booking, 'completed'),
                      ),
                    ),
                  )
                else
                  _BookingsTable(
                    bookings: load.bookings,
                    onOpenDetails: _openDetails,
                    onStatus: (booking, status) =>
                        _setStatus(load.profile, booking, status),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BookingsTable extends StatelessWidget {
  const _BookingsTable({
    required this.bookings,
    required this.onOpenDetails,
    required this.onStatus,
  });

  final List<SubTenantBooking> bookings;
  final ValueChanged<SubTenantBooking> onOpenDetails;
  final void Function(SubTenantBooking booking, String status) onStatus;

  @override
  Widget build(BuildContext context) {
    return ResponsiveTableWrapper(
      minWidth: 1080,
      child: DataTable(
        showCheckboxColumn: false,
        headingTextStyle: const TextStyle(
          color: SubTenantColors.muted,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
        dataTextStyle: const TextStyle(
          color: SubTenantColors.text,
          fontWeight: FontWeight.w700,
          fontSize: 12.5,
        ),
        columns: const [
          DataColumn(label: Text('Package')),
          DataColumn(label: Text('Tourist')),
          DataColumn(label: Text('Travel Date')),
          DataColumn(label: Text('Pax')),
          DataColumn(label: Text('Amount')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: bookings
            .map((booking) {
              final date = booking.travelDate == null
                  ? 'No travel date'
                  : DateFormat('MMM d, yyyy').format(booking.travelDate!);
              final amount = NumberFormat.currency(
                symbol: 'PHP ',
                decimalDigits: 0,
              ).format(booking.totalAmount);
              return DataRow(
                onSelectChanged: (_) => onOpenDetails(booking),
                cells: [
                  DataCell(Text(booking.packageTitle)),
                  DataCell(Text(booking.touristName)),
                  DataCell(Text(date)),
                  DataCell(Text('${booking.adults}')),
                  DataCell(Text(amount)),
                  DataCell(SubTenantStatusPill(status: booking.status)),
                  DataCell(
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton(
                          onPressed: () => onStatus(booking, 'confirmed'),
                          child: const Text('Confirm'),
                        ),
                        TextButton(
                          onPressed: () => onStatus(booking, 'completed'),
                          child: const Text('Complete'),
                        ),
                        TextButton(
                          onPressed: () => onStatus(booking, 'cancelled'),
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFFDC2626),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            })
            .toList(growable: false),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.onTap,
    required this.onConfirm,
    required this.onCancel,
    required this.onComplete,
  });

  final SubTenantBooking booking;
  final VoidCallback onTap;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final date = booking.travelDate == null
        ? 'No travel date'
        : DateFormat('MMM d, yyyy').format(booking.travelDate!);
    final amount = NumberFormat.currency(
      symbol: 'PHP ',
      decimalDigits: 0,
    ).format(booking.totalAmount);

    return SubTenantDashboardCard(
      padding: const EdgeInsets.all(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        booking.packageTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SubTenantColors.text,
                          fontSize: 15.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${booking.touristName} - $date',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SubTenantColors.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SubTenantStatusPill(status: booking.status),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                _MiniMeta(
                  icon: Icons.groups_rounded,
                  label: '${booking.adults} pax',
                ),
                _MiniMeta(icon: Icons.payments_rounded, label: amount),
                _MiniMeta(
                  icon: Icons.account_balance_wallet_rounded,
                  label: booking.paymentMethod.isEmpty
                      ? 'Payment N/A'
                      : booking.paymentMethod,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton(onPressed: onConfirm, child: const Text('Confirm')),
                TextButton(
                  onPressed: onComplete,
                  child: const Text('Complete'),
                ),
                TextButton(
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniMeta extends StatelessWidget {
  const _MiniMeta({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: SubTenantColors.blue, size: 14),
          const SizedBox(width: 5),
          Text(
            label,
            style: const TextStyle(
              color: SubTenantColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingListLoad {
  const _BookingListLoad({required this.profile, required this.bookings});

  final SubTenantProfile profile;
  final List<SubTenantBooking> bookings;
}
