# Automatic tour navigation

The driver location stream sends evidence to `observe_driver_journey_location`.
The RPC locks the booking then the authenticated driver's assignment, selects
only its persisted expected destination, and calls the existing
`advance_driver_journey_state` / `complete_current_itinerary_item` functions.
Existing convoy, payment, service-area and notification rules remain in place.

## Verification rules

- Entry: distance plus reported accuracy must fit within the server's arrival
  radius (currently 150 m); accuracy must be at most 50 m, speed 0–2 m/s.
- Arrival requires at least four distinct fixes spanning 15 seconds of both
  sample time and server receipt time. No burst of client events supplies dwell.
- Departure requires an already confirmed arrival, distance minus accuracy at
  least arrival radius plus 100 m (currently 250 m), speed at least 1 m/s, and
  four fixes spanning 12 seconds of both clocks.
- Fixes older than 20 seconds, more than two seconds in the future, invalid
  coordinates/accuracy/speed, and gaps over 20 seconds cannot establish dwell.
  Duplicate/out-of-order samples never advance the lifecycle.
- GPS-confirmed departure records the actual departure even when planned stay
  has not elapsed. Planned arrival/departure/stay values are never rewritten.
  Manual recovery retains the existing minimum-stay requirement.
- Verified final arrival completes through the existing all-driver finalizer.
  A reversed/unconfirmed payment leaves verified arrival in completion-pending.
- One mutable evidence row per assignment; compact evidence is retained only
  for milestones in `trip_status_logs`, not as continuous GPS history.

## Interruption and recovery

Cron runs `reconcile_stale_tour_tracking()` every five minutes. A started tour
becomes interrupted when its estimated end is more than two hours ago and any
unfinished driver has neither usable tracking nor progress for 30 minutes.
Missing estimates fall back to scheduled start plus 12 hours, then assignment
acceptance plus 12 hours for legacy records. Time never marks a tour completed.

Interruption is an orthogonal, server-owned `tracking_interrupted_at` field:
financial and itinerary state stay intact. Activity lists and driver overview
exclude it from the normal Active count and retain access for recovery. Existing
booking/availability restrictions still apply until the unfinished tour is
resolved. Fresh tracking/progress clears interruption only when no unfinished
driver still satisfies the stale condition.

Opening navigation or resuming the app reloads authoritative assignment/index
and tracking status. Normal operation uses the existing location stream with
three-second upload throttling; a recovery fix is attempted every 30 seconds
only when recent usable GPS is absent. It does not replay offline coordinates.
Manual recovery requires a 10–500 character reason, binds the request to the
displayed stage/index, and logs the change. Arrival recovery still needs recent
driver proximity or corroborating tourist GPS. Clients cannot write evidence or
the interruption flag, or directly update protected journey stages/indexes.

Android currently has foreground location permission only. This implementation
does not add an Android background service: location can stop when the screen is
disposed, the OS suspends the process, permission is revoked, or the app is
force-stopped. Reopen Trips → All → the interrupted/unfinished tour to resume.
Missed stops/departures are not invented. Use audited recovery when a confirmed
arrival or departure was missed during a tracking interruption. GPS still
cannot prove passengers boarded/alighted or resist device-level spoofing.

## Release and verification

Apply `20260927000000_automatic_tour_progression.sql` before releasing the client.
It replaces only the affected canonical function definitions and adds the GPS
evidence RPC/storage, guards, and interruption job. Coordinate client rollout:
legacy unaudited arrival/departure/completion RPC calls will be rejected.
Do not blanket-push older migrations into a drifted linked database.

Deployed to the linked project on 2026-09-25 as a single transactional migration,
then verified and recorded in migration history. All 11 function definitions and
23 deployment checks matched; the five-minute pg_cron job ran successfully.
See [migration reconciliation](SUPABASE_MIGRATION_RECONCILIATION.md) for repaired
history entries, outstanding historical drift, and regression results. Normal
`db push` remains blocked by unresolved older migrations; do not replay them.
For other environments, run `supabase/tests/verify_automatic_tour_progression.sql`
after deployment. Environments without pg_cron must provision the same five-minute
job before being considered ready; the migration emits a notice when it is absent.

Local SQL regression: `node supabase/tests/automatic_tour_progression_regression.mjs`.
It runs actual PostgreSQL functions in the existing isolated PGlite fixture.
Test-only timestamp adjustments simulate intervals; they are not a production
clock override. Flutter contract/model tests:
`flutter test test/automatic_tour_tracking_test.dart`.

## Android acceptance flow

1. Use a disposable, normally authorized booking with two distinct stops and a
   distinct drop-off, each more than 500 m apart. Confirm the downpayment; use
   accurate Android location and stable internet. Open driver tour navigation
   and press Start once. Test normal payment rules with debug bypass disabled.
2. At pickup, stop within 100 m for at least 20 seconds with accuracy below 50 m.
   Observe Detecting Arrival → Arrived. Board passengers, then leave beyond
   300 m at more than 1 m/s for at least 15 seconds. The first stop activates.
3. Pass near the second stop before reaching the first; the expected stop must
   remain the first. Pass the first at road speed; no arrival. Stop inside its
   entry zone for 20 seconds; observe arrival. Move within the 150–250 m band;
   no departure. Leave beyond 300 m in sustained motion; next stop activates.
4. Force-stop/reopen while arrived at the second stop. Open the same tour from
   Trips → All; it must retain its stop/index and arrival. Re-enable GPS/internet
   if interrupted. Leave the exit zone in sustained motion; no Next button.
5. Confirm the remaining payment through the existing payment flow. Stop at
   drop-off within 100 m for 20 seconds. Observe automatic Completed, actual
   timestamps, and existing notifications. With two drivers, repeat independently
   and confirm the whole booking finishes only after both finish.
6. Separately simulate an overdue disposable booking with stale progress in the
   test database. After the five-minute job it must read Interrupted, never
   Completed. Reopen, verify the saved stop, and resume fresh tracking. Disable
   GPS/internet and verify no new transitions; exercise manual recovery with a
   reason and inspect the audit log.
