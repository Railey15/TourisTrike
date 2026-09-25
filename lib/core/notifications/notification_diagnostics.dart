import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Diagnostic labels only. Never accepts/logs tokens, payload bodies or credentials.
class NotificationDiagnostics extends ChangeNotifier {
  static final instance = NotificationDiagnostics();
  String firebase = 'Not initialized';
  String permission = 'Not checked';
  String token = 'Not obtained';
  String registration = 'Not registered';
  String realtime = 'Not connected';
  String presentation = 'Waiting for an event';

  void record(String message) {
    if (kDebugMode) debugPrint('[NOTIFICATION] $message');
    notifyListeners();
  }

  void failure(String stage, Object error) {
    final code = switch (error) {
      FirebaseException e => e.code,
      PostgrestException e => e.code ?? 'unknown',
      _ => error.runtimeType.toString(),
    };
    // Error messages can contain request data. Log only allowlisted stage + code.
    if (kDebugMode) debugPrint('[NOTIFICATION][ERROR] $stage ($code)');
    notifyListeners();
  }
}
