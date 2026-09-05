# Post-trip feedback, payments, and driver progression

Implemented in the workspace. Apply the new migration before releasing the client. No remote database changes, Edge Function deployments, or real payments were performed.

This supplements `BOOKING_FLOW_IMPLEMENTATION.md`, covering the earlier booking review, automatic downpayment, and planned itinerary changes. Its “no new migration” statement applies only to that earlier change.

1. **Feedback-loop root cause:** `_checkAndShowReviewModal` awaited separate package/driver review checks before setting `_reviewShown`. Concurrent Realtime refreshes could pass that guard and queue multiple prompts. It also presented separate sheets for each driver and accepted legacy activity completion. The server review predicate compared counts instead of checking each driver's membership. The replacement reserves the prompt before any asynchronous read, uses canonical booking completion, and loads one feedback object. These are findings from repository code; the remotely deployed migration state was not inspected.

2. **Duplicate prevention:** `submit_booking_feedback` locks the booking and submits all missing reviews in one transaction. Existing `package_reviews_booking_tourist_idx` and `driver_reviews_booking_driver_tourist_uidx` are reused. `ON CONFLICT DO NOTHING` preserves original reviews on retry; incomplete submissions roll back. The sheet disables repeated submission, retains inputs on failure, and closes after confirmed success.

3. **Review completion:** The completed booking's owner needs a package review and an exact booking/tourist/driver review for every completed participating driver. Existing partial feedback is preserved; only missing items are requested. A fresh screen checks persisted rows, so fully reviewed bookings never prompt again.

4. **Booking-specific display:** Completed tourist tracking/details shows “Feedback for This Booking,” including the actual package and per-driver ratings/comments. `get_booking_feedback` reads that transaction, not global averages. Failed loading exposes Retry; dismissal leaves “Rate this booking.”

5. **Driver ratings:** `get_driver_home_overview` calculates average/count from valid 1–5 `driver_reviews.rating` values belonging to the authenticated driver, plus the five latest comments. Existing profile-aggregate triggers remain intact.

6. **Missing dashboard data:** Earlier earnings queried `payment_records.payee_id`, while group payments can have no single payee and use `payment_allocations`. Completed tours used the legacy activity driver; today's trips counted payment rows. Rating display used the wrong profile field names, and Upcoming Schedule reused the active ride. The existing identity mapping is `profiles.id = auth.uid()`; no guessed driver ID was added.

7. **Dashboard query fixes:** The driver-only overview RPC reads independent completed/active/upcoming assignments and confirmed allocated driver shares. Assigned tours scheduled later today count as upcoming; already started assignments count as active. Today's completed trips and earnings use `Asia/Manila` boundaries. Earnings exclude cancelled/manual-review allocations. Assignments, reviews, allocations, payment records, and booking Realtime updates refresh the dashboard. Loading/errors and retry are explicit. Assignment cards open the corresponding tour activity.

8. **Remaining-payment trigger:** Existing itinerary/booking/assignment/payment Realtime updates refresh the shared prompt state. It requires a complete roster, nonempty fully completed itinerary, positive unpaid remaining balance, an open booking, and no driver already navigating to/at drop-off or completed. The sheet displays package, driver count, total, confirmed downpayment, remaining balance, and existing GCash/Cash choices. Confirmed payments must cover the stage amount. The server independently rejects final navigation until its existing payment requirement is satisfied.

9. **Modal idempotence and checkout:** Each payment stage has a handled gate; a shared open/scheduled guard prevents simultaneous sheets. Reads are coalesced. Dismissal, rebuilds, and retries do not reopen a handled sheet, and a payment action remains below the tracking top bar. A new screen instance may prompt for an unpaid booking again. Remaining payment calls existing `_chooseRemainingPayment`: GCash uses `_openPayMongoCheckout(stage: 'remaining_balance')`; Cash uses existing group-cash preparation and per-driver share confirmation. Pending cash displays progress without another pay button. Webhook/database updates confirm the payment in place. Same-day and advance bookings share this flow and the downpayment flow.

