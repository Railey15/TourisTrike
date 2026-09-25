# TourisTrike notifications

Updated September 25, 2026. The actual remote notification schema was inspected, the scoped runtime repair and `send-notifications` were deployed, and the worker secret/Vault/scheduler were configured. Foreground Realtime delivery was visually verified on the emulator tracking screen. **FCM remains blocked by missing Firebase configuration.** See [the investigation, evidence, deployment status, and remaining acceptance checks](NOTIFICATION_INVESTIGATION.md).

## Architecture and inspected source of truth

Supabase owns events, recipients, persistent history, authorization, and delivery attempts. Firebase is only the Android transport. The existing `notifications` table, `user_id`, and partial unique `dedupe_key` index are reused.

The inspected current migrations use UUID booking/itinerary/driver IDs. The earliest core migration contains older bigint definitions and is not a faithful fresh-install baseline. The new migration targets the current schema used by the existing journey RPCs; isolated tests use that current schema shape. The delivery queue uses text notification IDs to support the existing notification ID variations without changing the history table's primary key.

| Source | Actual values / behavior | Notification use |
| --- | --- | --- |
| `package_bookings.status` / `booking_status` | `pending`, `waiting_for_drivers`, `approved`, `driver_on_the_way`, `on_tour`, `awaiting_remaining_payment`, `cancelled`, `rejected`, `completed` / `done` | Submission, approval, remaining balance due, cancellation, completion; schedule changes |
| `package_activities` | Shared mirror: `pending`, `accepted`, `ongoing`, `completed`; `tour_status` includes `waiting_driver`, `driver_accepted`, `driver_en_route`, `driver_arrived`, `picked_up`, `en_route_to_spot`, `at_spot`, `on_tour`, `en_route_to_dropoff`, `ready_to_complete` | Deliberately not a second event source; avoids duplicate notifications from mirrored writes |
| `booking_drivers.status` | `pending`, `accepted`, `rejected`, `completed`; cancellation logic also handles cancelled rows | Targeted assignment, full roster acceptance, material assignment release |
| `booking_drivers.journey_state` | `assigned`, `en_route_pickup`, `at_pickup`, `boarded`, `en_route_stop`, `at_stop`, `stop_done`, `en_route_dropoff`, `at_dropoff`, `completed` | Canonical journey milestones after existing RPC/GPS validation |
| `booking_itinerary_items.spot_status` | `pending`, `travelling`, `at_spot`, `completed` | Destination names/order resolved from this table; actual per-driver progress determines aggregate notifications |
| `booking_driver_arrivals` | Unique driver/item GPS arrival records | Covers the older `mark_itinerary_stop_arrived` RPC too, using the same event key as journey arrivals |
| `payment_records.status` | `pending_confirmation`, `confirmed`, `disputed`, `cancelled` | Confirmed payments; **there is no assumed `failed` payment status** |
| `payment_records.provider_status` | PayMongo `failed`, `checkout_failed`, `cancelled`, `expired` | Actionable failure, including checkout failure while status remains `pending_confirmation` |
| `booking_payment_requirements` | `required`, `satisfied`, `waived`; stages `down_payment`, `remaining_balance` | Downpayment prompt. Remaining requirement creation alone is intentionally silent because it can be created before the itinerary ends |
| `payment_allocations.status` | `awaiting_cash` | Prompt only the driver whose share needs confirmation |
| `emergency_alerts` | New `active` alert with stable alert ID | Accepted booking drivers, provincial admins, and matching-city subtenant staff; booking/tourist association checked |

Existing functions remain responsible for business decisions: `accept_package_booking`, `advance_driver_journey_state`, `guard_live_driver_journey_proximity`, `persist_driver_stop_milestones`, `mark_itinerary_stop_arrived`, `complete_current_itinerary_item`, `required_booking_driver_roster`, payment/webhook RPCs, and `finalize_package_booking_if_eligible`. None of these functions was rewritten.

The old available-job trigger's recipient selection is retained. Its notification is enriched with a booking link and generic copy. Existing cancellation and per-driver arrival inserts are suppressed only when replaced by the canonical observers. Emergency client-side notification inserts were moved into the trusted database observer; emergency email submission is unchanged. Old history rows are retained.

Flow: confirmed database transition → notification observer → persistent notification + device delivery rows → scheduled Edge worker → FCM. Realtime updates the shared Flutter service and bell. Push delivery never runs inside a booking/payment transaction. Notification observer errors emit PostgreSQL warnings instead of aborting source transactions. A queue insert failure leaves history intact; the worker reconciles missing deliveries from recent history. Notification-generation warnings require operational investigation; they are not silently presented as successful delivery.

