import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Provincial Admin bulk read stays owner-scoped and detects RLS no-ops',
    () {
      final service = File(
        'lib/screens/main_tenant/main_tenant_service.dart',
      ).readAsStringSync();
      final start = service.indexOf(
        'Future<Set<String>> markAllMainTenantNotificationsRead()',
      );
      final end = service.indexOf(
        'Future<List<CityTenant>> fetchCityTenants',
        start,
      );
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));

      final method = service.substring(start, end);
      expect(method, contains(".eq('user_id', profile.id)"));
      expect(method, contains(".eq('is_read', false)"));
      expect(method, contains("'is_read': true"));
      expect(method, contains("'read_at':"));
      expect(method, contains('if (unreadRows.isEmpty)'));
      expect(method, contains('updatedIds.containsAll(unreadIds)'));
    },
  );

  test('notification update RLS permits only the authenticated owner', () {
    final migration = File(
      'supabase/migrations/'
      '20260930030000_fix_main_tenant_notification_mark_all_read.sql',
    ).readAsStringSync();

    expect(
      migration,
      contains(
        'grant update (is_read, read_at) on public.notifications '
        'to authenticated',
      ),
    );
    expect(migration, contains('using (user_id = auth.uid())'));
    expect(migration, contains('with check (user_id = auth.uid())'));
    expect(migration, isNot(contains('using (true)')));
  });

  test('Provincial Admin UI applies successful bulk reads immediately', () {
    final ui = File(
      'lib/screens/main_tenant/widgets/main_tenant_header_tools.dart',
    ).readAsStringSync();

    expect(ui, contains('if (_markingAll) return;'));
    expect(ui, contains('onPressed: _markingAll ? null : _markAll'));
    expect(ui, contains('widget.onNotificationsRead(updatedIds)'));
    expect(ui, contains('item.copyWith(isRead: true)'));
    expect(ui, contains('_locallyReadNotificationIds.contains'));
    expect(ui, contains('Unable to mark notifications as read. Try again.'));
  });
}
