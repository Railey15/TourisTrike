# Testing Mode and convoy marker fixes

Implemented in the workspace. The linked database was inspected read-only; the new migration has **not** been applied remotely.

1. **Exact schedule root cause:** Read-only `pg_get_functiondef` inspection confirmed that the deployed `debug_advance_driver_journey_state` authorized the assignment and immediately called `advance_driver_journey_state`, without setting `touristrike.debug_progression_bypass`. The normal transition requires both an enabled test booking and that transaction-local flag. Consequently, its schedule guard remained active even though the client displayed Testing Mode. This was a deployed wrapper/transition mismatch, not a snackbar-only issue.

2. **Message source:** `_advanceConvoyStateCore` in `lib/screens/driver/driver_package_tracking_screen.dart` maps the server exception `BOOKING_START_TOO_EARLY` to “This tour cannot start before its scheduled date and time.” The exception originates in `public.advance_driver_journey_state` when starting an assigned future booking without an authorized bypass.

3. **Schedule/payment bypass:** `20260906010000_test_mode_live_tracking_consistency.sql` installs the matching canonical transition and debug wrapper together. The wrapper verifies the real test-booking assignment, sets the transaction-local bypass, calls the same real transition, then clears the flag. Normal state persistence, logs, notifications, payments, and finalization remain in the existing architecture. No payment record is fabricated by starting a test booking. Existing test stay-time/manual progression behavior is preserved.

4. **GPS stays enabled:** Removed the Testing Mode early return from `_recoverGpsFix`. Real Geolocator streaming and recovery keep publishing the authenticated driver's live location. Recovery also publishes while assigned or waiting at a stop, so a future test booking can have visible vehicles before navigation starts. Enabling Testing Mode alone never sets coordinates or distance to zero.

5. **Automatic arrival stays enabled:** Removed the Testing Mode early return from `_detectAutomaticArrival`. The same stable, accurate GPS fixes and 150 m radius are required in both modes. `automaticArrival: true` explicitly selects the normal transition RPC instead of the debug wrapper. The SQL proximity guard bypass now requires an authorized, explicit debug progression call; merely enabling the booking's test flag no longer bypasses GPS verification for automatic arrival. Automatic departures still wait for convoy readiness, while schedule/payment/stay constraints remain bypassable. The existing separately selected coordinate-simulation tool feeds the same detector and upload path; it is never enabled by the Testing Mode toggle alone. OS/emulator GPS simulation also continues through Geolocator normally.

6. **Exact marker root cause:** The driver screen had separate “current driver” and “other convoy drivers” construction. Its own marker used the tricycle asset and device/legacy activity coordinates; other drivers were rendered as violet default pins. Tourist markers came from the full roster and a different position cache. `_driverLatLng` could also borrow the legacy single-driver activity position for another driver. This explains the viewer-dependent tricycle appearance. Initial/reconnect caches used `putIfAbsent`, which could retain old positions after a missed event.

7. **Query/ID/Realtime assessment:** Driver marker IDs were already unique; duplicate `MarkerId`s and driver/user ID conversion were not the identified defect. Roster membership already came from `booking_drivers` by booking, retaining missing optional profile/GPS data. The rendering and own-driver fallback were inconsistent. Location fetching is now one bulk query for all roster driver IDs, instead of separate requests. Realtime updates use one shared timestamp-aware merge, and reconnect resync updates cached positions. The existing location RLS already authorizes the owner and drivers of the active booking; it was not widened.

8. **All drivers loaded:** `fetchConvoyRoster` selects all accepted/completed participating assignments for the booking, joins optional profile information, and loads `driver_live_locations` by the complete driver-ID collection. Missing GPS leaves the driver in the cards/roster; only the map marker waits for coordinates. Completed assignments retain the existing convoy-history behavior.

9. **Unique markers:** Both screens call `buildBookingDriverMarkers` in `lib/core/services/booking_driver_markers.dart`. It emits one marker per driver, keyed `driver_<driverId>`, using the same tricycle asset supplied by each screen. It never renders a driver avatar or a special violet convoy pin. Invalid coordinates are excluded consistently. Both screens use the same temporary loading fallback until the existing asset loads.

