TourisTrike map fixes — 7 September 2026

1. Share Trip root causes found in the checkout

   The local `build/web/index.html` still contained `__GOOGLE_MAPS_BROWSER_API_KEY__`. The source HTML deliberately skips loading the Maps JavaScript SDK when that placeholder remains. A plain Flutter web build does not substitute it. `build.sh` performed substitution, but `vercel.json` did not specify that build command. This is confirmed for the local artifact; the deployed domain's Google API restrictions/billing were not inspected.

   A second failure occurs before map construction: `20260827000000_p0_booking_integrity.sql` replaced the shared RPC with arguments named `p_ip_address` and `p_log_access`, while the repository sends `p_user_agent` and `p_silent`. PostgREST named-argument resolution cannot match that contract. The wrapper also forwarded the boolean with incompatible semantics. The new migration restores the app's named arguments and silent-refresh semantics.

   The guest map already had a finite SliverAppBar height and a fallback camera center, so optional GPS was not a prerequisite for building GoogleMap. The existing widget was retained, with explicit expanding Stack constraints. Missing subscriptions, RLS restrictions, and single-driver payloads affected tracking updates rather than tile initialization.

2. Share Trip files changed

   `lib/screens/guest/guest_trip_tracking_screen.dart`, `lib/core/supabase/touristrike_models.dart`, and `supabase/migrations/20260907010000_shared_trip_read_only_tracking.sql`. Web configuration files: `build.sh`, `vercel.json`, and `tool/build_web.ps1`.

3. Tourist visual/component reuse

   Retains the blue tracking header, status/ETA card, map, pickup/drop-off pins, and itinerary cards. Completed/current/upcoming destinations keep green/orange/blue markers. Uses the existing `buildBookingDriverMarkers` and tricycle artwork used by Tourist/Driver maps, and the existing platform-selected `RoutePolylineService`. The initial camera fits available map markers; driver follow/recenter remains a viewing action. Driver rows show anonymous numbered vehicles and the shared `ConvoyJourneyState.label`.

4. Authoritative status and refresh

   Share link/token → access-code screen → repository `validateGuestTripLink` → `get_shared_trip_details` → validated `shared_trip_links.booking_id` → persisted booking, activity, itinerary and assignment data. No status table or `sharedTripStatus` column was added. The RPC returns `package_activities.tour_status`, both persisted booking statuses, itinerary `spot_status`, and `booking_drivers.journey_state/current_stop_index`.

   Anonymous table subscriptions could not read active locations under the existing P0 RLS policy. They were replaced by a non-overlapping, token-validated snapshot refresh every five seconds. Each refresh includes activity, assignment, itinerary and location changes. This is polling, not WebSocket realtime. Refresh timeout/failure hides stale tracking and provides Retry. Terminal trips stop polling. Route requests are limited to once per 30 seconds for an unchanged destination/state, with stale-response guards.

5. All driver locations

   The RPC builds the accepted/completed `booking_drivers` roster, left-joins GPS so missing locations do not remove assignments, and requires the location's `activity_id` to belong to the shared booking. Only active accepted assignments can return coordinates. A legacy assigned driver is used only if no booking-driver rows exist. Invalid coordinates are discarded; the existing marker normalizer controls membership/vehicle rendering. Names and phone numbers are not exposed. Route origin comes from a valid roster location, not cached activity GPS.

6. Read-only access and completion

   Token, code, active flag, expiry and revocation are checked server-side on every snapshot. No payment, chat, rating, cancellation, booking-edit, contact, account or Testing Mode controls are added. Payment-wait states get safe text without amounts/actions. Existing emergency-service access is retained. Terminal bookings return no driver coordinates, and the client stops tracking and shows an ended-trip message. Driver location rows for another booking are never used as fallback.

7. RLS/SQL changes

   The migration replaces only the shared-details RPC and removes the old `anon_shared_booking_select` and `anon_shared_itinerary_select` policies, which checked link existence rather than token possession. It does not relax `driver_live_locations` RLS or change authenticated Tourist/Driver policies. Execute access is granted to anon/authenticated for the validated RPC; PUBLIC execution is revoked. Existing access logging semantics are preserved for initial access and suppressed for silent polling.

