import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/places/google_places_errors.dart';
import 'package:touristrike/widgets/optional_places_builder.dart';

Widget home(Future<List<String>> Function() load) => MaterialApp(
  home: Scaffold(
    body: OptionalPlacesBuilder<List<String>>(
      key: const ValueKey('home-places'),
      load: load,
      builder: (context, data, loading, unavailable, retry) => Column(
        children: [
          const Text('Saved destination from Supabase'),
          const Text('Published tour package from Supabase'),
          if (loading || unavailable)
            OptionalPlacesNotice(loading: loading, onRetry: retry),
          for (final spot in data ?? const <String>[]) Text(spot),
        ],
      ),
    ),
  ),
);

void main() {
  for (final kind in [
    GooglePlacesFailureKind.unauthorized,
    GooglePlacesFailureKind.network,
    GooglePlacesFailureKind.notConfigured,
  ]) {
    testWidgets(
      'Home preserves core content when optional Places fails: $kind',
      (tester) async {
        final result = Completer<List<String>>();
        await tester.pumpWidget(home(() => result.future));
        expect(find.text('Saved destination from Supabase'), findsOneWidget);
        expect(
          find.text('Published tour package from Supabase'),
          findsOneWidget,
        );
        expect(find.text('Loading nearby suggestions…'), findsOneWidget);
        result.completeError(
          GooglePlacesException(kind: kind, message: 'Unavailable'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Nearby suggestions unavailable'), findsOneWidget);
        expect(find.text('Saved destination from Supabase'), findsOneWidget);
        expect(
          find.text('Published tour package from Supabase'),
          findsOneWidget,
        );
        expect(find.text('Unable to load home'), findsNothing);
      },
    );
  }

  testWidgets(
    'Try Again executes one load, blocks duplicates, and clears stale error on recovery',
    (tester) async {
      final recovery = Completer<List<String>>();
      var requests = 0;
      Future<List<String>> load() {
        requests++;
        if (requests == 1) {
          return Future.error(
            const GooglePlacesException(
              kind: GooglePlacesFailureKind.unauthorized,
              message: 'Rejected',
            ),
          );
        }
        return recovery.future;
      }

      await tester.pumpWidget(home(load));
      await tester.pumpAndSettle();
      expect(requests, 1);
      final retryButton = find.ancestor(
        of: find.text('Try Again'),
        matching: find.byWidgetPredicate((widget) => widget is TextButton),
      );
      final retry = tester.widget<TextButton>(retryButton).onPressed!;
      retry();
      retry();
      retry();
      await tester.pump();
      expect(requests, 2);
      expect(find.text('Loading nearby suggestions…'), findsOneWidget);
      expect(find.text('Nearby suggestions unavailable'), findsNothing);
      await tester.pumpWidget(home(load));
      expect(requests, 2);
      recovery.complete(['Real Google result']);
      await tester.pumpAndSettle();
      expect(find.text('Real Google result'), findsOneWidget);
      expect(find.text('Try Again'), findsNothing);
      expect(find.text('Nearby suggestions unavailable'), findsNothing);
      expect(find.text('Loading nearby suggestions…'), findsNothing);
      expect(find.text('Published tour package from Supabase'), findsOneWidget);
      expect(requests, 2);
    },
  );

  testWidgets('disposing Home safely ignores a late Places response', (
    tester,
  ) async {
    final result = Completer<List<String>>();
    await tester.pumpWidget(home(() => result.future));
    await tester.pumpWidget(const SizedBox());
    result.completeError(Exception('Offline'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'successful zero results do not show an unavailable error or fake suggestions',
    (tester) async {
      await tester.pumpWidget(home(() async => []));
      await tester.pumpAndSettle();
      expect(find.text('Nearby suggestions unavailable'), findsNothing);
      expect(find.text('Try Again'), findsNothing);
      expect(find.text('Saved destination from Supabase'), findsOneWidget);
    },
  );

  testWidgets('Places notice fits narrow Android screen at enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(280, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: OptionalPlacesNotice(loading: false, onRetry: () {}),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Try Again'), findsOneWidget);
  });
}