10. **Driver POV:** The caller supplies `viewerId`. A matching driver's info-window label includes `(YOU)`; identity does not alter roster membership, coordinates, or base icon. Own-device location is published to the same driver row. Navigation no longer borrows another driver's legacy activity coordinates.

11. **Tourist POV:** Tourist tracking passes the same full roster and normalized position collection to the same marker builder. Selected-driver behavior changes selection/camera emphasis only. Two roster drivers with valid coordinates produce two tricycle marker objects for Tourist, Driver A, and Driver B. Physically identical GPS coordinates naturally overlap on the map; no fake coordinate offsets are introduced.

12. **Realtime:** `mergeBookingDriverLocation` updates only the matching assignment and ignores invalid/stale fixes and unrelated drivers. Each animation updates that driver's cached position without replacing other drivers. A late first fix adds the missing marker without a restart. Subscription reconnect triggers a fresh roster/location read. Existing route rendering, ETA, and camera controls remain connected.

13. **Files changed:**

    - `lib/core/services/booking_driver_markers.dart` — shared rendering, coordinate validation, and location merge.
    - `lib/core/supabase/touristrike_repository.dart` — bulk roster locations and explicit normal RPC for automatic arrival.
    - `lib/screens/driver/driver_package_tracking_screen.dart` — GPS/test separation, shared markers, recovery and reconnect.
    - `lib/screens/tourist/tourist_activity_tracking_screen.dart` — shared markers and location merge/reconnect.
    - `supabase/migrations/20260906010000_test_mode_live_tracking_consistency.sql` — matching debug wrapper/transition and proximity guard.
    - `supabase/tests/event_driven_trip_regression.mjs` — reproduces the deployed broken wrapper and verifies its replacement.
    - `test/test_mode_convoy_markers_test.dart` — viewer membership/icons, late first fix, independent movement, stale events, and automatic/manual RPC selection.
    - `test/booking_schedule_improvements_test.dart`, `test/high_priority_payment_gate_and_convoy_map_test.dart` — existing wiring checks now point to the shared marker builder.
    - This report.

14. **SQL/RLS deployment:** No new table, column, status, or RLS policy is needed. The new migration replaces the three functions and preserves debug authorization. Apply it after `20260906000000_event_driven_trip_feedback.sql` and its existing prerequisites. The linked project's migration ledger is incomplete relative to its installed functions, so replaying all old migrations blindly can overwrite newer definitions. For the currently inspected database, execute the **entire new file** in Supabase SQL Editor, or run:

    ```powershell
    supabase db query --linked --file supabase/migrations/20260906010000_test_mode_live_tracking_consistency.sql
    ```

    Reconcile the migration ledger with actually installed changes before using a broad `supabase db push`. No Edge Function deployment is needed. Rebuild/restart the updated Flutter clients after applying SQL. The migration has not been deployed by this implementation turn.

15. **Testing Mode OFF:** The repository chooses the normal RPC when the booking's authoritative Testing Mode is off, and release builds never choose the debug RPC. The normal future-date/time and payment gates remain. SQL regression tests verify future start blocked with Testing Mode off, blocked using the exact broken deployed wrapper even with Test Mode on, allowed after installing the corrected wrapper, real proximity still required for automatic arrival, and blocked again after disabling Test Mode.

## Verification

- 190 Flutter tests passed.
- 56 isolated PostgreSQL regression checks passed, including the exact deployed schedule failure and corrected behavior. The database fixture uses the real modified transition functions; unrelated services/auth are test fixtures.
- Targeted analysis on changed Dart files: no issues.
- Web debug build: passed.
- `git diff --check`: passed.
- Linked database function definitions and migration history were inspected read-only. No live bookings, coordinates, payments, or schema were mutated remotely.
- Physical three-device/emulator movement and platform map rendering still need a device run after deployment. Tests verify marker membership/icon consistency and RPC behavior; they do not claim a live Google Maps/Supabase session was exercised.

Repeat local checks:

```powershell
flutter test
node supabase/tests/event_driven_trip_regression.mjs
flutter build web --debug --no-pub --no-wasm-dry-run
```

If the ignored PostgreSQL test dependency was removed by `flutter clean`, reinstall it with `npm install --prefix build/sql-validation --no-audit --no-fund @electric-sql/pglite@0.5.8`.
