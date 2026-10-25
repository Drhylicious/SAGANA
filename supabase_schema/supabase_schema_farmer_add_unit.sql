-- ============================================================
-- SAGANA — Farmers can add a measurement unit ("+ Unit" in Record New Harvest)
--
-- The units list (public.units, see supabase_schema_units.sql) was managed by
-- staff only. Record New Harvest now offers the same "+ Unit" row Price
-- Management and Inventory Management have, so an active Farmer needs to be
-- able to ADD a unit when the one they need is missing.
--
--   * INSERT only. A Farmer still cannot rename, deactivate or delete a unit;
--     only staff can (the existing "units: staff manages all" policy).
--   * The new unit is always active, is stamped with the Farmer as its creator
--     by the existing trigger, and goes through the same name rule (lower-case,
--     1-20 characters, letters/digits/space . / -) and the same
--     case-insensitive unique index as a unit a Manager adds.
--   * To keep the list tidy, a Farmer can add at most 10 units in 24 hours.
--     Staff are not limited.
--
-- Nothing existing is changed or removed. Safe to re-run.
-- Not applied automatically: run in the Supabase SQL editor, then the
-- VERIFICATION block at the end.
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.units') IS NULL THEN
    RAISE EXCEPTION 'public.units is missing. Run supabase_schema_units.sql first.';
  END IF;
END;
$$;

DROP POLICY IF EXISTS "units: active farmer adds" ON public.units;
CREATE POLICY "units: active farmer adds"
  ON public.units FOR INSERT TO authenticated
  WITH CHECK (
    is_active = TRUE
    AND EXISTS (
      SELECT 1 FROM public.user_roles r
      WHERE r.user_id = auth.uid() AND r.role = 'farmer' AND r.status = 'active'
    )
  );

CREATE OR REPLACE FUNCTION public.limit_farmer_unit_additions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only a signed-in Farmer is limited; staff and the SQL editor are not.
  IF auth.uid() IS NOT NULL
     AND NOT public.is_staff()
     AND (SELECT count(*) FROM public.units
           WHERE created_by = auth.uid() AND created_at > now() - interval '24 hours') >= 10 THEN
    RAISE EXCEPTION 'You have added the most units allowed for today. Please choose one from the list.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_units_limit_farmer ON public.units;
CREATE TRIGGER trg_units_limit_farmer
  BEFORE INSERT ON public.units
  FOR EACH ROW EXECUTE FUNCTION public.limit_farmer_unit_additions();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. Policy and trigger exist (expect 1 row each):
--    SELECT policyname, cmd FROM pg_policies WHERE tablename = 'units' ORDER BY 1;
--    SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.units'::regclass AND tgname = 'trg_units_limit_farmer';
-- 2. Then run supabase_schema_farmer_add_unit_test.sql (expect FAILED CHECKS: 0).
-- ───────────────────────────────────────────────────────────────────────────
