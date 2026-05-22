-- Emergency Alerts: safety feature for tourists during trips
-- Creates the emergency_alerts table and adds email support to emergency_contacts

-- ── emergency_alerts table ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.emergency_alerts (
  id                  uuid NOT NULL DEFAULT gen_random_uuid(),
  tourist_id          uuid NOT NULL,
  booking_id          uuid,
  activity_id         uuid,
  driver_id           uuid,
  alert_status        text NOT NULL DEFAULT 'active'
                        CHECK (alert_status = ANY (ARRAY['active','resolved','false_alarm'])),
  latitude            double precision,
  longitude           double precision,
  maps_link           text,
  current_spot_name   text,
  trip_status         text,
  tourist_note        text,
  email_sent          boolean NOT NULL DEFAULT false,
  notifications_sent  boolean NOT NULL DEFAULT false,
  resolved_at         timestamp with time zone,
  resolved_by         uuid,
  resolution_note     text,
  created_at          timestamp with time zone NOT NULL DEFAULT now(),
  updated_at          timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT emergency_alerts_pkey PRIMARY KEY (id),
  CONSTRAINT emergency_alerts_tourist_id_fkey
    FOREIGN KEY (tourist_id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT emergency_alerts_booking_id_fkey
    FOREIGN KEY (booking_id) REFERENCES public.package_bookings(id),
  CONSTRAINT emergency_alerts_driver_id_fkey
    FOREIGN KEY (driver_id) REFERENCES auth.users(id)
);

-- ── RLS ───────────────────────────────────────────────────────
ALTER TABLE public.emergency_alerts ENABLE ROW LEVEL SECURITY;

-- Tourist: insert own alerts
CREATE POLICY "tourist_insert_own_emergency" ON public.emergency_alerts
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = tourist_id);

-- Tourist: read own alerts
CREATE POLICY "tourist_read_own_emergency" ON public.emergency_alerts
  FOR SELECT TO authenticated
  USING (auth.uid() = tourist_id);

-- Driver: read alerts where they are the assigned driver
CREATE POLICY "driver_read_assigned_emergency" ON public.emergency_alerts
  FOR SELECT TO authenticated
  USING (auth.uid() = driver_id);

-- Admin / subtenant: full access
CREATE POLICY "admin_full_emergency_access" ON public.emergency_alerts
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('admin', 'subtenant')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid()
        AND role IN ('admin', 'subtenant')
    )
  );

-- ── Realtime ──────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE public.emergency_alerts;

-- ── Add email column to emergency_contacts ────────────────────
ALTER TABLE public.emergency_contacts
  ADD COLUMN IF NOT EXISTS email text;

-- ── updated_at trigger ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_emergency_alerts_updated_at()
  RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_emergency_alerts_updated_at
  BEFORE UPDATE ON public.emergency_alerts
  FOR EACH ROW EXECUTE FUNCTION public.set_emergency_alerts_updated_at();
