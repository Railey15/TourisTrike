-- Fix infinite recursion on profiles RLS (42P17) introduced when a profiles
-- policy joined back into profiles. Use SECURITY DEFINER helpers instead.

CREATE OR REPLACE FUNCTION public.profile_city(p_profile_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT city FROM public.profiles WHERE id = p_profile_id
$$;

CREATE OR REPLACE FUNCTION public.subtenant_can_view_review_tourist(p_tourist_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.driver_reviews dr
    WHERE dr.tourist_id = p_tourist_id
      AND public.current_profile_role() = 'subtenant'
      AND public.profile_city(dr.driver_id) = public.current_profile_city()
  )
$$;

DROP POLICY IF EXISTS driver_reviews_select ON public.driver_reviews;
CREATE POLICY driver_reviews_select ON public.driver_reviews
  FOR SELECT TO authenticated
  USING (
    tourist_id = auth.uid()
    OR driver_id = auth.uid()
    OR public.current_profile_role() = 'admin'
    OR (
      public.current_profile_role() = 'subtenant'
      AND public.profile_city(driver_id) = public.current_profile_city()
    )
  );

DROP POLICY IF EXISTS profiles_select_driver_review_tourists ON public.profiles;
CREATE POLICY profiles_select_driver_review_tourists ON public.profiles
  FOR SELECT TO authenticated
  USING (public.subtenant_can_view_review_tourist(id));
