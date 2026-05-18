-- Add pickup and drop-off location fields to package_bookings
ALTER TABLE public.package_bookings
  ADD COLUMN IF NOT EXISTS pickup_address text,
  ADD COLUMN IF NOT EXISTS pickup_latitude double precision,
  ADD COLUMN IF NOT EXISTS pickup_longitude double precision,
  ADD COLUMN IF NOT EXISTS dropoff_address text,
  ADD COLUMN IF NOT EXISTS dropoff_latitude double precision,
  ADD COLUMN IF NOT EXISTS dropoff_longitude double precision;
