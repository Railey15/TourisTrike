# Notification investigation — September 25, 2026

**The reported arrival did create exactly one persistent notification. Foreground rendering had a reproducible layout failure, now fixed and visually verified on the emulator. Android FCM remains blocked by missing real Firebase credentials.** GPS, itinerary progression, payment, map, convoy, and booking decision functions were not changed during this investigation.

## Root causes and actual pipeline evidence

The linked remote project is `mvtqhsrdgtwdeootgjci`. Remote SQL was executed through authenticated Supabase CLI access, not inferred from local migration files.

| Stage | Evidence / result |
| --- | --- |
| Arrival | Booking `b19410d6-a64c-4676-8690-80b78b7c68ca`, itinerary item `558ec9af-ff00-4518-920e-96044f4f8242`, iPlant Cafe, actual arrival `2026-09-24 18:27:44.41799 UTC` = September 25, **02:27:44 UTC+8**. Item `at_spot`, driver `at_stop`. Developer Test Mode false; required drivers = 1. |
| Event → history | Exactly one `spot_arrived` row: `6d6e129b-f688-4bf2-bf2f-332494483b47`, created at that same timestamp, title **Arrived at iPlant Cafe**, unread, push eligible. Actual body: “You have arrived at your next tour destination.” |
| Recipient | Tourist `9c7091f5-8797-4e72-a85d-585d65b3b312`. Driver `bec9af99-aff4-4742-991f-756d37da76b0` intentionally does not receive a self-push for their own arrival. The emulator was signed in as this driver. |
| RLS / history | An actual remote query under `authenticated` with the tourist's JWT claims could SELECT the unread arrival row. No access token was printed or needed for this database-role check. |
| Token | Remote `notification_devices` had **0 rows**, including **0 active devices for both test accounts**. Delivery queue also had 0 rows. A valid token was not obtained; this is not a successful registration claim. |
| Firebase runtime | Local `android/app/google-services.json` and `lib/firebase_options.dart` are absent. Device logs reported **Default FirebaseApp failed to initialize because no default options were found**. The latest emulator startup also recorded an initialization timeout; configuration remains unavailable. |
| Android permission | `POST_NOTIFICATIONS` is in the manifest; installed physical/emulator permission was **not granted**. Existing permission request UX is user-initiated from the center when Firebase is available; no repeated launch dialog. Grant flow could not be accepted without valid Firebase setup. |
| Server before repair | `send-notifications` was **not deployed**. `FIREBASE_SERVICE_ACCOUNT_JSON` and `NOTIFICATION_WORKER_SECRET` were absent. No worker Vault entries or `pg_cron` existed. |
| Foreground bug | `NotificationHost` is installed in `MaterialApp.builder`, **above** the Navigator's Overlay. Its dismiss `IconButton` tooltip threw **No Overlay widget found**, followed by **Trailing widget consumes the entire tile width** and **RenderBox was not laid out**. Runtime render inspection showed `Tooltip → ErrorWidget`, a full-width trailing control, and a banner with `size: MISSING`. Initial “displayed” logs alone were misleading; screenshots exposed this failure. |
| Foreground after repair | `Overlay.wrap` supplies the missing ancestor. A real backend-created diagnostic row was received through Realtime and a visible banner was captured **while Tour Navigation remained open at the destination**. Map and bottom action controls remained available. Firebase was still unavailable, proving independence from push setup. |

This explains separate failures: foreground presentation broke during layout; Android delivery could not proceed because Firebase initialization, device registration, and sender infrastructure were absent. The exact original event's foreground subscription timing cannot be reconstructed retrospectively, but the rendering failure was reproduced with real backend events.

### Authoritative arrival trace

1. `lib/screens/driver/driver_package_tracking_screen.dart` calls `advanceDriverJourneyState` from the existing GPS/action path.
2. `lib/core/supabase/touristrike_repository.dart` calls `advance_driver_journey_state` for arrival. Arrival validation remains authoritative even when other debug transitions are allowed.
3. Existing `persist_driver_stop_milestones` records `booking_driver_arrivals`, the itinerary's actual arrival, and `at_spot`. The tourist tracking screen maps `at_spot` to **At Tour Destination**.
4. Deferred notification observers on `booking_drivers` and `booking_driver_arrivals` call `emit_tour_notification` with the **same stable event key**. The unique partial `dedupe_key` index reduces these to one tourist row.
5. The row feeds two independent paths: recipient-filtered Realtime → app banner/center; queued registered-device deliveries → scheduled Edge Function → FCM HTTP v1.

There is no separate `notification_events` table or notification INSERT webhook. `notifications` is the persistent event/history record; database observers and the outbox/scheduler are the actual implementation. No tracking-screen status callback was made to invent notification rows or display a fake arrival snackbar.