10. **Driver state machine:** Existing assignment states remain:

    ```text
    assigned -> en_route_pickup -> at_pickup -> boarded
      -> en_route_stop -> at_stop -> stop_done
      -> [repeat for following stops]
      -> en_route_dropoff -> at_dropoff -> completed
    ```

    After the final shared stop, the existing booking/activity becomes `awaiting_remaining_payment`. Each driver completes independently. The existing finalizer requires all required drivers, itinerary completion, and payment before completing the whole booking. No duplicate status system was created.

11. **Automatic actions:** Stable GPS advances the current driver's pickup, stop, and drop-off arrivals through the authoritative transition RPC. Navigation starts after boarding/stop-readiness when convoy and payment gates clear. Persisted journey state prevents repeated arrival events.

12. **Manual actions:** Start Navigation to Pickup, Tourist Picked Up, Proceed to Next Stop (Finish Tour Stops at the last destination), and Tourist Dropped Off. One primary action is shown at a time. Normal en-route arrival buttons are removed; debug test controls remain. GPS cannot confirm that passengers boarded or alighted.

13. **Arrival radius:** The existing 150 m rule remains. The server validates the current stage's target and the existing two-minute driver-location freshness limit; the client detector uses the same screen radius.

14. **Noise protection:** Automatic arrival needs three distinct fixes over at least six seconds, inside the radius and with accuracy of 50 m or better. Duplicate/out-of-order, invalid, future, or over-20-second-old readings do not qualify. Leaving the radius, poor accuracy, long gaps, and changed targets reset stability. In-flight guards and retry throttling prevent competing transitions. An eight-second recovery check obtains fresh positions while en route, including when stationary streams stop emitting.

15. **Stay timer:** The driver's actual persisted arrival starts the operational timer. The screen updates every second; the server validates that driver's arrival plus `estimated_stay_duration_minutes`. Readiness changes only that assignment to `stop_done`. Planned times cannot shorten a delayed driver's stay.

16. **Planned versus actual:** Existing planned arrival/departure/travel durations and booking pickup/final ETA remain unchanged. `booking_driver_arrivals.arrived_at` stores each arrival; new `departed_at` stores departure on the next navigation transition. Existing shared actual arrival means first convoy arrival; shared actual departure means latest recorded convoy departure. Labels distinguish Planned, First convoy arrival, and Actual departure. `package_activities.dropped_off_at` now follows passenger drop-off confirmation, not GPS arrival. The live card shows each driver's current actual arrival and stay end.

