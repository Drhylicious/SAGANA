-- ═══════════════════════════════════════════════════════════════════════════
-- SAGANA · Shelf life s04 · Every usable crop must have a shelf life
-- ═══════════════════════════════════════════════════════════════════════════
-- Run AFTER s03 (supabase_schema_shelf_life_s03_crop_request_shelf_life.sql).
-- Safe to run more than once.
--
-- The rule:
--   • A crop added to Crop Management must have its shelf life set.
--   • A Farmer's crop request cannot be approved until its shelf life is set;
--     the Manager / authorized Officer confirms or corrects the Farmer's figure
--     in the approval form.
--   • A Farmer cannot add a catalog crop whose shelf life is not set.
--
-- What this adds:
--   1. set_crop_request_shelf_life(p_request_id, p_days)   staff set the figure
--      on a pending request before approving it.
--   2. trg_crop_requests_require_shelf_life   approving a request with no shelf
--      life is refused (unless the crop is already in the catalog with one).
--   3. _apply_requested_shelf_life   also fills in a catalog crop that has none.
--   4. trg_crop_master_require_shelf_life     a NEW catalog crop must have a
--      shelf life by the end of its transaction, and a shelf life that is set
--      cannot be cleared again.
--   5. trg_farmer_crops_require_shelf_life    a Farmer adding a catalog crop
--      with no shelf life is refused.
--
-- NOT changed:
--   • approve_crop_request is not rewritten.
--   • Crops ALREADY in the catalog without a shelf life stay as they are (they
--     are simply not offered to Farmers until the Manager sets one). Crops
--     Farmers already have on their Crop Roster are untouched.
--   • Program Management adds crops to a Farmer's roster on the staff side;
--     that path is not blocked here (it is reviewed separately).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='crop_requests' AND column_name='shelf_life_days') THEN
    RAISE EXCEPTION 'Run supabase_schema_shelf_life_s03_crop_request_shelf_life.sql first (crop_requests.shelf_life_days is missing).';
  END IF;
END;
$$;

