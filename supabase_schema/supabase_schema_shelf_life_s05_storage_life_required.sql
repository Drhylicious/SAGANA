-- ═══════════════════════════════════════════════════════════════════════════
-- SAGANA · Shelf life s05 · Storage Life is required too
-- ═══════════════════════════════════════════════════════════════════════════
-- Run AFTER c01 (it adds crop_master.storage_life_days) and s04.
-- One transaction. Safe to run more than once.
--
-- THE RULE
--   Every crop has BOTH: a Shelf Life for its harvested produce and a Storage
--   Life for its planting materials. A new crop cannot be saved, and a Farmer's
--   crop request cannot be approved, without both.
--
-- WHAT THIS CHANGES
--   crop_requests.storage_life_days               set by the Manager / Officer in the approval form
--   set_crop_request_storage_life(request, days)   new
--   _crop_request_require_shelf_life()             approval also needs the Storage Life
--   _apply_requested_shelf_life()                  also gives the new crop its Storage Life
--   _crop_master_require_shelf_life()              a NEW crop needs both by the end of its transaction
--   trg_crop_master_keep_storage_life              a Storage Life that is set cannot be cleared
--
-- NOT CHANGED: approve_crop_request is not rewritten. Crops already in the
-- catalog WITHOUT a Storage Life stay as they are until they are edited (the
-- Edit Crop form now asks for it); their planting-material stock is simply not
-- tracked until then. Farmers are never asked for a Storage Life.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='crop_master' AND column_name='storage_life_days') THEN
    RAISE EXCEPTION 'Run supabase_schema_coop_shelf_life_c01_inventory_lots.sql first (crop_master.storage_life_days is missing).';
  END IF;
  IF to_regprocedure('public._crop_master_require_shelf_life()') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_shelf_life_s04_shelf_life_required.sql first.';
  END IF;
END;
$$;

-- ═══ 1. The Storage Life of a requested crop ══════════════════════════════
ALTER TABLE public.crop_requests
  ADD COLUMN IF NOT EXISTS storage_life_days INTEGER
    CHECK (storage_life_days IS NULL OR storage_life_days BETWEEN 1 AND 36500);

COMMENT ON COLUMN public.crop_requests.storage_life_days IS
  'Storage Life in days for the requested crop''s planting materials, set by the Manager or '
  'Officer before approving. Becomes the new crop''s Storage Life on approval.';

