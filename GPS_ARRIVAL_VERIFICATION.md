# Driver Tour Navigation verification — September 6, 2026

**Latest live result:** the deployment-pending and live-delivery limitations below were resolved in the follow-up session. All four deployed function bodies exactly match the prepared migrations. The current debug APK was installed on three emulators without clearing data. Pickup, all three stops, independent multi-driver arrivals, and drop-off were exercised through emulator GPS and the actual Flutter screens. Tourist driver cards updated while the screen stayed open, without refresh. See [GPS_ARRIVAL_LIVE_TEST_RESULTS.md](GPS_ARRIVAL_LIVE_TEST_RESULTS.md) for evidence, exact commands, and the remaining unrelated Maps billing error. The table below preserves the initial audit findings.

This audit traced the current working tree after the GPS changes, not just similarly named helpers. The initial verdict was delivered before the follow-up radius changes. PASS means the actual routed code path, relevant automated tests, and inspected database wiring support the requirement. It does not mean the installed emulator binary was rebuilt or a live GPS-to-Supabase-to-Tourist session was exercised.

| Requirement | Initial verdict | Evidence / smallest correction |
| --- | --- | --- |
| 1. Pickup GPS auto-arrival | PASS | `DriverPackageTrackingScreen._markEnRoutePickup` calls `_advanceConvoyStateCore(enRoutePickup)`. `_startGpsStreaming` continues, `_arrivalTarget` selects pickup, `_detectAutomaticArrival` calls the canonical RPC with `atPickup`. |
| 2. No manual Arrived at Pickup button | PASS | `_currentPrimaryAction` returns null for `enRoutePickup`; `_buildContent` passes that result to `_PersistentDriverActionBar`. No secondary itinerary arrival callback exists. |
| 3. Stop GPS auto-arrival | PASS | `_arrivalTarget` selects `_currentSpotLatLng`, whose item is selected using the authenticated driver's `currentStopIndex`; stable fixes submit `atStop`. |
| 4. No manual Mark Arrived at stops | PASS | `_currentPrimaryAction` returns null for `enRouteStop`; the removed `_markAtStop` has no remaining call site. |
| 5. Drop-off GPS auto-arrival | PASS | Same listener and detector select drop-off and submit `atDropoff`. `enRouteDropoff` has no primary arrival action. |
| 6. Tourist Picked Up | PASS | `_markBoarded` submits `boarded`, then the existing server milestones persist pickup. This remains an explicit passenger confirmation. |
| 7. Proceed to Next Stop | PASS | `_markStopDone` invokes `completeCurrentItineraryItem`; `_progressReadyJourney` invokes `_departStop` once convoy/payment gates permit. `_departStop` advances the index and refreshes the next route. No second manual Navigate step. |
| 8. Tourist Dropped Off | PASS | `_completeTour` submits `completed` for the driver's assignment and invokes the existing finalizer. `_shouldShareDriverLocation` stops that driver's uploads independently of overall convoy completion. |
| 9. Testing Mode keeps GPS automation | PARTIAL | Current Flutter arrival targets always use the canonical RPC. However, read-only `pg_get_functiondef` showed the linked database's `debug_advance_driver_journey_state` still sets bypass true for every target, and its proximity trigger honours that flag. The existing local `20260906030000_keep_debug_arrivals_gps_verified.sql` is the minimal fix; deployment remains required. |
| 10. Arrival radius centralized | PARTIAL | Screen `_proximityMeters`, SQL `guard_live_driver_journey_proximity`, and SQL `confirm_driver_arrival_fallback` independently contained 150. Follow-up fix: `driver_arrival_radius_meters()` owns the value; the screen fetches it and both SQL paths call it. New migration `20260906040000_centralize_driver_arrival_radius.sql` must be deployed. |
| 11. GPS noise protection | PASS | `StableArrivalDetector.observe` requires three distinct fixes over six seconds. `_acceptGpsFix` rejects invalid coordinates, accuracy over 50 m, stale fixes over 20 seconds, and future fixes over two seconds. Leaving the radius resets the streak, including samples skipped by upload throttling. |
| 12. Duplicate arrival protection | PASS | In-flight/throttle/successful-target guards in `_detectAutomaticArrival`, persisted journey state, canonical SQL no-op handling, and unique per-assignment/item arrival rows. Tests verify unchanged timestamps and log counts on repeated arrival. |
| 13. Supabase arrival state updates | PASS | Canonical function and the deployed proximity, milestone, and stop-persistence triggers exist on `booking_drivers`. Tests execute the actual functions and triggers against an isolated PostgreSQL fixture. |
| 14. Tourist realtime reflection | PASS (wiring) | `TouristActivityTrackingScreen._subscribeToConvoyRoster` listens for `booking_drivers`, reloads via `_refreshConvoyRoster`, and renders `ConvoyTouristDriverList`. The linked database publishes all four relevant tables and allows participants to select driver rows. Actual device delivery remains an end-to-end check. |
| 15. Independent arrivals | PASS | `advance_driver_journey_state` selects and updates only `auth.uid()`'s assignment. Repository maps each row's own journey state, and `ConvoyTouristDriverList._DriverCard` renders `driver.journeyState.label`. SQL and detector tests cover A arriving while B remains en route. |

