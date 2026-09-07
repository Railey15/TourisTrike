# Share Trip convoy tracking

## Findings

Tourist Tracking reads `booking_drivers` (accepted/completed assignments), then
`driver_live_locations` keyed by each assigned `driver_id`. Its map already uses
`buildBookingDriverMarkers` and the tricycle asset. The guest Dart screen also
uses that builder, so marker ID collisions were not the problem in the current
source.

The guest RPC had an additional inner join from each live location through
`package_activities`. A valid location with nullable `activity_id` was therefore
discarded. The SQL regression test reproduces two assignments becoming only one
visible location. Older deployed share RPCs also return only legacy scalar
driver coordinates; the new migration replaces the whole RPC with the roster
projection. The exact deployed booking's rows have not been inspected.

The RPC omitted display names, vehicle details, and location timestamps. The
guest parser replaced names with `Driver`; the UI had only generic tricycle rows
and one route ETA. It did not render the Tourist roster or live arrival widget.

## Implementation

- `supabase/migrations/20260907020000_shared_trip_convoy_read.sql`: token/code
  validation retained. Reads every accepted/completed assignment in acceptance
  order, with the same per-driver GPS table as Tourist Tracking. Nullable
  activity references are supported when the GPS timestamp is not older than
  the assignment. Explicit locations for another booking remain excluded.
  Missing GPS/profile data never removes an assignment. Only display name,
  plate/TODA, journey/stop state, coordinates, heading, and timestamp are added
  to the guest-safe roster. No table/schema, lifecycle, or global RLS change.
- `lib/core/supabase/touristrike_models.dart`: reads those safe fields into the
  existing `ConvoyDriverSnapshot`; adapts existing itinerary/coordinate fields
  into the models consumed by the shared live ETA widget.
- `lib/screens/guest/guest_trip_tracking_screen.dart`: uses the shared roster
  and live ETA components; keeps all driver markers/routes independently keyed;
  supports selecting a driver or framing the whole group; uses plural status
  wording. Pickup, drop-off, itinerary, token checks, and terminal behavior stay
  intact. Optional service injection supports isolated widget tests.
- `lib/widgets/convoy/convoy_tourist_driver_list.dart`: optional `guestView`
  renders `Drivers (N)` and suppresses contact actions/passenger counts. Existing
  Tourist behavior remains the default.
- `lib/widgets/live_itinerary_estimates.dart`: optional injected service for
  tests. Production ETA calculation is unchanged.
- `test/guest_convoy_tracking_test.dart`, `test/shared_trip_map_test.dart`, and
  `tool/verify_guest_convoy_sql.cjs`: model, RPC, UI, marker, refresh, and security
  coverage.

Marker IDs remain `driver_<driverId>` using the SAME marker builder and tricycle
asset as Tourist Tracking. Route IDs are `driver_route_<driverId>`; no locations
are duplicated or averaged to create artificial markers.

Guest automatic refresh remains the existing five-second, token-scoped RPC
poll. Each response replaces the whole roster snapshot, including every
driver's independent location/state. It uses `p_silent: true`, so routine reads
do not create access logs or notifications. Guests receive no direct table
subscriptions or anonymous table permissions. Expired/revoked links hide the
previous map; terminal bookings stop live tracking.

Per-driver ETAs come from the unchanged `LiveItineraryEstimates` widget and
`ItineraryScheduleService.live`, including its traffic-aware Google route legs,
fresh-location checks, journey-state handling, stop stays, and 30-second refresh.
State/stop changes also refresh its estimates. No second ETA algorithm or
guest-only trip-state field is introduced.

## Emergency authorization

The existing anonymous guest permission is 911 calling. The current
`EmergencyAlertForm` / `EmergencyService` and email endpoint require the tourist
session. This change preserves that permission boundary and the guest Emergency
Assistance sheet. Opening/cancelling the sheet has no database side effects.
Whether a valid share token/code should additionally authorize guest alert
submission (note/photo plus final confirmation) is awaiting the user's decision;
that new write capability is not implemented or claimed to be working.

## Validation and deployment

Run:

```text
flutter test --no-pub test/guest_convoy_tracking_test.dart test/shared_trip_map_test.dart
node tool/verify_guest_convoy_sql.cjs
```

The SQL tool uses isolated PGlite installed in the same temporary directory as
`verify_shared_trip_sql.cjs`; it never contacts Supabase. Coverage includes one
and two assignments; two independent updates; missing/invalid GPS; foreign-booking
and pre-assignment GPS exclusion; correct names/status/ETA inputs; revoked/expired
links; terminal tracking; denied direct anonymous table reads/mutations; and
side-effect-free emergency sheet cancellation.

Apply the existing `20260907010000_shared_trip_read_only_tracking.sql` migration
if it has not been deployed, followed by
`20260907020000_shared_trip_convoy_read.sql`, then rebuild/redeploy the web app.
Do not deploy only Dart changes against an older single-driver RPC. Keep the
existing Vercel build command/output and environment-based Maps browser key.
No production migration, deployment, or emergency notification was performed
as part of local verification.
