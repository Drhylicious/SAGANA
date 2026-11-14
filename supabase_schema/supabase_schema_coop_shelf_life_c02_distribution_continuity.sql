-- ═══════════════════════════════════════════════════════════════════════════
-- SAGANA · Cooperative shelf life c02 · Distribution keeps the countdown
-- ═══════════════════════════════════════════════════════════════════════════
-- Run AFTER c01 (supabase_schema_coop_shelf_life_c01_inventory_lots.sql).
-- One transaction. Safe to run more than once.
--
-- THE RULES
--   • Harvested Produce handed to a Farmer through a program KEEPS the end date
--     of the cooperative stock it came from. The countdown never restarts; the
--     Farmer receives it with the days it has left and manages it from there.
--   • Harvested Produce cannot be distributed while its crop has no Shelf Life
--     (it would reach the Farmer untracked). Set it in Crop Management first.
--   • Planting Materials: the cooperative's Storage Life countdown simply ends
--     when they are handed out (c01 takes them out of the lot). Nothing is
--     tracked on the Farmer's side, and Storage Life is never required here.
--
-- WHAT THIS ADDS
--   trg_program_members_require_shelf_life   (program_members, BEFORE UPDATE OF distributed_at)
--   trg_inventory_batches_zz_coop_carry      (inventory_batches, AFTER INSERT)
--
-- NOT CHANGED: no existing function or trigger is rewritten. The Farmer's
-- received batch is created exactly as before (program rework p25); only its
-- shelf-life dates are aligned with the cooperative's afterwards.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.cooperative_stock_lots') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_coop_shelf_life_c01_inventory_lots.sql first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='harvest_records' AND column_name='source_program_member_id') THEN
    RAISE EXCEPTION 'harvest_records.source_program_member_id is missing (program rework p25).';
  END IF;
END;
$$;

-- ═══ 1. No produce is handed out without a Shelf Life ═════════════════════
CREATE OR REPLACE FUNCTION public._program_members_require_shelf_life()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT;
  v_days INTEGER;
  v_crop TEXT;
BEGIN
  IF NEW.inventory_item_id IS NULL THEN
    RETURN NEW;
  END IF;
  SELECT i.item_type, cm.shelf_life_days, cm.crop_name
    INTO v_type, v_days, v_crop
  FROM cooperative_inventory i
  LEFT JOIN crop_master cm ON cm.id = i.crop_master_id
  WHERE i.id = NEW.inventory_item_id;

  IF v_type = 'harvested_produce' AND v_days IS NULL THEN
    RAISE EXCEPTION 'CROP_SHELF_LIFE_REQUIRED: Set the shelf life of % in Crop Management before distributing it.',
      COALESCE(v_crop, 'this crop');
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._program_members_require_shelf_life() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_program_members_require_shelf_life ON public.program_members;
CREATE TRIGGER trg_program_members_require_shelf_life
  BEFORE UPDATE OF distributed_at ON public.program_members
  FOR EACH ROW
  WHEN (OLD.distributed_at IS NULL AND NEW.distributed_at IS NOT NULL)
  EXECUTE FUNCTION public._program_members_require_shelf_life();

-- ═══ 2. The received batch continues the cooperative's countdown ══════════
-- Fires after the Farmer batch got its own shelf-life row (the s01 trigger
-- sorts before this one by name). The stock that was handed out is the lot
-- that was reduced in THIS transaction (c01 stamps it with the transaction's
-- time); if several were touched, the one ending first is used, which is the
-- safe side for the Farmer. When no such lot is found, the batch keeps the
-- dates it already has.
CREATE OR REPLACE FUNCTION public._inventory_batches_coop_carry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_member UUID;
  v_item   UUID;
  v_start  DATE;
  v_end    DATE;
BEGIN
  SELECT hr.source_program_member_id INTO v_member
  FROM harvest_records hr
  WHERE hr.id = NEW.harvest_record_id AND hr.source_type = 'program_received';
  IF v_member IS NULL THEN
    RETURN NULL;                                  -- not produce received from a program
  END IF;

  SELECT pm.inventory_item_id INTO v_item FROM program_members pm WHERE pm.id = v_member;
  IF v_item IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT l.starts_on, l.expires_on INTO v_start, v_end
  FROM cooperative_stock_lots l
  WHERE l.inventory_id = v_item
    AND l.updated_at = NOW()                      -- reduced in this transaction
    AND l.remaining < l.quantity
  ORDER BY l.expires_on
  LIMIT 1;
  IF v_end IS NULL THEN
    RETURN NULL;
  END IF;

  UPDATE batch_shelf_life
     SET starts_on = v_start, expires_on = v_end,
         hold = (v_end < public._ph_today()), updated_at = NOW()
   WHERE batch_id = NEW.id;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._inventory_batches_coop_carry() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_inventory_batches_zz_coop_carry ON public.inventory_batches;
CREATE TRIGGER trg_inventory_batches_zz_coop_carry
  AFTER INSERT ON public.inventory_batches
  FOR EACH ROW EXECUTE FUNCTION public._inventory_batches_coop_carry();

COMMIT;

-- ═══ Checks (run after the script) ════════════════════════════════════════
-- 1. The triggers exist (expect 2 rows):
--      SELECT tgname FROM pg_trigger WHERE tgname IN
--        ('trg_program_members_require_shelf_life', 'trg_inventory_batches_zz_coop_carry');
--
-- 2. After distributing produce to a Farmer, the Farmer's batch ends on the same
--    date as the cooperative stock it came from (compare the two end dates):
--      SELECT b.batch_number, s.starts_on, s.expires_on
--      FROM inventory_batches b
--      JOIN harvest_records hr ON hr.id = b.harvest_record_id
--      JOIN batch_shelf_life s ON s.batch_id = b.id
--      WHERE hr.source_type = 'program_received'
--      ORDER BY b.created_at DESC LIMIT 5;
