-- ============================================================
-- SAGANA — Copra: delete it from the crop catalog (history kept), and make
-- archiving a crop affect nothing but new selections
--
-- Replaces supabase_schema_copra_archive.sql. If that script was already run,
-- this one undoes the part of it that hid archived crops' prices, and finishes
-- the job by deleting Copra instead of leaving it archived.
--
-- Business rules this implements
--   * Archiving a crop changes nothing about its existing data. Its reference
--     prices stay visible and editable, and its names, photos and categories
--     keep resolving for Farmers and Buyers.
--   * An archived crop is simply not offered for a NEW reference price or a NEW
--     Farmer crop request (the app's crop pickers list only active crops).
--     Restoring it offers it again.
--
-- What it does
--   1. Restores the original price_records read rule (markets only) and drops
--      the crop_is_listed() helper added by the archive script.
--   2. Lets signed-in users read ARCHIVED crop_master rows too. Before, the
--      policy showed Farmers and Buyers active crops only, so archiving a crop
--      silently broke every join to it for them (e.g. Farmer Market Rates drops
--      its prices). The pickers filter on is_active themselves.
--   3. Deletes Copra from crop_master, keeping its history: the one price
--      record that points at it is kept with crop_id cleared (its crop_name text
--      stays), and the app treats it as history, not a current price. Its batch
--      number counters (just sequence counters) go with it. If Copra is still
--      used by a farmer crop, a listing or a member sale, nothing is changed
--      and the script stops with the counts.
--
-- Run supabase_schema_copra_preflight.sql first if you have not. Safe to re-run.
-- ============================================================

BEGIN;

-- 1. Undo the price-hiding from the archive script.
DROP POLICY IF EXISTS "price_records: restricted markets hidden from buyers"
  ON public.price_records;
CREATE POLICY "price_records: restricted markets hidden from buyers"
  ON public.price_records
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (public.can_view_market_type(price_type));

DROP FUNCTION IF EXISTS public.crop_is_listed(UUID);

-- 2. Archived crops stay readable.
DROP POLICY IF EXISTS "crop_master: authenticated reads active" ON public.crop_master;
DROP POLICY IF EXISTS "crop_master: authenticated reads all" ON public.crop_master;
CREATE POLICY "crop_master: authenticated reads all"
  ON public.crop_master FOR SELECT
  USING (auth.role() = 'authenticated');

-- 3. Delete Copra, keeping its records.
DO $$
DECLARE
  v_id   UUID;
  n_farm INT;
  n_list INT;
  n_sale INT;
BEGIN
  SELECT id INTO v_id FROM public.crop_master
  WHERE lower(btrim(crop_name)) = 'copra';

  IF v_id IS NULL THEN
    RAISE NOTICE 'Copra is not in the crop catalog; nothing to delete.';
    RETURN;
  END IF;

  SELECT COUNT(*) INTO n_farm FROM public.farmer_crops
    WHERE crop_master_id = v_id;
  SELECT COUNT(*) INTO n_list FROM public.marketplace_listings
    WHERE crop_id = v_id;
  SELECT COUNT(*) INTO n_sale FROM public.member_sales_transactions
    WHERE crop_id = v_id;

  IF n_farm + n_list + n_sale > 0 THEN
    RAISE EXCEPTION
      'Copra is still in use (farmer crops: %, listings: %, member sales: %). Nothing was changed.',
      n_farm, n_list, n_sale;
  END IF;

  -- Keep the price history; only the link to the catalog row is cleared.
  UPDATE public.price_records SET crop_id = NULL WHERE crop_id = v_id;

  DELETE FROM public.crop_master WHERE id = v_id;
  RAISE NOTICE 'Copra deleted from the crop catalog.';
END $$;

COMMIT;

-- ── Verify (read-only) ──────────────────────────────────────────────────────
-- SELECT COUNT(*) FROM public.crop_master WHERE crop_name ILIKE '%copra%';
--   (expect 0: not active, not archived)
-- SELECT id, crop_name, crop_id, price, recorded_at FROM public.price_records
--   WHERE crop_name ILIKE '%copra%';
--   (expect the 1 record kept, crop_id empty)
-- SELECT policyname FROM pg_policies WHERE tablename = 'crop_master';
--   (expect "authenticated reads all" and "admin manages all")
-- SELECT policyname, permissive FROM pg_policies
--   WHERE tablename = 'price_records' AND policyname LIKE '%restricted markets%';
--   (expect RESTRICTIVE)