## Events and convoy behavior

Implemented: booking submitted (history only), booking approved, drivers assigned (aggregate history), tour confirmed, targeted driver assignment, eligible new job, downpayment required/confirmed, payment complete/failure, cash confirmation required, driver on the way, partial pickup arrival (history only), all drivers arrived, tour started, heading to a spot / next destination, aggregate arrival at a spot, convoy ready for other drivers at a completed stop, remaining balance due, heading to drop-off, arrival at drop-off, tour completed, booking cancellation/rejection, driver assignment changed, schedule updated, and emergency alert.

The required roster comes from the existing `required_booking_driver_roster` function and `required_drivers` count. Deferred driver observers see the final state of multi-row transactions. One of two pickup arrivals records “1 of 2 drivers have arrived…” without push; a single aggregate push follows when both required drivers have arrived. A missing roster slot cannot satisfy an all-drivers gate. Stop movement and arrival pushes also wait for the full roster. Individual driver acceptance and the driver's own button/GPS action do not generate self-push. Only other drivers receive a convoy-ready alert.

No new events are generated by coordinates, ETA recalculation, map refresh, route updates, reconnects, screen builds, tab changes, profile refresh, normal synchronization, polling, typing/presence, unchanged statuses, or intermediate provider states. There is no extra tourist “spot completed” push immediately before “Next Destination.” Existing shared-link access history is retained as center-only and never becomes Android push. Developer-test bookings are suppressed through the existing `is_developer_test_booking` predicate. No guest registration, guest push, new public notification API, or shared-trip data exposure was introduced.

## Privacy, deduplication, and failure handling

- Stable event keys include booking/stop/payment/alert identity and recipient, enforced by the existing unique partial index. Driver journey and persisted stop-arrival observers share their arrival key.
- Notification RLS allows only the recipient to read rows. Clients may change only `is_read` and `read_at`; staff's existing ordinary history insertion remains column-limited. Push flags, routing metadata, and event identities are backend-only.
- Tokens are server-only rows with one installation binding and support multiple devices per user. Registration handles refresh/account switching. Tourist and driver sign-out revoke the binding and delete the local FCM token on a best-effort basis. Resume refreshes the registration.
- Delivery jobs are unique per notification/device, claimed with `FOR UPDATE SKIP LOCKED`, a two-minute lease, and a per-claim fence. The worker checks the current user/installation/token binding again immediately before sending.
- Eight maximum delivery attempts, exponential retry, invalid-token deactivation only on FCM `UNREGISTERED`, and explicit failed/skipped states. Expired events remain in history but are no longer pushed (15 minutes for emergencies; one hour for regular events). Tokens not refreshed for 60 days are not targeted. A daily job removes terminal delivery attempts after 30 days, retaining notification history.
- FCM has no transactional exactly-once acknowledgement shared with PostgreSQL. If a send succeeds and its acknowledgement is lost, a retry is possible. Stable Android notification tags replace the same visible tray entry; the foreground guard deduplicates FCM plus Realtime. A guarantee of exactly one audible alert under every network failure is not claimed.
- Lock-screen payloads omit coordinates, tourist notes, payment references, and credentials. Android visibility is private. The payload carries only `notification_id`; `notification_destination` rechecks ownership and current booking membership before returning a supported destination. Old messages without booking metadata fall back to history.
- Where the optional legacy `notification_settings` table and user row exist, booking/driver/payment preferences remain editable and respected by the backend. History persists even when push is opted out. Emergency pushes still obey Android permissions and channel settings.

## Flutter and Android behavior

Both home screens use one bell and a badge capped at `9+`. The shared center has Today/Yesterday/Earlier groups, relative time, compact rows, unread emphasis, mark-all-read, pagination, pull-to-refresh, error/empty states, and optional existing preferences. The old tourist profile route is a compatibility wrapper to this screen.

Foreground: recipient-filtered Realtime plus FCM feed one non-modal, five-second banner in its own layout space above the navigator, so map and action controls remain uncovered. History reload/reconnect does not produce a backlog of banners. Background/locked: Android displays the FCM notification payload. Terminated launch: `getInitialMessage` stores a pending tap until the authenticated tourist/driver home is ready. Background taps use `onMessageOpenedApp`. The background handler does not insert history or display a second copy.