## Actual runtime path

Package entry points in `driver_package_booking_details_screen.dart`, `driver_package_jobs_screen.dart`, `driver_trips.dart`, `driver_overview_details.dart`, and the existing developer tools open `DriverPackageTrackingScreen(activityId: ...)`.

1. `lib/screens/driver/driver_package_tracking_screen.dart`: `initState` calls `_load`. It resolves the activity/booking, loads the shared radius, constructs the detector, starts GPS, and loads/subscribes to the convoy.
2. `_startGpsStreaming` attaches `Geolocator.getPositionStream`. `_recoverGpsFix` supplies periodic real current fixes or the existing developer simulator's coordinates. Permission/service failures expose the controlled fallback rather than silently confirming arrival.
3. `_acceptGpsFix` checks coordinate range, age, accuracy, and ordering. `TourisTrikeRepository.upsertDriverLiveLocation` writes the authenticated driver's row before attempting the server arrival transition.
4. `_arrivalTarget` maps the driver's persisted en-route state to pickup, their current itinerary stop, or drop-off. `_haversineMeters` computes distance; `StableArrivalDetector.observe` checks radius and stability.
5. `_detectAutomaticArrival` calls `TourisTrikeRepository.advanceDriverJourneyState(automaticArrival: true)`. Arrival targets always select `advance_driver_journey_state`, including in Testing Mode.
6. SQL validates membership, transition, and fresh live-location proximity, then updates the assignment. Existing triggers persist actual milestones, shared activity/itinerary data, logs, and deduplicated notifications.
7. Driver `_loadConvoy` and `_refreshTrackingState` reload persisted state; `_currentPrimaryAction` selects Tourist Picked Up, the stay/proceed action, or Tourist Dropped Off.
8. Tourist `_subscribeToConvoyRoster` reloads each assignment; `_subscribeToActivity` and the itinerary/location listeners refresh shared progress, maps, and timing. A shared summary can wait for the slowest driver while the individual driver cards show different states.

## Manual-arrival search inventory

| Location and function | What remains | Disposition |
| --- | --- | --- |
| `lib/screens/driver/driver_package_tracking_screen.dart`, `_manualArrivalFallback` / `_buildJourneyAutomationNotice` | Verify Arrival Manually, followed by Confirm arrival in the reason dialog | Retained only for location failure; rechecks that the failure and target still apply. Server requires a reason and recent driver/tourist proximity, and logs the fallback. Not a normal primary action. |
| Same file, `_selectedCurrentActionLabel` | Strings such as Arrived at Pickup / Drop-off / destination | Existing diagnostic strings used only by `_debugTourState`; no button callback. They do not drive the trip. |
| `lib/screens/driver/incoming_ride_screen.dart`, `_primaryAction` | Arrived at Pickup changes ride status from `enroute_pickup` to `arrived`; explanatory pickup text also remains | Real manual action, but in the separate rides flow. Verified package-tour entry points do not open this screen. Retained to avoid rewriting unrelated rides. |
| `lib/screens/driver/driver_messages_screen.dart`, quick-reply ActionChip | Arrived at pickup | Fills the message composer; does not submit a journey transition. Retained. |
| `lib/core/supabase/touristrike_repository.dart`, `markSpotActualArrival` | Legacy normal/debug `mark_itinerary_stop_arrived` RPC wrapper | No caller found in `lib`; not used by the current Driver Tour Navigation screen. Retained as an unrelated compatibility method. |

The primary trip actions are Start Navigation to Pickup, Tourist Picked Up, Proceed to Next Stop (Finish Tour Stops at the final stop), and Tourist Dropped Off. During en-route states and while required gates are pending, there is no primary arrival/progression button. Existing auxiliary actions remain: calls/chat, convoy selection, map focus/follow controls, ETA refresh, payment/cash receipt confirmations and reports, screen retry/back, and GPS retry/fallback when eligible. None of the auxiliary actions replaces the canonical GPS arrival flow.

