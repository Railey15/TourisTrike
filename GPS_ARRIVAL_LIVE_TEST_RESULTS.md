# GPS arrival deployment and live test results

Verified September 6, 2026. No already-PASS source logic or IncomingRideScreen was changed in this follow-up.

## Deployment

The two prepared migrations were already applied when this session began. Read-only inspection confirmed every function body matches its local migration exactly after normalizing CRLF. No redundant remote schema writes were issued.

| Function | Signature | Exact body match |
| --- | --- | --- |
| `debug_advance_driver_journey_state` | `p_booking_id uuid, p_target_state text` | true |
| `driver_arrival_radius_meters` | no arguments; returns double precision | true |
| `guard_live_driver_journey_proximity` | no arguments; returns trigger | true |
| `confirm_driver_arrival_fallback` | `p_booking_id uuid, p_reason text` | true |

The complete SQL is in these existing files, in application order:

1. [Testing Mode GPS enforcement](supabase/migrations/20260906030000_keep_debug_arrivals_gps_verified.sql)
2. [Centralized radius and fallback](supabase/migrations/20260906040000_centralize_driver_arrival_radius.sql)

Exact commands to apply those definitions to a database that still needs them:

```powershell
supabase db query --linked --file supabase/migrations/20260906030000_keep_debug_arrivals_gps_verified.sql
supabase db query --linked --file supabase/migrations/20260906040000_centralize_driver_arrival_radius.sql
```

No Edge Functions or generated database types require deployment. A blanket `supabase db push` is not needed for these already-applied functions. The project's migration ledger contains older gaps, so the specific file commands also avoid replaying unrelated migrations.

Run [verify_deployed_gps_arrival.sql](supabase/tests/verify_deployed_gps_arrival.sql) in SQL Editor for exact signatures, definitions, prepared-body hashes, radius value, trigger attachment, and realtime publication membership.

## One radius source

`public.driver_arrival_radius_meters()` is authoritative and returns **150 metres**. `TourisTrikeRepository.fetchDriverArrivalRadiusMeters` calls that RPC. `DriverPackageTrackingScreen._load` uses the returned value to construct `StableArrivalDetector`; all three arrival targets use it. Both the SQL proximity guard and corroborated fallback call the same function. There is no separate Flutter numeric fallback. The app reads configuration when loading the screen, so reopen the tracking screen after intentionally changing the radius.

## Installed app

The emulators initially ran an older build that still showed Arrived at Pickup — TEST. Built the current source and installed it without clearing data:

```powershell
flutter build apk --debug
$adbTool = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
foreach ($serial in @('emulator-5554','emulator-5556','emulator-5558')) {
  & $adbTool -s $serial install -r build/app/outputs/flutter-apk/app-debug.apk
  & $adbTool -s $serial shell am start -n com.example.touristrike/.MainActivity
}
```

The current app showed passive automatic-GPS notices and the intended passenger/proceed actions.

## Live scenario and results

- Booking: `e0b6f65e-8dab-419a-ad81-13d6a356df4f` (Capstone Testing), verified by `is_developer_test_booking` as a registered test booking.
- Tourist: emulator-5554.
- Driver A / Juan Dela Cruz: emulator-5556, driver `a912c958-1991-4b8f-8afc-9603ffae2a67`.
- Driver B / Bench Railey: emulator-5558, driver `59a7c2c3-817d-4ec3-b970-18be5c94fc39`.
- Initial state: A already en route to pickup; B already boarded before this session. No states were reset or forced through SQL. This was a live two-driver booking, not a newly created one-driver booking.

| Check | Observed result |
| --- | --- |
| Outside pickup radius | A remained `en_route_pickup` with GPS at latitude 14.9200, longitude 120.9000, over 150 m away. |
| Pickup arrival | Moving A to latitude 14.9261133, longitude 120.8986933 produced `at_pickup` at **01:51:31.370967 UTC**. One pickup-arrival log. Driver action became Tourist Picked Up; Tourist card became At Pickup without refresh. B remained Passengers Boarded. |
| First stop, A only | A reached Cafe Galilea Bustos at **01:53:31.308904 UTC**. Tourist showed A At Stop and B En Route to Stop. B had no arrival row for this stop yet. |
| First stop, then B | Moving B to that stop produced its own arrival at **01:54:19.585585 UTC**. Tourist then showed both At Stop without refresh. |
| Second stop | Both reached Bustos Municipal Hall through GPS and saved distinct `at_stop` transitions at index 1. |
| Third stop | Both reached Cafe Portillo through GPS and saved distinct `at_stop` transitions at index 2. |
| Stay bypass | The existing Proceed/Finish buttons worked in authorized Testing Mode while displayed 60-minute stays still had time remaining. No manual arrival button was used. |
| Payment bypass | The existing configured test path allowed the drop-off leg without submitting a payment. No PayMongo checkout or payment-confirmation action was invoked. |
| Drop-off, A only | A reached `at_dropoff` at **02:03:39.278049 UTC**. Tourist showed A At Drop-off and B En Route to Drop-off. A's primary action became Tourist Dropped Off. |
| Drop-off, then B | Moving B near drop-off produced `at_dropoff` at **02:04:35.487804 UTC**. Tourist showed both At Drop-off without refresh. Each driver had exactly one drop-off-arrival log. |

