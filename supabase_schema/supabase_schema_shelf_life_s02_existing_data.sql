-- ============================================================
-- SAGANA — Crop Shelf Life Management  (script s02: existing data)
--
-- FOR YOUR REVIEW — NOT APPLIED. Run AFTER s01, once. Safe to re-run: it only
-- fills what is still empty and never overwrites a value someone set.
--
-- WHAT IT DOES
--   1. Existing crops get the sourced default shelf life where one is on file
--      (crop_shelf_life_reference). Crops with no sourced figure stay "not set"
--      for the Manager to fill in Crop Management (see PREVIEW P2 for the list).
--   2. Existing harvest batches that still hold stock (available or reserved)
--      and whose crop has a shelf life start their countdown TODAY (the rollout
--      date), as decided: nothing is blocked, discounted or delisted on day one.
--      After that the normal reminder, discount and unavailability rules apply.
--      Batches with nothing left are not tracked (there is nothing to monitor).
--
-- When the Manager later sets the shelf life of a crop that had none, its
-- existing unsold batches start being tracked that day automatically (trigger
-- trg_crop_master_first_shelf_life in s01). New harvests are always tracked.
-- ============================================================

-- ─── PREVIEW (read-only; run each by itself BEFORE the script) ───────────
-- P1  Crops that will receive a sourced default:
--     SELECT cm.crop_name, cm.category, public._reference_shelf_life(cm.crop_name) AS will_get_days
--       FROM crop_master cm
--      WHERE cm.shelf_life_days IS NULL AND public._reference_shelf_life(cm.crop_name) IS NOT NULL
--      ORDER BY 1;
-- P2  Crops that will stay "not set" (enter these in Crop Management):
--     SELECT cm.crop_name, cm.category, cm.is_active
--       FROM crop_master cm
--      WHERE cm.shelf_life_days IS NULL AND public._reference_shelf_life(cm.crop_name) IS NULL
--      ORDER BY cm.is_active DESC, 1;
-- P3  Batches that will start being tracked today:
--     SELECT b.batch_number, b.crop_name, b.available_kg, b.reserved_kg, b.unit
--       FROM inventory_batches b
--       JOIN farmer_crops fc ON fc.id = b.crop_id
--       JOIN crop_master cm  ON cm.id = fc.crop_master_id
--      WHERE b.available_kg + b.reserved_kg > 0
--        AND COALESCE(cm.shelf_life_days, public._reference_shelf_life(cm.crop_name)) IS NOT NULL
--        AND NOT EXISTS (SELECT 1 FROM batch_shelf_life s WHERE s.batch_id = b.id)
--      ORDER BY 2, 1;
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.batch_shelf_life') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_shelf_life_s01_foundation.sql first.';
  END IF;
END;
$$;

-- ═══ 1. Sourced defaults for existing crops ═════════════════════════════
UPDATE public.crop_master cm
   SET shelf_life_days = public._reference_shelf_life(cm.crop_name)
 WHERE cm.shelf_life_days IS NULL
   AND public._reference_shelf_life(cm.crop_name) IS NOT NULL;

-- ═══ 2. Existing unsold batches: the clock starts at rollout ════════════
INSERT INTO public.batch_shelf_life (batch_id, farmer_id, default_days, shelf_life_days, starts_on, expires_on)
SELECT b.id, b.farmer_id, cm.shelf_life_days, cm.shelf_life_days,
       public._ph_today(), public._ph_today() + cm.shelf_life_days
FROM public.inventory_batches b
JOIN public.farmer_crops fc ON fc.id = b.crop_id
JOIN public.crop_master cm  ON cm.id = fc.crop_master_id
WHERE cm.shelf_life_days IS NOT NULL
  AND b.available_kg + b.reserved_kg > 0
ON CONFLICT (batch_id) DO NOTHING;

COMMIT;

-- ─── CHECKS (read-only) ──────────────────────────────────────────────────
-- C1  Crops by whether a shelf life is set:
--     SELECT (shelf_life_days IS NOT NULL) AS has_shelf_life, count(*) FROM crop_master GROUP BY 1;
-- C2  Every unsold batch of a crop that has a shelf life is tracked (expect 0):
--     SELECT count(*) FROM inventory_batches b
--       JOIN farmer_crops fc ON fc.id = b.crop_id
--       JOIN crop_master cm  ON cm.id = fc.crop_master_id
--      WHERE cm.shelf_life_days IS NOT NULL AND b.available_kg + b.reserved_kg > 0
--        AND NOT EXISTS (SELECT 1 FROM batch_shelf_life s WHERE s.batch_id = b.id);
-- C3  Nothing was put on hold or made unavailable by the rollout (expect 0, 0):
--     SELECT (SELECT count(*) FROM batch_shelf_life WHERE hold)            AS on_hold,
--            (SELECT count(*) FROM listing_shelf_life WHERE unavailable)   AS unavailable;
