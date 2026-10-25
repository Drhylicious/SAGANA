-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_registration_13_farm_address_parts.sql
--
-- Farm Details: the farm address now follows My Addresses. The five area fields
-- (MIMAROPA Region, Marinduque, Torrijos, Payanas, 4903) are fixed in the app,
-- so only the three typed parts need their own columns.
--
--   farm_street, farm_building, farm_house_no   typed parts (new, nullable)
--   farm_address                                 full one-line address. Still the
--                                                column every screen reads. The app
--                                                writes it from the parts plus the
--                                                fixed area, in the same order as
--                                                My Addresses.
--   farm_latitude / farm_longitude               the farm's map pin (unchanged)
--
-- Existing farms are NOT converted. A farm saved before this has only the old
-- free-text farm_address and NULL parts; the app keeps that text until the
-- farmer fills in the new fields. Nothing is parsed or guessed.
--
-- The home addresses (buyer_addresses) are a different table and are not touched.
--
-- Safe to re-run. Run once in the Supabase SQL Editor.
-- ─────────────────────────────────────────────────────────────────────────────

BEGIN;

ALTER TABLE public.farmer_profiles
  ADD COLUMN IF NOT EXISTS farm_street   text,
  ADD COLUMN IF NOT EXISTS farm_building text,
  ADD COLUMN IF NOT EXISTS farm_house_no text;

COMMENT ON COLUMN public.farmer_profiles.farm_street   IS 'Typed street of the farm. Area is fixed: Payanas, Torrijos, Marinduque, MIMAROPA 4903.';
COMMENT ON COLUMN public.farmer_profiles.farm_building IS 'Typed building of the farm (optional).';
COMMENT ON COLUMN public.farmer_profiles.farm_house_no IS 'Typed house / lot number of the farm.';

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (run each on its own) ──────────────────────────────────────
-- 1. The three columns exist (expect 3 rows):
--    SELECT column_name, data_type FROM information_schema.columns
--    WHERE table_schema = 'public' AND table_name = 'farmer_profiles'
--      AND column_name IN ('farm_street', 'farm_building', 'farm_house_no')
--    ORDER BY 1;
--
-- 2. How many farms are on the old free-text address, and how many are structured:
--    SELECT count(*) FILTER (WHERE farm_address IS NOT NULL AND farm_street IS NULL) AS old_text_only,
--           count(*) FILTER (WHERE farm_street IS NOT NULL)                          AS structured,
--           count(*) FILTER (WHERE farm_address IS NULL)                             AS no_address
--    FROM public.farmer_profiles;
--
-- 3. Every structured farm's one-line address matches its parts (expect 0 rows;
--    the app builds it as house no., building, street, Payanas, Torrijos,
--    Marinduque, MIMAROPA Region, 4903):
--    SELECT user_id, farm_address FROM public.farmer_profiles
--    WHERE farm_street IS NOT NULL
--      AND farm_address IS DISTINCT FROM concat_ws(', ',
--            nullif(btrim(farm_house_no), ''), nullif(btrim(farm_building), ''), btrim(farm_street),
--            'Payanas', 'Torrijos', 'Marinduque', 'MIMAROPA Region', '4903');
--
-- 4. Farm pins: both coordinates or neither (expect 0 rows):
--    SELECT user_id, farm_latitude, farm_longitude FROM public.farmer_profiles
--    WHERE (farm_latitude IS NULL) <> (farm_longitude IS NULL);
--
-- 5. Farm pins that are NOT on Marinduque island (expect 0 rows; Marinduque lies
--    roughly between 13.17 and 13.58 N and 121.81 and 122.20 E). A row here is a
--    pin saved in the wrong place and should be re-pinned by the farmer:
--    SELECT ui.full_name, fp.farm_name, fp.farm_latitude, fp.farm_longitude
--    FROM public.farmer_profiles fp JOIN public.user_information ui ON ui.user_id = fp.user_id
--    WHERE fp.farm_latitude IS NOT NULL
--      AND NOT (fp.farm_latitude BETWEEN 13.17 AND 13.58 AND fp.farm_longitude BETWEEN 121.81 AND 122.20);
--
-- 6. How far each pin is from the middle of Payanas (13.3213 N, 122.0394 E), in
--    kilometres, farthest first. The app warns above 6 km:
--    SELECT ui.full_name, fp.farm_name,
--           round((111.32 * sqrt(power(fp.farm_latitude - 13.3213, 2)
--             + power((fp.farm_longitude - 122.0394) * cos(radians(13.3213)), 2)))::numeric, 2) AS km_from_payanas
--    FROM public.farmer_profiles fp JOIN public.user_information ui ON ui.user_id = fp.user_id
--    WHERE fp.farm_latitude IS NOT NULL ORDER BY km_from_payanas DESC LIMIT 20;
