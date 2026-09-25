# Booking service-area boundaries

`bulacan.geojson` contains the **unmodified, unsimplified geometries** of Baliuag,
Bustos and City of Malolos extracted from geoBoundaries gbOpen Philippines ADM3,
commit `9469f09`. These cover the current package/subtenant municipalities found
during inspection. They are configuration, not a permanent limit to Bulacan.
Baliuag is the dataset's historical spelling; the app displays Baliwag.

- [Pinned source](https://github.com/wmgeolab/geoBoundaries/blob/9469f09/releaseData/gbOpen/PHL/ADM3/geoBoundaries-PHL-ADM3.geojson)
- [Dataset metadata](https://www.geoboundaries.org/api/current/gbOpen/PHL/ADM3/)
- Source agencies: National Mapping and Resource Information Authority (NAMRIA),
  Philippine Statistics Authority (PSA), OCHA Philippines; distributed by geoBoundaries.
- Boundary year represented: **2020**; build date December 12, 2023.
- License: [CC BY 3.0 IGO](https://creativecommons.org/licenses/by/3.0/igo/).
- Coordinates: WGS84 GeoJSON longitude, latitude. Names/feature IDs retained.

These are public administrative boundaries used as initial operational coverage,
not a claim of current cadastral precision or municipal approval. Replace them with
an approved service-area polygon when available. Record source, license and version
for every replacement; validate topology with a GIS tool before publication.

Run `node supabase/service_areas/build_seed.mjs` to reproduce the seed migration.
To add a municipality, insert an active `booking_service_areas` row through a trusted
database/server role. Supply its polygon/multipolygon, province and lowercase exact
municipality aliases (including those used by its package and owning subtenant).
Keep one active match per province/alias: ambiguous or missing matches fail closed.
Do not reuse a city's name alone across provinces or use bounding boxes as coverage.
The client fetches coverage from the database by package ID. Clients cannot write it.

The two migrations must be deployed together before the updated client. An area
change applies to new bookings/location edits; history and status updates are not
revalidated. Existing deployments with custom coverage are not overwritten by the
initial seed (`ON CONFLICT DO NOTHING`). Google Maps keys remain unchanged.
