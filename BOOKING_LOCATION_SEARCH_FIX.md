# Booking Route location search repair

## Verified cause

On September 6, 2026, direct requests using the same configured `.env` key as the app returned:

```text
Places Autocomplete: REQUEST_DENIED
Geocoding (Bustos coordinates 14.9539783, 120.9185984): REQUEST_DENIED
You must enable Billing on the Google Cloud Project
```

The current Route widget was still calling Google Places Autocomplete. Its HTTP-200 handling ignored Google's JSON `status`, treated a denied request as an empty suggestions list, and swallowed network exceptions. Thus the field looked like ordinary text entry even though autocomplete code still existed.

The current-location path swallowed reverse-geocoding errors and returned a `latitude, longitude` string instead of resolved country data. Validation then searched that string for `Philippines`, producing the false country error in the screenshot. A selected-place details response with `PH` already passed the old country check, but a missing country code had no reverse-geocoding fallback. The old additional municipality/province text gate could also reject valid Philippine addresses.

History comparison: `7eff78c` already contains the silent autocomplete catch and string-only reverse-geocoding fallback. `5900c18` removed an old hardcoded fallback key from `CitySpotSuggestionService`; the current `.env` key is present, so that removal is not the cause of these live denied requests. No key was restored, rotated, or changed. Android Maps metadata is present, `.env` is bundled by `pubspec.yaml`, and `main.dart` loads it before app initialization. Native map metadata does not authorize these REST calls: they use `CitySpotSuggestionService.resolveApiKey()`.

## Changes limited to booking locations

- `lib/core/places/booking_location_service.dart`: extracts the existing Places Autocomplete, Place Details, and Geocoding REST integration into a testable service. Explicit API-status errors replace silent empty results and fake coordinate-address fallbacks. Autocomplete retains `components=country:ph` and sends the user's actual query instead of appending the package municipality.
- `lib/widgets/booking_location_picker.dart`: retains the existing field, suggestions, current-location button, selected-address card, colors, and spacing. Each instance owns its selected state and request revision. Adds service-error feedback and retry search.
- `lib/screens/tourist/package_booking_screen.dart`: uses these two independent pickers, stores their complete resolved objects, and sends actual locality/province/country values through existing booking persistence fields. Route Preview uses the selected coordinates, displays both markers, requests the existing Directions integration, and draws the returned route on the existing static map. It displays calculation/loading failure and retry without creating a fake route.
- `test/booking_location_search_test.dart`: service and widget regression tests.

No payment, driver navigation, convoy, itinerary scheduling, Supabase function, or schema changes are part of this repair.

## Selected data and country validation

`BookingLocation` carries address, latitude, longitude, optional place ID, country, country code, province, and locality. Pickup and Drop-off each have their own object. Place ID and country name remain in booking-screen state; no duplicate persistence columns were introduced. The existing repository receives the resolved address, coordinates, province, locality, and country code.

Validation requires real, finite coordinates in geographic bounds. An explicit country code is authoritative: `PH` passes and a foreign code is rejected even if the address includes `Philippines`. If Place Details omits the country code, the service reverse-geocodes the resolved coordinates before accepting the selection. Successful reverse geocoding uses structured country code/name; only missing structured country data may fall back to a country suffix in the returned formatted address. Typed text is never validated as a place. Verified PH results are normalized to country code `PH` for the existing persistence fields.

Current Location follows permission/service checks → GPS fix → reverse geocode → country validation → selection. It preserves the exact GPS coordinates rather than substituting a geocoder centroid. A Places ID is optional. Provider failures remain service errors, not claims that the coordinates are outside the Philippines.

Validation no longer requires the selected point's municipality to match the package municipality; it implements the requested Philippines-only rule for pickup/drop-off.

## Async behavior and preview

Previously, typing after selection left the old coordinates valid, and asynchronous search/details/GPS responses had no revision guard. Each edit, selection, clear, or current-location operation now advances an instance-specific revision. Stale responses cannot alter text, errors, suggestions, or selected coordinates. Editing clears that field's accepted coordinates immediately. Country validation happens only after details/reverse geocoding finish; no country errors run on screen opening or ordinary typing. Continuing with unresolved/free text is blocked by the existing booking-step validation.

The preview receives `_selectedPickup` and `_selectedDropoff` coordinates directly. A missing selection displays the waiting card and issues no Directions request. Changes to either coordinate pair invalidate the previous preview request; only the current result is rendered. The existing `fetchItineraryDirections` platform integration calculates the route; Static Maps displays its encoded overview polyline and both coordinate markers. Route failure is explicit and retryable.

## Verification and remaining external requirement

Automated tests cover Bustos details without `Philippines` in the display address, actual structured province/locality retention, foreign-country rejection, missing-country reverse geocoding, GPS without a place ID, geocoding denial, invalid coordinates, the PH autocomplete filter, independent Pickup/Drop-off selection, free-text invalidation, stale autocomplete/details responses, and visible service-error retry. These are controlled HTTP-response tests, not a claim that Google's currently denied live requests succeeded.

Validation completed: `flutter test` passed all **212 tests**, including **13 new location regression tests**. Targeted `flutter analyze` on the booking screen, extracted picker/service, and new tests reported **no issues**.

`flutter build apk --debug` also succeeded. Updated APK: `build/app/outputs/flutter-apk/app-debug.apk`.

Google documents the JSON response status and country component filter in [Place Autocomplete (Legacy)](https://developers.google.com/maps/documentation/places/web-service/legacy/autocomplete). This repair preserves that existing provider rather than introducing another search source.

The configured Google Cloud project's billing must be enabled before live autocomplete, reverse geocoding, and route calculation can work. API keys were not exposed or changed by this fix. Google's returned error establishes the billing blocker; whether an additional API restriction will appear after billing is enabled cannot be verified from the denied responses. The existing integration needs Places API (Legacy Autocomplete/Details), Geocoding API, Directions API, and Maps Static API access.

No SQL, Supabase deployment, or generated types update is required. After resolving billing, rebuild/restart the Flutter app and test both fields with `Bustos Municipal Hall` and `SM City Baliwag`, selecting the returned suggestions. Verify green selected-address cards, two preview markers and a route, then edit one field and verify its old selection disappears while the other stays selected. Also test Current Location with a Philippine emulator GPS fix.
