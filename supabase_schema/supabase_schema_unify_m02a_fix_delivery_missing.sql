-- ============================================================
-- SAGANA — Unified purchasing m02a: fix for m02's _delivery_missing()
--
-- FOR YOUR REVIEW — NOT APPLIED. Run ONLY if you already ran the ORIGINAL m02 (before this fix).
-- If you have not run m02 yet, run the corrected m02 instead and skip this file.
--
-- THE BUG. In m02, _delivery_missing() built its list with `text[] || 'literal'`. PostgreSQL reads
-- the bare literal as an ARRAY, so every call failed with
--   22P02: malformed array literal: "cooperative_pin"
-- and get_delivery_status() (which calls it) answered 400. The app treated that as "Delivery is
-- off", so nothing broke for users, but the Delivery Settings checklist could not load.
--
-- THE FIX. array_append(), which takes the text value directly. Same function, same result shape:
-- nothing else is changed, no data is touched, no rate is created, Delivery stays OFF.
-- ============================================================

BEGIN;

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

COMMIT;

NOTIFY pgrst, 'reload schema';

-- VERIFICATION (read-only)
-- V1  It runs, Delivery is off, and everything is listed as missing:
--     SELECT public.get_delivery_status();
--     -- expect: enabled false, ready false, missing = ["cooperative_pin","contact_number","fee_bands"]
--     -- (as the owner in the SQL editor you are not "staff", so "missing" may show [] there; the app
--     --  shows it to the Manager)
-- V2  The raw list:
--     SELECT public._delivery_missing();
--     -- expect: {cooperative_pin,contact_number,fee_bands}
