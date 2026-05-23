CREATE TABLE IF NOT EXISTS public.subtenant_fare_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  subtenant_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  city text NOT NULL,
  base_fare numeric NOT NULL DEFAULT 50,
  fare_per_km numeric NOT NULL DEFAULT 50,
  minimum_fare numeric NOT NULL DEFAULT 0,
  additional_passenger_fee numeric NOT NULL DEFAULT 0,
  waiting_fee numeric NOT NULL DEFAULT 0,
  guide_fee numeric NOT NULL DEFAULT 0,
  weekend_surcharge numeric NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.subtenant_fare_settings
  ADD COLUMN IF NOT EXISTS id uuid DEFAULT gen_random_uuid(),
  ADD COLUMN IF NOT EXISTS subtenant_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS city text,
  ADD COLUMN IF NOT EXISTS base_fare numeric NOT NULL DEFAULT 50,
  ADD COLUMN IF NOT EXISTS fare_per_km numeric NOT NULL DEFAULT 50,
  ADD COLUMN IF NOT EXISTS minimum_fare numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS additional_passenger_fee numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS waiting_fee numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS guide_fee numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS weekend_surcharge numeric NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_active boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now(),
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

ALTER TABLE public.subtenant_fare_settings
  ALTER COLUMN base_fare SET DEFAULT 50,
  ALTER COLUMN fare_per_km SET DEFAULT 50,
  ALTER COLUMN minimum_fare SET DEFAULT 0,
  ALTER COLUMN additional_passenger_fee SET DEFAULT 0,
  ALTER COLUMN waiting_fee SET DEFAULT 0,
  ALTER COLUMN guide_fee SET DEFAULT 0,
  ALTER COLUMN weekend_surcharge SET DEFAULT 0,
  ALTER COLUMN is_active SET DEFAULT true,
  ALTER COLUMN created_at SET DEFAULT now(),
  ALTER COLUMN updated_at SET DEFAULT now();

UPDATE public.subtenant_fare_settings
SET city = COALESCE(NULLIF(city, ''), profiles.city)
FROM public.profiles
WHERE profiles.id = subtenant_fare_settings.subtenant_id
  AND (subtenant_fare_settings.city IS NULL OR subtenant_fare_settings.city = '');

CREATE UNIQUE INDEX IF NOT EXISTS subtenant_fare_settings_subtenant_city_idx
ON public.subtenant_fare_settings (subtenant_id, city);

CREATE INDEX IF NOT EXISTS subtenant_fare_settings_subtenant_idx
ON public.subtenant_fare_settings (subtenant_id);

CREATE INDEX IF NOT EXISTS subtenant_fare_settings_city_idx
ON public.subtenant_fare_settings (city);

DROP TRIGGER IF EXISTS set_subtenant_fare_settings_updated_at
ON public.subtenant_fare_settings;

CREATE TRIGGER set_subtenant_fare_settings_updated_at
BEFORE UPDATE ON public.subtenant_fare_settings
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.subtenant_fare_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subtenant_fare_settings_owner_city
ON public.subtenant_fare_settings;

CREATE POLICY subtenant_fare_settings_owner_city
ON public.subtenant_fare_settings
FOR ALL
USING (
  subtenant_id = auth.uid()
  OR public.current_profile_role() = 'admin'
  OR (
    public.current_profile_role() = 'subtenant'
    AND city = public.current_profile_city()
  )
)
WITH CHECK (
  subtenant_id = auth.uid()
  OR public.current_profile_role() = 'admin'
  OR (
    public.current_profile_role() = 'subtenant'
    AND city = public.current_profile_city()
  )
);
