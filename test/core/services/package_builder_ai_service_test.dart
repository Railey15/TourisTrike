import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/services/package_builder_ai_service.dart';

void main() {
  const candidates = [
    PackageBuilderCandidate(
      key: 'db:1',
      title: 'Town Cafe',
      category: 'Food',
      address: 'Town Center',
      rating: 4.8,
    ),
    PackageBuilderCandidate(
      key: 'google:2',
      title: 'Garden Coffee',
      category: 'Food',
      address: 'Poblacion',
      rating: 4.6,
    ),
    PackageBuilderCandidate(
      key: 'db:3',
      title: 'Kape House',
      category: 'Food',
      address: 'Market Road',
      rating: 4.4,
    ),
    PackageBuilderCandidate(
      key: 'db:4',
      title: 'Heritage Museum',
      category: 'Museum',
      address: 'Old Town',
      rating: 4.9,
    ),
  ];

  test(
    'invokes generate-tour-package and validates returned candidate IDs',
    () async {
      String? invokedFunction;
      Map<String, dynamic>? invokedBody;
      final service = PackageBuilderAiService(
        invokeFunction: ({required functionName, required body}) async {
          invokedFunction = functionName;
          invokedBody = body;
          return {
            'package': {
              'title': 'Baliwag Cafe Hopping',
              'subtitle': 'Coffee around town',
              'description': 'A relaxed cafe tour.',
              'category': 'Food',
              'orderedSpotIds': ['invented:99', 'db:1'],
              'selectedSpotIds': ['db:1'],
              'suggestedStayMinutes': {'invented:99': 999, 'db:1': 45},
            },
          };
        },
      );

      final plan = await service.generate(
        request: 'Create a cafe hopping package',
        municipality: 'Baliwag',
        spotCount: 3,
        preferences: 'near town center',
        candidates: candidates,
      );

      expect(plan.orderedCandidateKeys, hasLength(3));
      expect(plan.orderedCandidateKeys, isNot(contains('invented:99')));
      expect(
        plan.orderedCandidateKeys.toSet(),
        everyElement(isIn(candidates.map((item) => item.key))),
      );
      expect(plan.suggestedStayMinutes['db:1'], 45);
      expect(invokedFunction, 'generate-tour-package');
      expect(invokedBody?['municipality'], 'Baliwag');
      expect(invokedBody?['spotCount'], 3);
      expect(
        (invokedBody?['candidates'] as List).first,
        containsPair('name', 'Town Cafe'),
      );
    },
  );

  test('never fabricates spots when fewer candidates exist', () async {
    final service = PackageBuilderAiService(
      invokeFunction: ({required functionName, required body}) async {
        return {
          'package': {
            'orderedSpotIds': ['missing'],
          },
        };
      },
    );

    final plan = await service.generate(
      request: 'Create a cafe hopping package',
      municipality: 'Baliwag',
      spotCount: 3,
      preferences: '',
      candidates: candidates.take(2).toList(),
    );

    expect(plan.orderedCandidateKeys, hasLength(2));
    expect(plan.orderedCandidateKeys.toSet(), {'db:1', 'google:2'});
  });

  test('surfaces an unavailable warning only from a function error', () async {
    final service = PackageBuilderAiService(
      invokeFunction: ({required functionName, required body}) async {
        return {'error': 'AI package generation is not configured.'};
      },
    );

    expect(
      () => service.generate(
        request: 'Create a cafe hopping package',
        municipality: 'Baliwag',
        spotCount: 3,
        preferences: '',
        candidates: candidates,
      ),
      throwsA(
        isA<PackageBuilderAiException>().having(
          (error) => error.message,
          'message',
          'AI package generation is not configured.',
        ),
      ),
    );
  });
}