The Tourist screen stayed open from pickup onward; only scrolling was used to expose the driver cards. No refresh button, ETA refresh button, navigation away/reopen, or manual arrival fallback was used during delivery checks. Backend state changes came from the actual app's GPS path; SQL was used only to inspect results.

Both drivers are intentionally left **at_dropoff**, awaiting Tourist Dropped Off. Their assignments were not marked completed by this test. All three itinerary stops have been completed through the existing test-mode UI actions. Starting a new trip from `assigned` and a separate one-driver booking were not rerun; the procedures below cover those fresh-start checks.

Saved screenshots under the local ignored build directory:

- [Pickup realtime result](build/tourist-pickup-live.png)
- [A at stop, B still en route](build/tourist-stop-a-only.png)
- [Both at stop](build/tourist-stop-both-arrived.png)
- [A at drop-off, B still en route](build/emulator-5554-dropoff-a-only.png)
- [Driver drop-off confirmation button](build/emulator-5556-dropoff-a-only.png)
- [Both at drop-off](build/tourist-dropoff-both.png)

## Repeat with one Tourist and one Driver

Use a fresh test booking requiring one driver, and open the Tourist tracking screen and the driver's package Tour Navigation screen. For normal-mode payment testing, satisfy actual required payments instead of using the developer bypass. For Testing Mode, use the existing registered test booking controls.

1. Keep the driver more than 150 m from pickup. Press Start Navigation to Pickup. Driver: Heading to pickup, no arrival button. Tourist: En Route to Pickup. Database: `en_route_pickup`.
2. In emulator Extended Controls → Location, send the booking's exact pickup coordinates. Send at least three distinct valid fixes over six seconds; allow up to about 20–30 seconds for fix/recovery/network processing. Driver: At Pickup, Tourist Picked Up button. Tourist: At Pickup, automatically. Database: `at_pickup` and one arrival log.
3. Press Tourist Picked Up. Once the driver enters `en_route_stop`, move GPS to that itinerary item's coordinates. Driver: actual arrival, stay countdown, expected departure. Tourist: At Stop and updated itinerary. After stay or authorized test bypass, press Proceed to Next Stop.
4. Repeat stops. Finish Tour Stops. In normal mode, settle the remaining balance through the existing flow; in configured Testing Mode, the existing bypass permits departure. Wait for `en_route_dropoff` before testing final arrival.
5. Move GPS to drop-off. Driver: At Drop-off and Tourist Dropped Off button. Tourist: At Drop-off without refresh. Merely arriving must not complete the assignment.

ADB alternative for each target (arguments are **longitude, then latitude**):

```powershell
$adbTool = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
# This example uses the tested booking's pickup/drop-off coordinates.
# Substitute the actual target for a different booking or stop.
foreach ($fix in 1..6) {
  & $adbTool -s emulator-5556 emu geo fix 120.8986933 14.9261133
  Start-Sleep -Seconds 3
}
```

## Repeat with Tourist, Driver A, and Driver B

Use a fresh booking requiring two drivers. Both must accept and start pickup navigation. Keep both initially outside the radius. Move A near pickup while B remains outside; Tourist must show A At Pickup and B En Route to Pickup. Then move B near pickup; its card must independently become At Pickup. Confirm boarding for each driver to continue the convoy.

At the next stop, leave B outside while moving A inside; verify A At Stop and B En Route to Stop on the open Tourist screen. Then move B inside and verify its separate arrival. Repeat the same isolation for drop-off. Check unique driver/stop arrival rows and log counts rather than relying only on the shared summary card, which intentionally reflects convoy progress.

## Remaining issue outside this scope

Live Google Maps route/ETA requests returned `REQUEST_DENIED` with the message that billing must be enabled on the Google Cloud project. GPS proximity and Tourist realtime delivery succeeded independently. No Maps/billing configuration or unrelated source was changed. This prevents claiming fresh route/ETA calculation passed during this test.
