import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:touristrike/core/services/developer_settings.dart';
import 'package:touristrike/core/supabase/touristrike_repository.dart';
import 'package:touristrike/screens/tourist/tourist_activity_tracking_screen.dart';

class DeveloperToolsSection extends StatefulWidget {
  const DeveloperToolsSection({super.key});

  @override
  State<DeveloperToolsSection> createState() => _DeveloperToolsSectionState();
}

class _DeveloperToolsSectionState extends State<DeveloperToolsSection> {
  final DeveloperSettings _settings = DeveloperSettings.instance;
  final TourisTrikeRepository _repository = TourisTrikeRepository();
  late final TextEditingController _bookingIdController;

  Timer? _saveTimer;
  bool _opening = false;
  bool _changingTestingMode = false;

  @override
  void initState() {
    super.initState();
    _bookingIdController = TextEditingController(text: _settings.testBookingId);
    if (_settings.testModeActive && _settings.testBookingId.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _registerPersistedTestMode(),
      );
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _bookingIdController.dispose();
    super.dispose();
  }

  void _scheduleBookingIdSave(String value) {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () async {
      final bookingId = value.trim();
      if (_settings.testModeActive && bookingId.isNotEmpty) {
        try {
          await _repository.setDeveloperTestBookingMode(
            bookingId: bookingId,
            enabled: true,
          );
        } catch (error) {
          _showError(_testingModeError(error));
          return;
        }
      }
      await _settings.setTestBookingId(bookingId);
    });
  }

  Future<void> _registerPersistedTestMode() async {
    final bookingId = _settings.testBookingId.trim();
    if (!kDebugMode || bookingId.isEmpty) return;
    try {
      await _repository.setDeveloperTestBookingMode(
        bookingId: bookingId,
        enabled: true,
      );
    } catch (error) {
      await _settings.setTestingModeEnabled(false);
      _showError(_testingModeError(error));
    }
  }

  Future<void> _toggleTestingMode(bool enabled) async {
    if (_changingTestingMode) return;

    final bookingId = _bookingIdController.text.trim();
    if (bookingId.isEmpty) {
      _showError('Enter a Test Booking ID first.');
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
      _showMessage(
        enabled
            ? 'Testing Mode enabled and registered in Supabase.'
            : 'Testing Mode disabled. Production validations restored.',
      );
    } catch (error) {
      _showError(_testingModeError(error));
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          content: Text(
            message,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      );
  }

  void _showError(String message) {
    _showMessage(message, error: true);
  }

  Future<void> _openTestOngoingTrip() async {
    // This is the second, non-UI release guard. The centralized setting also
    // applies its own kDebugMode check.
    if (!kDebugMode || !_settings.testModeActive || _opening) return;

    final bookingId = _bookingIdController.text.trim();
    if (bookingId.isEmpty) {
      _showError('Enter a Test Booking ID first.');
      return;
    }

    _saveTimer?.cancel();
    try {
      await _repository.setDeveloperTestBookingMode(
        bookingId: bookingId,
        enabled: true,
      );
      await _settings.setTestBookingId(bookingId);
    } catch (error) {
      _showError(_testingModeError(error));
      return;
    }

    if (!mounted) return;
    setState(() => _opening = true);

    try {
      // Confirm that Supabase permits access and preload the same real records
      // consumed by Tour Tracking. The destination screen still owns and
      // subscribes to the production state.
      final results = await Future.wait<dynamic>([
        _repository.fetchPackageBookingDetails(bookingId),
        _repository.fetchActivityForBooking(bookingId),
        _repository.fetchBookingItinerary(bookingId),
        _repository.fetchBookingDrivers(bookingId),
        _repository.fetchPaymentRecordsFor(bookingId: bookingId),
        _repository.fetchPaymentAllocationsForBooking(bookingId),
      ]);
      final booking = results[0];
      if (booking == null) {
        _showError('No accessible booking was found for that ID.');
        return;
      }

      try {
        await _repository.ensureBookingGroupConversation(bookingId);
      } catch (_) {
        // Chat membership remains enforced by the production group-chat RPC.
      }

      if (!mounted || !kDebugMode || !_settings.testModeActive) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ActivityTrackingScreen(bookingId: bookingId),
        ),
      );
    } catch (error) {
      debugPrint('Open Test Ongoing Trip failed: $error');
      _showError(
        'Unable to load that booking. Check the ID and your Supabase access.',
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _settings,
      builder: (context, _) {
        final active = _settings.testModeActive;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: active ? const Color(0xFFFCA5A5) : const Color(0xFFE5ECF5),
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0F172A).withValues(alpha: 0.055),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Developer Tools',
                style: TextStyle(
                  color: Color(0xFF111827),
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Available only in debug builds',
                style: TextStyle(
                  color: Color(0xFF8391A4),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Testing Mode',
                          style: TextStyle(
                            color: Color(0xFF111827),
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Open an existing booking for development testing.',
                          style: TextStyle(
                            color: Color(0xFF667085),
                            fontSize: 11.5,
                            fontWeight: FontWeight.w500,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Switch.adaptive(
                    value: active,
                    onChanged: _changingTestingMode ? null : _toggleTestingMode,
                  ),
                ],
              ),
              if (active) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: Color(0xFFB91C1C),
                      ),
                      SizedBox(width: 8),
                      Text(
                        'TEST MODE ACTIVE',
                        style: TextStyle(
                          color: Color(0xFFB91C1C),
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                'Test Booking ID',
                style: TextStyle(
                  color: Color(0xFF344054),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 7),
              TextField(
                controller: _bookingIdController,
                enabled: !active && !_changingTestingMode,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                onChanged: _scheduleBookingIdSave,
                onSubmitted: _settings.setTestBookingId,
                decoration: InputDecoration(
                  hintText: 'Paste an existing booking ID',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 13,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(color: Color(0xFFDCE4EE)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(13),
                    borderSide: const BorderSide(color: Color(0xFFDCE4EE)),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: !active || _opening ? null : _openTestOngoingTrip,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(46),
                  backgroundColor: const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: _opening
                    ? const SizedBox.square(
                        dimension: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.route_rounded, size: 19),
                label: Text(
                  _opening ? 'Loading Test Trip...' : 'Open Test Ongoing Trip',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
