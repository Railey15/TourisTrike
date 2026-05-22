ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS driver_status text;

UPDATE public.profiles p
SET driver_status = COALESCE(d.status, p.driver_status, 'pending')
FROM public.driver_details d
WHERE p.id = d.driver_id
  AND p.role = 'driver'
  AND (
    p.driver_status IS NULL
    OR p.driver_status = ''
    OR p.driver_status <> d.status
  );
