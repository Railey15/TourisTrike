# TourisTrike booking and payment flow

Follow-up: [Post-trip flow implementation](POST_TRIP_FLOW_IMPLEMENTATION.md) adds feedback, driver overview, remaining-payment, and GPS progression changes. That follow-up requires a new September 6 SQL migration; the no-migration statements below describe only this earlier booking-flow change.

Implemented September 5, 2026. The existing Flutter booking architecture, atomic booking RPC, PayMongo checkout, webhook, payment records/allocations, earnings split, convoy, tracking, developer testing mode, chat, notifications and navigation remain in use.

1. **Files modified/added**

   | File | Change |
   | --- | --- |
   | `lib/screens/tourist/package_booking_screen.dart` | Review before submission; route calculation/error/retry state; automatic itinerary recalculation and validation. |
   | `lib/widgets/booking_review_sheet.dart` | New scrollable booking review and policy agreement sheet. |
   | `lib/screens/tourist/tourist_activity_tracking_screen.dart` | Realtime payment prompt, dismissal handling, fixed payment action, confirmation indicator. |
   | `lib/widgets/booking_payment_sheet.dart` | New payment sheet that reacts to booking/payment updates. |
   | `lib/core/models/booking_payment_prompt.dart` | Shared payment eligibility and presentation gate. |
   | `lib/core/services/itinerary_schedule_service.dart` | Strict Maps leg parsing; removal of approximate fallback. |
   | `lib/core/services/itinerary_directions_mobile.dart` | Native Directions REST transport extracted from the existing service. |
   | `lib/core/services/itinerary_directions_web.dart` | Web scheduling through the existing Maps JavaScript bridge. |
   | `web/index.html` | Optional stopover waypoints and numeric route legs in the existing bridge; existing navigation callers retain their behavior. |
   | `test/booking_review_payment_flow_test.dart` | Payment eligibility, Maps failures, schedule calculations, agreement interaction, responsive layouts and payment-state updates. |
   | `test/same_day_downpayment_consistency_test.dart` | Updated tracking assertion for the shared payment sheet. |
   | `BOOKING_FLOW_IMPLEMENTATION.md` | This report. |

2. **Review modal:** “Confirm Booking” opens a TourisTrike bottom sheet with rounded cards, existing booking colors, inherited app typography, scrollable details and a fixed submission footer.

3. **Review details:** Current package, pickup address/date/time, adults/children/total passengers, selected tricycles, same-day/advance booking type, total duration including pickup/drop-off travel, drop-off address/ETA, total, downpayment, remaining balance, GCash via PayMongo, and every stop's name, travel time, arrival, stay and departure. Values come from validated booking state; the sheet contains no editable schedule inputs.

4. **Confirmation:** The sheet links to the existing published TourisTrike policies screen. “Confirm & Submit Booking” stays disabled until agreement is checked. Dismissal creates no booking. Confirmation validates again, including same-day pickup time, then calls the existing atomic `create_package_booking` RPC. Schedule and price are not recalculated after agreement. The request starts pending/`waiting_for_drivers`; submission never launches payment. A saving guard prevents duplicate submissions.

5. **Required drivers:** Existing calculation is `max(selectedTricycles, ceil((adults + children) / 3))`, with at least one tricycle. This is saved in `package_bookings.required_drivers`; server capacity validation remains unchanged.

6. **Automatic payment detection:** Existing `booking_drivers` and `package_bookings` Realtime subscriptions trigger fresh booking/payment reads. The current acceptance RPC sets `booking_status = 'accepted'`, `status = 'confirmed'`, and `accepted_drivers_count` when the roster fills. The prompt requires the accepted count to meet the saved required count, a payable accepted/confirmed booking, a positive downpayment, and no confirmed down/full payment or manual payment under review. Both initial loading and Realtime reconnect/app resume refresh the state, closing the initial read/subscription gap. Reads are serialized/coalesced so simultaneous events do not create competing prompts.

7. **Duplicate prevention:** A gate consumes one automatic presentation per complete-roster phase; a separate open/scheduled guard prevents concurrent sheets. Manual opening also marks the phase handled. Rebuilds, refreshes, checkout retries and dismissal do not reopen it. An observed incomplete roster resets the gate for a later completed roster. Dismissal keeps a payment button directly below the tracking top bar, outside the scrolling details. Handling lasts for the current tracking-screen instance; revisiting an unpaid booking may prompt again.

8. **PayMongo:** The sheet returns the pay action to `_openPayMongoCheckout(stage: 'down_payment')`, which already calls `createPayMongoCheckout` and the `paymongo-create-payment` Edge Function. Existing checkout launch, server validation, idempotency, webhook verification, payment records and allocations are unchanged. Payment Realtime updates refresh the sheet and the fixed confirmation indicator. No client action marks payment confirmed. Existing remaining-balance payment choices remain unchanged.

9. **Same-day/advance verification:** Tests exercise both `same_day` and `advanced` with 1, 2 and 3 required drivers, incomplete/full rosters, repeat updates, roster reopening, confirmed payments and terminal bookings. Existing 50/50 split, shared PayMongo preparation and driver payment-gate regression tests also pass. No booking-type exception skips the downpayment. Tests simulate payment confirmation; a live multi-device Supabase/PayMongo/GCash transaction was not performed.

