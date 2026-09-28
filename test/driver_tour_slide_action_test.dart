import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/convoy_state.dart';
import 'package:touristrike/core/models/driver_tour_action.dart';
import 'package:touristrike/widgets/driver_tour_slide_action.dart';

void main() {
  Future<void> show(
    WidgetTester tester, {
    String label = 'SLIDE TO CONFIRM PICKUP',
    String actionId = 'at_pickup:0',
    Future<void> Function()? onConfirmed,
    bool enabled = true,
    bool busy = false,
    double width = 390,
    double scale = 1,
    double bottom = 24,
  }) async {
    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: Size(width, 700),
            padding: EdgeInsets.only(bottom: bottom),
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox()),
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: DriverTourSlideAction(
                      actionId: actionId,
                      label: label,
                      enabled: enabled,
                      busy: busy,
                      onConfirmed: onConfirmed ?? () async {},
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> slide(WidgetTester tester, {double fraction = 1}) async {
    final track = tester.getRect(find.byType(DriverTourSlideAction));
    final handle = find.byKey(const ValueKey('driver-tour-slide-handle'));
    final gesture = await tester.startGesture(tester.getCenter(handle));
    await gesture.moveBy(const Offset(20, 0));
    await tester.pump();
    await gesture.moveBy(Offset((track.width - 68) * fraction, 0));
    await tester.pump();
    await gesture.up();
    await tester.pump();
  }

  final stages = [
    (ConvoyJourneyState.atPickup, 0, DriverTourSlideStage.confirmPickup),
    (ConvoyJourneyState.boarded, 0, DriverTourSlideStage.startTour),
    (ConvoyJourneyState.atStop, 0, DriverTourSlideStage.nextStop),
    (ConvoyJourneyState.atStop, 1, DriverTourSlideStage.leaveFinalStop),
    (ConvoyJourneyState.stopDone, 1, DriverTourSlideStage.dropOff),
    (ConvoyJourneyState.atDropoff, 1, DriverTourSlideStage.completeTour),
  ];
  for (final (state, index, expected) in stages) {
    testWidgets('${expected.label} uses the persisted stage and submits once', (
      tester,
    ) async {
      final stage = DriverTourSlideStage.forJourney(
        state,
        stopIndex: index,
        totalStops: 2,
      );
      expect(stage, expected);
      var calls = 0;
      await show(
        tester,
        label: stage!.label,
        actionId: '${state.dbValue}:$index',
        onConfirmed: () async {
          calls++;
        },
      );
      expect(find.text(expected.label), findsOneWidget);
      expect(tester.getSize(find.byType(DriverTourSlideAction)).width, 358);
      await slide(tester);
      expect(calls, 1);
      expect(find.text('ACTION CONFIRMED'), findsOneWidget);
      await slide(tester);
      expect(calls, 1);
    });
  }

  testWidgets('tapping the track or dragging from the label does not confirm', (
    tester,
  ) async {
    var calls = 0;
    await show(
      tester,
      onConfirmed: () async {
        calls++;
      },
    );
    await tester.tap(find.text('SLIDE TO CONFIRM PICKUP'));
    await tester.drag(
      find.text('SLIDE TO CONFIRM PICKUP'),
      const Offset(300, 0),
    );
    await tester.pumpAndSettle();
    expect(calls, 0);
  });

  testWidgets(
    'incomplete and cancelled slides animate back without submitting',
    (tester) async {
      var calls = 0;
      await show(
        tester,
        onConfirmed: () async {
          calls++;
        },
      );
      final handle = find.byKey(const ValueKey('driver-tour-slide-handle'));
      final origin = tester.getTopLeft(handle);
      await slide(tester, fraction: .5);
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(tester.getTopLeft(handle), origin);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      await gesture.moveBy(const Offset(180, 0));
      await tester.pump();
      await gesture.cancel();
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(tester.getTopLeft(handle), origin);
    },
  );

  testWidgets('processing and confirmed state block repeated swipes', (
    tester,
  ) async {
    final pending = Completer<void>();
    var calls = 0;
    await show(
      tester,
      onConfirmed: () {
        calls++;
        return pending.future;
      },
    );
    await slide(tester);
    expect(calls, 1);
    expect(find.text('UPDATING TOUR…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await slide(tester);
    expect(calls, 1);
    pending.complete();
    await tester.pumpAndSettle();
    await slide(tester);
    expect(calls, 1);
  });

  testWidgets(
    'server failure resets the control; persisted next action resets success',
    (tester) async {
      var calls = 0;
      Future<void> submit() async {
        calls++;
        if (calls == 1) throw StateError('server denied');
      }

      await show(tester, onConfirmed: submit);
      await slide(tester);
      await tester.pumpAndSettle();
      expect(find.text('SLIDE TO CONFIRM PICKUP'), findsOneWidget);
      await slide(tester);
      expect(calls, 2);
      await show(
        tester,
        actionId: 'boarded:0',
        label: 'SLIDE TO START TOUR',
        onConfirmed: submit,
      );
      await slide(tester);
      expect(calls, 3);
    },
  );

  for (final busy in [false, true]) {
    testWidgets(
      '${busy ? 'busy' : 'disabled'} control is locked with accessible feedback',
      (tester) async {
        var calls = 0;
        await show(
          tester,
          enabled: busy,
          busy: busy,
          onConfirmed: () async {
            calls++;
          },
        );
        await slide(tester);
        expect(calls, 0);
        expect(
          find.byIcon(Icons.lock_outline_rounded),
          busy ? findsNothing : findsOneWidget,
        );
        if (busy) {
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
        }
        final semantics = tester.getSemantics(
          find.byType(DriverTourSlideAction),
        );
        expect(semantics.label, 'SLIDE TO CONFIRM PICKUP');
      },
    );
  }

  for (final width in [280.0, 320.0, 430.0]) {
    testWidgets('$width px screen preserves width, SafeArea, and large text', (
      tester,
    ) async {
      await show(
        tester,
        width: width,
        scale: 2,
        bottom: 34,
        label: 'SLIDE TO LEAVE FINAL STOP',
      );
      final rect = tester.getRect(find.byType(DriverTourSlideAction));
      expect(rect.width, width - 32);
      expect(rect.left, 16);
      expect(rect.bottom, lessThanOrEqualTo(700 - 34));
      expect(rect.height, greaterThanOrEqualTo(72));
      expect(tester.takeException(), isNull);
    });
  }

  test('navigation and automatic arrival stages expose no slide', () {
    for (final state in [
      ConvoyJourneyState.assigned,
      ConvoyJourneyState.enRoutePickup,
      ConvoyJourneyState.enRouteStop,
      ConvoyJourneyState.enRouteDropoff,
      ConvoyJourneyState.completed,
    ]) {
      expect(
        DriverTourSlideStage.forJourney(state, stopIndex: 0, totalStops: 2),
        isNull,
      );
    }
  });
}
