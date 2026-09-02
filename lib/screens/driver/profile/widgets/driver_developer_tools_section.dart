import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:touristrike/core/services/developer_settings.dart';
import 'package:touristrike/core/supabase/touristrike_models.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/driver/driver_package_tracking_screen.dart';
import 'package:touristrike/screens/driver/profile/widgets/driver_profile_components.dart';

class DriverDeveloperToolsSection extends StatefulWidget {
  const DriverDeveloperToolsSection({super.key});

  @override
  State<DriverDeveloperToolsSection> createState() =>
      _DriverDeveloperToolsSectionState();
}

class _DriverDeveloperToolsSectionState
    extends State<DriverDeveloperToolsSection> {
  final DeveloperSettings _settings = DeveloperSettings.instance;
  final TourisTrikeRepository _repository = TourisTrikeRepository();

  late final TextEditingController _bookingController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;

  Timer? _bookingSaveTimer;
  List<_TestDriverAssignment> _assignments = const [];
  String _activityId = '';
  String _selectedAssignmentId = '';
  bool _loadingBooking = false;
  bool _opening = false;
  bool _resetting = false;
  bool _savingLocation = false;
  bool _changingTestingMode = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _bookingController = TextEditingController(text: _settings.testBookingId);
    _latitudeController = TextEditingController(
      text: _settings.simulatedLatitude?.toString() ?? '',
    );
    _longitudeController = TextEditingController(
      text: _settings.simulatedLongitude?.toString() ?? '',
    );

    if (_settings.testModeActive && _settings.testBookingId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadTestBooking());
    }
  }

  @override
  void dispose() {
    _bookingSaveTimer?.cancel();
    _bookingController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          backgroundColor: error
              ? const Color(0xFFDC2626)
              : const Color(0xFF166534),
          content: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      );
  }

  void _bookingChanged(String value) {
    _bookingSaveTimer?.cancel();
    _bookingSaveTimer = Timer(const Duration(milliseconds: 350), () async {
      final bookingId = value.trim();
      if (_settings.testModeActive && bookingId.isNotEmpty) {
        try {
          await _repository.setDeveloperTestBookingMode(
            bookingId: bookingId,
            enabled: true,
          );
        } catch (error) {
          _showMessage(_testingModeError(error), error: true);
          return;
        }
      }
      await _settings.setTestBookingId(bookingId);
      if (!mounted) return;
      setState(() {
        _assignments = const [];
        _activityId = '';
        _selectedAssignmentId = '';
        _loadError = null;
      });
    });
  }

  Future<void> _toggleTestingMode(bool enabled) async {
    if (_changingTestingMode) return;

    final bookingId = _bookingController.text.trim();
    if (bookingId.isEmpty) {
      _showMessage('Enter a Test Booking ID first.', error: true);
      return;
    }

    setState(() => _changingTestingMode = true);
    try {
      await _repository.setDeveloperTestBookingMode(
        bookingId: bookingId,
        enabled: enabled,
      );
      await _settings.setTestBookingId(bookingId);
      await _settings.setTestingModeEnabled(enabled);

      if (enabled) {
        await _loadTestBooking();
        _showMessage('Testing Mode enabled and registered in Supabase.');
      } else {
        _showMessage('Testing Mode disabled. Production validations restored.');
      }
    } catch (error) {
      _showMessage(_testingModeError(error), error: true);
    } finally {
      if (mounted) setState(() => _changingTestingMode = false);
    }
  }

  String _testingModeError(Object error) {
    final raw = error.toString();
    if (raw.contains('DEVELOPER_TEST_USER_NOT_AUTHORIZED')) {
      return 'This account is not authorized for server-side Testing Mode.';
    }
    if (raw.contains('NOT_TEST_BOOKING_PARTICIPANT')) {
      return 'Testing Mode can only be enabled by the booking tourist or an assigned driver.';
    }
    if (raw.contains('CANCELLED_BOOKING_CANNOT_ENABLE_TEST_MODE')) {
      return 'Cancelled bookings cannot be enabled for Testing Mode.';
    }
    if (raw.contains('PGRST202') || raw.contains('not found')) {
      return 'Apply the pending automatic Testing Mode migration, then retry.';
    }
    return 'Unable to update server-side Testing Mode: $error';
  }

  Future<void> _loadTestBooking() async {
    if (!kDebugMode || !_settings.testModeActive || _loadingBooking) return;

    final bookingId = _bookingController.text.trim();
    if (bookingId.isEmpty) {
      _showMessage('Enter a Test Booking ID first.', error: true);
      return;
    }

    _bookingSaveTimer?.cancel();
    try {
      await _repository.setDeveloperTestBookingMode(
        bookingId: bookingId,
        enabled: true,
      );
      await _settings.setTestBookingId(bookingId);
    } catch (error) {
      _showMessage(_testingModeError(error), error: true);
      return;
    }
    if (!mounted) return;

    setState(() {
      _loadingBooking = true;
      _loadError = null;
    });

    try {
      final results = await Future.wait<dynamic>([
        _repository.fetchPackageBookingDetails(bookingId),
        _repository.fetchActivityForBooking(bookingId),
        _repository.fetchBookingDrivers(bookingId),
        _repository.fetchBookingItinerary(bookingId),
        _repository.fetchPaymentRecordsFor(bookingId: bookingId),
        _repository.fetchPaymentAllocationsForBooking(bookingId),
      ]);

      final booking = results[0] as PackageBooking?;
      final activity = results[1] as PackageActivity?;
      final drivers = results[2] as List<BookingDriver>;
      if (booking == null || activity == null) {
        throw StateError('Booking or activity not found.');
      }

      final eligibleDrivers = drivers
          .where(
            (driver) =>
                driver.status == 'accepted' || driver.status == 'completed',
          )
          .toList(growable: false);
      if (eligibleDrivers.isEmpty) {
        throw StateError('This booking has no real driver assignments.');
      }

      final infos = await _repository.fetchDriverInfos(
        eligibleDrivers.map((driver) => driver.driverId),
      );
      final assignments = eligibleDrivers
          .map((driver) {
            final info = infos[driver.driverId];
            return _TestDriverAssignment(
              assignmentId: driver.id?.toString() ?? '',
              driverId: driver.driverId,
              driverName: info?.name.isNotEmpty == true ? info!.name : 'Driver',
              plateNumber: info?.details?.plateNumber ?? '',
              status: driver.status,
              journeyState: driver.journeyState.label,
            );
          })
          .toList(growable: false);

      final currentDriverId = _repository.currentUserId ?? '';
      var selected = assignments
          .where(
            (item) =>
                item.assignmentId == _settings.selectedTestDriverAssignmentId,
          )
          .firstOrNull;
      selected ??= assignments
          .where((item) => item.driverId == currentDriverId)
          .firstOrNull;
      selected ??= assignments.first;

      await _settings.selectTestDriverAssignment(
        assignmentId: selected.assignmentId,
        driverId: selected.driverId,
      );

      // The same production group conversation is used. Failure here remains
      // non-fatal because membership/RLS is correctly enforced by Supabase.
      try {
        await _repository.ensureBookingGroupConversation(bookingId);
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _assignments = assignments;
        _activityId = activity.id?.toString() ?? '';
        _selectedAssignmentId = selected!.assignmentId;
        _loadingBooking = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString().replaceFirst('Bad state: ', '');
        _assignments = const [];
        _activityId = '';
        _loadingBooking = false;
      });
    }
  }

  _TestDriverAssignment? get _selectedAssignment => _assignments
      .where((item) => item.assignmentId == _selectedAssignmentId)
      .firstOrNull;

  bool get _selectedDriverMatchesSession =>
      _selectedAssignment?.driverId == _repository.currentUserId;

  Future<void> _selectAssignment(String? assignmentId) async {
    if (assignmentId == null) return;
    final selected = _assignments
        .where((item) => item.assignmentId == assignmentId)
        .firstOrNull;
    if (selected == null) return;
    setState(() => _selectedAssignmentId = assignmentId);
    await _settings.selectTestDriverAssignment(
      assignmentId: selected.assignmentId,
      driverId: selected.driverId,
    );
  }

  Future<bool> _ensureSelectedDriverSession() async {
    if (_assignments.isEmpty || _activityId.isEmpty) {
      await _loadTestBooking();
    }
    final selected = _selectedAssignment;
    if (selected == null) {
      _showMessage('Select a real driver assignment first.', error: true);
      return false;
    }
    if (selected.driverId != _repository.currentUserId) {
      _showMessage(
        'Sign in as ${selected.driverName} on this device to use this assignment.',
        error: true,
      );
      return false;
    }
    return true;
  }

  Future<void> _openTestDriverTrip() async {
    if (!kDebugMode || !_settings.testModeActive || _opening) return;
    if (!await _ensureSelectedDriverSession() || !mounted) return;

    setState(() => _opening = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => DriverPackageTrackingScreen(activityId: _activityId),
        ),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _applySimulatedLocation() async {
    if (!kDebugMode || !_settings.testModeActive || _savingLocation) return;
    if (!await _ensureSelectedDriverSession()) return;

    final latitude = double.tryParse(_latitudeController.text.trim());
    final longitude = double.tryParse(_longitudeController.text.trim());
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      _showMessage('Enter valid latitude and longitude values.', error: true);
      return;
    }

    setState(() => _savingLocation = true);
    try {
      await _settings.setSimulatedDriverLocation(
        enabled: true,
        latitude: latitude,
        longitude: longitude,
      );
      await _repository.upsertDriverLiveLocation(
        activityId: _activityId,
        latitude: latitude,
        longitude: longitude,
      );
      _showMessage('Simulated location written to driver_live_locations.');
    } catch (error) {
      _showMessage('Unable to update test location: $error', error: true);
    } finally {
      if (mounted) setState(() => _savingLocation = false);
    }
  }

  Future<void> _disableSimulatedLocation() async {
    await _settings.setSimulatedDriverLocation(enabled: false);
    _showMessage('Location simulation disabled; device GPS will be used.');
  }

  Future<void> _resetTestTrip() async {
    if (!kDebugMode || !_settings.testModeActive || _resetting) return;
    if (!await _ensureSelectedDriverSession() || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset test trip?'),
        content: const Text(
          'Trip, itinerary, and per-driver journey progress will return to the initial assigned state. Payment records, allocations, assignments, and group chat are preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            child: const Text('Reset Test Trip'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _resetting = true);
    try {
      await _repository.resetDebugTestTrip(_bookingController.text.trim());
      await _settings.setSimulatedDriverLocation(enabled: false);
      await _loadTestBooking();
      _showMessage('Test trip progress reset. Payments and chat preserved.');
    } catch (error) {
      final raw = error.toString();
      final message = raw.contains('TEST_BOOKING_NOT_REGISTERED')
          ? 'Re-enable server-side Testing Mode for this booking first.'
          : raw.contains('CANCELLED_BOOKING_CANNOT_RESET')
          ? 'Cancelled bookings cannot be reset.'
          : 'Unable to reset this test trip: $error';
      _showMessage(message, error: true);
    } finally {
      if (mounted) setState(() => _resetting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        final active = _settings.testModeActive;
        final selected = _selectedAssignment;

        return DriverProfileCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Developer Tools',
                style: TextStyle(
                  color: Color(0xFF0F172A),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                'Debug builds only',
                style: TextStyle(
                  color: Color(0xFF64748B),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Testing Mode',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Switch.adaptive(
                    value: active,
                    onChanged: _changingTestingMode ? null : _toggleTestingMode,
                  ),
                ],
              ),
              if (active) ...[
                Container(
                  padding: const EdgeInsets.all(9),
                  color: const Color(0xFFFEF2F2),
                  child: const Text(
                    'TEST MODE ACTIVE',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                'Test Booking ID',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _bookingController,
                enabled: !active && !_changingTestingMode,
                autocorrect: false,
                enableSuggestions: false,
                onChanged: _bookingChanged,
                decoration: const InputDecoration(
                  hintText: 'Paste the shared test booking ID',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: active && !_loadingBooking ? _loadTestBooking : null,
                icon: _loadingBooking
                    ? const SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync_rounded),
                label: const Text('Load Booking & Assignments'),
              ),
              if (_loadError case final error?) ...[
                const SizedBox(height: 8),
                Text(
                  error,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_assignments.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Driver Assignment',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _selectedAssignmentId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: _assignments
                      .map(
                        (assignment) => DropdownMenuItem(
                          value: assignment.assignmentId,
                          child: Text(assignment.label),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _selectAssignment,
                ),
                if (selected != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Assignment: ${selected.assignmentId}\nDriver: ${selected.driverId}\nState: ${selected.journeyState}',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 9.5,
                      height: 1.4,
                    ),
                  ),
                  if (!_selectedDriverMatchesSession)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'This device is not signed in as ${selected.driverName}.',
                        style: const TextStyle(
                          color: Color(0xFFD97706),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: active && !_opening ? _openTestDriverTrip : null,
                  icon: _opening
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.navigation_rounded),
                  label: const Text('Open Test Driver Trip'),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Test Driver Location',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _latitudeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Latitude',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _longitudeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Longitude',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _savingLocation
                            ? null
                            : _applySimulatedLocation,
                        child: Text(
                          _savingLocation ? 'Applying...' : 'Apply Location',
                        ),
                      ),
                    ),
                    if (_settings.simulatedLocationEnabled) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _disableSimulatedLocation,
                        child: const Text('Use GPS'),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: active && !_resetting ? _resetTestTrip : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                  ),
                  icon: _resetting
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.restart_alt_rounded),
                  label: const Text('Reset Test Trip'),
                ),
                const SizedBox(height: 5),
                const Text(
                  'Testing Mode automatically registers this disposable booking in Supabase. Turning it off immediately restores production validations.',
                  style: TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 9,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _TestDriverAssignment {
  const _TestDriverAssignment({
    required this.assignmentId,
    required this.driverId,
    required this.driverName,
    required this.plateNumber,
    required this.status,
    required this.journeyState,
  });

  final String assignmentId;
  final String driverId;
  final String driverName;
  final String plateNumber;
  final String status;
  final String journeyState;

  String get label {
    final plate = plateNumber.isEmpty ? '' : ' • $plateNumber';
    return '$driverName$plate • $journeyState';
  }
}
