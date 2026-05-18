import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantBookingDetailsScreen extends StatefulWidget {
  const SubTenantBookingDetailsScreen({super.key, required this.bookingId});

  final dynamic bookingId;

  @override
  State<SubTenantBookingDetailsScreen> createState() =>
      _SubTenantBookingDetailsScreenState();
}

class _SubTenantBookingDetailsScreenState
    extends State<SubTenantBookingDetailsScreen> {
  final SubTenantService _service = SubTenantService();
  late Future<_BookingDetailsLoad> _future;
  String? _selectedDriverId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_BookingDetailsLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final booking = await _service.fetchBookingById(profile, widget.bookingId);
    if (booking == null) {
      throw StateError('Booking not found in your assigned city.');
    }
    final drivers = await _service.fetchDrivers(profile);
    _selectedDriverId = booking.assignedDriverId.isEmpty
        ? null
        : booking.assignedDriverId;
    return _BookingDetailsLoad(
      profile: profile,
      booking: booking,
      drivers: drivers,
    );
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _setStatus(_BookingDetailsLoad load, String status) async {
    setState(() => _saving = true);
    try {
      await _service.updateBookingStatus(load.profile, load.booking, status);
      if (!mounted) return;
      showSubTenantSnack(context, 'Booking updated.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to update booking: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _assignDriver(_BookingDetailsLoad load) async {
    final driverId = _selectedDriverId;
    if (driverId == null || driverId.isEmpty) {
      showSubTenantSnack(context, 'Select a local driver first.');
      return;
    }

    final driver = load.drivers
        .where((item) => item.id == driverId)
        .firstOrNull;
    if (driver == null) {
      showSubTenantSnack(context, 'Selected driver is unavailable.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _service.assignDriverToBooking(load.profile, load.booking, driver);
      if (!mounted) return;
      showSubTenantSnack(context, 'Driver assigned.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(
        context,
        'Assigning drivers needs package_bookings.assigned_driver_id: $e',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SubTenantColors.background,
      appBar: subTenantAppBar(
        context,
        title: 'Booking Details',
        showBack: true,
      ),
      body: FutureBuilder<_BookingDetailsLoad>(
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
          final booking = load.booking;
          final travelDate = booking.travelDate == null
              ? 'No travel date'
              : DateFormat('MMMM d, yyyy').format(booking.travelDate!);
          final amount = NumberFormat.currency(
            symbol: 'PHP ',
            decimalDigits: 0,
          ).format(booking.totalAmount);

          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              SubTenantDashboardCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            booking.packageTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SubTenantColors.text,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        SubTenantStatusPill(status: booking.status),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      booking.package?.description ?? '',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SubTenantDashboardCard(
                child: Column(
                  children: [
                    const SubTenantSectionHeader(title: 'Booking Information'),
                    const SizedBox(height: 8),
                    SubTenantInfoTile(
                      icon: Icons.person_rounded,
                      title: 'Tourist',
                      subtitle: booking.touristName,
                    ),
                    SubTenantInfoTile(
                      icon: Icons.phone_rounded,
                      title: 'Tourist Mobile',
                      subtitle: booking.touristMobile.isEmpty
                          ? 'Not provided'
                          : booking.touristMobile,
                    ),
                    SubTenantInfoTile(
                      icon: Icons.calendar_month_rounded,
                      title: 'Travel Date',
                      subtitle: travelDate,
                    ),
                    SubTenantInfoTile(
                      icon: Icons.groups_rounded,
                      title: 'Adults',
                      subtitle: '${booking.adults}',
                    ),
                    SubTenantInfoTile(
                      icon: Icons.payments_rounded,
                      title: 'Total Amount',
                      subtitle: amount,
                    ),
                    SubTenantInfoTile(
                      icon: Icons.account_balance_wallet_rounded,
                      title: 'Payment Method',
                      subtitle: booking.paymentMethod.isEmpty
                          ? 'Not provided'
                          : booking.paymentMethod,
                    ),
                    SubTenantInfoTile(
                      icon: Icons.notes_rounded,
                      title: 'Notes',
                      subtitle: booking.notes.isEmpty
                          ? 'No notes'
                          : booking.notes,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              SubTenantDashboardCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SubTenantSectionHeader(
                      title: 'Assign Driver / Guide',
                      subtitle:
                          'Only drivers from the assigned city are available.',
                    ),
                    const SizedBox(height: 12),
                    if (load.drivers.isEmpty)
                      const SubTenantEmptyState(
                        icon: Icons.badge_outlined,
                        title: 'No local drivers',
                        message:
                            'Add or approve local drivers before assigning tours.',
                      )
                    else ...[
                      DropdownButtonFormField<String>(
                        initialValue: _selectedDriverId,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: SubTenantColors.line,
                            ),
                          ),
                        ),
                        hint: const Text('Select driver'),
                        items: load.drivers
                            .map(
                              (driver) => DropdownMenuItem<String>(
                                value: driver.id,
                                child: Text(
                                  [
                                    driver.fullName,
                                    if (driver.plateNumber.isNotEmpty)
                                      driver.plateNumber,
                                  ].join(' - '),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setState(() => _selectedDriverId = value),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _assignDriver(load),
                        icon: const Icon(Icons.assignment_ind_rounded),
                        label: const Text('Assign Driver'),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => _setStatus(load, 'confirmed'),
                      child: const Text('Confirm'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => _setStatus(load, 'completed'),
                      child: const Text('Complete'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving
                          ? null
                          : () => _setStatus(load, 'cancelled'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BookingDetailsLoad {
  const _BookingDetailsLoad({
    required this.profile,
    required this.booking,
    required this.drivers,
  });

  final SubTenantProfile profile;
  final SubTenantBooking booking;
  final List<SubTenantDriver> drivers;
}
