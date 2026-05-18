-- Add children count to package_bookings for tricycle calculation
ALTER TABLE public.package_bookings
  ADD COLUMN IF NOT EXISTS children integer NOT NULL DEFAULT 0
    CHECK (children >= 0);