Tourist events open the existing booking tracking screen, which already contains payment and completed-tour/feedback controls. Accepted driver events open existing tracking; new jobs open the existing driver job list, which reapplies dispatch eligibility. Unsupported/stale resources fall back to history. No booking/payment control flow was replaced.

Permission is requested only from the explanatory “Stay updated on your tour” action in the center. There is no launch-time permission nag. Denial does not disable history. Android channels are Tour Updates and Payment Updates at default importance, and Emergency Alerts at high importance. Normal transport priority is NORMAL; emergency transport priority is HIGH. System sound, vibration, notification visibility, power management, and permission choices remain authoritative. FCM delivery after an Android Settings force-stop requires reopening the app; this is an Android/FCM constraint, not a retry promise. See [Firebase message handling](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages).

## Firebase configuration you must provide

1. Create/select a Firebase project and register the Android application ID **`com.example.touristrike`**, matching `android/app/build.gradle.kts`. If you intentionally change the application ID for release, register that exact ID instead.
2. Download its real `google-services.json` into **`android/app/google-services.json`**. The path is git-ignored. No placeholder configuration or server key is in Flutter. Initialization safely leaves history available if this file is absent.
3. Enable Firebase Cloud Messaging API (HTTP v1) for the Firebase project. Create a dedicated service account permitted to send FCM messages in that project. Download its JSON key and keep it outside the repository; store its **complete compact JSON** as the Supabase Edge secret **`FIREBASE_SERVICE_ACCOUNT_JSON`**. It must contain `project_id`, `client_email`, and `private_key` from the actual account. Never put this JSON into app assets, `google-services.json`, Flutter defines, or public environment variables.
4. Generate a separate cryptographically random worker secret, e.g. at least 32 random bytes. Store it as the Supabase Edge secret **`NOTIFICATION_WORKER_SECRET`**. The scheduler will use the matching value in Supabase Vault.
5. Use a physical Android device with Google Play Services or a Google Play/Google APIs emulator. Open the app, sign in, open the bell, and enable notifications. No Firebase database or Firebase Auth migration is needed. See [Firebase Android setup](https://firebase.google.com/docs/android/setup) and [FCM Flutter setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started).

Android permission, channels, icon, and conditional Google Services Gradle integration are implemented in source. Your remaining Android setup is the real `google-services.json`, permission on the device, and your existing release signing process. Added Flutter packages: `firebase_core: ^4.15.0`, `firebase_messaging: ^16.7.0`. Native plugin registrants were regenerated by Flutter.

## Deployment commands and scheduler

For the linked project, the repair, sender, worker secret, Vault entries, and scheduler have now been deployed. The remaining setup is the real Firebase client file and server secret; see the investigation report. Do not run a blanket `db push` or `db push --include-all`: remote history is incomplete although notification objects already exist. For a different environment, inspect the actual schema first and apply only the required notification SQL files, then record only versions actually applied.

```powershell
flutter pub get
npx supabase secrets set --env-file C:\private\touristrike-notifications.env
npx supabase functions deploy send-notifications --use-api
flutter build apk --debug
```

The private env file contains only the actual server values, with the JSON compacted onto one line:

```dotenv
FIREBASE_SERVICE_ACCOUNT_JSON=<your actual compact service-account JSON>
NOTIFICATION_WORKER_SECRET=<your actual random worker secret>
```

Do not copy these placeholder strings as credentials. On the current linked project, configure only the missing `FIREBASE_SERVICE_ACCOUNT_JSON`; the worker secret is already configured and must match Vault. The Edge runtime already supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`; do not copy the service-role key into Flutter. This checkout's earliest migrations differ from its current UUID schema.

In Supabase Vault, create:

- `notification_worker_url`: your project's `https://<project-ref>.supabase.co/functions/v1/send-notifications` URL.
- `notification_worker_secret`: the same actual value as `NOTIFICATION_WORKER_SECRET`.

Then run **`supabase/notification_worker_schedule.sql`** in the Supabase SQL Editor. It enables `pg_cron`/`pg_net`, checks the Vault prerequisites, schedules eligible work every ten seconds, and adds delivery retention cleanup. Re-running the named schedule updates it. The Edge Function deliberately has `verify_jwt = false` because it authenticates the dedicated server secret itself; an ordinary user JWT or anon key is insufficient. This follows the [Supabase scheduled Edge Function pattern](https://supabase.com/docs/guides/functions/schedule-functions).

Verify `cron.job_run_details`, Edge logs, and grouped `notification_deliveries.status` counts after deployment. Do not log device tokens or service-account JSON. Fix provider configuration before manually requeueing failed jobs; expired history should remain history instead of becoming a late push storm.

## Files added and changed

Database/backend:

- `supabase/migrations/20260924000000_notification_delivery.sql` — the single added schema/RLS/observer/outbox migration.
- `supabase/functions/send-notifications/index.ts` — the single new Edge worker.
- `supabase/functions/send-notifications/delivery.ts` — HTTP v1 payload, OAuth signing, and result classification.
- `supabase/config.toml` — worker authentication configuration.
- `supabase/notification_worker_schedule.sql` — explicit post-deploy scheduling.

Flutter:

- `lib/core/notifications/tour_notification.dart`
- `lib/core/notifications/notification_service.dart`
- `lib/core/notifications/notification_presentation_guard.dart`
- `lib/widgets/notification_bell.dart`
- `lib/widgets/notification_host.dart`
- `lib/screens/shared/notification_center_screen.dart`
- `lib/screens/tourist/profile/notifications_screen.dart`
- `lib/screens/tourist/tourist_home_screen.dart`
- `lib/screens/driver/driver_home_screen.dart`
- `lib/screens/tourist/profile/tourist_profile_screen.dart`
- `lib/screens/driver/profile/driver_profile_screen.dart`
- `lib/core/services/emergency_service.dart`
- `lib/main.dart`
- `pubspec.yaml`, `pubspec.lock`

Platform and tooling:

- `android/settings.gradle.kts`
- `android/app/build.gradle.kts`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/example/touristrike/MainActivity.kt`
- `android/app/src/main/res/drawable/ic_notification.xml`
- `macos/Flutter/GeneratedPluginRegistrant.swift`
- `windows/flutter/generated_plugin_registrant.cc`
- `windows/flutter/generated_plugins.cmake`
- `.gitignore`

Tests and documentation:

- `supabase/tests/notification_regression.mjs`
- `test/notification_delivery_test.mjs`
- `test/notification_model_test.dart`
- `test/notification_presentation_test.dart`
- `docs/NOTIFICATION_SYSTEM.md`

`pubspec.lock` and the macOS registrant already had local changes at task start; those files were not reset to HEAD. Firebase additions are included alongside the prior working-tree state.

## Original implementation verification (September 24)

The following is the earlier local validation record. For September 25 remote and device findings, see [NOTIFICATION_INVESTIGATION.md](NOTIFICATION_INVESTIGATION.md).

Commands used:

```powershell
npm install --prefix build/sql-validation --no-audit --no-fund @electric-sql/pglite
node supabase/tests/notification_regression.mjs
node supabase/tests/event_driven_trip_regression.mjs
node --test test/notification_delivery_test.mjs
flutter test test/notification_model_test.dart test/notification_presentation_test.dart test/emergency_service_test.dart test/driver_page_header_test.dart test/widget_test.dart
flutter analyze --no-pub lib/core/notifications lib/widgets/notification_bell.dart lib/widgets/notification_host.dart lib/screens/shared/notification_center_screen.dart lib/screens/tourist/profile/notifications_screen.dart lib/main.dart
npx --yes deno check --node-modules-dir=auto --no-lock supabase/functions/send-notifications/index.ts
flutter build apk --debug --no-pub
```

Results: 60 new PostgreSQL checks passed; 86 existing journey/GPS PostgreSQL regression checks passed; 3 FCM payload/result tests passed; 15 targeted Flutter tests passed. Deno type checking and targeted Flutter analysis passed with no issues. Android debug APK built, installed, and launched on the existing emulator without Android runtime crashes; the real existing history was visible through the new tourist bell. No notification was tapped or marked read during that smoke check. The final APK was rebuilt successfully after the preferences and foreground-banner changes; their widget tests passed.

The SQL runner exercises the real new migration with a local PostgreSQL fixture, including multi-driver/solo gates, GPS/ETA silence, both arrival sources, deduplication, real payment/provider failure states, read/write RLS, navigation authorization, emergency association checks, provider failures, fenced retries, invalid tokens, queue recovery, account switches, and opt-outs. It is not a claim that all historical migrations were replayed successfully from scratch.

Still requires deployment/device acceptance with your credentials: actual FCM delivery on physical hardware and a Play-enabled emulator in foreground, background, locked and terminated states; Android 13 permission denial/grant; tap after login and account switch; real token rotation; provider outage/recovery. Permission-disabled history and the app without Firebase configuration work independently. Production readiness depends on completing those external configuration and acceptance steps.
