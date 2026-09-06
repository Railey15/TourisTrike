import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/screens/subtenant/subtenant_workspace_search.dart';

void main() {
  test(
    'changing active workspace scope does not notify during shell build',
    () {
      final search = SubTenantWorkspaceSearchController.instance;
      var notifications = 0;
      void listener() => notifications++;
      search.addListener(listener);
      addTearDown(() => search.removeListener(listener));

      search.setActiveScope(101);
      expect(notifications, 0);

      search.setQuery(101, 'heritage');
      expect(notifications, 1);
    },
  );
}