## Database fields actually written

- `booking_drivers.journey_state`, `current_stop_index`, and `state_updated_at`; arrival leaves membership `status` accepted. Passenger drop-off confirmation changes membership to completed and saves `completed_at`.
- `trip_status_logs`: driver ID, previous/new state, stop index, log time, and notes. These retain per-driver pickup/drop-off arrival history after `state_updated_at` moves to the next state.
- Pickup triggers set `package_bookings.arrived_at` and `package_activities.arrived_at` once. Boarding sets existing `picked_up_at` fields. Passenger drop-off sets `package_activities.dropped_off_at`.
- Stop trigger inserts `booking_driver_arrivals.arrived_at` per assignment/item; shared itinerary uses `actual_arrival_time`. Departure writes per-driver `departed_at` and shared `actual_departure_time`. Planned `arrival_time` / `departure_time` are not overwritten.
- Canonical transition mirrors the convoy's slowest state into `package_activities.tour_status` / `status` and updates `package_bookings.booking_status`, shared index, and `updated_at`.
- No new `actual_arrival_at` column or duplicate status system was introduced.

## Follow-up fixes and deployment

Only the radius PARTIAL required additional source changes after the initial report: the screen's `_load` / detector initialization; repository `fetchDriverArrivalRadiusMeters`; the new radius migration; configuration tests; and SQL regression coverage. Testing Mode's fix was already in the preceding local migration. PASS trip progression, payment, maps, and Tourist realtime paths were not rewritten during this follow-up.

Apply these two files in order in Supabase SQL Editor, or run:

```powershell
supabase db query --linked --file supabase/migrations/20260906030000_keep_debug_arrivals_gps_verified.sql
supabase db query --linked --file supabase/migrations/20260906040000_centralize_driver_arrival_radius.sql
```

The radius is defined only in `public.driver_arrival_radius_meters()` for the current package arrival path. Historical migrations and the separate legacy arrival APIs retain their original definitions; the new migration replaces the active guard and fallback definitions. The screen loads this RPC before starting GPS, without a duplicate numeric fallback. Deploy before restarting the updated app; if configuration cannot load, the screen reports a load error and offers retry instead of inventing a radius.

Read-only database inspection confirmed the earlier missing `is_booking_downpayment_confirmed(uuid)` repair is now present. No remote schema writes or app deployment were performed during this verification. Items 9 and 10 therefore remain deployment-pending for the linked environment despite their local fixes.

## Emulator and Tourist checks

Validation after fixes: 199 Flutter tests passed, 84 isolated PostgreSQL checks passed, and targeted Dart analysis found no issues. `test/driver_arrival_configuration_test.dart` exercises the actual repository RPC with multiple radius values and rejects malformed responses. The SQL runner changes the single radius to 80 m and verifies that both normal and fallback checks reject a fix about 111 m away, then restores 150 m and accepts the same fix. No live booking records were changed by these tests.

1. Open the updated package-tour screen for each driver and Tourist Tracking for the same booking. Keep Driver B outside the target radius to check independent states.
2. Pickup: press Start Navigation to Pickup. Send real emulator GPS fixes near the stored pickup via Extended Controls → Location, or use the existing authorized location simulator. Keep at least three distinct valid fixes within 150 m over six seconds; periodic recovery may take about 16 seconds to accumulate three fixes. Observe automatic At Pickup and Tourist Picked Up. A single fix must not trigger arrival.
3. Boarding: press Tourist Picked Up for the assigned passengers. Existing convoy readiness starts navigation to the first stop.
4. Stops: move only Driver A near its current stored stop. Confirm A shows At Stop while B remains En Route to Stop. Check actual arrival, stay, expected departure, and then Proceed to Next Stop. The final stop still waits for the remaining payment under normal rules.
5. Drop-off: after departure is allowed, move near the stored drop-off. Confirm automatic At Drop-off, followed by the separate Tourist Dropped Off confirmation. Verify the assignment completes and this driver's GPS uploads stop.
6. Tourist: keep the screen open throughout. Confirm individual driver labels change without reopening, and check `booking_drivers` / `trip_status_logs` in Supabase if a realtime connection fails. Repeated inside-radius fixes must not add arrival logs or change the original arrival timestamp.
7. Repeat in Testing Mode: future schedule/payment/stay gates can use existing authorized bypasses, but distant coordinates must never cause arrival. Disable GPS or withhold valid fixes to exercise fallback visibility; healthy GPS while driving for more than two minutes must not expose fallback merely due to travel time.
