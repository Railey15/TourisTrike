# Booking location/service-area restriction

Implemented and verified September 25, 2026. Scope: user-selectable package-booking
locations only. Existing notification work was preserved. Fees, cancellation rules,
terms, registration/privacy and analytics were not changed.

## Existing flow and root cause

`PackageBookingScreen` used two `BookingLocationPicker` instances. Google Places
autocomplete resolved details; GPS selection used reverse geocoding. Native calls
used the existing Maps key resolver, while web used `GooglePlacesGateway` and the
authenticated `google-places` Edge Function. Validation only checked finite
coordinates and the Philippines country code. Autocomplete used `country:ph`,
so other municipalities remained selectable. Additional destinations relied on
municipality text. `create_package_booking` accepted arbitrary coordinates.

The existing booking map was a route preview, with no selectable/draggable pin.
Tracking maps and the admin spot editor are separate and were not changed.

Inspection found `tour_packages.city` and `submitted_by`, linked to
`subtenant_details.city/province`; there was no service-area polygon/configuration
or PostGIS extension. The remote `tour_packages` table has no province column.
Seven packages currently resolve to Baliwag or Bustos; Malolos has a subtenant.

## Shared source of truth and geometry

`booking_service_areas` stores versioned GeoJSON Polygon/MultiPolygon boundaries,
municipality aliases, province, source and license. Authenticated users can read
active configuration; only trusted database/server roles can change it.
`booking_service_area(package_id)` supplies the client with the same geometry used
by the server. Resolution uses the stored package and its owning subtenant;
request address/municipality/province labels cannot select a different boundary.
Missing, disabled or ambiguous coverage fails closed with a retry/support message.