10. **Pickup storage:** The selected date and exact time form the existing `scheduledStartAt` value. The repository sends its UTC ISO timestamp to `package_bookings.scheduled_start_at`; `travel_date` retains the selected calendar date. Existing server validation checks the pickup date in `Asia/Manila`. The application continues using its existing device-local date/time input and display convention.

11. **Maps service:** `ItineraryScheduleService` uses the existing Google Directions integration: native clients call `/maps/api/directions/json`; web clients call the existing `_flutterGetRoute` bridge backed by `google.maps.DirectionsService`. Scheduling requests use stopover waypoints with order optimization disabled, yielding one numeric leg per segment. Seconds are rounded up to whole minutes. Web navigation requests keep their previous non-stopover behavior. See [Google's Directions service documentation](https://developers.google.com/maps/documentation/javascript/legacy/directions).

12. **First ETA:** `pickup time + Google Maps pickup-to-first-stop duration`.

13. **Following ETAs:** `previous stop departure + Google Maps duration to this stop`. All stops are calculated in their selected order.

14. **Departures:** `arrival + Time of Stay`. Validation prevents invalid stays, schedules outside the existing 7 AM–5 PM tour window and overnight wrapping.

15. **Stay and route updates:** Editing a stay or pickup time immediately recalculates following times using the latest successful Maps durations for that exact ordered route. This avoids another network request when only arithmetic changes. Pickup/date/location, destination add/remove/reorder, itinerary mode and final drop-off changes trigger recalculation; changed route coordinates/order fetch new legs. Surviving customized stays/order are preserved when adding/removing destinations. A revision guard ignores obsolete asynchronous responses. Route failures block review/submission and expose Retry; loading never displays invented zero-minute travel.

16. **Drop-off ETA:** `last departure + Google Maps final leg`. The full pickup-to-drop-off duration appears in the booking schedule/review. The existing `estimated_end_at` stores the final ETA. Tourist tracking and driver tracking already display this field and the persisted itinerary, so no independent driver-side schedule computation was added.

17. **Automatic fields:** Arrival, departure and travel duration are read-only; the existing disabled arrival/departure controls are explicitly labeled automatic. The unused manual stop time-picker widget was removed. Each customized stop edits only “Time of Stay,” with validation; the existing exact pickup time picker remains editable.

18. **Schema:** No new columns. Reused `package_bookings.scheduled_start_at`, `estimated_end_at`, `travel_date`, `required_drivers`, and `booking_itinerary_items.arrival_time`, `departure_time`, `estimated_stay_duration_minutes`, `travel_duration_minutes`, `route_distance_meters`, plus existing destination/order fields. The final travel leg is represented by the stored final ETA; no duplicate drop-off-duration column is needed. Persisting the approved schedule keeps tourist and drivers consistent; live navigation may still refresh traffic/navigation ETA separately.

19. **SQL migration:** None added. The existing schedule/capacity migration `20260830000000_booking_schedule_group_chat_arrivals.sql`, payment foundation and transaction-lifecycle migrations remain prerequisites. The active developer diagnostics migration was not changed.

20. **Google configuration:** No new API or credential name. Native scheduling uses the existing `GOOGLE_MAPS_API_KEY`/`GOOGLE_PLACES_API_KEY` resolution; web uses the existing Maps JavaScript loader key. The existing Google project must allow Directions and Maps JavaScript where applicable, with billing and appropriate key restrictions. A rejected or unavailable route now produces an explicit error instead of an approximation. No live API credential/billing check was performed.

21. **Supabase deployment:** No new migration or Edge Function deployment is required for this change when the repository's existing migrations/functions are deployed. Existing Realtime publication membership for `package_bookings`, `booking_drivers`, `payment_records`, `payment_allocations` and booking payment requirements must remain enabled. Rebuild/release the Flutter client and include the updated `web/index.html` in the web release. No remote database or production deployment was performed.

## Validation

- 66 focused Flutter tests passed across the new flow tests and existing schedule, same-day downpayment, PayMongo architecture, convoy/payment-gate and atomic-booking suites.
- `flutter analyze` on changed Dart files and the new test: no issues.
- `flutter build web --debug --no-pub --no-wasm-dry-run`: passed.
- `git diff --check`: passed.
- Review sheets rendered and inspected at 320 px and 390 px; payment-required and payment-confirmed layouts rendered and inspected. Local captures are in ignored `build/booking_flow_qa/` (SDK Roboto used for test captures; production inherits the app theme).

To repeat the focused checks:

```powershell
flutter test test/booking_review_payment_flow_test.dart test/booking_schedule_improvements_test.dart test/same_day_downpayment_consistency_test.dart test/paymongo_payment_architecture_test.dart test/high_priority_payment_gate_and_convoy_map_test.dart test/atomic_package_booking_test.dart
flutter build web --debug --no-pub --no-wasm-dry-run
```
