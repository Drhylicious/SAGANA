-- ============================================================
-- SAGANA — Ginger / DA-AMAD follows the harvest's unit (no more "kg only")
--
-- WHY
--   Every other selling channel (Marketplace, Offer to Cooperative, Informal Sale)
--   already carries the unit of the harvest batch it came from. Ginger was the one
--   exception: harvest_batch_number_and_units.sql fixed it to kg and the Market
--   Linking tables had no unit of their own. The harvest record is now the single
--   source of truth for the unit in ALL four channels, and nothing is converted.
--
-- WHAT THIS DOES
--   1. market_linking_programs.unit and market_linking_sales.unit (default 'kg',
--      so every existing row stays what it was: kg). Backfilled from the batch.
--   2. A BEFORE INSERT trigger on each copies the unit: a request takes its
--      batch's unit, a sale takes its request's unit. A client can never choose it.
--   3. prepare_harvest_record() without the "channel crops must be kg" rule. It is
--      otherwise identical to the function in
--      supabase_schema_harvest_batch_number_and_units.sql (unit validated against
--      the active units list, batch number issued by the database).
--   Quantity and price columns keep their names (volume_kg, price_per_kg ...): they
--   mean "in the row's unit", exactly as on every other table.
--
-- WHAT IS NOT CHANGED
--   * Ginger still cannot be listed, offered or sold informally (the exclusive
--     channel rules), and Market Linking still requires the approved enrollment
--     and the Farmer's own crop photo.
--   * Stock arithmetic: a request, its sales and the batch all share one unit, so
--     reserve / sell / release remain plain additions.
--   * Totals labelled "kg" in the app add only kg rows.
--
-- Run after: supabase_schema_harvest_batch_number_and_units.sql and
-- supabase_schema_market_linking_partial_sales.sql (and the files they name).
-- Safe to re-run. Not applied automatically. Then run
-- supabase_schema_ginger_any_unit_test.sql.
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'inventory_batches' AND column_name = 'unit') THEN
    RAISE EXCEPTION 'Run supabase_schema_harvest_batch_number_and_units.sql first (inventory_batches.unit is missing).';
  END IF;
  IF to_regclass('public.market_linking_sales') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_market_linking_partial_sales.sql first (market_linking_sales is missing).';
  END IF;
  IF to_regprocedure('public.inherit_unit_from_batch()') IS NULL THEN
    RAISE EXCEPTION 'inherit_unit_from_batch() is missing. Run supabase_schema_harvest_batch_number_and_units.sql first.';
  END IF;
END;
$$;

-- ═══ 1. The unit on the request and on each sale ═════════════════════════
ALTER TABLE public.market_linking_programs ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'kg';
ALTER TABLE public.market_linking_sales    ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'kg';

-- Requests that already point at a batch take that batch's unit (all kg today).
UPDATE public.market_linking_programs p
   SET unit = b.unit
  FROM public.inventory_batches b
 WHERE b.id = p.inventory_batch_id
   AND p.unit IS DISTINCT FROM b.unit;

UPDATE public.market_linking_sales s
   SET unit = p.unit
  FROM public.market_linking_programs p
 WHERE p.id = s.program_id
   AND s.unit IS DISTINCT FROM p.unit;

-- ═══ 2. Copy the unit on insert ═══════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.inherit_unit_from_program()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.program_id IS NOT NULL THEN
    SELECT unit INTO NEW.unit FROM public.market_linking_programs WHERE id = NEW.program_id;
  END IF;
  NEW.unit := COALESCE(NEW.unit, 'kg');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_market_linking_programs_inherit_unit ON public.market_linking_programs;
CREATE TRIGGER trg_market_linking_programs_inherit_unit
  BEFORE INSERT ON public.market_linking_programs
  FOR EACH ROW EXECUTE FUNCTION public.inherit_unit_from_batch();

DROP TRIGGER IF EXISTS trg_market_linking_sales_inherit_unit ON public.market_linking_sales;
CREATE TRIGGER trg_market_linking_sales_inherit_unit
  BEFORE INSERT ON public.market_linking_sales
  FOR EACH ROW EXECUTE FUNCTION public.inherit_unit_from_program();

-- ═══ 3. A Ginger harvest may be recorded in any active unit ═══════════════
CREATE OR REPLACE FUNCTION public.prepare_harvest_record()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_master UUID;
BEGIN
  SELECT fc.crop_master_id
    INTO v_master
  FROM public.farmer_crops fc
  WHERE fc.id = NEW.crop_id;

  IF v_master IS NULL THEN
    RAISE EXCEPTION 'This crop has not been approved by the Manager yet, so a harvest cannot be recorded.';
  END IF;

  -- Unit: normalised, and it must be one of the active units.
  NEW.unit := lower(btrim(COALESCE(NEW.unit, 'kg')));
  IF NOT EXISTS (
    SELECT 1 FROM public.units WHERE is_active AND lower(name) = NEW.unit
  ) THEN
    RAISE EXCEPTION 'Unknown unit "%". Choose a unit from the list.', NEW.unit;
  END IF;

  -- Always issued here; whatever a client sent is replaced.
  NEW.batch_number := public.next_batch_number(v_master, NEW.harvest_date);
  RETURN NEW;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY CHECKS (read-only) ───────────────────────────────────────
-- 1. Both tables have the column, and every row agrees with its batch / request
--    (expect 0 rows from each):
--      SELECT p.id FROM market_linking_programs p JOIN inventory_batches b ON b.id = p.inventory_batch_id
--       WHERE p.unit IS DISTINCT FROM b.unit;
--      SELECT s.id FROM market_linking_sales s JOIN market_linking_programs p ON p.id = s.program_id
--       WHERE s.unit IS DISTINCT FROM p.unit;
-- 2. The kg-only rule is gone from the function (expect 0):
--      SELECT count(*) FROM pg_proc WHERE proname = 'prepare_harvest_record'
--        AND pg_get_functiondef(oid) ILIKE '%measured in kg%';
-- 3. The three triggers exist (expect 3 rows):
--      SELECT tgname FROM pg_trigger WHERE NOT tgisinternal AND tgname IN
--        ('trg_market_linking_programs_inherit_unit','trg_market_linking_sales_inherit_unit',
--         'trg_harvest_records_prepare');
