ALTER TABLE public.admin_settings
  ADD COLUMN IF NOT EXISTS default_package_visibility text NOT NULL DEFAULT 'visible',
  ADD COLUMN IF NOT EXISTS default_spot_status text NOT NULL DEFAULT 'active',
  ADD COLUMN IF NOT EXISTS allow_instant_booking boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS manual_booking_confirmation boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS allow_cancellation boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS driver_auto_approval boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS require_driver_documents boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS require_toda_verification boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS require_spot_verification boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS require_map_pin boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS require_cover_image boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS auto_publish_spots boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS enable_ai_suggestions boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS diverse_place_types boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS prioritize_popular boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS prioritize_nearby boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS prioritize_food boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS prioritize_nature boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS prioritize_historical boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS booking_notifications boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS driver_notifications boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS review_notifications boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS email_notifications boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS revenue_tracking boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS spot_popularity_tracking boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS driver_analytics boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS monthly_reports boolean NOT NULL DEFAULT true;

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
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT subtenant_fare_settings_unique_city UNIQUE (subtenant_id, city)
);

DROP TRIGGER IF EXISTS set_subtenant_fare_settings_updated_at
  ON public.subtenant_fare_settings;
CREATE TRIGGER set_subtenant_fare_settings_updated_at
BEFORE UPDATE ON public.subtenant_fare_settings
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.subtenant_fare_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS subtenant_fare_settings_owner_city ON public.subtenant_fare_settings;
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

INSERT INTO storage.buckets (id, name, public)
VALUES ('public-assets', 'public-assets', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS public_assets_select ON storage.objects;
CREATE POLICY public_assets_select
ON storage.objects
FOR SELECT
USING (bucket_id = 'public-assets');

DROP POLICY IF EXISTS public_assets_subtenant_insert ON storage.objects;
CREATE POLICY public_assets_subtenant_insert
ON storage.objects
FOR INSERT
WITH CHECK (
  bucket_id = 'public-assets'
  AND auth.uid() IS NOT NULL
  AND public.current_profile_role() IN ('admin', 'subtenant')
);

DROP POLICY IF EXISTS public_assets_subtenant_update ON storage.objects;
CREATE POLICY public_assets_subtenant_update
ON storage.objects
FOR UPDATE
USING (
  bucket_id = 'public-assets'
  AND auth.uid() IS NOT NULL
  AND public.current_profile_role() IN ('admin', 'subtenant')
)
WITH CHECK (
  bucket_id = 'public-assets'
  AND auth.uid() IS NOT NULL
  AND public.current_profile_role() IN ('admin', 'subtenant')
);
