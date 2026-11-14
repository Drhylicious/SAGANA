-- ═══════════════════════════════════════════════════════════════════════════
-- SAGANA · Cooperative shelf life c04 · Stock is tracked as soon as a life is set
-- ═══════════════════════════════════════════════════════════════════════════
-- Run AFTER c01. One transaction. Safe to run more than once.
--
-- THE GAP THIS CLOSES
--   c01 gave a lot to the stock of every item whose crop ALREADY had a Shelf Life
--   / Storage Life on the day it was run. An item whose crop received its value
--   LATER (for example a Storage Life entered in Crop Management afterwards) kept
--   its stock but had no lot, so Inventory Management showed no countdown for it.
--
-- WHAT THIS ADDS
--   _coop_track_untracked_stock(crop)   gives one lot, counting from today, to the
--                                       stock of every tracked item that has stock
--                                       but no lot with stock left (all crops when
--                                       called with NULL).
--   trg_crop_master_track_stock         runs it for a crop the moment its Shelf Life
--                                       or Storage Life is set for the first time.
--   One run for all crops now, to pick up the stock that is waiting.
--
-- NOT CHANGED: lots that already exist keep their dates. Changing a value that
-- was already set does not move the end date of stock already in the inventory
-- (each lot keeps the countdown it started with; use Check Produce to adjust one).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.cooperative_stock_lots') IS NULL
     OR to_regprocedure('public._coop_item_life_days(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_coop_shelf_life_c01_inventory_lots.sql first.';
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public._coop_track_untracked_stock(p_crop_master_id UUID DEFAULT NULL)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  INSERT INTO cooperative_stock_lots (inventory_id, source, unit, quantity, remaining, life_days, starts_on, expires_on)
  SELECT i.id, 'existing', COALESCE(i.unit, 'kg'),
         i.quantity_on_hand - COALESCE(l.in_lots, 0),
         i.quantity_on_hand - COALESCE(l.in_lots, 0),
         public._coop_item_life_days(i.id), public._ph_today(),
         public._ph_today() + public._coop_item_life_days(i.id)
  FROM cooperative_inventory i
  LEFT JOIN LATERAL (
    SELECT sum(x.remaining) AS in_lots FROM cooperative_stock_lots x WHERE x.inventory_id = i.id
  ) l ON TRUE
  WHERE i.is_active AND i.archived_at IS NULL
    AND (p_crop_master_id IS NULL OR i.crop_master_id = p_crop_master_id)
    AND public._coop_item_life_days(i.id) IS NOT NULL
    -- Stock on hand that no lot accounts for.
    AND i.quantity_on_hand - COALESCE(l.in_lots, 0) >= 0.01;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
REVOKE ALL ON FUNCTION public._coop_track_untracked_stock(UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._crop_master_track_stock()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._coop_track_untracked_stock(NEW.id);
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._crop_master_track_stock() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_crop_master_track_stock ON public.crop_master;
CREATE TRIGGER trg_crop_master_track_stock
  AFTER UPDATE OF shelf_life_days, storage_life_days ON public.crop_master
  FOR EACH ROW
  WHEN ((OLD.shelf_life_days IS NULL AND NEW.shelf_life_days IS NOT NULL)
     OR (OLD.storage_life_days IS NULL AND NEW.storage_life_days IS NOT NULL))
  EXECUTE FUNCTION public._crop_master_track_stock();

-- The stock that is waiting right now.
SELECT public._coop_track_untracked_stock(NULL);

COMMIT;

-- ═══ Checks (run after the script) ════════════════════════════════════════
-- 1. The trigger exists (expect 1 row):
--      SELECT tgname FROM pg_trigger WHERE tgname = 'trg_crop_master_track_stock';
--
-- 2. Planting Materials and Harvested Produce with stock that are STILL not
--    tracked. A row here means the crop has no Storage Life / Shelf Life yet:
--    set it in Crop Management and the stock is tracked at once.
--      SELECT i.item_name, i.item_type, i.quantity_on_hand, cm.crop_name,
--             cm.shelf_life_days, cm.storage_life_days
--      FROM cooperative_inventory i
--      LEFT JOIN crop_master cm ON cm.id = i.crop_master_id
--      WHERE i.is_active AND i.archived_at IS NULL AND i.quantity_on_hand > 0
--        AND i.item_type IN ('harvested_produce', 'seeds_seedlings')
--        AND NOT EXISTS (SELECT 1 FROM cooperative_stock_lots l
--                        WHERE l.inventory_id = i.id AND l.remaining > 0);
