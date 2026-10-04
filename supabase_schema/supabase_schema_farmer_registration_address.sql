-- Farmer Registration (Batch 4): contact number on saved addresses
--
-- Outsider Farmers now save their registration address to buyer_addresses.
-- Phone number is optional for Farmers, so a registration address can have
-- no contact number. This relaxes contact_number from NOT NULL to nullable.
-- Relaxing a constraint only: no rows change, and no column is dropped.
--
-- Must be applied BEFORE the Batch 4 app build is used for registration,
-- because a Farmer who leaves phone blank would otherwise fail the insert.
--
-- Not applied automatically. Run it in the Supabase SQL editor, then run
-- the verification block at the end.

BEGIN;

ALTER TABLE public.buyer_addresses
  ALTER COLUMN contact_number DROP NOT NULL;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION (read-only) ────────────────────────────────
-- 1. contact_number is now nullable (expect is_nullable = 'YES'):
--    SELECT is_nullable FROM information_schema.columns
--    WHERE table_schema = 'public' AND table_name = 'buyer_addresses'
--      AND column_name = 'contact_number';
--
-- 2. Existing rows are untouched (expect rows_missing_contact = 0 on a fresh
--    database; any nonzero count is a pre-existing row, not caused by this):
--    SELECT count(*) AS rows_total,
--           count(*) FILTER (WHERE contact_number IS NULL) AS rows_missing_contact
--    FROM public.buyer_addresses;
--
-- 3. Batch 3 structured-address migration is also applied (expect 12 rows):
--    SELECT count(*) FROM information_schema.columns
--    WHERE table_schema = 'public' AND table_name = 'buyer_addresses'
--      AND column_name IN ('region_code','region_name','province_code',
--        'province_name','city_municipality_code','city_municipality_name',
--        'barangay_code','barangay_name','postal_code','street','building',
--        'house_no');
