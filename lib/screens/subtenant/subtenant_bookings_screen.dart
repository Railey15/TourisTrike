import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_booking_details_screen.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/subtenant_workspace_search.dart';
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
  final TextEditingController _searchCtrl = TextEditingController();
  final _workspaceSearch = SubTenantWorkspaceSearchController.instance;

  late Future<_BookingListLoad> _future;
  String _status = 'all';

  @override
  void initState() {
    super.initState();
    _future = _load();
    _searchCtrl.addListener(() => setState(() {}));
    _workspaceSearch.addListener(_handleWorkspaceSearchChanged);
  }

  @override
  void dispose() {
    _workspaceSearch.removeListener(_handleWorkspaceSearchChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleWorkspaceSearchChanged() {
    if (!mounted || _workspaceSearch.activeScope != 3) return;
    setState(() {});
  }

  Future<_BookingListLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final bookings = await _service.fetchBookings(profile, status: _status);
    return _BookingListLoad(profile: profile, bookings: bookings);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  List<SubTenantBooking> _filteredBookings(List<SubTenantBooking> bookings) {
    final query = [
      _searchCtrl.text.trim(),
      _workspaceSearch.queryFor(3),
    ].where((value) => value.isNotEmpty).join(' ').toLowerCase();

    if (query.isEmpty) return bookings;

    return bookings
        .where((booking) {
          final date = booking.travelDate == null
              ? 'no travel date'
              : DateFormat(
                  'MMM d, yyyy',
                ).format(booking.travelDate!).toLowerCase();

          final amount = NumberFormat.currency(
            symbol: 'PHP ',
            decimalDigits: 0,
          ).format(booking.totalAmount).toLowerCase();

          final searchable = [
            booking.packageTitle,
            booking.touristName,
            booking.status,
            booking.paymentMethod,
            date,
            amount,
            '${booking.adults}',
          ].join(' ').toLowerCase();

          return searchable.contains(query);
        })
        .toList(growable: false);
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

  @override
  Widget build(BuildContext context) {
    return SubTenantAdminShell(
      currentIndex: 3,
      title: 'Bookings',
      subtitle: 'Review package bookings with read-only city-scoped details.',
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
          final bookings = _filteredBookings(load.bookings);

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ResponsivePageContainer(
              children: [
                _BookingsToolbar(
                  controller: _searchCtrl,
                  selectedStatus: _status,
                  resultCount: bookings.length,
                  totalCount: load.bookings.length,
                  onStatusChanged: (value) {
                    setState(() {
                      _status = value;
                      _future = _load();
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (bookings.isEmpty)
                  EmptyStateCard(
                    icon: Icons.receipt_long_outlined,
                    title: 'No bookings found',
                    message: _searchCtrl.text.trim().isNotEmpty
                        ? 'No bookings match your search.'
                        : 'Bookings are filtered through tour packages in ${load.profile.assignedCity}.',
                  )
                else
                  _BookingsGrid(
                    bookings: bookings,
                    onOpenDetails: _openDetails,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _BookingsGrid extends StatelessWidget {
  const _BookingsGrid({
    required this.bookings,
    required this.onOpenDetails,
  });

  final List<SubTenantBooking> bookings;
  final ValueChanged<SubTenantBooking> onOpenDetails;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final mobile = Responsive.isMobile(context);
        final isDesktop = Responsive.isDesktop(context);
        final cols = mobile ? 1 : (isDesktop ? 3 : 2);
        const spacing = 14.0;
        final cardWidth =
            (constraints.maxWidth - spacing * (cols - 1)) / cols;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: bookings
              .map(
                (booking) => SizedBox(
                  width: cardWidth,
                  child: _BookingCard(
                    booking: booking,
                    onTap: () => onOpenDetails(booking),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _BookingsToolbar extends StatelessWidget {
  const _BookingsToolbar({
    required this.controller,
    required this.selectedStatus,
    required this.resultCount,
    required this.totalCount,
    required this.onStatusChanged,
  });

  final TextEditingController controller;
  final String selectedStatus;
  final int resultCount;
  final int totalCount;
  final ValueChanged<String> onStatusChanged;

  String get _countLabel {
    if (resultCount == totalCount) {
      return '$totalCount booking${totalCount == 1 ? '' : 's'}';
    }
    return '$resultCount of $totalCount bookings';
  }

  @override
  Widget build(BuildContext context) {
    final desktop = Responsive.isDesktop(context);

    return DashboardSectionCard(
      child: desktop
          ? Row(
              children: [
                Expanded(
                  flex: 5,
                  child: SubTenantSearchBar(
                    controller: controller,
                    hintText: 'Search package, tourist, payment, date...',
                    onChanged: (_) {},
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _StatusDropdown(
                    value: selectedStatus,
                    onChanged: onStatusChanged,
                  ),
                ),
                const SizedBox(width: 12),
                _ResultPill(label: _countLabel),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SubTenantSearchBar(
                  controller: controller,
                  hintText: 'Search bookings...',
                  onChanged: (_) {},
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _StatusDropdown(
                        value: selectedStatus,
                        onChanged: onStatusChanged,
                      ),
                    ),
                    const SizedBox(width: 10),
                    _ResultPill(label: _countLabel),
                  ],
                ),
              ],
            ),
    );
  }
}

class _StatusDropdown extends StatelessWidget {
  const _StatusDropdown({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  String _pretty(String value) {
    if (value == 'all') return 'All Status';
    return value[0].toUpperCase() + value.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    const values = ['all', 'pending', 'confirmed', 'cancelled', 'completed'];

    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        prefixIcon: const Icon(
          Icons.tune_rounded,
          color: SubTenantColors.blue,
          size: 20,
        ),
        filled: true,
        fillColor: const Color(0xFFF7FAFF),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SubTenantColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SubTenantColors.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: SubTenantColors.blue, width: 1.3),
        ),
      ),
      items: values
          .map(
            (status) => DropdownMenuItem<String>(
              value: status,
              child: Text(
                _pretty(status),
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: SubTenantColors.text,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
          )
          .toList(),
      onChanged: (next) {
        if (next != null) onChanged(next);
      },
    );
  }
}

class _ResultPill extends StatelessWidget {
  const _ResultPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: SubTenantColors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubTenantColors.blue.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.receipt_long_rounded,
            size: 16,
            color: SubTenantColors.blue,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: SubTenantColors.blue,
              fontSize: 12,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingCard extends StatefulWidget {
  const _BookingCard({required this.booking, required this.onTap});

  final SubTenantBooking booking;
  final VoidCallback onTap;

  @override
  State<_BookingCard> createState() => _BookingCardState();
}

class _BookingCardState extends State<_BookingCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final date = booking.travelDate == null
        ? 'No travel date'
        : DateFormat('MMM d, yyyy').format(booking.travelDate!);
    final amount = NumberFormat.currency(
      symbol: 'PHP ',
      decimalDigits: 0,
    ).format(booking.totalAmount);
    final payment = booking.paymentMethod.isEmpty
        ? 'Payment N/A'
        : booking.paymentMethod;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        transform: Matrix4.identity()
          ..translate(0.0, _hovered ? -3.0 : 0.0),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: _hovered
                ? SubTenantColors.blue.withValues(alpha: 0.35)
                : SubTenantColors.line,
          ),
          boxShadow: [
            BoxShadow(
              color: _hovered
                  ? SubTenantColors.blue.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.045),
              blurRadius: _hovered ? 24 : 14,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(22),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(22),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Header ─────────────────────────────────────────────
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: SubTenantColors.gradient,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: SubTenantColors.blue.withValues(alpha: 0.22),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.tour_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
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
                                fontSize: 14.5,
                                fontWeight: FontWeight.w900,
                                height: 1.25,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(
                                  Icons.person_rounded,
                                  size: 13,
                                  color: SubTenantColors.muted,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    booking.touristName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: SubTenantColors.muted,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      SubTenantStatusPill(status: booking.status),
                    ],
                  ),

                  const SizedBox(height: 16),
                  Divider(
                    height: 1,
                    color: SubTenantColors.line.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: 14),

                  // ── Details grid ────────────────────────────────────────
                  _DetailRow(
                    icon: Icons.calendar_today_rounded,
                    label: 'Travel Date',
                    value: date,
                  ),
                  const SizedBox(height: 9),
                  _DetailRow(
                    icon: Icons.groups_rounded,
                    label: 'Passengers',
                    value: '${booking.adults} pax',
                  ),
                  const SizedBox(height: 9),
                  _DetailRow(
                    icon: Icons.payments_rounded,
                    label: 'Amount',
                    value: amount,
                    valueColor: SubTenantColors.blue,
                    valueBold: true,
                  ),
                  const SizedBox(height: 9),
                  _DetailRow(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'Payment',
                    value: payment,
                  ),

                  const SizedBox(height: 16),

                  // ── Action button ───────────────────────────────────────
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: widget.onTap,
                      icon: const Icon(Icons.visibility_rounded, size: 16),
                      label: const Text('View Details'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _hovered
                            ? SubTenantColors.blue
                            : SubTenantColors.blue.withValues(alpha: 0.09),
                        foregroundColor: _hovered
                            ? Colors.white
                            : SubTenantColors.blue,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
    this.valueBold = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;
  final bool valueBold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: SubTenantColors.blue.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 15, color: SubTenantColors.blue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: SubTenantColors.lightMuted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: valueColor ?? SubTenantColors.text,
                  fontSize: 12.5,
                  fontWeight: valueBold ? FontWeight.w900 : FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BookingListLoad {
  const _BookingListLoad({required this.profile, required this.bookings});

  final SubTenantProfile profile;
  final List<SubTenantBooking> bookings;
}