CREATE OR REPLACE FUNCTION public.set_crop_request_storage_life(p_request_id UUID, p_days INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can set the storage life of a crop request.';
  END IF;
  IF p_days IS NULL OR p_days < 1 OR p_days > 36500 THEN
    RAISE EXCEPTION 'CROP_STORAGE_LIFE_REQUIRED: Enter the storage life in days (1 to 36500).';
  END IF;

  UPDATE crop_requests
     SET storage_life_days = p_days
   WHERE id = p_request_id AND status = 'pending';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This crop request was not found or has already been reviewed.';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.set_crop_request_storage_life(UUID, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_crop_request_storage_life(UUID, INTEGER) TO authenticated;

-- ═══ 2. No approval without both ══════════════════════════════════════════
-- Same function as s04, now checking the Storage Life as well. A request for a
-- crop that is already in the catalog uses the catalog's values.
CREATE OR REPLACE FUNCTION public._crop_request_require_shelf_life()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_shelf   INTEGER;
  v_storage INTEGER;
BEGIN
  SELECT cm.shelf_life_days, cm.storage_life_days INTO v_shelf, v_storage
  FROM crop_master cm
  WHERE lower(btrim(cm.crop_name)) = lower(btrim(NEW.requested_name))
  LIMIT 1;

  IF COALESCE(NEW.shelf_life_days, v_shelf) IS NULL THEN
    RAISE EXCEPTION 'CROP_SHELF_LIFE_REQUIRED: Set the shelf life of % before approving this request.',
      COALESCE(NEW.requested_name, 'this crop');
  END IF;
  IF COALESCE(NEW.storage_life_days, v_storage) IS NULL THEN
    RAISE EXCEPTION 'CROP_STORAGE_LIFE_REQUIRED: Set the storage life of % before approving this request.',
      COALESCE(NEW.requested_name, 'this crop');
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._crop_request_require_shelf_life() FROM PUBLIC, anon, authenticated;

-- ═══ 3. The approved crop receives both values ════════════════════════════
-- Same function as s04, with the Storage Life handled the same way as the
-- Shelf Life: given to a crop created by this approval, or to a catalog crop
-- that has none. A value already in the catalog is never overwritten.
CREATE OR REPLACE FUNCTION public._apply_requested_shelf_life(p_farmer_crop_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days    INTEGER;
  v_storage INTEGER;
  v_master  UUID;
BEGIN
  IF p_farmer_crop_id IS NULL THEN
    RETURN;
  END IF;

  SELECT r.shelf_life_days, r.storage_life_days INTO v_days, v_storage
  FROM crop_requests r
  WHERE r.farmer_crop_id = p_farmer_crop_id
    AND (r.shelf_life_days IS NOT NULL OR r.storage_life_days IS NOT NULL)
    AND r.status IN ('pending', 'approved')
  ORDER BY r.created_at DESC
  LIMIT 1;
  IF v_days IS NULL AND v_storage IS NULL THEN
    RETURN;
  END IF;

  SELECT fc.crop_master_id INTO v_master FROM farmer_crops fc WHERE fc.id = p_farmer_crop_id;
  IF v_master IS NULL THEN
    RETURN;                                     -- not linked to the catalog yet
  END IF;

  IF v_days IS NOT NULL THEN
    UPDATE crop_master cm
       SET shelf_life_days = v_days
     WHERE cm.id = v_master
       AND (cm.created_at = now() OR cm.shelf_life_days IS NULL)
       AND cm.shelf_life_days IS DISTINCT FROM v_days;
  END IF;
  IF v_storage IS NOT NULL THEN
    UPDATE crop_master cm
       SET storage_life_days = v_storage
     WHERE cm.id = v_master
       AND (cm.created_at = now() OR cm.storage_life_days IS NULL)
       AND cm.storage_life_days IS DISTINCT FROM v_storage;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public._apply_requested_shelf_life(UUID) FROM PUBLIC, anon, authenticated;

-- ═══ 4. A NEW catalog crop needs both ═════════════════════════════════════
-- Same deferred check as s04 (it runs at the end of the transaction, after an
-- approval has filled the values in), now for the Storage Life as well.
CREATE OR REPLACE FUNCTION public._crop_master_require_shelf_life()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days    INTEGER;
  v_storage INTEGER;
  v_name    TEXT;
BEGIN
  SELECT cm.shelf_life_days, cm.storage_life_days, cm.crop_name INTO v_days, v_storage, v_name
  FROM crop_master cm WHERE cm.id = NEW.id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  IF v_days IS NULL THEN
    RAISE EXCEPTION 'CROP_SHELF_LIFE_REQUIRED: Set the shelf life of % before saving it.',
      COALESCE(v_name, 'this crop');
  END IF;
  IF v_storage IS NULL THEN
    RAISE EXCEPTION 'CROP_STORAGE_LIFE_REQUIRED: Set the storage life of % before saving it.',
      COALESCE(v_name, 'this crop');
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._crop_master_require_shelf_life() FROM PUBLIC, anon, authenticated;

-- A Storage Life that is set cannot be cleared again.
CREATE OR REPLACE FUNCTION public._crop_master_keep_storage_life()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'CROP_STORAGE_LIFE_REQUIRED: The storage life of % cannot be removed. Enter a new number of days instead.',
    COALESCE(NEW.crop_name, 'this crop');
END;
$$;

DROP TRIGGER IF EXISTS trg_crop_master_keep_storage_life ON public.crop_master;
CREATE TRIGGER trg_crop_master_keep_storage_life
  BEFORE UPDATE OF storage_life_days ON public.crop_master
  FOR EACH ROW
  WHEN (OLD.storage_life_days IS NOT NULL AND NEW.storage_life_days IS NULL)
  EXECUTE FUNCTION public._crop_master_keep_storage_life();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ═══ Checks (run after the script) ════════════════════════════════════════
-- 1. Objects exist (expect 1 column, 1 trigger, 1 function):
--      SELECT column_name FROM information_schema.columns
--       WHERE table_name = 'crop_requests' AND column_name = 'storage_life_days';
--      SELECT tgname FROM pg_trigger WHERE tgname = 'trg_crop_master_keep_storage_life';
--      SELECT proname FROM pg_proc WHERE proname = 'set_crop_request_storage_life';
--
-- 2. Crops that still need a Storage Life (set it in Crop Management → Edit Crop):
--      SELECT crop_name, category, shelf_life_days FROM crop_master
--      WHERE storage_life_days IS NULL ORDER BY crop_name;
--
-- 3. Crops with no image (the Add / Edit Crop form now requires one):
--      SELECT crop_name FROM crop_master
--      WHERE COALESCE(btrim(image_url), '') = '' ORDER BY crop_name;
