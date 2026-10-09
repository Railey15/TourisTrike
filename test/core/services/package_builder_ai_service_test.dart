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
              'orderedSpotIds': ['invented:99', 'db:1', 'google:2', 'db:3'],
              'selectedSpotIds': ['db:1', 'google:2', 'db:3'],
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

  test('rejects generation when fewer than three usable spots exist', () async {
    var invoked = false;
    final service = PackageBuilderAiService(
      invokeFunction: ({required functionName, required body}) async {
        invoked = true;
        return {
          'package': {
            'orderedSpotIds': ['missing'],
          },
        };
      },
    );

    await expectLater(
      () => service.generate(
        request: 'Create a cafe hopping package',
        municipality: 'Baliwag',
        spotCount: 3,
        preferences: '',
        candidates: candidates.take(2).toList(),
      ),
      throwsA(isA<PackageBuilderAiException>()),
    );
    expect(invoked, isFalse);
  });

  test('rejects an AI response with only two valid spots', () async {
    final service = PackageBuilderAiService(
      invokeFunction: ({required functionName, required body}) async {
        return {
          'package': {
            'orderedSpotIds': ['db:1', 'google:2', 'invented:99'],
            'selectedSpotIds': ['db:1', 'google:2'],
          },
        };
      },
    );

    await expectLater(
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
          contains('fewer than 3 usable spots'),
        ),
      ),
    );
  });

  test('rejects requested spot counts outside three through six', () async {
    final service = PackageBuilderAiService(
      invokeFunction: ({required functionName, required body}) async => {
        'package': <String, dynamic>{},
      },
    );

    for (final count in [2, 7]) {
      await expectLater(
        () => service.generate(
          request: 'Create a cafe hopping package',
          municipality: 'Baliwag',
          spotCount: count,
          preferences: '',
          candidates: candidates,
        ),
        throwsArgumentError,
      );
    }
  });

  test(
    'accepts and caps a six-spot AI package at the configured maximum',
    () async {
      final sixCandidates = [
        ...candidates,
        const PackageBuilderCandidate(
          key: 'db:5',
          title: 'River Park',
          category: 'Nature',
          address: 'Riverside',
          rating: 4.3,
        ),
        const PackageBuilderCandidate(
          key: 'db:6',
          title: 'Town Church',
          category: 'Church',
          address: 'Town Center',
          rating: 4.5,
        ),
      ];
      final keys = sixCandidates.map((item) => item.key).toList();
      final service = PackageBuilderAiService(
        invokeFunction: ({required functionName, required body}) async => {
          'package': {
            'orderedSpotIds': [...keys, 'invented:7'],
            'selectedSpotIds': keys,
          },
        },
      );

      final plan = await service.generate(
        request: 'Create a complete town tour',
        municipality: 'Baliwag',
        spotCount: 6,
        preferences: '',
        candidates: sixCandidates,
      );

      expect(plan.orderedCandidateKeys, hasLength(6));
      expect(plan.orderedCandidateKeys, isNot(contains('invented:7')));
    },
  );

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
