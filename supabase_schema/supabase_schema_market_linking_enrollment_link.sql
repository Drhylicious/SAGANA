-- ============================================================
-- SAGANA — Explicit link from a harvest submission to its Enrollment
-- (Final verification follow-up — architectural improvement)
--
-- market_linking_programs (one row per harvest sale) and
-- da_amad_enrollments (one row per program-membership decision) were only
-- ever related implicitly, by matching farmer_id — correct in practice
-- (submit_ginger_for_sale() already checks for an approved enrollment
-- before allowing the insert) but not expressed in the schema itself.
-- This adds the real FK, and has submit_ginger_for_sale() populate it,
-- so "which enrollment authorized this sale" is a direct join instead of
-- an inferred relationship.
--
-- Nullable and additive only — existing rows are simply backfilled where
-- a matching approved enrollment can be found; nothing else about either
-- table changes, and no existing query breaks.
-- ============================================================

BEGIN;

ALTER TABLE public.market_linking_programs
  ADD COLUMN IF NOT EXISTS enrollment_id UUID REFERENCES public.da_amad_enrollments(id);

CREATE INDEX IF NOT EXISTS idx_market_linking_programs_enrollment
  ON public.market_linking_programs (enrollment_id);

-- ─── submit_ginger_for_sale(): populate enrollment_id going forward ────────
-- Full function body re-supplied (CREATE OR REPLACE requires the whole
-- thing) — identical to supabase_schema_da_amad_enrollment.sql's version,
-- plus looking up and storing the approving enrollment's id.
CREATE OR REPLACE FUNCTION submit_ginger_for_sale(
  p_inventory_batch_id UUID,
  p_volume_kg NUMERIC
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer_id UUID := auth.uid();
  v_enrollment_id UUID;
  v_new_id UUID;
BEGIN
  SELECT id INTO v_enrollment_id
  FROM da_amad_enrollments
  WHERE farmer_id = v_farmer_id AND status = 'approved'
  ORDER BY reviewed_at DESC NULLS LAST
  LIMIT 1;

  IF v_enrollment_id IS NULL THEN
    RAISE EXCEPTION 'An approved Market Linking enrollment is required to submit a Ginger harvest';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM inventory_batches
    WHERE id = p_inventory_batch_id AND farmer_id = v_farmer_id
  ) THEN
    RAISE EXCEPTION 'That batch does not belong to you';
  END IF;

  INSERT INTO market_linking_programs (
    farmer_id, crop_name, season_year, status, created_by,
    inventory_batch_id, volume_kg, submitted_at, enrollment_id
  )
  VALUES (
    v_farmer_id, 'Ginger', EXTRACT(YEAR FROM NOW())::INT, 'submitted', v_farmer_id,
    p_inventory_batch_id, p_volume_kg, NOW(), v_enrollment_id
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

GRANT EXECUTE ON FUNCTION submit_ginger_for_sale(UUID, NUMERIC) TO authenticated;

-- ─── Backfill existing rows where a matching approved enrollment exists ────
-- Best-effort only — a row submitted before Enrollment existed has no
-- real enrollment to point to, and is simply left NULL (that's accurate,
-- not a gap: it genuinely wasn't authorized through this gate).
UPDATE public.market_linking_programs mlp
SET enrollment_id = de.id
FROM public.da_amad_enrollments de
WHERE mlp.farmer_id = de.farmer_id
  AND de.status = 'approved'
  AND mlp.enrollment_id IS NULL;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) New submissions populate the link:
--    SELECT id, enrollment_id FROM market_linking_programs
--    ORDER BY submitted_at DESC LIMIT 1;
--    -- expect enrollment_id NOT NULL for anything submitted after this
--    -- migration, via submit_ginger_for_sale()
--
-- 2) The join resolves correctly:
--    SELECT mlp.id, mlp.status, de.status AS enrollment_status
--    FROM market_linking_programs mlp
--    JOIN da_amad_enrollments de ON de.id = mlp.enrollment_id;