-- ═══ 1. Staff set the shelf life of a pending request ═════════════════════
CREATE OR REPLACE FUNCTION public.set_crop_request_shelf_life(p_request_id UUID, p_days INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can set the shelf life of a crop request.';
  END IF;
  IF p_days IS NULL OR p_days < 1 OR p_days > 3650 THEN
    RAISE EXCEPTION 'CROP_SHELF_LIFE_REQUIRED: Enter the shelf life in days (1 to 3650).';
  END IF;

  UPDATE crop_requests
     SET shelf_life_days = p_days
   WHERE id = p_request_id AND status = 'pending';
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This crop request was not found or has already been reviewed.';
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.set_crop_request_shelf_life(UUID, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_crop_request_shelf_life(UUID, INTEGER) TO authenticated;

-- ═══ 2. No approval without a shelf life ══════════════════════════════════
CREATE OR REPLACE FUNCTION public._crop_request_require_shelf_life()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.shelf_life_days IS NOT NULL THEN
    RETURN NEW;
  END IF;
  -- The requested crop is already in the catalog with a shelf life: that one applies.
  IF EXISTS (SELECT 1 FROM crop_master cm
             WHERE lower(btrim(cm.crop_name)) = lower(btrim(NEW.requested_name))
               AND cm.shelf_life_days IS NOT NULL) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'CROP_SHELF_LIFE_REQUIRED: Set the shelf life of % before approving this request.',
    COALESCE(NEW.requested_name, 'this crop');
END;
$$;
REVOKE ALL ON FUNCTION public._crop_request_require_shelf_life() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_crop_requests_require_shelf_life ON public.crop_requests;
CREATE TRIGGER trg_crop_requests_require_shelf_life
  BEFORE UPDATE OF status ON public.crop_requests
  FOR EACH ROW
  WHEN (NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved')
  EXECUTE FUNCTION public._crop_request_require_shelf_life();

-- ═══ 3. The request's figure also fills a catalog crop that has none ══════
-- Same function as s03 with one change in the last UPDATE: besides a crop
-- created by this approval, a catalog crop with NO shelf life receives it too.
-- A catalog crop that already has a shelf life is never overwritten.
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

  UPDATE crop_master cm
     SET shelf_life_days = v_days
   WHERE cm.id = v_master
     AND (cm.created_at = now() OR cm.shelf_life_days IS NULL)
     AND cm.shelf_life_days IS DISTINCT FROM v_days;
END;
$$;
REVOKE ALL ON FUNCTION public._apply_requested_shelf_life(UUID) FROM PUBLIC, anon, authenticated;

-- ═══ 4. A catalog crop must have a shelf life ═════════════════════════════
-- Checked at the END of the transaction, because an approval creates the crop
-- first and gives it the request's shelf life a moment later (s03).
CREATE OR REPLACE FUNCTION public._crop_master_require_shelf_life()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days INTEGER;
  v_name TEXT;
BEGIN
  SELECT cm.shelf_life_days, cm.crop_name INTO v_days, v_name
  FROM crop_master cm WHERE cm.id = NEW.id;
  IF FOUND AND v_days IS NULL THEN
    RAISE EXCEPTION 'CROP_SHELF_LIFE_REQUIRED: Set the shelf life of % before saving it.',
      COALESCE(v_name, 'this crop');
  END IF;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._crop_master_require_shelf_life() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_crop_master_require_shelf_life ON public.crop_master;
CREATE CONSTRAINT TRIGGER trg_crop_master_require_shelf_life
  AFTER INSERT ON public.crop_master
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION public._crop_master_require_shelf_life();

-- A shelf life that is set cannot be cleared again.
CREATE OR REPLACE FUNCTION public._crop_master_keep_shelf_life()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'CROP_SHELF_LIFE_REQUIRED: The shelf life of % cannot be removed. Enter a new number of days instead.',
    COALESCE(NEW.crop_name, 'this crop');
END;
$$;

DROP TRIGGER IF EXISTS trg_crop_master_keep_shelf_life ON public.crop_master;
CREATE TRIGGER trg_crop_master_keep_shelf_life
  BEFORE UPDATE OF shelf_life_days ON public.crop_master
  FOR EACH ROW
  WHEN (OLD.shelf_life_days IS NOT NULL AND NEW.shelf_life_days IS NULL)
  EXECUTE FUNCTION public._crop_master_keep_shelf_life();

-- ═══ 5. A Farmer cannot add a catalog crop with no shelf life ═════════════
-- Applies to the Farmer's own action only (Crop Roster → Add Crop). Rows added
-- for a Farmer by staff or by a program are not checked here.
CREATE OR REPLACE FUNCTION public._farmer_crop_require_shelf_life()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days INTEGER;
  v_name TEXT;
BEGIN
  IF NEW.crop_master_id IS NULL OR auth.uid() IS DISTINCT FROM NEW.farmer_id THEN
    RETURN NEW;
  END IF;
  SELECT cm.shelf_life_days, cm.crop_name INTO v_days, v_name
  FROM crop_master cm WHERE cm.id = NEW.crop_master_id;
  IF FOUND AND v_days IS NULL THEN
    RAISE EXCEPTION 'CROP_SHELF_LIFE_REQUIRED: % is not available yet. The cooperative still has to set its shelf life.',
      COALESCE(v_name, NEW.crop_name, 'This crop');
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._farmer_crop_require_shelf_life() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_farmer_crops_require_shelf_life ON public.farmer_crops;
CREATE TRIGGER trg_farmer_crops_require_shelf_life
  BEFORE INSERT OR UPDATE OF crop_master_id ON public.farmer_crops
  FOR EACH ROW EXECUTE FUNCTION public._farmer_crop_require_shelf_life();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ═══ Checks (run after the script) ════════════════════════════════════════
-- 1. The triggers exist (expect 4 rows):
--      SELECT tgname FROM pg_trigger WHERE tgname IN
--        ('trg_crop_requests_require_shelf_life','trg_crop_master_require_shelf_life',
--         'trg_crop_master_keep_shelf_life','trg_farmer_crops_require_shelf_life');
--
-- 2. Catalog crops that still have NO shelf life. These are hidden from the
--    Farmer's Add Crop list until the Manager sets one in Crop Management:
--      SELECT crop_name, category, is_active FROM crop_master
--      WHERE shelf_life_days IS NULL ORDER BY crop_name;
--
-- 3. Farmers who already have one of those crops on their Crop Roster (their
--    harvests of it are not shelf-life tracked until the shelf life is set):
--      SELECT cm.crop_name, count(*) AS farmers
--      FROM farmer_crops fc JOIN crop_master cm ON cm.id = fc.crop_master_id
--      WHERE cm.shelf_life_days IS NULL
--      GROUP BY cm.crop_name ORDER BY cm.crop_name;
--
-- 4. Pending crop requests with no shelf life yet (the approval form asks for it):
--      SELECT requested_name, created_at FROM crop_requests
--      WHERE status = 'pending' AND shelf_life_days IS NULL;
