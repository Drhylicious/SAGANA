-- ============================================================
-- SAGANA — Registration refactor, step 11: the fixed service-area address
-- applies to Buyers as well as Farmers
--
-- WHY. Script 04 forced Region, Province, City / Municipality, Barangay and
-- Postal Code to MIMAROPA Region / Marinduque / Torrijos / Payanas / 4903 for
-- a Farmer's saved addresses only; a Buyer's addresses stayed free-form.
-- Farmers and Buyers now use the same locked area in the app (My Addresses,
-- add and edit), so the database enforces it for both: whatever a client
-- sends for those five fields, a Farmer's or a Buyer's saved address is stored
-- with the fixed values, and the one-line address is rebuilt from them.
--
-- WHAT CHANGES. Only the role test inside the existing function
-- public.buyer_addresses_farmer_fixed_area(): 'farmer' becomes 'farmer' or
-- 'buyer'. Everything else is copied unchanged from script 04. The function
-- and trigger keep their names (trg_buyer_addresses_farmer_fixed_area), so the
-- earlier checks that count triggers still read the same.
--
-- WHAT DOES NOT CHANGE.
--   * Addresses already saved are NOT rewritten. An update that does not touch
--     the location fields (label, map pin, notes, default flag) leaves the row
--     as it is; the fixed values are applied the next time the address itself
--     is saved. A Buyer's older address elsewhere therefore stays until they
--     edit it.
--   * Address rows are not deleted or merged.
--
-- Not applied automatically. Run it in the Supabase SQL editor, then run the
-- verification block at the end.
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ──────────────────────────────────────────────
-- A. The trigger from script 04 exists (expect 1 row):
--    SELECT tgname FROM pg_trigger WHERE tgname = 'trg_buyer_addresses_farmer_fixed_area';
--
-- B. Existing addresses that are NOT in the fixed area, by role. These are not
--    changed by this script; they are listed so you know what a Buyer or Farmer
--    will see replaced the next time they edit the address:
--    SELECT ur.role, ui.username, ba.label, ba.address_line, ba.region_name,
--           ba.barangay_name, ba.postal_code
--    FROM public.buyer_addresses ba
--    JOIN public.user_roles ur USING (user_id)
--    JOIN public.user_information ui USING (user_id)
--    WHERE ur.role IN ('farmer', 'buyer')
--      AND (ba.barangay_name IS DISTINCT FROM 'Payanas' OR ba.postal_code IS DISTINCT FROM '4903')
--    ORDER BY ur.role, ui.username;
-- ────────────────────────────────────────────────────────────────────────

BEGIN;

CREATE OR REPLACE FUNCTION public.buyer_addresses_farmer_fixed_area()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  SELECT role INTO v_role FROM public.user_roles WHERE user_id = NEW.user_id;
  -- Farmers and Buyers share the fixed service area. Anyone else (there is
  -- no other role with addresses today) is left alone.
  IF v_role IS NULL OR v_role NOT IN ('farmer', 'buyer') THEN
    RETURN NEW;
  END IF;

  -- On an update that does not touch the location fields (label, map pin,
  -- notes, default flag ...) leave the row exactly as it is.
  IF TG_OP = 'UPDATE'
     AND NEW.region_code            IS NOT DISTINCT FROM OLD.region_code
     AND NEW.region_name            IS NOT DISTINCT FROM OLD.region_name
     AND NEW.province_code          IS NOT DISTINCT FROM OLD.province_code
     AND NEW.province_name          IS NOT DISTINCT FROM OLD.province_name
     AND NEW.city_municipality_code IS NOT DISTINCT FROM OLD.city_municipality_code
     AND NEW.city_municipality_name IS NOT DISTINCT FROM OLD.city_municipality_name
     AND NEW.barangay_code          IS NOT DISTINCT FROM OLD.barangay_code
     AND NEW.barangay_name          IS NOT DISTINCT FROM OLD.barangay_name
     AND NEW.postal_code            IS NOT DISTINCT FROM OLD.postal_code
     AND NEW.street                 IS NOT DISTINCT FROM OLD.street
     AND NEW.building               IS NOT DISTINCT FROM OLD.building
     AND NEW.house_no               IS NOT DISTINCT FROM OLD.house_no
     AND NEW.address_line           IS NOT DISTINCT FROM OLD.address_line THEN
    RETURN NEW;
  END IF;

  -- The five fixed fields are not negotiable, whatever the caller sent.
  NEW.region_code            := '1700000000';
  NEW.region_name            := 'MIMAROPA Region';
  NEW.province_code          := '1704000000';
  NEW.province_name          := 'Marinduque';
  NEW.city_municipality_code := '1704006000';
  NEW.city_municipality_name := 'Torrijos';
  NEW.barangay_code          := '1704006019';
  NEW.barangay_name          := 'Payanas';
  NEW.postal_code            := '4903';

  -- The three typed fields stay the user's.
  NEW.street   := NULLIF(btrim(NEW.street), '');
  NEW.building := NULLIF(btrim(NEW.building), '');
  NEW.house_no := NULLIF(btrim(NEW.house_no), '');

  NEW.address_line := concat_ws(', ',
    NEW.house_no, NEW.building, NEW.street,
    'Payanas', 'Torrijos', 'Marinduque', 'MIMAROPA Region', '4903');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_buyer_addresses_farmer_fixed_area ON public.buyer_addresses;
CREATE TRIGGER trg_buyer_addresses_farmer_fixed_area
  BEFORE INSERT OR UPDATE ON public.buyer_addresses
  FOR EACH ROW EXECUTE FUNCTION public.buyer_addresses_farmer_fixed_area();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION ────────────────────────────────────────────
-- 1. Still one trigger, and the function now names both roles
--    (expect 1 row, then true):
--    SELECT tgname FROM pg_trigger WHERE tgname = 'trg_buyer_addresses_farmer_fixed_area';
--    SELECT prosrc LIKE '%''farmer'', ''buyer''%' AS covers_buyers
--    FROM pg_proc WHERE proname = 'buyer_addresses_farmer_fixed_area';
--
-- 2. Behaviour, both roles, nothing saved. Use your own ids from:
--    SELECT ur.role, ui.username, ur.user_id FROM public.user_roles ur
--    JOIN public.user_information ui USING (user_id) WHERE ur.role IN ('buyer','farmer');
--    Expect, for BOTH a buyer and a farmer: address_line
--    '12, Rizal St, Payanas, Torrijos, Marinduque, MIMAROPA Region, 4903',
--    barangay_name 'Payanas', postal_code '4903', whatever was sent:
--    DO $t$
--    DECLARE r record; v_line text; v_all text := '';
--    BEGIN
--      FOR r IN SELECT * FROM (VALUES
--          ('BUYER',  'a5fdf139-9552-4291-aac2-2bb5147bd774'::uuid),
--          ('FARMER', '533accad-bee5-4a4e-842c-683c9448192a'::uuid)) AS t(label, uid)
--      LOOP
--        INSERT INTO public.buyer_addresses (user_id, label, address_line, region_name, barangay_name, postal_code, street, house_no)
--        VALUES (r.uid, 'Test', 'x', 'NCR', 'Elsewhere', '1000', 'Rizal St', '12')
--        RETURNING address_line INTO v_line;
--        v_all := v_all || E'\n' || r.label || ' -> ' || v_line;
--      END LOOP;
--      RAISE EXCEPTION E'RESULT (nothing was saved):%', v_all;   -- the error rolls everything back
--    END $t$;
-- ============================================================
