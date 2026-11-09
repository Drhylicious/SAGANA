-- ============================================================
-- SAGANA — Unified purchasing m02: Cooperative Details and Delivery settings
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after m01.
--
-- WHAT IT DOES
--   1. cooperative_details: ONE shared record for the whole cooperative (never a Manager's
--      or an Officer's personal details): name, the fixed Barangay Payanas address, a flexible
--      rural address (Sitio / Purok, directions), a map pin and a contact number.
--      The contact number starts as an unset PLACEHOLDER. No street / building / house number
--      is required.
--   2. delivery_settings: the Delivery on/off switch (OFF), the barangays delivery may go to
--      (only Payanas), and whether demonstration rates may be used (never in production).
--   3. delivery_fee_bands: distance bands, versioned (history kept). EMPTY: no rates are invented.
--   4. Manager-only functions to save all of it; Officers can only view. Every change is in the
--      Accountability Log (module "marketplace").
--   5. Delivery can be switched on only when ALL of these are true:
--        - the cooperative's map pin is set,
--        - the contact number is entered, is NOT a placeholder, and has been VERIFIED by the Manager,
--        - a current set of distance bands exists (and is not demonstration data),
--        - at least one allowed barangay is listed.
--      Changing the pin or the contact number switches Delivery off again until re-verified.
--      Pickup is never affected.
--
-- Nothing existing is changed. Delivery stays OFF after this script.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.is_manager(uuid)') IS NULL OR to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_manager() / is_staff() are missing.';
  END IF;
  IF to_regprocedure('public.audit_staff_change()') IS NULL THEN
    RAISE EXCEPTION 'audit_staff_change() is missing.';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1. Cooperative Details (one row)
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.cooperative_details (
  id                    BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
  cooperative_name      TEXT NOT NULL DEFAULT 'SP3 Agriculture Cooperative',
  -- The fixed service area (written by the trigger below, not by the app).
  region_code           TEXT NOT NULL DEFAULT '1700000000',
  region_name           TEXT NOT NULL DEFAULT 'MIMAROPA Region',
  province_code         TEXT NOT NULL DEFAULT '1704000000',
  province_name         TEXT NOT NULL DEFAULT 'Marinduque',
  city_municipality_code TEXT NOT NULL DEFAULT '1704006000',
  city_municipality_name TEXT NOT NULL DEFAULT 'Torrijos',
  barangay_code         TEXT NOT NULL DEFAULT '1704006019',
  barangay_name         TEXT NOT NULL DEFAULT 'Payanas',
  postal_code           TEXT NOT NULL DEFAULT '4903',
  -- A flexible rural address: Sitio / Purok and directions. Nothing here is required.
  sitio_purok           TEXT,
  address_notes         TEXT,
  latitude              DOUBLE PRECISION CHECK (latitude  IS NULL OR latitude  BETWEEN -90  AND 90),
  longitude             DOUBLE PRECISION CHECK (longitude IS NULL OR longitude BETWEEN -180 AND 180),
  contact_number        TEXT,
  contact_is_placeholder BOOLEAN NOT NULL DEFAULT TRUE,
  contact_verified_at   TIMESTAMPTZ,
  contact_verified_by   UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by            UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK ((latitude IS NULL) = (longitude IS NULL))
);

-- The service area is fixed: whatever is sent for these fields is replaced.
CREATE OR REPLACE FUNCTION public._cooperative_details_fixed_area()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  NEW.region_code := '1700000000';  NEW.region_name := 'MIMAROPA Region';
  NEW.province_code := '1704000000'; NEW.province_name := 'Marinduque';
  NEW.city_municipality_code := '1704006000'; NEW.city_municipality_name := 'Torrijos';
  NEW.barangay_code := '1704006019'; NEW.barangay_name := 'Payanas';
  NEW.postal_code := '4903';
  NEW.updated_at := NOW();
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_cooperative_details_fixed_area ON public.cooperative_details;
CREATE TRIGGER trg_cooperative_details_fixed_area
  BEFORE INSERT OR UPDATE ON public.cooperative_details
  FOR EACH ROW EXECUTE FUNCTION public._cooperative_details_fixed_area();

INSERT INTO public.cooperative_details (id) VALUES (TRUE) ON CONFLICT (id) DO NOTHING;

-- ════════════════════════════════════════════════════════════
-- 2. Delivery settings (one row) and the fee bands
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.delivery_settings (
  id                     BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
  delivery_enabled       BOOLEAN NOT NULL DEFAULT FALSE,
  allowed_barangay_codes TEXT[]  NOT NULL DEFAULT ARRAY['1704006019'],
  -- Demonstration rates may be used ONLY when this is switched on (development). Never in production.
  allow_demo_rates       BOOLEAN NOT NULL DEFAULT FALSE,
  enabled_at             TIMESTAMPTZ,
  enabled_by             UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by             UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
INSERT INTO public.delivery_settings (id) VALUES (TRUE) ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.delivery_fee_bands (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  set_version INTEGER NOT NULL,
  min_km      NUMERIC(8,2) NOT NULL CHECK (min_km >= 0),
  max_km      NUMERIC(8,2) NOT NULL,
  fee         NUMERIC(10,2) NOT NULL CHECK (fee >= 0),
  is_demo     BOOLEAN NOT NULL DEFAULT FALSE,
  is_current  BOOLEAN NOT NULL DEFAULT TRUE,
  created_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK (max_km > min_km),
  UNIQUE (set_version, min_km)
);
CREATE INDEX IF NOT EXISTS delivery_fee_bands_current ON public.delivery_fee_bands (is_current, min_km);

-- Bands are history: never edited or deleted, only superseded by a new version.
CREATE OR REPLACE FUNCTION public._delivery_bands_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'A delivery fee band is part of the permanent history and cannot be deleted.';
  END IF;
  IF (NEW.set_version, NEW.min_km, NEW.max_km, NEW.fee, NEW.is_demo)
     IS DISTINCT FROM (OLD.set_version, OLD.min_km, OLD.max_km, OLD.fee, OLD.is_demo) THEN
    RAISE EXCEPTION 'A delivery fee band cannot be edited. Save a new set of bands instead.';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_delivery_bands_guard ON public.delivery_fee_bands;
CREATE TRIGGER trg_delivery_bands_guard BEFORE UPDATE OR DELETE ON public.delivery_fee_bands
  FOR EACH ROW EXECUTE FUNCTION public._delivery_bands_guard();

-- ════════════════════════════════════════════════════════════
-- 3. Read access (staff read the tables; writes only through the functions below)
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.cooperative_details  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_settings    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.delivery_fee_bands   ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cooperative_details: staff read" ON public.cooperative_details;
CREATE POLICY "cooperative_details: staff read" ON public.cooperative_details FOR SELECT TO authenticated USING (public.is_staff());
DROP POLICY IF EXISTS "delivery_settings: staff read" ON public.delivery_settings;
CREATE POLICY "delivery_settings: staff read" ON public.delivery_settings FOR SELECT TO authenticated USING (public.is_staff());
DROP POLICY IF EXISTS "delivery_fee_bands: staff read" ON public.delivery_fee_bands;
CREATE POLICY "delivery_fee_bands: staff read" ON public.delivery_fee_bands FOR SELECT TO authenticated USING (public.is_staff());
REVOKE ALL ON public.cooperative_details, public.delivery_settings, public.delivery_fee_bands FROM PUBLIC, anon;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.cooperative_details, public.delivery_settings, public.delivery_fee_bands FROM authenticated;
GRANT SELECT ON public.cooperative_details, public.delivery_settings, public.delivery_fee_bands TO authenticated;

-- Every change lands in the Accountability Log.
DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.cooperative_details;
CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.cooperative_details
  FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change('marketplace', '');
DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.delivery_settings;
CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.delivery_settings
  FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change('marketplace', '');
DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.delivery_fee_bands;
CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.delivery_fee_bands
  FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change('marketplace', '');

-- ════════════════════════════════════════════════════════════
-- 4. What is still missing before Delivery may be switched on
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._delivery_missing()
RETURNS text[]
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  d cooperative_details%ROWTYPE;
  s delivery_settings%ROWTYPE;
  v_missing text[] := ARRAY[]::text[];
  v_bands integer;
  v_demo  integer;
BEGIN
  SELECT * INTO d FROM cooperative_details WHERE id;
  SELECT * INTO s FROM delivery_settings WHERE id;
  IF d.latitude IS NULL OR d.longitude IS NULL THEN v_missing := array_append(v_missing, 'cooperative_pin'); END IF;
  IF d.contact_number IS NULL OR btrim(d.contact_number) = '' OR d.contact_is_placeholder THEN
    v_missing := array_append(v_missing, 'contact_number');
  ELSIF d.contact_verified_at IS NULL THEN
    v_missing := array_append(v_missing, 'contact_verified');
  END IF;
  IF COALESCE(array_length(s.allowed_barangay_codes, 1), 0) = 0 THEN v_missing := array_append(v_missing, 'allowed_barangay'); END IF;
  SELECT count(*), count(*) FILTER (WHERE is_demo) INTO v_bands, v_demo FROM delivery_fee_bands WHERE is_current;
  IF v_bands = 0 THEN
    v_missing := array_append(v_missing, 'fee_bands');
  ELSIF v_demo > 0 AND NOT s.allow_demo_rates THEN
    v_missing := array_append(v_missing, 'fee_bands_demo_only');
  END IF;
  RETURN v_missing;
END $$;
REVOKE ALL ON FUNCTION public._delivery_missing() FROM PUBLIC, anon, authenticated;

-- Everyone signed in may ask whether Delivery is available (a consumer needs to know);
-- the list of what is missing is for staff only.
CREATE OR REPLACE FUNCTION public.get_delivery_status()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  s delivery_settings%ROWTYPE;
  v_missing text[];
BEGIN
  SELECT * INTO s FROM delivery_settings WHERE id;
  v_missing := public._delivery_missing();
  RETURN jsonb_build_object(
    'enabled', s.delivery_enabled AND COALESCE(array_length(v_missing, 1), 0) = 0,
    'ready',   COALESCE(array_length(v_missing, 1), 0) = 0,
    'allowed_barangay_codes', to_jsonb(s.allowed_barangay_codes),
    'missing', CASE WHEN public.is_staff() THEN to_jsonb(v_missing) ELSE '[]'::jsonb END
  );
END $$;
GRANT EXECUTE ON FUNCTION public.get_delivery_status() TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 5. Cooperative Details: read (everyone) and save / verify (Manager only)
-- ════════════════════════════════════════════════════════════
-- The pin is for staff and for the fee calculation only; a consumer sees name, address, contact.
CREATE OR REPLACE FUNCTION public.get_cooperative_details()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE d cooperative_details%ROWTYPE;
BEGIN
  SELECT * INTO d FROM cooperative_details WHERE id;
  RETURN jsonb_build_object(
    'cooperative_name', d.cooperative_name,
    'barangay_code', d.barangay_code, 'barangay_name', d.barangay_name,
    'city_municipality_name', d.city_municipality_name, 'province_name', d.province_name,
    'region_name', d.region_name, 'postal_code', d.postal_code,
    'sitio_purok', d.sitio_purok, 'address_notes', d.address_notes,
    'contact_number', CASE WHEN d.contact_is_placeholder THEN NULL ELSE d.contact_number END,
    'contact_is_placeholder', d.contact_is_placeholder,
    'contact_verified', d.contact_verified_at IS NOT NULL,
    'latitude',  CASE WHEN public.is_staff() THEN d.latitude  ELSE NULL END,
    'longitude', CASE WHEN public.is_staff() THEN d.longitude ELSE NULL END,
    'updated_at', d.updated_at
  );
END $$;
GRANT EXECUTE ON FUNCTION public.get_cooperative_details() TO authenticated;

CREATE OR REPLACE FUNCTION public.save_cooperative_details(
  p_sitio_purok    TEXT,
  p_address_notes  TEXT,
  p_latitude       DOUBLE PRECISION,
  p_longitude      DOUBLE PRECISION,
  p_contact_number TEXT
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  d cooperative_details%ROWTYPE;
  v_digits TEXT;
  v_contact TEXT := NULLIF(btrim(COALESCE(p_contact_number, '')), '');
  v_pin_changed BOOLEAN;
  v_contact_changed BOOLEAN;
BEGIN
  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only the Manager can change the Cooperative Details.';
  END IF;
  IF (p_latitude IS NULL) <> (p_longitude IS NULL) THEN
    RAISE EXCEPTION 'The map pin needs both a latitude and a longitude.';
  END IF;
  IF v_contact IS NOT NULL THEN
    v_digits := regexp_replace(v_contact, '[^0-9]', '', 'g');
    IF length(v_digits) < 7 OR length(v_digits) > 13 THEN
      RAISE EXCEPTION 'Enter a valid contact number.';
    END IF;
  END IF;

  SELECT * INTO d FROM cooperative_details WHERE id FOR UPDATE;
  v_pin_changed := (d.latitude, d.longitude) IS DISTINCT FROM (p_latitude, p_longitude);
  v_contact_changed := d.contact_number IS DISTINCT FROM v_contact;

  UPDATE cooperative_details
     SET sitio_purok = NULLIF(btrim(COALESCE(p_sitio_purok, '')), ''),
         address_notes = NULLIF(btrim(COALESCE(p_address_notes, '')), ''),
         latitude = p_latitude, longitude = p_longitude,
         contact_number = v_contact,
         contact_is_placeholder = (v_contact IS NULL),
         contact_verified_at = CASE WHEN v_contact_changed THEN NULL ELSE contact_verified_at END,
         contact_verified_by = CASE WHEN v_contact_changed THEN NULL ELSE contact_verified_by END,
         updated_by = auth.uid()
   WHERE id;

  -- A new pin (the starting point of every fee) or a new number means Delivery must be
  -- checked again: switch it off until it is re-verified.
  IF v_pin_changed OR v_contact_changed THEN
    UPDATE delivery_settings SET delivery_enabled = FALSE, updated_by = auth.uid(), updated_at = NOW()
     WHERE id AND delivery_enabled;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.save_cooperative_details(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_cooperative_details(TEXT, TEXT, DOUBLE PRECISION, DOUBLE PRECISION, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.verify_cooperative_contact()
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE d cooperative_details%ROWTYPE;
BEGIN
  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only the Manager can verify the cooperative contact number.';
  END IF;
  SELECT * INTO d FROM cooperative_details WHERE id FOR UPDATE;
  IF d.contact_number IS NULL OR d.contact_is_placeholder THEN
    RAISE EXCEPTION 'Enter the official contact number first.';
  END IF;
  UPDATE cooperative_details SET contact_verified_at = NOW(), contact_verified_by = auth.uid(), updated_by = auth.uid() WHERE id;
END $$;
REVOKE ALL ON FUNCTION public.verify_cooperative_contact() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_cooperative_contact() TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 6. Delivery fee bands (Manager only): saved as a new version, history kept
-- ════════════════════════════════════════════════════════════
-- p_bands: [{"min_km":0,"max_km":1,"fee":20}, {"min_km":1,"max_km":2.5,"fee":35}, ...]
-- Rules: starts at 0, no gaps, no overlaps; the LAST band's max_km is the farthest delivery.
CREATE OR REPLACE FUNCTION public.save_delivery_fee_bands(p_bands jsonb, p_is_demo boolean DEFAULT FALSE)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  r RECORD;
  v_prev_max NUMERIC := NULL;
  v_version INTEGER;
  v_n INTEGER := 0;
BEGIN
  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only the Manager can change the delivery fee rates.';
  END IF;
  IF p_bands IS NULL OR jsonb_typeof(p_bands) <> 'array' OR jsonb_array_length(p_bands) = 0 THEN
    RAISE EXCEPTION 'BANDS_INVALID: Add at least one distance band.';
  END IF;

  FOR r IN
    SELECT (b ->> 'min_km')::numeric AS min_km, (b ->> 'max_km')::numeric AS max_km, (b ->> 'fee')::numeric AS fee
      FROM jsonb_array_elements(p_bands) b ORDER BY (b ->> 'min_km')::numeric
  LOOP
    v_n := v_n + 1;
    IF r.min_km IS NULL OR r.max_km IS NULL OR r.fee IS NULL OR r.max_km <= r.min_km OR r.fee < 0 THEN
      RAISE EXCEPTION 'BANDS_INVALID: Each band needs a start, a larger end and a fee of zero or more.';
    END IF;
    IF v_prev_max IS NULL AND r.min_km <> 0 THEN
      RAISE EXCEPTION 'BANDS_INVALID: The first band must start at 0 km.';
    END IF;
    IF v_prev_max IS NOT NULL AND r.min_km <> v_prev_max THEN
      RAISE EXCEPTION 'BANDS_INVALID: Bands must follow each other with no gap and no overlap (a band starts where the last one ends).';
    END IF;
    v_prev_max := r.max_km;
  END LOOP;

  SELECT COALESCE(max(set_version), 0) + 1 INTO v_version FROM delivery_fee_bands;
  UPDATE delivery_fee_bands SET is_current = FALSE WHERE is_current;
  INSERT INTO delivery_fee_bands (set_version, min_km, max_km, fee, is_demo, is_current, created_by)
  SELECT v_version, (b ->> 'min_km')::numeric, (b ->> 'max_km')::numeric, (b ->> 'fee')::numeric, COALESCE(p_is_demo, FALSE), TRUE, auth.uid()
    FROM jsonb_array_elements(p_bands) b;

  -- New rates must be looked at again before Delivery stays on.
  UPDATE delivery_settings SET delivery_enabled = FALSE, updated_by = auth.uid(), updated_at = NOW() WHERE id AND delivery_enabled;
  RETURN v_version;
END $$;
REVOKE ALL ON FUNCTION public.save_delivery_fee_bands(jsonb, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_delivery_fee_bands(jsonb, boolean) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 7. The Delivery switch (Manager only). It cannot be turned on until everything is in place.
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.set_delivery_enabled(p_enabled boolean)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_missing text[];
BEGIN
  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only the Manager can switch Delivery on or off.';
  END IF;
  IF p_enabled THEN
    v_missing := public._delivery_missing();
    IF COALESCE(array_length(v_missing, 1), 0) > 0 THEN
      RAISE EXCEPTION 'DELIVERY_NOT_READY: Delivery cannot be switched on yet. Still missing: %', array_to_string(v_missing, ', ');
    END IF;
  END IF;
  UPDATE delivery_settings
     SET delivery_enabled = p_enabled,
         enabled_at = CASE WHEN p_enabled THEN NOW() ELSE enabled_at END,
         enabled_by = CASE WHEN p_enabled THEN auth.uid() ELSE enabled_by END,
         updated_by = auth.uid(), updated_at = NOW()
   WHERE id;
END $$;
REVOKE ALL ON FUNCTION public.set_delivery_enabled(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_delivery_enabled(boolean) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  One cooperative record, one settings row, no fee bands, Delivery OFF:
--     SELECT cooperative_name, barangay_name, contact_is_placeholder, latitude FROM cooperative_details;
--     SELECT delivery_enabled, allowed_barangay_codes FROM delivery_settings;
--     SELECT count(*) FROM delivery_fee_bands;                        -- 0
-- V2  What is missing today (expect all four):
--     SELECT public._delivery_missing();   -- run as the owner in the SQL editor
-- V3  The switch refuses while incomplete (run from the app as the Manager).
