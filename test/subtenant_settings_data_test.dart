import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';

void main() {
  const profile = SubTenantProfile(
    id: 'subtenant-id',
    role: 'subtenant',
    fullName: 'Tourism Officer',
    firstName: '',
    lastName: '',
    email: 'office@example.com',
    mobile: '',
    address: '',
    city: 'Bustos',
    province: 'Bulacan',
    profileImageUrl: '',
    raw: <String, dynamic>{},
  );

  test(
    'generates municipal and city office names from assignment metadata',
    () {
      expect(
        defaultTourismOfficeName(
          assignedLocation: 'Bustos',
          localGovernmentType: 'municipality',
        ),
        'Bustos Municipal Tourism Office',
      );
      expect(
        defaultTourismOfficeName(
          assignedLocation: 'Baliwag',
          localGovernmentType: 'city',
        ),
        'Baliwag City Tourism Office',
      );
      expect(
        defaultTourismOfficeName(
          assignedLocation: 'City of Malolos',
          localGovernmentType: 'city',
        ),
        'Malolos City Tourism Office',
      );
    },
  );

  test(
    'loads the generated default when the office name is not customized',
    () {
      final data = SubTenantCityProfileData.fromMap(const {
        'city': 'Bustos',
        'province': 'Bulacan',
        'local_government_type': 'municipality',
        'office_name': '',
        'office_name_customized': false,
      }, profile);

      expect(data.tourismOfficeName, 'Bustos Municipal Tourism Office');
      expect(data.officeNameCustomized, isFalse);
    },
  );

  test('custom office name survives load and persistence mapping', () {
    final data = SubTenantCityProfileData.fromMap(const {
      'city': 'Bustos',
      'province': 'Bulacan',
      'local_government_type': 'municipality',
      'office_name': 'Bustos Culture and Tourism Office',
      'office_name_customized': true,
      'contact_person': 'Tourism Officer',
    }, profile);

    final saved = data.toPersistenceMap();

    expect(data.tourismOfficeName, 'Bustos Culture and Tourism Office');
    expect(saved['office_name'], 'Bustos Culture and Tourism Office');
    expect(saved['office_name_customized'], isTrue);
    expect(saved, isNot(contains('city')));
    expect(saved, isNot(contains('province')));
    expect(saved, isNot(contains('local_government_type')));
  });
}
