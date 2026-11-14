-- ============================================================
-- SAGANA — Crop Shelf Life: the Farmer states the shelf life when requesting
--          a new crop  (script s03)
--
-- FOR YOUR REVIEW — NOT APPLIED. Run AFTER s01. One transaction, safe to re-run.
--
-- WHAT IT ADDS
--   crop_requests.shelf_life_days   the shelf life (days) the Farmer gives for
--                                   the crop they are requesting.
--   When the Manager / Officer approves the request and the crop is created in
--   the catalog, the new crop takes the Farmer's figure as its shelf life. It is
--   applied by triggers, so approve_crop_request() itself is not replaced. The
--   Manager can still change it afterwards in Crop Management.
--
--   A crop that already existed in the catalog is never changed by a request:
--   the figure is applied only to a crop created by that same approval.
--   A request with no figure (older requests) behaves exactly as before: the
--   crop gets the reference figure if one is on file, otherwise "not set".
--
-- NOT CHANGED: the request / approval functions, their notifications, RLS.
-- A request still carries no photo.
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='crop_master' AND column_name='shelf_life_days') THEN
    RAISE EXCEPTION 'Run supabase_schema_shelf_life_s01_foundation.sql first (crop_master.shelf_life_days is missing).';
  END IF;
END;
$$;

ALTER TABLE public.crop_requests
  ADD COLUMN IF NOT EXISTS shelf_life_days INTEGER
    CHECK (shelf_life_days IS NULL OR shelf_life_days BETWEEN 1 AND 3650);

COMMENT ON COLUMN public.crop_requests.shelf_life_days IS
  'Shelf life in days the Farmer gave for the requested crop. Becomes the new '
  'crop''s default shelf life when the request is approved.';

-- Gives the crop created for a request the Farmer's shelf life. Called when the
-- request is approved AND when the Farmer's crop is linked to the catalog,
-- because the approval function may do those two things in either order; the
-- second call finds nothing left to do.
CREATE OR REPLACE FUNCTION public._apply_requested_shelf_life(p_farmer_crop_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days   INTEGER;
  v_master UUID;
BEGIN
  IF p_farmer_crop_id IS NULL THEN
    RETURN;
  END IF;

  SELECT r.shelf_life_days INTO v_days
  FROM crop_requests r
  WHERE r.farmer_crop_id = p_farmer_crop_id
    AND r.shelf_life_days IS NOT NULL
    AND r.status IN ('pending', 'approved')
  ORDER BY r.created_at DESC
  LIMIT 1;
  IF v_days IS NULL THEN
    RETURN;
  END IF;

  SELECT fc.crop_master_id INTO v_master FROM farmer_crops fc WHERE fc.id = p_farmer_crop_id;
  IF v_master IS NULL THEN
    RETURN;                                     -- not linked to the catalog yet
  END IF;

  -- Only a crop created by THIS approval (same transaction): an existing
  -- catalog crop keeps the shelf life the cooperative gave it.
  UPDATE crop_master cm
     SET shelf_life_days = v_days
   WHERE cm.id = v_master
     AND cm.created_at = now()
     AND cm.shelf_life_days IS DISTINCT FROM v_days;
END;
$$;
REVOKE ALL ON FUNCTION public._apply_requested_shelf_life(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._crop_request_apply_shelf_life()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_TABLE_NAME = 'crop_requests' THEN
    PERFORM public._apply_requested_shelf_life(NEW.farmer_crop_id);
  ELSE
    PERFORM public._apply_requested_shelf_life(NEW.id);
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._crop_request_apply_shelf_life() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_crop_requests_apply_shelf_life ON public.crop_requests;
CREATE TRIGGER trg_crop_requests_apply_shelf_life
  AFTER UPDATE OF status ON public.crop_requests
  FOR EACH ROW
  WHEN (NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved')
  EXECUTE FUNCTION public._crop_request_apply_shelf_life();

DROP TRIGGER IF EXISTS trg_farmer_crops_apply_shelf_life ON public.farmer_crops;
CREATE TRIGGER trg_farmer_crops_apply_shelf_life
  AFTER UPDATE OF crop_master_id ON public.farmer_crops
  FOR EACH ROW
  WHEN (OLD.crop_master_id IS NULL AND NEW.crop_master_id IS NOT NULL)
  EXECUTE FUNCTION public._crop_request_apply_shelf_life();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── CHECKS (read-only) ──────────────────────────────────────────────────
-- C1  The column and the two triggers exist (expect 1 row, then 2 rows):
--     SELECT column_name FROM information_schema.columns
--      WHERE table_name='crop_requests' AND column_name='shelf_life_days';
--     SELECT tgname FROM pg_trigger WHERE tgname IN
--       ('trg_crop_requests_apply_shelf_life','trg_farmer_crops_apply_shelf_life');
-- C2  After approving a request that carried a shelf life, the new crop has it:
--     SELECT r.requested_name, r.shelf_life_days AS farmer_said, cm.shelf_life_days AS crop_has
--       FROM crop_requests r
--       JOIN farmer_crops fc ON fc.id = r.farmer_crop_id
--       JOIN crop_master cm  ON cm.id = fc.crop_master_id
--      WHERE r.status = 'approved' AND r.shelf_life_days IS NOT NULL
--      ORDER BY r.reviewed_at DESC LIMIT 10;
