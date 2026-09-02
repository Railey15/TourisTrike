import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized, local-only settings for development workflows.
///
/// Every public value and mutation is guarded by [kDebugMode]. This keeps the
/// testing bypass disabled even if a caller accidentally reaches this service
/// in a release build.
class DeveloperSettings extends ChangeNotifier {
  DeveloperSettings();

  static final DeveloperSettings instance = DeveloperSettings();

  static const String _testingModeKey =
      'developer_settings.testing_mode_enabled';
  static const String _testBookingIdKey = 'developer_settings.test_booking_id';
  static const String _selectedDriverAssignmentIdKey =
      'developer_settings.selected_driver_assignment_id';
  static const String _selectedDriverIdKey =
      'developer_settings.selected_driver_id';
  static const String _simulatedLocationEnabledKey =
      'developer_settings.simulated_location_enabled';
  static const String _simulatedLatitudeKey =
      'developer_settings.simulated_latitude';
  static const String _simulatedLongitudeKey =
      'developer_settings.simulated_longitude';

  SharedPreferences? _preferences;
  bool _initialized = false;
  bool _testingModeEnabled = false;
  String _testBookingId = '';
  String _selectedTestDriverAssignmentId = '';
  String _selectedTestDriverId = '';
  bool _simulatedLocationEnabled = false;
  double? _simulatedLatitude;
  double? _simulatedLongitude;

  bool get isInitialized => _initialized;

  /// Local developer-tools preference only. Transaction code must confirm the
  /// booking's authoritative server registration before bypassing validation.
  bool get testModeActive => kDebugMode && _testingModeEnabled;

  bool get testingModeEnabled => kDebugMode && _testingModeEnabled;

  String get testBookingId => kDebugMode ? _testBookingId : '';

  String get selectedTestDriverAssignmentId =>
      kDebugMode ? _selectedTestDriverAssignmentId : '';

  String get selectedTestDriverId => kDebugMode ? _selectedTestDriverId : '';

  bool get simulatedLocationEnabled =>
      kDebugMode && testModeActive && _simulatedLocationEnabled;

  double? get simulatedLatitude => kDebugMode ? _simulatedLatitude : null;

  double? get simulatedLongitude => kDebugMode ? _simulatedLongitude : null;

  bool isConfiguredTestBooking(String bookingId) =>
      testModeActive &&
      _testBookingId.isNotEmpty &&
      _testBookingId == bookingId.trim();

  bool canSimulateLocationFor({
    required String bookingId,
    required String driverId,
  }) =>
      isConfiguredTestBooking(bookingId) &&
      simulatedLocationEnabled &&
      driverId.isNotEmpty &&
      driverId == _selectedTestDriverId &&
      _simulatedLatitude != null &&
      _simulatedLongitude != null;

  Future<void> initialize() async {
    if (_initialized) return;

    if (!kDebugMode) {
      _testingModeEnabled = false;
      _testBookingId = '';
      _initialized = true;
      return;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      _preferences = preferences;
      _testingModeEnabled = preferences.getBool(_testingModeKey) ?? false;
      _testBookingId = preferences.getString(_testBookingIdKey)?.trim() ?? '';
      _selectedTestDriverAssignmentId =
          preferences.getString(_selectedDriverAssignmentIdKey)?.trim() ?? '';
      _selectedTestDriverId =
          preferences.getString(_selectedDriverIdKey)?.trim() ?? '';
      _simulatedLocationEnabled =
          preferences.getBool(_simulatedLocationEnabledKey) ?? false;
      _simulatedLatitude = preferences.getDouble(_simulatedLatitudeKey);
      _simulatedLongitude = preferences.getDouble(_simulatedLongitudeKey);
    } catch (error) {
      debugPrint('Unable to load developer settings: $error');
      _testingModeEnabled = false;
      _testBookingId = '';
      _selectedTestDriverAssignmentId = '';
      _selectedTestDriverId = '';
      _simulatedLocationEnabled = false;
      _simulatedLatitude = null;
      _simulatedLongitude = null;
    }

    _initialized = true;
    notifyListeners();
  }

  Future<void> setTestingModeEnabled(bool enabled) async {
    if (!kDebugMode) {
      _testingModeEnabled = false;
      return;
    }

    if (!_initialized) await initialize();
    if (_testingModeEnabled == enabled) return;

    _testingModeEnabled = enabled;
    notifyListeners();

    try {
      await _preferences?.setBool(_testingModeKey, enabled);
    } catch (error) {
      debugPrint('Unable to save Testing Mode: $error');
    }
  }

  Future<void> setTestBookingId(String bookingId) async {
    if (!kDebugMode) {
      _testBookingId = '';
      return;
    }

    if (!_initialized) await initialize();

    final normalized = bookingId.trim();
    if (_testBookingId == normalized) return;

    _testBookingId = normalized;
    _selectedTestDriverAssignmentId = '';
    _selectedTestDriverId = '';
    _simulatedLocationEnabled = false;
    notifyListeners();

    try {
      final preferences = _preferences;
      if (preferences == null) return;
      if (normalized.isEmpty) {
        await preferences.remove(_testBookingIdKey);
      } else {
        await preferences.setString(_testBookingIdKey, normalized);
      }
      await preferences.remove(_selectedDriverAssignmentIdKey);
      await preferences.remove(_selectedDriverIdKey);
      await preferences.setBool(_simulatedLocationEnabledKey, false);
    } catch (error) {
      debugPrint('Unable to save the test booking ID: $error');
    }
  }

  Future<void> selectTestDriverAssignment({
    required String assignmentId,
    required String driverId,
  }) async {
    if (!kDebugMode) return;
    if (!_initialized) await initialize();

    _selectedTestDriverAssignmentId = assignmentId.trim();
    _selectedTestDriverId = driverId.trim();
    notifyListeners();

    try {
      await _preferences?.setString(
        _selectedDriverAssignmentIdKey,
        _selectedTestDriverAssignmentId,
      );
      await _preferences?.setString(
        _selectedDriverIdKey,
        _selectedTestDriverId,
      );
    } catch (error) {
      debugPrint('Unable to save the selected test driver: $error');
    }
  }

  Future<void> setSimulatedDriverLocation({
    required bool enabled,
    double? latitude,
    double? longitude,
  }) async {
    if (!kDebugMode) return;
    if (!_initialized) await initialize();

    final coordinatesValid =
        latitude != null &&
        longitude != null &&
        latitude >= -90 &&
        latitude <= 90 &&
        longitude >= -180 &&
        longitude <= 180;

    _simulatedLocationEnabled = enabled && coordinatesValid;
    if (coordinatesValid) {
      _simulatedLatitude = latitude;
      _simulatedLongitude = longitude;
    }
    notifyListeners();

    try {
      await _preferences?.setBool(
        _simulatedLocationEnabledKey,
        _simulatedLocationEnabled,
      );
      if (coordinatesValid) {
        await _preferences?.setDouble(_simulatedLatitudeKey, latitude);
        await _preferences?.setDouble(_simulatedLongitudeKey, longitude);
      }
    } catch (error) {
      debugPrint('Unable to save the simulated driver location: $error');
    }
  }
}