## Remote deployment and migration history

The original `20260924000000_notification_delivery.sql` version was absent from remote migration history, **but its actual tables, functions, observers, indexes, RLS, token RPCs, queue RPCs, and Realtime publication already existed remotely**. The original recorded remote history consisted only of versions `20260829000000`, `20260829010000`, `20260829020000`, and `20260830000000`. This is schema/history drift, not proof that notification DDL was missing.

Completed during this investigation:

- Applied only `20260925000000_notification_runtime_diagnostics.sql`, then recorded **only that version** as applied. No blanket `db push`, `--include-all`, old migration replay, or unrelated history repair.
- Added independent `in_app_enabled` and a safe, own-device registration verification RPC. Historical push-eligible rows were backfilled without creating new events. Removed the actual remote legacy unrestricted INSERT policy; retained staff-scoped insertion and recipient-scoped reads.
- Deployed **`send-notifications`** using `--use-api` with its dedicated worker authentication (`verify_jwt = false` plus the secret check).
- Generated an actual cryptographically random worker secret, configured `NOTIFICATION_WORKER_SECRET`, and stored matching `notification_worker_secret` plus `notification_worker_url` in Vault. Values were not logged or committed.
- Installed the named scheduler jobs: eligible work every **10 seconds**, terminal delivery cleanup at **03:00 UTC**. Queried `cron.job` and `cron.job_run_details`; jobs were active and recent runs succeeded with no eligible deliveries. A successful idle cron run is **not** an FCM success.
- Called the deployed endpoint: no worker secret → **401 Unauthorized**; valid worker secret → **503 `FIREBASE_NOT_CONFIGURED`**. This proves the deployed authentication/configuration path. No OAuth or FCM request could be executed; no provider success is claimed. Live Edge log retrieval was not available through the installed tooling; the endpoint response and local handler identify the failure. Sanitized worker logs now cover authorization, claims, FCM responses, and acknowledgement failures.

Re-runnable read-only evidence commands:

```powershell
npx supabase db query --linked --file supabase/verification/notification_pipeline_read_only.sql
npx supabase db query --linked --file supabase/verification/notification_arrival_evidence.sql
npx supabase migration list
npx supabase functions list
```

For another environment, inspect first. If base notification objects are absent, apply only the base notification migration after checking its prerequisites, then the runtime repair. If they already exist as here, apply only the runtime repair. Mark a version applied only after verifying that exact SQL succeeded. Existing unrelated migration-history drift remains deliberately unresolved.

## Flutter repair

- Banner host now has its own Overlay, safe-area handling, an animated size transition, dismissal, and independent readiness. It does not require the home bell to be built first.
- Opening the center schedules its initial refresh after the route's first frame, preventing a shared-notifier `setState during build` exception affecting the underlying bell.
- Live Realtime/FCM receipt deduplicates by persistent ID without rejecting a live event solely because its timestamp differs from the device clock. History refresh/reconnect does not replay banners.
- In-app eligibility is independent of FCM permission, token, sender availability, and push preference; persistent history remains independent of both transports.
- Firebase/background-handler setup is awaited before `runApp`; network history/token work runs independently. The existing top-level background handler lets Android display the notification payload, avoiding duplicate local notifications. No second notification plugin was added.
- Debug diagnostics report Firebase, permission, token, verified Supabase registration, Realtime, and presentation status. Errors report stage and safe error code/type, without credentials or full tokens. Banner logging now checks for a successfully laid-out render box.
- Registration still handles `getToken`, `onTokenRefresh`, resume, and logout/account changes; it now confirms the server row through the own-device RPC. Actual token generation/rotation remains unverified until Firebase is configured.

## Device and test results

| Check | Physical Android 16 | Google Play emulator, Android 17 |
| --- | --- | --- |
| Permission at inspection | Not granted | Not granted |
| Firebase initialized / valid FCM token | Failed configuration; no token row | Failed configuration; no token row |
| Token registered remotely | No | No |
| Foreground FCM receipt | Blocked, not tested successfully | Blocked, not tested successfully |
| Realtime foreground banner after fix | Not tested; physical ADB device disconnected | **Passed visually on Tour Navigation**, from a real backend event |
| Background / locked / terminated FCM | Blocked | Blocked |
| Persistent center | Tourist's actual arrival is readable under its remote RLS identity; fixed physical app not tested | **Passed:** diagnostic events remained visible after auto-dismiss and navigation to the bell |

The diagnostic notification used **TourisTrike Test / In-app notification delivery is working.** It did not falsely claim that push was configured. Six isolated diagnostic rows were created for the driver during rendering investigation; five intermediate test rows were subsequently removed by their exact IDs, retaining the successful final test `84a91a65-3371-4279-858d-6e0697d53306`. No real history was deleted and the source booking was not advanced. Replaying an identical event key returned the same row ID and generated no second INSERT/banner. The original iPlant Cafe arrival remained exactly one unread record. A fresh GPS arrival and complete physical-device FCM acceptance were **not** reproduced.

