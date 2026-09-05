import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/screens/admin/admin_models.dart';

void main() {
  test(
    'tenant classification review metadata is parsed from assignment data',
    () {
      final tenant = CityTenant.fromProfile(const {
        'id': 'tenant-id',
        'role': 'subtenant',
        'city': 'Baliwag',
        'province': 'Bulacan',
        'office_name': 'Baliwag City Tourism Office',
        'local_government_type': 'city',
        'local_government_type_reviewed': true,
        'is_active': true,
      });

      expect(tenant.localGovernmentType, 'city');
      expect(tenant.localGovernmentTypeReviewed, isTrue);
    },
  );

  test('ambiguous tenant classification remains visible for review', () {
    final tenant = CityTenant.fromProfile(const {
      'id': 'tenant-id',
      'city': 'Sample LGU',
      'local_government_type': 'municipality',
      'local_government_type_reviewed': false,
    });

    expect(tenant.localGovernmentType, 'municipality');
    expect(tenant.localGovernmentTypeReviewed, isFalse);
  });

  test('admin notification parses unread state and navigation type', () {
    final notification = AdminNotification.fromMap(const {
      'id': 42,
      'title': 'Package requires review',
      'body': 'A package was submitted.',
      'type': 'package_review',
      'is_read': false,
      'created_at': '2026-09-05T01:00:00Z',
    });

    expect(notification.id, 42);
    expect(notification.type, 'package_review');
    expect(notification.isRead, isFalse);
    expect(notification.createdAt, isNotNull);
  });
}
