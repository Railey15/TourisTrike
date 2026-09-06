import 'dart:async';

import 'package:flutter/foundation.dart';

class SubTenantWorkspaceSearchController extends ChangeNotifier {
  SubTenantWorkspaceSearchController._();

  static final SubTenantWorkspaceSearchController instance =
      SubTenantWorkspaceSearchController._();

  final Map<int, String> _queries = <int, String>{};
  int _activeScope = -1;

  int get activeScope => _activeScope;

  String queryFor(int scope) => _queries[scope] ?? '';

  void setActiveScope(int scope) {
    if (_activeScope == scope) return;
    // The active scope only controls which scoped query may emit below. It is
    // routing metadata, not observable search state, so changing it while the
    // shell selects a page must not synchronously rebuild listeners.
    _activeScope = scope;
  }

  void setQuery(int scope, String value) {
    final normalized = value.trim();
    if (_queries[scope] == normalized) return;
    _queries[scope] = normalized;
    if (_activeScope == scope) notifyListeners();
  }

  void clear(int scope) => setQuery(scope, '');
}

class SubTenantSearchDebouncer {
  Timer? _timer;

  void run(
    VoidCallback action, {
    Duration delay = const Duration(milliseconds: 280),
  }) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }
}
