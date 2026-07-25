import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
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
  final SupabaseClient _supabase = Supabase.instance.client;
  final List<RealtimeChannel> _channels = <RealtimeChannel>[];

  bool _loading = true;
  String? _errorMessage;

  _BookingDetailsData? _details;
  _AssignedDriverView? _assignedDriver;
  List<_PackagePlaceView> _packagePlaces = const <_PackagePlaceView>[];
  List<_CustomizedPlaceView> _customizedPlaces = const <_CustomizedPlaceView>[];
  List<_ItineraryStopView> _itinerary = const <_ItineraryStopView>[];
  List<_PaymentView> _payments = const <_PaymentView>[];

  User? get _user => _supabase.auth.currentUser;
  String get _bookingIdText => stId(widget.bookingId);

  @override
  void initState() {
    super.initState();
    unawaited(_loadBookingDetails());
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    for (final channel in _channels) {
      unawaited(_supabase.removeChannel(channel));
    }
    _channels.clear();
    super.dispose();
  }

  Future<void> _loadBookingDetails({bool showLoading = true}) async {
    final user = _user;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'No active session. Please sign in again.';
      });
      return;
    }

    if (showLoading && mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final profile = await _loadCurrentSubtenantProfile(user.id);
      final bookingRow = await _loadBookingRow();
      final packageFuture = _loadPackageDetails(bookingRow, profile);
      final touristFuture = _loadTouristDetails(bookingRow);
      final driverFuture = _loadAssignedDriver(bookingRow);
      final packagePlacesFuture = _loadPackagePlaces(bookingRow['package_id']);
      final customizedPlacesFuture = _loadCustomizedPlaces();
      final itineraryFuture = _loadItinerary();
      final paymentsFuture = _loadPayments();

      final packageRow = await packageFuture;
      final touristRow = await touristFuture;
      final assignedDriver = await driverFuture;
      final packagePlaces = await packagePlacesFuture;
      final customizedPlaces = await customizedPlacesFuture;
      final itinerary = await itineraryFuture;
      final payments = await paymentsFuture;

      if (!mounted) return;
      setState(() {
        _details = _BookingDetailsData(
          bookingRow: bookingRow,
          packageRow: packageRow,
          touristRow: touristRow,
        );
        _assignedDriver = assignedDriver;
        _packagePlaces = packagePlaces;
        _customizedPlaces = customizedPlaces;
        _itinerary = itinerary;
        _payments = payments;
        _loading = false;
        _errorMessage = null;
      });
    } catch (error, stackTrace) {
      debugPrint(
        'SubTenantBookingDetailsScreen _loadBookingDetails error: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.toString();
      });
      _showError('Unable to load booking details.');
    }
  }

  Future<SubTenantProfile> _loadCurrentSubtenantProfile(String userId) async {
    try {
      final row = await _supabase
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
      if (row == null) {
        throw StateError('Subtenant profile not found.');
      }
      final profile = SubTenantProfile.fromMap(
        Map<String, dynamic>.from(row as Map),
      );
      if (!profile.isSubTenant) {
        throw StateError('Only subtenant users can view this booking page.');
      }
      return profile;
    } catch (error, stackTrace) {
      debugPrint(
        'SubTenantBookingDetailsScreen _loadCurrentSubtenantProfile '
        'error: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _loadBookingRow() async {
    try {
      final row = await _supabase
          .from('package_bookings')
          .select()
          .eq('id', widget.bookingId)
          .maybeSingle();
      if (row == null) {
        throw StateError('Booking not found.');
      }
      return Map<String, dynamic>.from(row as Map);
    } catch (error, stackTrace) {
      debugPrint(
        'SubTenantBookingDetailsScreen _loadBookingRow error: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _loadPackageDetails(
    Map<String, dynamic> bookingRow,
    SubTenantProfile profile,
  ) async {
    try {
      final packageId = bookingRow['package_id'];
      if (packageId == null) {
        return const <String, dynamic>{};
      }

      final row = await _supabase
          .from('tour_packages')
          .select()
          .eq('id', packageId)
          .maybeSingle();
      if (row == null) {
        return const <String, dynamic>{};
      }

      final packageRow = Map<String, dynamic>.from(row as Map);
      final packageCity = stString(packageRow, const <String>[
        'city',
        'municipality',
      ]);
      if (packageCity.isNotEmpty &&
          profile.assignedCity.isNotEmpty &&
          packageCity.toLowerCase() != profile.assignedCity.toLowerCase()) {
        throw StateError('Booking not found in your assigned city.');
      }
      return packageRow;
    } catch (error, stackTrace) {
      debugPrint(
        'SubTenantBookingDetailsScreen _loadPackageDetails error: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _loadTouristDetails(
    Map<String, dynamic> bookingRow,
  ) async {
    try {
      final touristId = stString(bookingRow, const <String>['tourist_id']);
      if (touristId.isEmpty) {
        return const <String, dynamic>{};
      }
      final row = await _supabase
          .from('profiles')
          .select()
          .eq('id', touristId)
          .maybeSingle();
      if (row == null) {
        return const <String, dynamic>{};
      }
      return Map<String, dynamic>.from(row as Map);
    } catch (error, stackTrace) {
      debugPrint(
        'SubTenantBookingDetailsScreen _loadTouristDetails error: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<_AssignedDriverView?> _loadAssignedDriver(
    Map<String, dynamic> bookingRow,
  ) async {
    try {
      final bookingId = bookingRow['id'];
      String driverId = stString(bookingRow, const <String>[
        'assigned_driver_id',
      ]);
      String assignmentStatus = '';

      if (driverId.isEmpty && bookingId != null) {
        final rows = await _supabase
            .from('package_activities')
            .select()
            .eq('booking_id', bookingId)
            .order('created_at', ascending: false);
        final activityRow = (rows as List<dynamic>)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .firstWhere(
              (row) =>
                  stString(row, const <String>['driver_id']).trim().isNotEmpty,
              orElse: () => const <String, dynamic>{},
            );
        driverId = stString(activityRow, const <String>['driver_id']);
        assignmentStatus = stString(activityRow, const <String>[
          'assignment_status',
          'status',
          'tour_status',
        ]);
      }

      if (driverId.isEmpty && bookingId != null) {
        final rows = await _supabase
            .from('booking_drivers')
            .select()
            .eq('booking_id', bookingId)
            .inFilter('status', <String>['accepted', 'pending'])
            .order('created_at', ascending: false);
        final driverRow = (rows as List<dynamic>)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .firstWhere(
              (row) =>
                  stString(row, const <String>['driver_id']).trim().isNotEmpty,
              orElse: () => const <String, dynamic>{},
            );
        driverId = stString(driverRow, const <String>['driver_id']);
        assignmentStatus = stString(driverRow, const <String>[
          'assignment_status',
          'status',
        ]);
      }

      if (driverId.isEmpty && bookingId != null) {
        final rows = await _supabase
            .from('booking_driver_assignments')
            .select()
            .eq('booking_id', bookingId)
            .order('created_at', ascending: false);
        final assignmentRow = (rows as List<dynamic>)
            .map((row) => Map<String, dynamic>.from(row as Map))
            .firstWhere(
              (row) =>
                  stString(row, const <String>['driver_id']).trim().isNotEmpty,
              orElse: () => const <String, dynamic>{},
            );
        driverId = stString(assignmentRow, const <String>['driver_id']);
        assignmentStatus = stString(assignmentRow, const <String>[
          'assignment_status',
          'status',
        ]);
      }

      if (driverId.isEmpty) {
        return null;
      }

      final row = await _supabase
          .from('profiles')
          .select()
          .eq('id', driverId)
          .maybeSingle();
      final driverProfile = row == null
          ? <String, dynamic>{'id': driverId}
          : Map<String, dynamic>.from(row as Map);
      return _AssignedDriverView.fromMap(
        driverProfile,
        assignmentStatus: assignmentStatus,
      );
    } catch (error, stackTrace) {
      debugPrint(
        'SubTenantBookingDetailsScreen _loadAssignedDriver error: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<List<_PackagePlaceView>> _loadPackagePlaces(dynamic packageId) async {
    try {
      if (packageId == null) {
        return const <_PackagePlaceView>[];
      }

      final packageSpotRows = await _supabase
          .from('tour_package_spots')
          .select()
          .eq('package_id', packageId)
          .order('sort_order', ascending: true);
      final packageSpots = (packageSpotRows as List<dynamic>)
          .map((row) => Map<String, dynamic>.from(row as Map))
          .toList(growable: false);
      if (packageSpots.isEmpty) {
        return const <_PackagePlaceView>[];
      }

      final spotIds = packageSpots
          .map((row) => row['spot_id'])
          .where((id) => id != null)
          .toList(growable: false);
      final touristSpotRows = spotIds.isEmpty
          ? const <dynamic>[]
          : await _supabase
                .from('tourist_spots')
                .select()
                .inFilter('id', spotIds);

      final spotsById = <String, Map<String, dynamic>>{
        for (final row in touristSpotRows)
          stId(row['id']): Map<String, dynamic>.from(row),
      };

      return packageSpots
          .map(
            (row) => _PackagePlaceView.fromMaps(
              row,
              spotsById[stId(row['spot_id'])] ?? const <String, dynamic>{},
            ),
          )
          .toList(growable: false);
    } catch (error, stackTrace) {
      debugPrint(
        'SubTenantBookingDetailsScreen _loadPackagePlaces error: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<List<_CustomizedPlaceView>> _loadCustomizedPlaces() async {
    try {
      final rows = await _supabase
          .from('customized_package_spots')
          .select()
          .eq('booking_id', widget.bookingId)
          .order('sort_order', ascending: true);
      return (rows as List<dynamic>)
          .map(
            (row) => _CustomizedPlaceView.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false);
    } catch (error, stackTrace) {
      debugPrint(
        'SubTenantBookingDetailsScreen _loadCustomizedPlaces error: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<List<_ItineraryStopView>> _loadItinerary() async {
    try {
      final rows = await _supabase
          .from('booking_itinerary_items')
          .select()
          .eq('booking_id', widget.bookingId)
          .order('destination_order', ascending: true)
          .order('order_number', ascending: true);
      return (rows as List<dynamic>)
          .map(
            (row) => _ItineraryStopView.fromMap(
              Map<String, dynamic>.from(row as Map),
            ),
          )
          .toList(growable: false);
    } catch (error, stackTrace) {
      debugPrint('SubTenantBookingDetailsScreen _loadItinerary error: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<List<_PaymentView>> _loadPayments() async {
    try {
      final rows = await _supabase
          .from('payment_records')
          .select()
          .eq('booking_id', widget.bookingId)
          .order('created_at', ascending: false);
      return (rows as List<dynamic>)
          .map(
            (row) =>
                _PaymentView.fromMap(Map<String, dynamic>.from(row as Map)),
          )
          .toList(growable: false);
    } catch (error, stackTrace) {
      debugPrint('SubTenantBookingDetailsScreen _loadPayments error: $error');
      debugPrintStack(stackTrace: stackTrace);
      rethrow;
    }
  }

  Future<void> _reloadAssignedDriver() async {
    final details = _details;
    if (details == null) {
      await _loadBookingDetails(showLoading: false);
      return;
    }

    try {
      final driver = await _loadAssignedDriver(details.bookingRow);
      if (!mounted) return;
      setState(() => _assignedDriver = driver);
    } catch (error, stackTrace) {
      debugPrint(
        'SubTenantBookingDetailsScreen _reloadAssignedDriver error: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      _showError('Unable to refresh assigned driver.');
    }
  }

  Future<void> _reloadCustomizedPlaces() async {
    try {
      final places = await _loadCustomizedPlaces();
      if (!mounted) return;
      setState(() => _customizedPlaces = places);
    } catch (error, stackTrace) {
      debugPrint(
        'SubTenantBookingDetailsScreen _reloadCustomizedPlaces error: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      _showError('Unable to refresh customized places.');
    }
  }

  Future<void> _reloadItinerary() async {
    try {
      final itinerary = await _loadItinerary();
      if (!mounted) return;
      setState(() => _itinerary = itinerary);
    } catch (error, stackTrace) {
      debugPrint(
        'SubTenantBookingDetailsScreen _reloadItinerary error: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      _showError('Unable to refresh itinerary.');
    }
  }

  Future<void> _reloadPayments() async {
    try {
      final payments = await _loadPayments();
      if (!mounted) return;
      setState(() => _payments = payments);
    } catch (error, stackTrace) {
      debugPrint(
        'SubTenantBookingDetailsScreen _reloadPayments error: '
        '$error',
      );
      debugPrintStack(stackTrace: stackTrace);
      _showError('Unable to refresh payments.');
    }
  }

  void _subscribeToRealtime() {
    for (final channel in _channels) {
      unawaited(_supabase.removeChannel(channel));
    }
    _channels.clear();

    final bookingId = _bookingIdText;
    if (bookingId.isEmpty) {
      return;
    }

    _channels.addAll(<RealtimeChannel>[
      _supabase
          .channel('subtenant-booking:$bookingId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'package_bookings',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: bookingId,
            ),
            callback: (_) => unawaited(_loadBookingDetails(showLoading: false)),
          )
          .subscribe(),
      _supabase
          .channel('subtenant-booking-activities:$bookingId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'package_activities',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'booking_id',
              value: bookingId,
            ),
            callback: (_) => unawaited(_reloadAssignedDriver()),
          )
          .subscribe(),
      _supabase
          .channel('subtenant-booking-drivers:$bookingId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'booking_drivers',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'booking_id',
              value: bookingId,
            ),
            callback: (_) => unawaited(_reloadAssignedDriver()),
          )
          .subscribe(),
      _supabase
          .channel('subtenant-booking-driver-assignments:$bookingId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'booking_driver_assignments',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'booking_id',
              value: bookingId,
            ),
            callback: (_) => unawaited(_reloadAssignedDriver()),
          )
          .subscribe(),
      _supabase
          .channel('subtenant-booking-itinerary:$bookingId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'booking_itinerary_items',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'booking_id',
              value: bookingId,
            ),
            callback: (_) => unawaited(_reloadItinerary()),
          )
          .subscribe(),
      _supabase
          .channel('subtenant-booking-customized:$bookingId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'customized_package_spots',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'booking_id',
              value: bookingId,
            ),
            callback: (_) => unawaited(_reloadCustomizedPlaces()),
          )
          .subscribe(),
      _supabase
          .channel('subtenant-booking-payments:$bookingId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'payment_records',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'booking_id',
              value: bookingId,
            ),
            callback: (_) => unawaited(_reloadPayments()),
          )
          .subscribe(),
    ]);
  }

  void _showError(String message) {
    if (!mounted) return;
    showSubTenantSnack(context, message);
  }

  Widget _refreshableTab(List<Widget> children) {
    return RefreshIndicator(
      onRefresh: () => _loadBookingDetails(showLoading: false),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
        children: children,
      ),
    );
  }

  Widget _overviewTab(_BookingDetailsData details) {
    return _refreshableTab([
      _SectionCard(
        title: 'Booking Summary',
        subtitle: 'Quick booking details without repeating destinations.',
        child: _KeyValueWrap(
          items: <_KeyValueItem>[
            _KeyValueItem(
              icon: Icons.location_city_rounded,
              label: 'City',
              value: details.cityLabel,
            ),
            _KeyValueItem(
              icon: Icons.calendar_month_rounded,
              label: 'Travel Date',
              value: details.travelDateLabel,
            ),
            _KeyValueItem(
              icon: Icons.groups_rounded,
              label: 'Passengers',
              value: details.passengerSummary,
            ),
            _KeyValueItem(
              icon: Icons.assignment_rounded,
              label: 'Booking Type',
              value: details.bookingTypeLabel,
            ),
            _KeyValueItem(
              icon: Icons.account_balance_wallet_rounded,
              label: 'Payment Method',
              value: details.paymentMethodLabel,
            ),
            _KeyValueItem(
              icon: Icons.payments_rounded,
              label: 'Total Amount',
              value: details.totalAmountLabel,
            ),
            _KeyValueItem(
              icon: Icons.savings_rounded,
              label: 'Downpayment',
              value: details.downpaymentLabel,
            ),
            _KeyValueItem(
              icon: Icons.request_quote_rounded,
              label: 'Remaining Balance',
              value: details.remainingBalanceLabel,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _SectionCard(
        title: 'Pickup and Drop-off',
        subtitle: 'Main route contact points for the booking.',
        child: _KeyValueWrap(
          items: <_KeyValueItem>[
            _KeyValueItem(
              icon: Icons.trip_origin_rounded,
              label: 'Pickup Address',
              value: details.pickupAddressLabel,
            ),
            _KeyValueItem(
              icon: Icons.flag_rounded,
              label: 'Drop-off Address',
              value: details.dropoffAddressLabel,
            ),
          ],
        ),
      ),
      const SizedBox(height: 14),
      _SectionCard(
        title: 'Booking Notes',
        subtitle: 'System-generated and tourist-provided notes.',
        child: _NoteBox(text: details.notesLabel),
      ),
    ]);
  }

  Widget _itineraryTab() {
    return _refreshableTab([
      _SectionCard(
        title: 'Final Tour Itinerary',
        subtitle:
            'The actual destination list for this booking. Package and customized places are merged here to avoid duplicates.',
        child: _itinerary.isEmpty
            ? const _SectionEmptyMessage(
                icon: Icons.route_outlined,
                title: 'No itinerary items yet',
                message:
                    'Itinerary items will appear here once the route is created.',
              )
            : _ItineraryTimeline(items: _itinerary),
      ),
    ]);
  }

  Widget _touristTab(_BookingDetailsData details) {
    return _refreshableTab([
      _SectionCard(
        title: 'Tourist Profile',
        subtitle: 'Traveler information linked to this booking.',
        child: _TouristDetailsCard(details: details),
      ),
    ]);
  }

  Widget _driverTab() {
    return _refreshableTab([
      _SectionCard(
        title: 'Assigned Driver',
        subtitle: 'Driver assignment is view-only for subtenant users.',
        child: _assignedDriver == null
            ? const _SectionEmptyMessage(
                icon: Icons.badge_outlined,
                title: 'No driver assigned yet.',
                message: 'This booking has not been matched with a driver.',
              )
            : _DriverSummaryCard(driver: _assignedDriver!),
      ),
    ]);
  }

  Widget _paymentsTab() {
    return _refreshableTab([
      _SectionCard(
        title: 'Payment Information',
        subtitle: 'Read-only payment history for this booking.',
        child: _payments.isEmpty
            ? const _SectionEmptyMessage(
                icon: Icons.payments_outlined,
                title: 'No payments recorded',
                message: 'Payments linked to this booking will appear here.',
              )
            : Column(
                children: _payments
                    .map(
                      (payment) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _PaymentTile(payment: payment),
                      ),
                    )
                    .toList(growable: false),
              ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final details = _details;

    return Scaffold(
      backgroundColor: SubTenantColors.background,
      appBar: subTenantAppBar(
        context,
        title: 'Booking Details',
        showBack: true,
      ),
      body: _loading && details == null
          ? const SubTenantLoadingView()
          : _errorMessage != null && details == null
          ? SubTenantErrorView(
              message: _errorMessage!,
              onRetry: () => unawaited(_loadBookingDetails()),
            )
          : DefaultTabController(
              length: 5,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                    child: _HeroBookingCard(details: details!),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _BookingDetailsTabBar(),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _overviewTab(details),
                        _itineraryTab(),
                        _touristTab(details),
                        _driverTab(),
                        _paymentsTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _BookingDetailsData {
  const _BookingDetailsData({
    required this.bookingRow,
    required this.packageRow,
    required this.touristRow,
  });

  final Map<String, dynamic> bookingRow;
  final Map<String, dynamic> packageRow;
  final Map<String, dynamic> touristRow;

  static final NumberFormat _money = NumberFormat.currency(
    symbol: 'PHP ',
    decimalDigits: 2,
  );

  String get packageTitle => stString(
    packageRow,
    const <String>['title'],
    fallback: stString(bookingRow, const <String>[
      'package_title',
    ], fallback: 'Tour Package'),
  );
  String get packageSubtitle => stString(packageRow, const <String>[
    'subtitle',
  ], fallback: stString(bookingRow, const <String>['subtitle']));
  String get packageDescription => stString(packageRow, const <String>[
    'description',
  ], fallback: stString(bookingRow, const <String>['description']));
  String get cityLabel {
    final city = stString(
      packageRow,
      const <String>['city', 'municipality'],
      fallback: stString(bookingRow, const <String>['city', 'municipality']),
    );
    return city.isEmpty ? 'Not provided' : city;
  }

  String get status => stString(bookingRow, const <String>[
    'booking_status',
    'status',
  ], fallback: 'pending');
  DateTime? get travelDate =>
      stDate(bookingRow['travel_date'] ?? bookingRow['date']);
  String get travelDateLabel => travelDate == null
      ? 'Not scheduled'
      : DateFormat('MMMM d, yyyy').format(travelDate!);
  int get adults => stInt(bookingRow['adults'] ?? bookingRow['adult_count']);
  int get children =>
      stInt(bookingRow['children'] ?? bookingRow['child_count']);
  int get totalPassengers => stInt(
    bookingRow['total_passengers'] ?? bookingRow['pax'] ?? (adults + children),
  );
  String get passengerSummary =>
      '$adults adult${adults == 1 ? '' : 's'} • '
      '$children child${children == 1 ? '' : 'ren'} • '
      '$totalPassengers total';
  String get bookingTypeLabel {
    final value = stString(bookingRow, const <String>['booking_type', 'type']);
    return value.isEmpty ? 'Standard booking' : stTitleCase(value);
  }

  double get totalAmount =>
      stDouble(bookingRow['total_amount'] ?? bookingRow['amount']);
  double get downpaymentAmount =>
      stDouble(bookingRow['downpayment_amount'] ?? bookingRow['downpayment']);
  double get remainingBalance => stDouble(
    bookingRow['remaining_balance'] ??
        (totalAmount > 0 ? totalAmount - downpaymentAmount : 0),
  );
  String get totalAmountLabel => _money.format(totalAmount);
  String get downpaymentLabel => _money.format(downpaymentAmount);
  String get remainingBalanceLabel => _money.format(remainingBalance);

  String get paymentMethodLabel {
    final value = stString(bookingRow, const <String>['payment_method']);
    return value.isEmpty ? 'Not provided' : stTitleCase(value);
  }

  String get notesLabel {
    final value = stString(bookingRow, const <String>[
      'notes',
      'special_requests',
    ]);
    return value.isEmpty ? 'No notes provided' : value;
  }

  String get pickupAddressLabel {
    final value = stString(bookingRow, const <String>['pickup_address']);
    return value.isEmpty ? 'Not provided' : value;
  }

  String get dropoffAddressLabel {
    final value = stString(bookingRow, const <String>['dropoff_address']);
    return value.isEmpty ? 'Not provided' : value;
  }

  String get touristName {
    final fullName = stString(touristRow, const <String>['full_name']);
    if (fullName.isNotEmpty) return fullName;
    final generated = <String>[
      stString(touristRow, const <String>['first_name']),
      stString(touristRow, const <String>['last_name']),
    ].where((value) => value.isNotEmpty).join(' ');
    return generated.isEmpty ? 'Tourist' : generated;
  }

  String get touristMobileLabel {
    final value = stString(touristRow, const <String>['mobile', 'phone']);
    return value.isEmpty ? 'Not provided' : value;
  }

  String get touristAddressLabel {
    final value = stString(touristRow, const <String>['address']);
    return value.isEmpty ? 'Not provided' : value;
  }

  String get touristBarangayLabel {
    final value = stString(touristRow, const <String>['barangay']);
    return value.isEmpty ? 'Not provided' : value;
  }

  String get touristCityLabel {
    final value = stString(touristRow, const <String>['city']);
    return value.isEmpty ? 'Not provided' : value;
  }

  String get touristProvinceLabel {
    final value = stString(touristRow, const <String>['province']);
    return value.isEmpty ? 'Not provided' : value;
  }
}

class _AssignedDriverView {
  const _AssignedDriverView({
    required this.id,
    required this.fullName,
    required this.mobile,
    required this.driverStatus,
    required this.averageRating,
    required this.totalReviews,
    required this.assignmentStatus,
  });

  final String id;
  final String fullName;
  final String mobile;
  final String driverStatus;
  final double averageRating;
  final int totalReviews;
  final String assignmentStatus;

  factory _AssignedDriverView.fromMap(
    Map<String, dynamic> row, {
    required String assignmentStatus,
  }) {
    final fullName = stString(
      row,
      const <String>['full_name'],
      fallback: <String>[
        stString(row, const <String>['first_name']),
        stString(row, const <String>['last_name']),
      ].where((value) => value.isNotEmpty).join(' '),
    );
    return _AssignedDriverView(
      id: stId(row['id']),
      fullName: fullName.isEmpty ? 'Assigned driver' : fullName,
      mobile: stString(row, const <String>['mobile', 'phone']),
      driverStatus: stString(row, const <String>[
        'driver_status',
        'status',
      ], fallback: 'unknown'),
      averageRating: stDouble(row['average_rating'] ?? row['rating']),
      totalReviews: stInt(row['total_reviews'] ?? row['review_count']),
      assignmentStatus: assignmentStatus,
    );
  }

  String get mobileLabel => mobile.isEmpty ? 'Not provided' : mobile;
  String get driverStatusLabel =>
      driverStatus.trim().isEmpty ? 'Unknown' : stTitleCase(driverStatus);
  String get ratingLabel =>
      averageRating <= 0 ? 'No rating yet' : averageRating.toStringAsFixed(1);
  String get reviewCountLabel =>
      totalReviews <= 0 ? 'No reviews yet' : '$totalReviews review(s)';
  String get assignmentStatusLabel => assignmentStatus.trim().isEmpty
      ? 'Assignment status unavailable'
      : stTitleCase(assignmentStatus);
}

class _PackagePlaceView {
  const _PackagePlaceView({
    required this.title,
    required this.address,
    required this.barangay,
    required this.municipality,
    required this.city,
    required this.province,
    required this.imageUrl,
    required this.openingTime,
    required this.closingTime,
    required this.estimatedDurationMinutes,
    required this.recommendedDurationMinutes,
    required this.sortOrder,
  });

  final String title;
  final String address;
  final String barangay;
  final String municipality;
  final String city;
  final String province;
  final String imageUrl;
  final String openingTime;
  final String closingTime;
  final int estimatedDurationMinutes;
  final int recommendedDurationMinutes;
  final int sortOrder;

  factory _PackagePlaceView.fromMaps(
    Map<String, dynamic> packageSpotRow,
    Map<String, dynamic> touristSpotRow,
  ) {
    return _PackagePlaceView(
      title: stString(touristSpotRow, const <String>[
        'title',
        'name',
      ], fallback: 'Tourist Spot'),
      address: stString(touristSpotRow, const <String>[
        'address',
        'place_address',
      ]),
      barangay: stString(touristSpotRow, const <String>['barangay']),
      municipality: stString(touristSpotRow, const <String>['municipality']),
      city: stString(touristSpotRow, const <String>['city']),
      province: stString(touristSpotRow, const <String>['province']),
      imageUrl: stString(touristSpotRow, const <String>[
        'image_url',
        'cover_image_url',
      ]),
      openingTime: stString(
        packageSpotRow,
        const <String>['opening_time'],
        fallback: stString(touristSpotRow, const <String>['opening_time']),
      ),
      closingTime: stString(
        packageSpotRow,
        const <String>['closing_time'],
        fallback: stString(touristSpotRow, const <String>['closing_time']),
      ),
      estimatedDurationMinutes: stInt(
        packageSpotRow['estimated_duration_minutes'] ??
            touristSpotRow['estimated_duration_minutes'],
      ),
      recommendedDurationMinutes: stInt(
        packageSpotRow['recommended_visit_duration_minutes'] ??
            touristSpotRow['recommended_visit_duration_minutes'],
      ),
      sortOrder: stInt(packageSpotRow['sort_order']),
    );
  }

  String get locationSummary => <String>[
    barangay,
    municipality.isNotEmpty ? municipality : city,
    province,
  ].where((value) => value.isNotEmpty).join(', ');
  String get addressLabel => address.isEmpty ? 'Not provided' : address;
  String get openingTimeLabel =>
      openingTime.isEmpty ? 'Not provided' : openingTime;
  String get closingTimeLabel =>
      closingTime.isEmpty ? 'Not provided' : closingTime;
  String get estimatedDurationLabel => estimatedDurationMinutes <= 0
      ? 'Not provided'
      : '$estimatedDurationMinutes minutes';
  String get recommendedDurationLabel => recommendedDurationMinutes <= 0
      ? 'Not provided'
      : '$recommendedDurationMinutes minutes';
  String get sortOrderLabel =>
      sortOrder <= 0 ? 'Not provided' : sortOrder.toString();
}

class _CustomizedPlaceView {
  const _CustomizedPlaceView({
    required this.title,
    required this.address,
    required this.municipality,
    required this.barangay,
    required this.imageUrl,
    required this.actionType,
    required this.additionalFee,
    required this.sortOrder,
    required this.openingTime,
    required this.closingTime,
    required this.arrivalTime,
    required this.durationMinutes,
  });

  final String title;
  final String address;
  final String municipality;
  final String barangay;
  final String imageUrl;
  final String actionType;
  final double additionalFee;
  final int sortOrder;
  final String openingTime;
  final String closingTime;
  final String arrivalTime;
  final int durationMinutes;

  factory _CustomizedPlaceView.fromMap(Map<String, dynamic> row) {
    return _CustomizedPlaceView(
      title: stString(row, const <String>[
        'spot_title',
        'place_name',
      ], fallback: 'Custom Place'),
      address: stString(row, const <String>['spot_address', 'place_address']),
      municipality: stString(row, const <String>['municipality', 'city']),
      barangay: stString(row, const <String>['barangay']),
      imageUrl: stString(row, const <String>['image_url']),
      actionType: stString(row, const <String>['action_type']),
      additionalFee: stDouble(row['additional_fee']),
      sortOrder: stInt(row['sort_order']),
      openingTime: stString(row, const <String>['opening_time']),
      closingTime: stString(row, const <String>['closing_time']),
      arrivalTime: stString(row, const <String>['estimated_arrival_time']),
      durationMinutes: stInt(row['estimated_duration_minutes']),
    );
  }

  String get locationSummary => <String>[
    barangay,
    municipality,
  ].where((value) => value.isNotEmpty).join(', ');
  String get addressLabel => address.isEmpty ? 'Not provided' : address;
  String get actionTypeLabel =>
      actionType.isEmpty ? 'Not provided' : stTitleCase(actionType);
  String get additionalFeeLabel => NumberFormat.currency(
    symbol: 'PHP ',
    decimalDigits: 2,
  ).format(additionalFee);
  String get sortOrderLabel =>
      sortOrder <= 0 ? 'Not provided' : sortOrder.toString();
  String get openingTimeLabel =>
      openingTime.isEmpty ? 'Not provided' : openingTime;
  String get closingTimeLabel =>
      closingTime.isEmpty ? 'Not provided' : closingTime;
  String get arrivalTimeLabel =>
      arrivalTime.isEmpty ? 'Not provided' : arrivalTime;
  String get durationLabel =>
      durationMinutes <= 0 ? 'Not provided' : '$durationMinutes minutes';
}

class _ItineraryStopView {
  const _ItineraryStopView({
    required this.destinationName,
    required this.destinationAddress,
    required this.arrivalTime,
    required this.departureTime,
    required this.estimatedStayDurationMinutes,
    required this.activityNote,
    required this.sourceType,
    required this.spotStatus,
    required this.imageUrl,
    required this.municipality,
    required this.barangay,
    required this.destinationOrder,
    required this.orderNumber,
  });

  final String destinationName;
  final String destinationAddress;
  final String arrivalTime;
  final String departureTime;
  final int estimatedStayDurationMinutes;
  final String activityNote;
  final String sourceType;
  final String spotStatus;
  final String imageUrl;
  final String municipality;
  final String barangay;
  final int destinationOrder;
  final int orderNumber;

  factory _ItineraryStopView.fromMap(Map<String, dynamic> row) {
    return _ItineraryStopView(
      destinationName: stString(row, const <String>[
        'destination_name',
      ], fallback: 'Destination'),
      destinationAddress: stString(row, const <String>['destination_address']),
      arrivalTime: stString(row, const <String>['arrival_time']),
      departureTime: stString(row, const <String>['departure_time']),
      estimatedStayDurationMinutes: stInt(
        row['estimated_stay_duration_minutes'],
      ),
      activityNote: stString(row, const <String>['activity_note']),
      sourceType: stString(row, const <String>[
        'source_type',
        'itinerary_source',
      ]),
      spotStatus: stString(row, const <String>['spot_status']),
      imageUrl: stString(row, const <String>['image_url']),
      municipality: stString(row, const <String>['municipality', 'city']),
      barangay: stString(row, const <String>['barangay']),
      destinationOrder: stInt(row['destination_order']),
      orderNumber: stInt(row['order_number']),
    );
  }

  String get locationSummary => <String>[
    barangay,
    municipality,
  ].where((value) => value.isNotEmpty).join(', ');
  String get addressLabel =>
      destinationAddress.isEmpty ? 'Not provided' : destinationAddress;
  String get scheduleLabel {
    final parts = <String>[
      if (arrivalTime.isNotEmpty) 'Arrive: $arrivalTime',
      if (departureTime.isNotEmpty) 'Depart: $departureTime',
    ];
    return parts.isEmpty ? 'Schedule not provided' : parts.join(' • ');
  }

  String get durationLabel => estimatedStayDurationMinutes <= 0
      ? 'Not provided'
      : '$estimatedStayDurationMinutes minutes';
  String get activityNoteLabel =>
      activityNote.isEmpty ? 'No activity note' : activityNote;
  String get sourceTypeLabel =>
      sourceType.isEmpty ? 'Not provided' : stTitleCase(sourceType);
  String get spotStatusLabel =>
      spotStatus.isEmpty ? 'Not provided' : stTitleCase(spotStatus);
  String get orderLabel =>
      'Destination ${destinationOrder <= 0 ? '-' : destinationOrder}'
      ' • Item ${orderNumber <= 0 ? '-' : orderNumber}';
}

class _PaymentView {
  const _PaymentView({
    required this.amount,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.paymentType,
    required this.paymentReference,
    required this.paidAt,
    required this.createdAt,
  });

  final double amount;
  final String paymentMethod;
  final String paymentStatus;
  final String paymentType;
  final String paymentReference;
  final DateTime? paidAt;
  final DateTime? createdAt;

  factory _PaymentView.fromMap(Map<String, dynamic> row) {
    return _PaymentView(
      amount: stDouble(row['amount']),
      paymentMethod: stString(row, const <String>['payment_method']),
      paymentStatus: stString(row, const <String>[
        'status',
      ], fallback: 'pending_confirmation'),
      paymentType: stString(row, const <String>['payment_stage']),
      paymentReference: stString(row, const <String>[
        'external_reference_no',
      ]),
      paidAt: stDate(row['payee_confirmed_at']),
      createdAt: stDate(row['created_at']),
    );
  }

  static final NumberFormat _money = NumberFormat.currency(
    symbol: 'PHP ',
    decimalDigits: 2,
  );

  String get amountLabel => _money.format(amount);
  String get paymentMethodLabel =>
      paymentMethod.isEmpty ? 'Not provided' : stTitleCase(paymentMethod);
  String get paymentStatusLabel => stTitleCase(paymentStatus);
  String get paymentTypeLabel =>
      paymentType.isEmpty ? 'Not provided' : stTitleCase(paymentType);
  String get paymentReferenceLabel =>
      paymentReference.isEmpty ? 'Not provided' : paymentReference;
  String get paidAtLabel => paidAt == null
      ? 'Not paid yet'
      : DateFormat('MMM d, yyyy • h:mm a').format(paidAt!);
  String get createdAtLabel => createdAt == null
      ? 'Not provided'
      : DateFormat('MMM d, yyyy • h:mm a').format(createdAt!);
}

class _HeroBookingCard extends StatelessWidget {
  const _HeroBookingCard({required this.details});

  final _BookingDetailsData details;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: SubTenantColors.gradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: SubTenantColors.blue.withValues(alpha: 0.24),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
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
                      details.packageTitle,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (details.packageSubtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        details.packageSubtitle,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SubTenantStatusPill(status: details.status),
                  const SizedBox(height: 8),
                  const _ReadOnlyPill(),
                ],
              ),
            ],
          ),
          if (details.packageDescription.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              details.packageDescription,
              style: const TextStyle(
                color: Colors.white,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _HeroPill(
                icon: Icons.location_city_rounded,
                text: details.cityLabel,
              ),
              _HeroPill(
                icon: Icons.calendar_today_rounded,
                text: details.travelDateLabel,
              ),
              _HeroPill(
                icon: Icons.groups_rounded,
                text: details.passengerSummary,
              ),
              _HeroPill(
                icon: Icons.payments_rounded,
                text: details.totalAmountLabel,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyPill extends StatelessWidget {
  const _ReadOnlyPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_rounded, color: Colors.white, size: 13),
          SizedBox(width: 6),
          Text(
            'View Only',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroPill extends StatelessWidget {
  const _HeroPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 250),
            child: Text(
              text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}


class _BookingDetailsTabBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TabBar(
        isScrollable: true,
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: SubTenantColors.blue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        labelColor: SubTenantColors.blue,
        unselectedLabelColor: SubTenantColors.muted,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12.5,
        ),
        padding: const EdgeInsets.all(6),
        tabs: const [
          Tab(icon: Icon(Icons.dashboard_rounded, size: 18), text: 'Overview'),
          Tab(icon: Icon(Icons.route_rounded, size: 18), text: 'Itinerary'),
          Tab(icon: Icon(Icons.person_rounded, size: 18), text: 'Tourist'),
          Tab(icon: Icon(Icons.badge_rounded, size: 18), text: 'Driver'),
          Tab(icon: Icon(Icons.payments_rounded, size: 18), text: 'Payments'),
        ],
      ),
    );
  }
}

class _NoteBox extends StatelessWidget {
  const _NoteBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final hasText = text.trim().isNotEmpty && text.trim() != 'Not provided';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: SubTenantColors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.notes_rounded,
              color: SubTenantColors.blue,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hasText ? text : 'No additional notes for this booking.',
              style: TextStyle(
                color: hasText ? SubTenantColors.text : SubTenantColors.muted,
                fontWeight: FontWeight.w800,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ItineraryTimeline extends StatelessWidget {
  const _ItineraryTimeline({required this.items});

  final List<_ItineraryStopView> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List<Widget>.generate(items.length, (index) {
        final item = items[index];
        final isLast = index == items.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 34,
                child: Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: SubTenantColors.blue,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          color: SubTenantColors.line,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                  child: _ItineraryTile(item: item),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SubTenantSectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _KeyValueItem {
  const _KeyValueItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _KeyValueWrap extends StatelessWidget {
  const _KeyValueWrap({required this.items});

  final List<_KeyValueItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 760;
        final itemWidth = isWide
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: items
              .map(
                (item) => SizedBox(
                  width: itemWidth,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FBFF),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: SubTenantColors.line),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: SubTenantColors.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            item.icon,
                            color: SubTenantColors.blue,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                style: const TextStyle(
                                  color: SubTenantColors.muted,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                item.value,
                                style: const TextStyle(
                                  color: SubTenantColors.text,
                                  fontWeight: FontWeight.w900,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _TouristDetailsCard extends StatelessWidget {
  const _TouristDetailsCard({required this.details});

  final _BookingDetailsData details;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SubTenantInfoTile(
          icon: Icons.person_rounded,
          title: 'Full Name',
          subtitle: details.touristName,
        ),
        SubTenantInfoTile(
          icon: Icons.phone_rounded,
          title: 'Mobile',
          subtitle: details.touristMobileLabel,
        ),
        SubTenantInfoTile(
          icon: Icons.home_rounded,
          title: 'Address',
          subtitle: details.touristAddressLabel,
        ),
        SubTenantInfoTile(
          icon: Icons.location_on_rounded,
          title: 'Barangay',
          subtitle: details.touristBarangayLabel,
        ),
        SubTenantInfoTile(
          icon: Icons.location_city_rounded,
          title: 'City',
          subtitle: details.touristCityLabel,
        ),
        SubTenantInfoTile(
          icon: Icons.map_rounded,
          title: 'Province',
          subtitle: details.touristProvinceLabel,
        ),
      ],
    );
  }
}

class _DriverSummaryCard extends StatelessWidget {
  const _DriverSummaryCard({required this.driver});

  final _AssignedDriverView driver;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Column(
        children: [
          SubTenantInfoTile(
            icon: Icons.badge_rounded,
            title: driver.fullName,
            subtitle: driver.mobileLabel,
            trailing: SubTenantStatusPill(status: driver.driverStatus),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _MiniInfoBox(
                  icon: Icons.assignment_ind_rounded,
                  label: 'Assignment',
                  value: driver.assignmentStatusLabel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _MiniInfoBox(
                  icon: Icons.star_rounded,
                  label: 'Rating',
                  value: driver.ratingLabel,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _MiniInfoBox(
            icon: Icons.reviews_rounded,
            label: 'Reviews',
            value: driver.reviewCountLabel,
          ),
        ],
      ),
    );
  }
}

class _MiniInfoBox extends StatelessWidget {
  const _MiniInfoBox({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: SubTenantColors.blue, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$label\n',
                    style: const TextStyle(
                      color: SubTenantColors.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  TextSpan(
                    text: value,
                    style: const TextStyle(
                      color: SubTenantColors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.details,
  });

  final String title;
  final String subtitle;
  final String imageUrl;
  final List<String> details;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ImageThumb(imageUrl: imageUrl, icon: Icons.place_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: SubTenantColors.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                ...details.map(
                  (detail) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      detail,
                      style: const TextStyle(
                        color: SubTenantColors.text,
                        fontSize: 12.3,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ItineraryTile extends StatelessWidget {
  const _ItineraryTile({required this.item});

  final _ItineraryStopView item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ImageThumb(imageUrl: item.imageUrl, icon: Icons.route_rounded),
          const SizedBox(width: 12),
          Expanded(
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
                            item.destinationName,
                            style: const TextStyle(
                              color: SubTenantColors.text,
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            item.orderLabel,
                            style: const TextStyle(
                              color: SubTenantColors.lightMuted,
                              fontWeight: FontWeight.w800,
                              fontSize: 11.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (item.spotStatus.trim().isNotEmpty)
                      SubTenantStatusPill(status: item.spotStatus),
                  ],
                ),
                const SizedBox(height: 8),
                _PlainDetailLine(label: 'Address', value: item.addressLabel),
                _PlainDetailLine(
                  label: 'Location',
                  value: item.locationSummary.isEmpty
                      ? 'Not provided'
                      : item.locationSummary,
                ),
                _PlainDetailLine(label: 'Schedule', value: item.scheduleLabel),
                _PlainDetailLine(
                  label: 'Stay Duration',
                  value: item.durationLabel,
                ),
                _PlainDetailLine(
                  label: 'Activity Note',
                  value: item.activityNoteLabel,
                ),
                _PlainDetailLine(label: 'Source', value: item.sourceTypeLabel),
                _PlainDetailLine(label: 'Status', value: item.spotStatusLabel),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PaymentTile extends StatelessWidget {
  const _PaymentTile({required this.payment});

  final _PaymentView payment;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: SubTenantColors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.payments_rounded,
              color: SubTenantColors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        payment.amountLabel,
                        style: const TextStyle(
                          color: SubTenantColors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    SubTenantStatusPill(status: payment.paymentStatus),
                  ],
                ),
                const SizedBox(height: 8),
                _PlainDetailLine(
                  label: 'Method',
                  value: payment.paymentMethodLabel,
                ),
                _PlainDetailLine(
                  label: 'Type',
                  value: payment.paymentTypeLabel,
                ),
                _PlainDetailLine(
                  label: 'Reference',
                  value: payment.paymentReferenceLabel,
                ),
                _PlainDetailLine(label: 'Paid At', value: payment.paidAtLabel),
                _PlainDetailLine(
                  label: 'Created At',
                  value: payment.createdAtLabel,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlainDetailLine extends StatelessWidget {
  const _PlainDetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(
                color: SubTenantColors.muted,
                fontWeight: FontWeight.w800,
                fontSize: 12.3,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: SubTenantColors.text,
                fontWeight: FontWeight.w700,
                fontSize: 12.3,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.imageUrl, required this.icon});

  final String imageUrl;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 68,
      height: 68,
      decoration: BoxDecoration(
        color: const Color(0xFFE8EEF7),
        borderRadius: BorderRadius.circular(18),
        image: imageUrl.isEmpty
            ? null
            : DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover),
      ),
      child: imageUrl.isEmpty
          ? Icon(icon, color: SubTenantColors.lightMuted)
          : null,
    );
  }
}

class _SectionEmptyMessage extends StatelessWidget {
  const _SectionEmptyMessage({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: SubTenantColors.blue),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SubTenantColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: SubTenantColors.muted,
              fontWeight: FontWeight.w700,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
