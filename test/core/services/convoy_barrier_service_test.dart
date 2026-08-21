import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/core/models/convoy_state.dart';
import 'package:touristrike/core/services/convoy_barrier_service.dart';

ConvoyDriverSnapshot _driver(
  String id,
  ConvoyJourneyState state, {
  int stopIndex = 0,
  DateTime? stateUpdatedAt,
  DateTime? lastLocationAt,
}) => ConvoyDriverSnapshot(
  driverId: id,
  driverName: id,
  plateNumber: 'ABC-$id',
  journeyState: state,
  currentStopIndex: stopIndex,
  stateUpdatedAt: stateUpdatedAt ?? DateTime(2026, 8, 5, 12, 0, 0),
  lastLocationAt: lastLocationAt,
);

void main() {
  group('ConvoyJourneyState', () {
    test('dbValue/fromDb round-trip for every state', () {
      for (final s in ConvoyJourneyState.values) {
        expect(ConvoyJourneyState.fromDb(s.dbValue), s);
      }
    });

    test('fromDb falls back to assigned for unknown/null input', () {
      expect(ConvoyJourneyState.fromDb(null), ConvoyJourneyState.assigned);
      expect(
        ConvoyJourneyState.fromDb('waiting_driver'), // legacy package_activities value
        ConvoyJourneyState.assigned,
      );
    });

    test('isAtLeast follows pipeline order', () {
      expect(
        ConvoyJourneyState.boarded.isAtLeast(ConvoyJourneyState.atPickup),
        isTrue,
      );
      expect(
        ConvoyJourneyState.atPickup.isAtLeast(ConvoyJourneyState.boarded),
        isFalse,
      );
    });
  });

  group('ConvoyBarrierService.canDepartFromPickup', () {
    test('blocked while one driver has not boarded', () {
      final convoy = [
        _driver('A', ConvoyJourneyState.boarded),
        _driver('B', ConvoyJourneyState.atPickup),
      ];
      expect(ConvoyBarrierService.canDepartFromPickup(convoy), isFalse);
      expect(
        ConvoyBarrierService.blockingDepartFromPickup(convoy).map((d) => d.driverId),
        ['B'],
      );
    });

    test('unblocked once every driver has boarded or moved further', () {
      final convoy = [
        _driver('A', ConvoyJourneyState.boarded),
        _driver('B', ConvoyJourneyState.enRouteStop),
      ];
      expect(ConvoyBarrierService.canDepartFromPickup(convoy), isTrue);
      expect(ConvoyBarrierService.blockingDepartFromPickup(convoy), isEmpty);
    });
  });

  group('ConvoyBarrierService.canDepartFromStop (stop-index aware)', () {
    test('blocked when a driver is behind on an EARLIER stop', () {
      final convoy = [
        _driver('A', ConvoyJourneyState.stopDone, stopIndex: 1),
        _driver('B', ConvoyJourneyState.enRouteStop, stopIndex: 0),
      ];
      // Barrier for stop 1: B hasn't even reached stop 1 yet.
      expect(ConvoyBarrierService.canDepartFromStop(convoy, 1), isFalse);
    });

    test(
      'raw enum order alone would be WRONG here — regression guard for the '
      'stop-index bug: a driver stopDone on an EARLIER stop must not '
      'count as clearing a LATER stop',
      () {
        final convoy = [
          // Finished stop 0 already, now en route to stop 1 (order LOWER
          // than stopDone, but this driver has legitimately cleared stop 0).
          _driver('A', ConvoyJourneyState.enRouteStop, stopIndex: 1),
          _driver('B', ConvoyJourneyState.stopDone, stopIndex: 0),
        ];
        expect(ConvoyBarrierService.canDepartFromStop(convoy, 0), isTrue);
        expect(ConvoyBarrierService.canDepartFromStop(convoy, 1), isFalse);
      },
    );

    test('unblocked once every driver has cleared the stop', () {
      final convoy = [
        _driver('A', ConvoyJourneyState.stopDone, stopIndex: 2),
        _driver('B', ConvoyJourneyState.enRouteDropoff, stopIndex: 2),
      ];
      expect(ConvoyBarrierService.canDepartFromStop(convoy, 2), isTrue);
    });
  });

  group('ConvoyBarrierService.canCompleteTour', () {
    test('blocked until every driver is at least at drop-off', () {
      final convoy = [
        _driver('A', ConvoyJourneyState.atDropoff),
        _driver('B', ConvoyJourneyState.enRouteDropoff),
      ];
      expect(ConvoyBarrierService.canCompleteTour(convoy), isFalse);
      expect(
        ConvoyBarrierService.blockingCompleteTour(convoy).map((d) => d.driverId),
        ['B'],
      );
    });
  });

  group('ConvoyBarrierService.deriveOverallState', () {
    test('returns null for an empty convoy', () {
      expect(ConvoyBarrierService.deriveOverallState([]), isNull);
    });

    test('returns the slowest driver state, not the fastest', () {
      final convoy = [
        _driver('A', ConvoyJourneyState.atDropoff),
        _driver('B', ConvoyJourneyState.enRoutePickup),
        _driver('C', ConvoyJourneyState.stopDone),
      ];
      expect(
        ConvoyBarrierService.deriveOverallState(convoy),
        ConvoyJourneyState.enRoutePickup,
      );
    });

    test('trivially the single driver for a solo (N=1) booking', () {
      final convoy = [_driver('A', ConvoyJourneyState.atStop)];
      expect(
        ConvoyBarrierService.deriveOverallState(convoy),
        ConvoyJourneyState.atStop,
      );
    });
  });

  group(
    'ConvoyBarrierService solo booking (N=1) — barrier reduces to self-check',
    () {
      test(
        'canDepartFromPickup depends only on the lone driver reaching boarded',
        () {
          expect(
            ConvoyBarrierService.canDepartFromPickup([
              _driver('solo', ConvoyJourneyState.atPickup),
            ]),
            isFalse,
          );
          expect(
            ConvoyBarrierService.canDepartFromPickup([
              _driver('solo', ConvoyJourneyState.boarded),
            ]),
            isTrue,
          );
        },
      );

      test(
        'canDepartFromStop depends only on the lone driver clearing that stop',
        () {
          final atStop1 = _driver(
            'solo',
            ConvoyJourneyState.atStop,
            stopIndex: 1,
          );
          expect(ConvoyBarrierService.canDepartFromStop([atStop1], 1), isFalse);

          final doneStop1 = _driver(
            'solo',
            ConvoyJourneyState.stopDone,
            stopIndex: 1,
          );
          expect(ConvoyBarrierService.canDepartFromStop([doneStop1], 1), isTrue);
        },
      );

      test('canCompleteTour depends only on the lone driver reaching drop-off', () {
        expect(
          ConvoyBarrierService.canCompleteTour([
            _driver('solo', ConvoyJourneyState.enRouteDropoff),
          ]),
          isFalse,
        );
        expect(
          ConvoyBarrierService.canCompleteTour([
            _driver('solo', ConvoyJourneyState.atDropoff),
          ]),
          isTrue,
        );
      });

      test('a lone driver is never blocked by a nonexistent "other" driver', () {
        // i.e. once their own state clears the gate, nothing else can hold
        // them back — there's no second driver to disagree.
        final ready = _driver('solo', ConvoyJourneyState.boarded);
        expect(ConvoyBarrierService.blockingDepartFromPickup([ready]), isEmpty);
      });
    },
  );

  group('ConvoyBarrierService deadlock/offline detection', () {
    final now = DateTime(2026, 8, 5, 12, 30, 0);

    test('isStuck true at exactly the 10-minute threshold', () {
      final d = _driver(
        'A',
        ConvoyJourneyState.enRoutePickup,
        stateUpdatedAt: now.subtract(const Duration(minutes: 10)),
      );
      expect(ConvoyBarrierService.isStuck(d, now: now), isTrue);
      expect(ConvoyBarrierService.isCriticallyStuck(d, now: now), isFalse);
    });

    test('isCriticallyStuck true at the 20-minute threshold', () {
      final d = _driver(
        'A',
        ConvoyJourneyState.enRoutePickup,
        stateUpdatedAt: now.subtract(const Duration(minutes: 20)),
      );
      expect(ConvoyBarrierService.isCriticallyStuck(d, now: now), isTrue);
    });

    test('not stuck just under the threshold', () {
      final d = _driver(
        'A',
        ConvoyJourneyState.enRoutePickup,
        stateUpdatedAt: now.subtract(const Duration(minutes: 9, seconds: 59)),
      );
      expect(ConvoyBarrierService.isStuck(d, now: now), isFalse);
    });

    test('offline when no location has ever been recorded', () {
      final d = _driver('A', ConvoyJourneyState.enRoutePickup);
      expect(ConvoyBarrierService.isOffline(d, now: now), isTrue);
    });

    test('offline after 5 minutes of silence, online just before', () {
      final stale = _driver(
        'A',
        ConvoyJourneyState.enRoutePickup,
        lastLocationAt: now.subtract(const Duration(minutes: 5)),
      );
      final fresh = _driver(
        'B',
        ConvoyJourneyState.enRoutePickup,
        lastLocationAt: now.subtract(const Duration(minutes: 4, seconds: 59)),
      );
      expect(ConvoyBarrierService.isOffline(stale, now: now), isTrue);
      expect(ConvoyBarrierService.isOffline(fresh, now: now), isFalse);
    });
  });
}