The initial seed contains unsimplified Baliuag/Baliwag, Bustos and City of Malolos
geometries from [geoBoundaries gbOpen PHL ADM3](https://www.geoboundaries.org/api/current/gbOpen/PHL/ADM3/),
pinned to commit `9469f09`, representing **2020** boundaries. Source: NAMRIA, PSA,
OCHA Philippines; CC BY 3.0 IGO. This is an initial public administrative boundary
configuration, not a claim of current municipal approval or cadastral precision.
See [source attribution and maintenance](../supabase/service_areas/README.md).
An approved operational polygon can replace it without changing Flutter screens.

Dart and PostgreSQL use matching point-in-polygon rules: GeoJSON longitude/latitude,
closed ring edges included, hole interiors excluded, multiple islands supported.
A `1e-10` degree tolerance handles floating-point equality at edges; it is not a
GPS accuracy buffer. Invalid/nonfinite/null coordinates are rejected. No address
substring determines containment. No database extension is required.

## Selection behavior

- Search sends `country:ph`, a boundary-derived enclosing circle and `strictbounds`.
  The [legacy Google API](https://developers.google.com/maps/documentation/places/web-service/legacy/autocomplete)
  does not implement the exact polygon restriction. Each of up to five predictions
  is therefore resolved and filtered before display; selecting it resolves and
  validates it again. This adds up to five Details requests per debounced search.
  Areas too large for Google's 50 km restriction use circle bias plus polygon filtering.
- GPS is checked against coverage before reverse geocoding. Accepted coordinates
  remain the actual GPS point, never Google's nearby centroid. Failed geocoding
  produces an error rather than an accepted point.
- `Choose on Map` opens a booking-only map with the boundary overlay. Tap or drag
  selects the exact point. Confirmation stays disabled outside coverage, while
  resolving the address, or when geocoding fails. Dragging immediately invalidates
  the previous selection; stale responses cannot re-enable it. Feedback is inline.
- Pickup and drop-off share the configuration, with independent selection state.
  Package changes load new coverage and discard old picker state.
- Additional destination search/results, selection/restoration, and final booking
  validation use coordinates. Existing package destinations outside coverage are
  flagged; they are not silently moved to a different location.

## Authoritative protection and existing bookings

BEFORE triggers protect `package_bookings`, `booking_itinerary_items` and
`customized_package_spots`, including direct inserts, existing RPCs, old clients,
coordinate edits and moving a destination to another booking. Changing a booking's
package also validates its existing selected destinations against the new area.
Removed customization rows are historical metadata; selecting them again validates
their coordinates. Google IDs and municipal-looking address text cannot bypass checks.

No historical rows were rewritten. Status, arrival, payment and schedule updates
that do not change location are not revalidated. This keeps old/active tours usable.
New bookings or actual location changes must satisfy the configured coverage.

## Deployment and live evidence

Deployed to linked Supabase project `mvtqhsrdgtwdeootgjci`:

1. `20260926000000_booking_service_areas.sql` — configuration, RPC and triggers.
2. `20260926000001_booking_service_area_seed.sql` — three initial boundaries.
3. `google-places` Edge Function — whitelist `strictbounds` for autocomplete.

Both SQL migrations were applied in one transaction after a rolled-back live schema
preflight. Only these two versions were marked applied in migration history; no
blanket `db push`, replay of old migrations or unrelated history repair was performed.
PostgREST schema was refreshed. **No Google key, API restriction, billing or secret
configuration change was made or required.** Other environments need both migrations
and the updated proxy before the new client is released.

`supabase/verification/booking_service_area.sql` passed against the live database:
three active areas, three protected tables, all seven packages resolve, and invalid
pickup/drop-off INSERT probes are rejected. Probes reuse an existing primary key
and roll back; no booking or notification was created for verification.

The live data audit identified these pre-existing package locations outside their
package boundary:

| Package | Spot | Saved title |
|---|---|---|
| 11 | 17 | Baliwag Community Museum |
| 12 | 19 | Bustos Resort and Leisure Area |
| 12 | 20 | Bustos Faith and Cultural Site |

The subtenant must verify/correct these coordinates, or tourists must replace the
destinations with valid ones when making a new booking. Coordinates and package
contents were not edited automatically. Existing bookings remain accessible.

## Verification results and limits

- **24 Flutter tests passed** in the final combined run across the three
  location/lifecycle test files, including the real-screen outside-drop-off test.
- **46 local PostgreSQL checks passed**, executing the actual migrations in PGlite.
- Targeted Flutter analysis: **no issues** in changed production/test files.
- Android debug APK built successfully and installed/launched on emulator-5554.
  The emulator has a driver session, so live tourist booking interaction was not
  claimed; map/pin/search behavior was verified with real widgets and mocked APIs.
- Adjacent regression run: **21 passed, 1 pre-existing failure**. The failure is
  `google_places_web_proxy_test.dart` expecting `google_maps_config.js`; unchanged
  `web/index.html` uses the browser-key build placeholder instead. The working key
  loader was preserved. Shared map, convoy, route failure and schedule tests passed.
- No new booking/payment was submitted to production. Live Google Places responses
  and physical-device GPS were not separately exercised in this batch. The test
  suite simulates both success and failure responses.

| Requested case | Evidence |
|---|---|
| Inside/outside search | Prediction filtering and selection revalidation tests |
| Inside/outside map pin | Real map widget callbacks; confirmation state tests |
| Inside/outside GPS | Exact coordinate preservation; reject before geocoder call |
| Valid pickup/drop-off | Picker independence and database insert checks |
| Inside pickup + outside drop-off | Real booking screen cannot leave Route; database rejects |
| UI bypass | Direct SQL insert/edit, forged labels, destination and package transfer checks |
| Near boundary | Edge/vertex/just-inside/just-outside, holes/islands; seed vertices tested |
| Historical bookings | Legacy null-location booking remains readable; status updates pass |
| Google/ geocoding errors | API denial, no-results, inline retry and disabled map confirmation |

Commands:

```text
flutter test test/booking_service_area_test.dart test/booking_location_search_test.dart test/package_booking_lifecycle_test.dart
node supabase/tests/booking_service_area_regression.mjs
supabase db query --linked --file supabase/verification/booking_service_area.sql
flutter build apk --debug
```

## Exact files in this batch

Production:

- `lib/core/places/booking_service_area.dart` (new)
- `lib/core/places/booking_location_service.dart`
- `lib/widgets/booking_location_picker.dart`
- `lib/widgets/booking_location_map_picker.dart` (new)
- `lib/screens/tourist/package_booking_screen.dart`
- `supabase/functions/google-places/index.ts`
- `supabase/migrations/20260926000000_booking_service_areas.sql` (new)
- `supabase/migrations/20260926000001_booking_service_area_seed.sql` (new)
- `supabase/service_areas/bulacan.geojson` (new)
- `supabase/service_areas/build_seed.mjs` (new)
- `supabase/service_areas/README.md` (new)

Verification/documentation:

- `test/booking_service_area_test.dart` (new)
- `test/fixtures/booking_service_area_fixture.dart` (new)
- `test/booking_location_search_test.dart`
- `test/package_booking_lifecycle_test.dart`
- `supabase/tests/booking_service_area_regression.mjs` (new)
- `supabase/verification/booking_service_area.sql` (new)
- `docs/BOOKING_SERVICE_AREA.md` (new)

Other pre-existing working-tree changes belong to earlier work.
