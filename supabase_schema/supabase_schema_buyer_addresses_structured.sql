-- My Addresses — Batch 3: structured address columns (additive only)
--
-- Adds the PSGC hierarchy (region → province → city/municipality →
-- barangay, names and codes), postal code, and street / building / house
-- number to buyer_addresses. Nothing is dropped or renamed: address_line
-- stays and existing rows keep working unchanged. New columns are NULL on
-- every row saved before this migration.
--
-- Not applied automatically. Run it in the Supabase SQL editor, then run
-- the verification block at the end.

BEGIN;

ALTER TABLE public.buyer_addresses
  ADD COLUMN IF NOT EXISTS region_code            TEXT,
  ADD COLUMN IF NOT EXISTS region_name            TEXT,
  ADD COLUMN IF NOT EXISTS province_code          TEXT,
  ADD COLUMN IF NOT EXISTS province_name          TEXT,
  ADD COLUMN IF NOT EXISTS city_municipality_code TEXT,
  ADD COLUMN IF NOT EXISTS city_municipality_name TEXT,
  ADD COLUMN IF NOT EXISTS barangay_code          TEXT,
  ADD COLUMN IF NOT EXISTS barangay_name          TEXT,
  ADD COLUMN IF NOT EXISTS postal_code            TEXT,
  ADD COLUMN IF NOT EXISTS street                 TEXT,
  ADD COLUMN IF NOT EXISTS building               TEXT,
  ADD COLUMN IF NOT EXISTS house_no               TEXT;

-- Postal codes are exactly four digits (format check only). Added as a
-- named constraint so it can be dropped later without touching the table.
ALTER TABLE public.buyer_addresses
  DROP CONSTRAINT IF EXISTS buyer_addresses_postal_code_format;
ALTER TABLE public.buyer_addresses
  ADD CONSTRAINT buyer_addresses_postal_code_format
  CHECK (postal_code IS NULL OR postal_code ~ '^[0-9]{4}$');

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION (read-only) ────────────────────────────────
-- 1. All twelve new columns exist (expect 12 rows):
--    SELECT column_name FROM information_schema.columns
--    WHERE table_schema = 'public' AND table_name = 'buyer_addresses'
--      AND column_name IN ('region_code','region_name','province_code',
--        'province_name','city_municipality_code','city_municipality_name',
--        'barangay_code','barangay_name','postal_code','street','building',
--        'house_no');
--
-- 2. Existing rows are untouched (new columns NULL, address_line intact):
--    SELECT count(*) AS rows_total,
--           count(*) FILTER (WHERE region_code IS NOT NULL) AS rows_structured,
--           count(*) FILTER (WHERE address_line IS NULL)   AS rows_missing_line
--    FROM public.buyer_addresses;
--    -- expect rows_structured = 0 right after deploy, rows_missing_line = 0.
--
-- 3. The postal-code constraint exists (expect 1 row):
--    SELECT conname FROM pg_constraint
--    WHERE conrelid = 'public.buyer_addresses'::regclass
--      AND conname = 'buyer_addresses_postal_code_format';
