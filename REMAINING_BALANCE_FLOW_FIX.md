# Remaining-balance payment repair

## Verified causes

The affected booking `e2b4e475-1507-4f73-bcdb-886dce22657b` was inspected read-only on September 6, 2026. It has two required/accepted drivers, `status = confirmed`, `booking_status = awaiting_final_payment`, and an unpaid remaining balance of PHP 1,800. It is a registered developer test booking. Its sole payment record is a confirmed PayMongo `down_payment` of PHP 1,800; a remaining-balance payment has not been prepared yet.

The card was not disabled: `_PaymentStageCard` uses `onPressed: busy ? null : onPay`. Its callback called `_showPaymentPrompt(remaining: true)`, which returned immediately when `notifier.value?.paymentRequired != true`.

`BookingPaymentPrompt.paymentRequired` previously required `itineraryComplete && !dropoffStarted`. The Tourist refresh sets `dropoffStarted` when **any** driver is `en_route_dropoff`, `at_dropoff`, or `completed`. Thus test progression made both the manual handler and the automatic prompt gate ineligible, despite an outstanding payable balance. The blue card and modal used inconsistent eligibility rules; no missing payment row was required to explain the dead action.

The phrase “Assignment completed • awaiting final payment” did not prove direct last-stop completion. Database logs show both drivers progressing from `stop_done` to `en_route_dropoff` through the authorized debug bypass at approximately 03:29 UTC, real GPS transitions to `at_dropoff` at 03:30, then `at_dropoff → completed` at 03:31. This is the existing test-mode exception. Their overall booking remained unpaid and open. No assignment or payment data was reset.

## Implementation and existing states

1. Removed the physical drop-off restriction from remaining-payment eligibility. An unfinished payable booking can still settle after debug/legacy progression. Cancelled, rejected, expired, and fully completed bookings remain excluded; confirmed payment and nonpositive balance remain excluded.
2. Tourist refresh requires completed shared itinerary items and every required active/completed assignment at the final `stop_done` or a subsequent drop-off state. One driver alone cannot enable the prompt.
3. Existing `BookingPaymentPromptGate` consumes one automatic presentation; manual opening does not depend on whether the gate was consumed. Closing a sheet rechecks pending prompts. Payment confirmation continues to update the existing notifier through Realtime refresh.
4. Existing sheet wording now distinguishes an outstanding post-drop-off payment from the normal payment-before-drop-off instruction.
5. Added a normal-mode driver completion check and a narrow database trigger. This handles switching payment bypass off after a test booking already reached drop-off unpaid. It does not modify arrival/proximity or stop progression.

Normal flow uses existing state names:

```text
All required drivers finish the last stop
  booking.booking_status / activity.tour_status = awaiting_remaining_payment
  driver.journey_state = stop_done; assignment.status = accepted
Remaining payment confirmed
  existing requirement trigger sets remaining_balance = 0
  booking/activity return to on_tour (drop-off is now eligible)
Existing driver refresh/progression advances to en_route_dropoff
GPS → at_dropoff
Tourist Dropped Off → assignment completed
All required assignments complete + payment satisfied → booking completed
```

No duplicate `WAITING_REMAINING_BALANCE` or `READY_FOR_DROPOFF` enum/status was added. The normal ready-for-drop-off condition is the existing confirmed payment requirement plus completed itinerary/convoy barrier. Test mode may still bypass payment progression without disabling real Tourist settlement.

## Payment record, GCash, cash, and unlock

- A missing remaining-balance row is valid before the tourist chooses a method. GCash calls the unchanged `_chooseRemainingPayment → _openPayMongoCheckout(stage: remaining_balance)` path and `paymongo-create-payment`. Its existing `prepare_paymongo_payment` RPC prepares/reuses the stage record and allocations using idempotency keys and booking locks. The existing webhook confirms the record and satisfies the payment requirement.
- Cash calls the unchanged `prepare_group_cash_remaining_balance` RPC. It prepares/reuses one manual cash `remaining_balance` record with `pending_confirmation` and the existing driver allocations. Each driver confirms their own received share; existing all-driver confirmation settles the record/requirement. The canonical required roster includes accepted **and completed** assignments, so the affected test booking can still settle.
- No new checkout, record creation on refresh, payment status system, earnings split, or webhook implementation was introduced.
- Normal `advance_driver_journey_state(..., en_route_dropoff)` already rejects unpaid remaining balances using `is_booking_remaining_payment_satisfied`. The new completion trigger uses that same predicate. Authorized registered-test bypass retains its existing flag checks and never fabricates payment records.
- The existing `finalize_booking_after_payment_requirement` trigger releases `awaiting_remaining_payment` to `on_tour`; existing booking/payment Realtime refreshes unblock both drivers. For the already dropped-off test booking, settlement instead allows the existing finalizer to close the booking.

## Files changed

- `lib/core/models/booking_payment_prompt.dart`
- `lib/screens/tourist/tourist_activity_tracking_screen.dart`
- `lib/widgets/booking_payment_sheet.dart`
- `lib/screens/driver/driver_package_tracking_screen.dart` (remaining-payment guard only)
- `supabase/migrations/20260906050000_guard_remaining_payment_completion.sql`
- `test/post_trip_flow_test.dart`
- `supabase/tests/event_driven_trip_regression.mjs`
- This report.

## Validation and deployment

Passed: **27 Flutter payment/post-trip tests**, including the affected post-drop-off prompt/button state, idempotent presentation, terminal booking rejection, same-day/advance payment eligibility, and live notifier confirmation updates. **86 isolated PostgreSQL regression checks** passed, including multi-driver stop barriers, normal payment-before-drop-off enforcement, successful paid completion, rejected unpaid completion, and authorized test bypass without fabricated records. Targeted analysis of all changed Dart files/tests reported no issues.

The deployed booking was read only. The new migration is **prepared and tested locally, not applied remotely**. It adds `public.guard_driver_completion_remaining_payment()` and trigger `trg_guard_driver_completion_remaining_payment`. The full migration file is directly pasteable into Supabase SQL Editor, or run:

```powershell
supabase db query --linked --file supabase/migrations/20260906050000_guard_remaining_payment_completion.sql
```

No Edge Function deployment or generated type update is needed. This migration adds completion protection; the dead payment action itself is repaired in Flutter.

Android live verification was attempted but **blocked before installation** by existing compilation errors in the unrelated `package_booking_screen.dart`: unresolved `BookingLocation`, `_AutocompleteResult`, and `BookingLocationPicker`, and an incomplete `_SharedRouteMapPreview`. That file was left unchanged per task scope. No updated emulator execution, real GCash checkout, webhook payment, or cash collection is claimed. No real payment was submitted.

After the build blocker is repaired, rebuild the app, open the affected Tourist booking, and verify the remaining-balance sheet opens automatically. Dismiss it and tap `Choose GCash or Cash`; press the payment-sheet action to see both methods. For a fresh normal-mode two-driver booking, verify one driver finishing does not enable payment, both finishing does, neither can depart unpaid, and confirmed settlement enables both drivers without restarting.