17. **Live ETA:** Both tracking screens use the existing Directions integration through `LiveItineraryEstimates`. State changes and a 30-second refresh recalculate from fresh driver coordinates; tourist location events now update those snapshots as well as markers. Individual live legs request departure now and prefer Google's `duration_in_traffic` where available. Future times sequentially add stays and following route durations through drop-off. Native uses Directions HTTP; web reuses `_flutterGetRoute` and Maps JavaScript DirectionsService. Planned scheduling retains ordered waypoints. Missing GPS/Maps results show errors and retry, not invented minutes. Forecasts stay transient because location, traffic, convoy readiness, and payment waits change. Google's traffic/stopover constraints are documented in [Directions documentation](https://developers.google.com/maps/documentation/directions/get-directions).

18. **Convoy synchronization:** Arrival, boarding, readiness, and drop-off confirmation update only the authenticated assignment. Existing convoy-stage calculation gates departures. A shared stop completes only after all participating drivers are ready. Navigation beyond the final stop index is rejected. Arrival notifications retain their existing deduplication keys and recipients; chat milestones remain connected.

19. **GPS/offline fallback:** The arrival notice exposes Retry GPS and secondary Arrival fallback when GPS fails or arrival remains unresolved after two minutes. Fallback requires a reason and server verification of assignment, stage, target, and a recent driver position. If driver GPS is unavailable, a fresh accurate tourist position at that booking's target can corroborate arrival. The reason is recorded in `trip_status_logs`. Without connectivity or any verifiable position, the action shows an error and retry; it cannot commit an authoritative offline arrival. Existing allowlisted debug bypasses remain available for configured test bookings.

20. **Files added/modified in this follow-up:**

    - Models: `lib/core/models/booking_feedback.dart`, `booking_payment_prompt.dart`, `convoy_state.dart`.
    - Services: `lib/core/services/stable_arrival_detector.dart`, `itinerary_schedule_service.dart`, `itinerary_directions_mobile.dart`, `itinerary_directions_web.dart`.
    - Repository: `lib/core/supabase/touristrike_repository.dart`.
    - Screens: `lib/screens/driver/driver_home_screen.dart`, `driver_package_tracking_screen.dart`, `lib/screens/tourist/tourist_activity_tracking_screen.dart`.
    - UI: `lib/components/tourist/driver_review_modal.dart`, `lib/widgets/booking_feedback_card.dart`, `booking_payment_sheet.dart`, `driver_overview_details.dart`, `live_itinerary_estimates.dart`.
    - Web bridge: `web/index.html`.
    - Migration: `supabase/migrations/20260906000000_event_driven_trip_feedback.sql`.
    - Tests: `test/post_trip_flow_test.dart`, `test/booking_review_payment_flow_test.dart`, `supabase/tests/event_driven_trip_fixture.sql`, `supabase/tests/event_driven_trip_regression.mjs`.
    - Reports: this file and a follow-up pointer in `BOOKING_FLOW_IMPLEMENTATION.md`. Earlier booking-screen/review-sheet changes remain and are documented in that report.

21. **Migration:** Apply `20260906000000_event_driven_trip_feedback.sql` after the existing migrations, including September 2's multi-driver review index/proximity migration. The only new column is `booking_driver_arrivals.departed_at timestamptz`. It adds an arrival/departure trigger, replaces the relevant functions, and ensures package reviews belong to the existing Realtime publication. Historical planned schedules remain unchanged; historical per-driver departures are not invented. The developer diagnostics migration is unchanged.

22. **RPCs/Edge Functions:** New RPCs: `get_booking_feedback`, `submit_booking_feedback`, `get_driver_home_overview`, `confirm_driver_arrival_fallback`. Replaced: `tourist_has_reviewed_booking`, `complete_current_itinerary_item`, `advance_driver_journey_state`, `guard_live_driver_journey_proximity`, `sync_driver_journey_milestones`. New trigger function: `persist_driver_stop_milestones`. PayMongo Edge Functions, webhook confirmation, earnings split, and cash confirmation RPCs are unchanged. No Edge Function deployment is required.

23. **Commands:** From the repository root against the intended linked project:

    ```powershell
    supabase migration list
    supabase db push --dry-run
    supabase db push
    ```

    If not linked, first run `supabase link --project-ref YOUR_PROJECT_REF`. Inspect the dry-run list: `db push` applies all outstanding migrations in timestamp order. Alternatively, run the entire new migration in the SQL editor after its prerequisites. Never run the test fixture in an application database.

    Client validation/build:

    ```powershell
    flutter test
    flutter build web --debug --no-pub --no-wasm-dry-run
    ```

    Isolated database regression checks:

    ```powershell
    npm install --prefix build/sql-validation --no-audit --no-fund @electric-sql/pglite@0.5.8
    node supabase/tests/event_driven_trip_regression.mjs
    ```

    Keep existing Maps keys, Directions/Maps JavaScript enablement, billing, location permissions, and Realtime configuration. No new credential name or payment method is required. Include the changed `web/index.html` in the release.

## Validation and device checks

- 185 Flutter tests passed, including both booking types, payment architecture, GPS stability/stay arithmetic, feedback retry/duplicate taps, live traffic request construction, and existing suites.
- 47 isolated PostgreSQL checks passed using PGlite. They execute the new migration plus the existing convoy calculation, remaining-payment predicate, and finalizer against a minimal fixture. Coverage includes independent drivers, repeating stops, unpaid drop-off rejection, notification deduplication, atomic/idempotent feedback, participant restrictions, and dashboard aggregation. Auth and unrelated services are fixture stand-ins; this is not a full Supabase RLS/Realtime integration environment.
- Targeted Dart analysis passed. Repository-wide analysis still has unrelated existing warnings/lints.
- Web debug compilation passed. The 320 px remaining-payment/feedback layouts were rendered and inspected; the detected star overflow was fixed. Captures are in ignored `build/booking_flow_qa/`.
- Live multi-device Supabase Realtime, physical GPS/background OS behavior, and real PayMongo/GCash were not exercised. After deployment, verify a two-driver trip with Testing Mode off: one late driver, all shares for cash or a payment webhook, reconnect, and reopening a fully reviewed booking.
