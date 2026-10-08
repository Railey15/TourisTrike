# Historical SQL held out of deployment

`20260930020000_booking_notices_cancellation_policy.sql` shares its version
with `20260930020000_repair_system_maintenance.sql`. The linked database's
`supabase_migrations.schema_migrations` row for that version is named
`repair_system_maintenance` and contains 24 recorded statements. Keep that
applied migration and its version unchanged.

The booking notices SQL is retained here for historical inspection. Read-only
checks of the linked database on 2026-10-09 found its privacy, booking terms,
and withdrawal columns; its booking terms and privacy triggers; and its
cancellation, same-day downpayment, and driver withdrawal functions and wrapper
functions. Later applied migrations have replaced some of these function
bodies. Replaying this historical file would overwrite those newer wrappers,
so it must not be put back into `supabase/migrations` or given a new version.

This move does not mark any SQL as applied in migration history. New changes
to these features require a separate, additive migration after checking the
current linked schema.

This reconciles the linked deployment. A brand-new database replaying only
`supabase/migrations` would lack the historical booking notices changes; it
needs a separately designed, guarded baseline before that workflow is used.