Local validation: **64 notification PostgreSQL checks, 86 existing journey/GPS checks, 3 FCM payload/result tests, and 18 targeted Flutter tests passed**. Deno type checking and targeted Flutter analysis passed. The SQL fixture exercises solo/convoy event gates, both arrival observers, deduplication, GPS/ETA silence, payment/emergency events, RLS, opt-outs, token ownership/account switching, queues and retries; it does not pretend to validate real Firebase transport. Flutter tests include a regression that mounts the banner in **MaterialApp.builder above the Navigator**, asserts no layout exception, verifies separate geometry, dismissal and timeout. APK compilation and emulator installation succeeded; actual physical installation after this repair is not claimed.

Local visual proof is saved at `build/notification-investigation/tracking-banner.png` (ignored build artifact). These screenshots contain test account/tour information and were not committed into public assets.

The final APK was rebuilt and reinstalled after the center refresh fix. After a fresh process launch, Realtime subscribed and the final test remained visible in the Notification Center. The inspected notification logs contained the expected missing-Firebase initialization failure and no Overlay/layout or `setState during build` errors. Final runtime Firebase initialization returned `PlatformException`; it still did not succeed.

## Remaining setup required from the project owner

1. Register Android application **`com.example.touristrike`** in the intended Firebase project. Place its real downloaded config at **`android/app/google-services.json`**. Native Android resources are used by `Firebase.initializeApp()`; a separate `firebase_options.dart` is optional for this native Android path. The registered Firebase package/project cannot be verified until the actual config exists.
2. Enable FCM HTTP v1 in that same project. Configure the **real service-account JSON** as the Supabase Edge secret **`FIREBASE_SERVICE_ACCOUNT_JSON`**. Keep the private key out of Flutter and source control. The worker secret, Vault configuration, migration repair, and Edge deployment above are already done; do not replace the worker secret with a placeholder.
3. Put just the missing secret in a private env file outside the repository, with compact JSON on one line, then run:

```powershell
npx supabase secrets set --env-file C:\private\touristrike-firebase.env
flutter build apk --debug --no-pub
```

The file must contain `FIREBASE_SERVICE_ACCOUNT_JSON=<actual compact service-account JSON>`. That placeholder is documentation, not a usable credential. No further DB push or function redeployment is required for the currently deployed repair.

4. Install the rebuilt APK on the physical device and emulator, sign into the intended tourist/driver account, and use **bell → Enable notifications**. Debug diagnostics must show Firebase initialized, authorized permission, token obtained, and **Verified on Supabase**. Check the server counts without selecting token values.
5. Only after registration succeeds, send the requested isolated push from the trusted backend: **TourisTrike Test / Push notifications are configured correctly.** Use [notification_test_push.sql](../supabase/verification/notification_test_push.sql), filling in the intended recipient and a unique test key. The script refuses an unregistered recipient. Run separately for foreground, minimized, and locked states; inspect delivery status and FCM response before calling each successful. Test notification tap from background/terminated state, then a real tourist arrival, convoy aggregation, and duplicate suppression. Do not force old expired arrival history back into the delivery queue.

Firebase's foreground notification messages require app presentation; see [Firebase Flutter message handling](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages). The app's Realtime banner now works without FCM, while Android tray delivery still needs the missing Firebase setup.

## Exact files changed during this investigation

- `lib/main.dart`
- `lib/core/notifications/notification_diagnostics.dart` (new)
- `lib/core/notifications/notification_service.dart`
- `lib/core/notifications/notification_presentation_guard.dart`
- `lib/core/notifications/tour_notification.dart`
- `lib/widgets/notification_host.dart`
- `lib/screens/shared/notification_center_screen.dart`
- `supabase/migrations/20260925000000_notification_runtime_diagnostics.sql` (new)
- `supabase/functions/send-notifications/index.ts`
- `supabase/verification/notification_pipeline_read_only.sql` (new)
- `supabase/verification/notification_arrival_evidence.sql` (new)
- `supabase/verification/notification_test_push.sql` (new)
- `supabase/tests/notification_regression.mjs`
- `test/notification_model_test.dart`
- `test/notification_presentation_test.dart`
- `docs/NOTIFICATION_SYSTEM.md`
- `docs/NOTIFICATION_INVESTIGATION.md` (new)

Earlier notification implementation files were already uncommitted when this investigation started. Their full feature inventory is in `NOTIFICATION_SYSTEM.md`; they were preserved. Ignored build/capture utilities and the CLI-generated version cache are not application changes.