8. Booking preview root cause

   `_SharedRouteMapPreview` used an `Image.network` Static Maps URL rather than the working Maps SDK. It depended on separate Static Maps authorization and asynchronously resolved key state, and rejected pickup-only rendering. Its error path replaced the entire image with “Map preview unavailable.” No live Google HTTP response was available to distinguish key restriction, API enablement, or billing rejection, so those are not claimed as verified causes.

9. Booking files changed

   `lib/screens/tourist/package_booking_screen.dart` and new `lib/widgets/booking_route_preview_map.dart`. Existing booking layout, location search/selection, pricing and timing logic were retained.

10. Coordinate flow

   Existing `_selectedPickup` and `_selectedDropoff` structured latitude/longitude values pass through `_SharedRouteMapPreview` into `BookingRoutePreviewMap`. Addresses are used only for legend text. Valid pickup coordinates immediately create the map and pickup marker; adding drop-off adds its marker without another action.

11. Markers, route and camera

   The map has a fixed 220-pixel height. Directions use the existing route service independently of map construction. Loading shows “Calculating route...” without hiding markers. Route failure preserves markers and offers Retry; straight-line failure fallbacks are not presented as successful road routes. Coordinate changes clear previous polylines; late responses cannot overwrite newer selections. Camera bounds include both selected points with padding; identical/nearby coordinates use a centered zoom instead of degenerate bounds.

12. Shared root cause?

   No single proven common rendering bug: the original guest map used the Maps SDK while booking used Static Maps. The missing web SDK substitution and shared RPC mismatch explain separate guest failures. Both corrected surfaces now use the established Maps SDK configuration and route service.

13. Verification

   - 25 tests passed across `shared_trip_map_test`, `test_mode_convoy_markers_test`, `booking_location_search_test`, and `gps_arrival_quality_test`.
   - Targeted Dart analysis: no issues. `git diff --check`: clean.
   - Flutter JavaScript web release compilation succeeded. Existing optional Wasm compatibility warnings remain.
   - `tool/verify_shared_trip_sql.cjs` passed against an isolated PostgreSQL/PGlite fixture: named arguments, three vehicles, activity status updates, wrong code, silent logging, booking-scoped GPS, completion, revocation and denial of direct anonymous table reads.
   - Tourist active tracking, Driver navigation, existing marker helper, GPS, payment, convoy progression and Testing Mode implementation files were not changed. Regression tests passed; actual Android/iOS navigation and Google tile rendering have not been exercised on a device in this session.
   - SQL was tested against a minimal schema fixture, not the deployed Supabase database. No production migration or deployment was performed. Only `GOOGLE_MAPS_API_KEY` exists in local `.env`; a separate browser key was not available. The compilation-only web artifact still needs browser-key injection before hosting.

14. Deployment commands

   From the project root, apply this one migration to a database with the preceding application schema. Set `SUPABASE_DB_URL` securely in the shell first:

   ```powershell
   psql "$env:SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/migrations/20260907010000_shared_trip_read_only_tracking.sql
   ```

   Set `GOOGLE_MAPS_BROWSER_API_KEY` to the browser key configured for the hosting domain, then build locally:

   ```powershell
   powershell -NoProfile -File tool/build_web.ps1
   ```

   Host the resulting `build/web` directory using the existing deployment process. Vercel now explicitly runs `bash build.sh`; configure `GOOGLE_MAPS_BROWSER_API_KEY` in that project's build environment before redeploying. The scripts fail early if it is missing. No AndroidManifest change or new Google API is required by this patch.

   Reproduce the automated checks:

   ```powershell
   flutter test --no-pub test/shared_trip_map_test.dart test/test_mode_convoy_markers_test.dart test/booking_location_search_test.dart test/gps_arrival_quality_test.dart
   npm install --prefix "$env:TEMP/TourisTrike-map-sql-check" --no-package-lock --no-save @electric-sql/pglite
   node tool/verify_shared_trip_sql.cjs
   ```
