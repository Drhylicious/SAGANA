-- ============================================================
-- SAGANA — Units lookup table
--
-- Problem: the unit of measure was a hardcoded Dart list in two places that
-- had drifted apart: Inventory Management offered bag/kg/sack/piece/liter/
-- set/bottle, Price Management offered kg/g/pc/sack. Neither could gain a unit
-- without an app release.
--
-- Fix: one staff-managed `units` table, shaped like inventory_categories /
-- crop_categories. Both screens read their dropdown from it and a Manager can
-- add a unit from the dropdown. Consuming tables keep storing the unit as
-- plain TEXT exactly as before (cooperative_inventory.unit, price_records
-- .unit), so no existing record, report or join changes.
--
-- What this script does
--   1. Creates public.units (names are lower-case, trimmed, 1-20 characters,
--      unique ignoring case) with RLS: staff manage, authenticated read active.
--   2. Seeds the units both screens already offered, plus every unit already
--      stored on an inventory item or a price record, so nothing in use is
--      missing from the dropdowns.
--   3. Drops any old CHECK constraint on a `unit` column of
--      cooperative_inventory, price_records, loan_items_master (found by
--      column, not by guessed name) so a new unit is not rejected by a stale
--      fixed list.
--   4. Adds a guard trigger on cooperative_inventory and price_records: a new
--      row, or a changed unit, must use a unit that exists in public.units.
--      Unchanged units on existing rows are never re-checked.
--
-- Safe to re-run. Run supabase_schema_units_preflight.sql first.
-- ============================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.units (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        TEXT        NOT NULL,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order  INT         NOT NULL DEFAULT 100,
  created_by  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT units_name_format CHECK (
    name = lower(btrim(name))
    AND char_length(name) BETWEEN 1 AND 20
    AND name ~ '^[a-z][a-z0-9 ./-]*$'
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS units_name_lower_key
  ON public.units (lower(name));

DROP TRIGGER IF EXISTS trg_units_updated_at ON public.units;
CREATE TRIGGER trg_units_updated_at
  BEFORE UPDATE ON public.units
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

-- Who added it: stamped by the database, not trusted from the client.
CREATE OR REPLACE FUNCTION public.units_stamp_creator()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  NEW.created_by := auth.uid();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_units_stamp_creator ON public.units;
CREATE TRIGGER trg_units_stamp_creator
  BEFORE INSERT ON public.units
  FOR EACH ROW EXECUTE FUNCTION public.units_stamp_creator();

ALTER TABLE public.units ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "units: staff manages all" ON public.units;
CREATE POLICY "units: staff manages all"
  ON public.units FOR ALL
  USING (public.is_staff())
  WITH CHECK (public.is_staff());

DROP POLICY IF EXISTS "units: authenticated reads active" ON public.units;
CREATE POLICY "units: authenticated reads active"
  ON public.units FOR SELECT
  USING (is_active = TRUE AND auth.role() = 'authenticated');

-- ── Seed: the units both screens already offered ────────────────────────────
INSERT INTO public.units (name, sort_order) VALUES
  ('kg', 1), ('g', 2), ('sack', 3), ('bag', 4),
  ('piece', 5), ('liter', 6), ('set', 7), ('bottle', 8)
ON CONFLICT (lower(name)) DO NOTHING;

-- ── Seed: every unit already in use (e.g. 'pc' on older price records) ──────
INSERT INTO public.units (name, sort_order)
SELECT DISTINCT lower(btrim(u)), 100
FROM (
  SELECT unit AS u FROM public.cooperative_inventory
  UNION
  SELECT unit FROM public.price_records
) used
WHERE u IS NOT NULL
  AND lower(btrim(u)) ~ '^[a-z][a-z0-9 ./-]*$'
  AND char_length(btrim(u)) BETWEEN 1 AND 20
ON CONFLICT (lower(name)) DO NOTHING;

-- ── Drop old fixed-list CHECK constraints on unit columns ───────────────────
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT c.conrelid::regclass AS tbl, c.conname
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
    WHERE c.contype = 'c'
      AND a.attname = 'unit'
      AND c.conrelid IN (
        to_regclass('public.cooperative_inventory'),
        to_regclass('public.price_records'),
        to_regclass('public.loan_items_master')
      )
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT %I', r.tbl, r.conname);
    RAISE NOTICE 'Dropped % on %', r.conname, r.tbl;
  END LOOP;
END $$;

-- ── Guard: a new or changed unit must exist in public.units ─────────────────
CREATE OR REPLACE FUNCTION public.enforce_known_unit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.unit IS NOT DISTINCT FROM OLD.unit THEN
    RETURN NEW;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.units
    WHERE is_active AND lower(name) = lower(btrim(NEW.unit))
  ) THEN
    RAISE EXCEPTION 'Unknown unit "%". Add it as a unit first.', NEW.unit
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cooperative_inventory_known_unit ON public.cooperative_inventory;
CREATE TRIGGER trg_cooperative_inventory_known_unit
  BEFORE INSERT OR UPDATE OF unit ON public.cooperative_inventory
  FOR EACH ROW EXECUTE FUNCTION public.enforce_known_unit();

DROP TRIGGER IF EXISTS trg_price_records_known_unit ON public.price_records;
CREATE TRIGGER trg_price_records_known_unit
  BEFORE INSERT OR UPDATE OF unit ON public.price_records
  FOR EACH ROW EXECUTE FUNCTION public.enforce_known_unit();

COMMIT;

-- ── Verify (read-only) ──────────────────────────────────────────────────────
-- SELECT name, sort_order, is_active FROM public.units ORDER BY sort_order, name;
-- -- Every unit in use must be present (expect 0 rows):
-- SELECT DISTINCT unit FROM public.cooperative_inventory
--   WHERE lower(btrim(unit)) NOT IN (SELECT lower(name) FROM public.units)
-- UNION
-- SELECT DISTINCT unit FROM public.price_records
--   WHERE lower(btrim(unit)) NOT IN (SELECT lower(name) FROM public.units);
