-- ============================================================
-- SAGANA — p24: ITEM TYPE + CROP LINK — Inventory Management classifies every item
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run AFTER p23 (the p20 rollback).
--
-- THE RULE
--   Inventory Management is the single source of an item's classification. Every
--   cooperative_inventory item has an ITEM TYPE (never decided by its Category):
--       seeds_seedlings    "Seeds & Seedlings"   linked to a Crop Master crop
--       harvested_produce  "Harvested Produce"   linked to a Crop Master crop
--       non_crop           "Non-Crop Item"       tools, livestock, fertilizer, feeds, supplies ...
--   The two crop types carry crop_master_id = the REAL Crop Master id (never a typed name).
--   Nothing is copied: the Loan Item Catalog (loan_items_master -> cooperative_inventory), Program
--   Management (program_members.inventory_item_id), Supply Chain and the Reports all read the type and
--   the crop from the inventory row.
--
-- WHAT IT DOES
--   1. cooperative_inventory.item_type (NOT NULL) + crop_master_id (FK to crop_master).
--   2. EXISTING items are classified once (nothing is deleted, renamed or restocked):
--        * Farmer-delivered stock (it has a source Farmer) and category 'Harvest Stock'
--              -> harvested_produce, crop = the Farmer's own crop's Crop Master id
--        * category 'Seeds' -> seeds_seedlings
--        * everything else (Fertilizer, Animal Feeds, Pesticide, Livestock, Agricultural Supplies,
--          Product Sales ...) -> non_crop
--      A crop type is linked to Crop Master ONLY when the item name contains exactly ONE crop name
--      (and the id is what is written). An ambiguous or unmatched item stays unlinked and is LISTED
--      (CHECK T3); nothing is guessed.
--   3. Guards, in the database:
--        * a crop type needs an ACTIVE Crop Master crop (a new item, or when its crop changes);
--        * a Non-Crop Item can never carry a crop;
--        * Farmer-delivered stock is always Harvested Produce (and takes its crop from the Farmer's crop);
--        * one active, cooperative-created item per crop + type + unit (no duplicate records for the
--          same crop). Farmer-delivered stock keeps its own per-Farmer identity.
--   4. Supply Chain: get_supply_chain_records() returns the item's type and crop with every record
--      (two new last columns). The original function is kept under the private name
--      _supply_chain_records_base and wrapped, so its stage queries are not rewritten.
--
-- NOT CHANGED: stock quantities, the ledger, categories (they stay independent of Item Type), loans,
-- programs, orders.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.cooperative_inventory') IS NULL OR to_regclass('public.crop_master') IS NULL THEN
    RAISE EXCEPTION 'cooperative_inventory / crop_master are missing.';
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'cooperative_inventory' AND column_name = 'item_form') THEN
    RAISE EXCEPTION 'Run p23 (the p20 rollback) first: cooperative_inventory.item_form still exists.';
  END IF;
  IF to_regprocedure('public.get_supply_chain_records(timestamptz,timestamptz)') IS NULL
     AND to_regprocedure('public._supply_chain_records_base(timestamptz,timestamptz)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_supply_chain_01_read_model.sql first.';
  END IF;
END $$;

-- 1. Columns ------------------------------------------------------------------------------------
-- An EARLIER 2-value version of this script may already have run (item_type 'crop' / 'non_crop', with its
-- own guard trigger). Remove its trigger FIRST, so it cannot rewrite rows while they are reclassified
-- below, then its constraint.
DROP TRIGGER IF EXISTS trg_inventory_item_type_guard ON public.cooperative_inventory;
ALTER TABLE public.cooperative_inventory DROP CONSTRAINT IF EXISTS cooperative_inventory_item_type_chk;
ALTER TABLE public.cooperative_inventory ADD COLUMN IF NOT EXISTS item_type TEXT;
ALTER TABLE public.cooperative_inventory
  ADD COLUMN IF NOT EXISTS crop_master_id UUID REFERENCES public.crop_master(id);

-- 2. Classify the existing items ---------------------------------------------------------------
-- New rows (no type yet) are classified by the rule below. Rows left by the earlier 2-value version
-- ('crop') are reclassified by the same rule, keeping any other 'crop' item as Harvested Produce.
-- A row already holding a 3-value type (or 'non_crop') is not touched.
UPDATE public.cooperative_inventory
   SET item_type = CASE
         WHEN source_farmer_id IS NOT NULL OR category = 'Harvest Stock' THEN 'harvested_produce'
         WHEN category = 'Seeds'                                         THEN 'seeds_seedlings'
         WHEN item_type = 'crop'                                         THEN 'harvested_produce'
         ELSE 'non_crop'
       END
 WHERE item_type IS NULL OR item_type = 'crop';

-- Farmer-delivered stock: the crop is the Farmer's own crop's Crop Master id (an id, not a name).
UPDATE public.cooperative_inventory ci
   SET crop_master_id = fc.crop_master_id
  FROM public.farmer_crops fc
 WHERE ci.source_crop_id = fc.id
   AND ci.item_type = 'harvested_produce'
   AND ci.crop_master_id IS NULL
   AND fc.crop_master_id IS NOT NULL;

-- Every other crop-type item: link when the name contains exactly ONE Crop Master crop. The id is written.
UPDATE public.cooperative_inventory ci
   SET crop_master_id = m.crop_id
  FROM (
    SELECT i.id AS inv_id, (array_agg(cm.id))[1] AS crop_id
      FROM public.cooperative_inventory i
      JOIN public.crop_master cm ON i.item_name ILIKE '%' || cm.crop_name || '%'
     WHERE i.item_type IN ('seeds_seedlings', 'harvested_produce')
       AND i.crop_master_id IS NULL
     GROUP BY i.id
    HAVING count(*) = 1
  ) m
 WHERE ci.id = m.inv_id;

-- A Non-Crop Item never carries a crop.
UPDATE public.cooperative_inventory SET crop_master_id = NULL WHERE item_type = 'non_crop' AND crop_master_id IS NOT NULL;

ALTER TABLE public.cooperative_inventory ALTER COLUMN item_type SET DEFAULT 'non_crop';
ALTER TABLE public.cooperative_inventory ALTER COLUMN item_type SET NOT NULL;
ALTER TABLE public.cooperative_inventory
  ADD CONSTRAINT cooperative_inventory_item_type_chk
  CHECK (item_type IN ('seeds_seedlings', 'harvested_produce', 'non_crop'));

-- 3. Guards -------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._inventory_item_type_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  -- Stock a Farmer delivered (an Offer to Cooperative) is always Harvested Produce of that Farmer's crop.
  IF NEW.source_farmer_id IS NOT NULL THEN
    NEW.item_type := 'harvested_produce';
    IF NEW.crop_master_id IS NULL AND NEW.source_crop_id IS NOT NULL THEN
      SELECT fc.crop_master_id INTO NEW.crop_master_id FROM farmer_crops fc WHERE fc.id = NEW.source_crop_id;
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.item_type = 'non_crop' THEN
    NEW.crop_master_id := NULL;                      -- tools, livestock, supplies: no crop
    RETURN NEW;
  END IF;

  -- Seeds & Seedlings / Harvested Produce: a Crop Master crop is required, and it must be active.
  IF NEW.crop_master_id IS NULL THEN
    RAISE EXCEPTION 'ITEM_CROP_REQUIRED: Choose the crop for this item from Crop Management.';
  END IF;
  IF TG_OP = 'INSERT' OR NEW.crop_master_id IS DISTINCT FROM OLD.crop_master_id THEN
    IF NOT EXISTS (SELECT 1 FROM crop_master WHERE id = NEW.crop_master_id AND is_active) THEN
      RAISE EXCEPTION 'ITEM_CROP_INACTIVE: That crop is not available in Crop Management.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_inventory_item_type_guard ON public.cooperative_inventory;
CREATE TRIGGER trg_inventory_item_type_guard
  BEFORE INSERT OR UPDATE OF item_type, crop_master_id, source_farmer_id, source_crop_id ON public.cooperative_inventory
  FOR EACH ROW EXECUTE FUNCTION public._inventory_item_type_guard();

-- One active cooperative-created item per crop + type + unit (no duplicate records for the same crop).
DO $$
DECLARE d RECORD;
BEGIN
  FOR d IN
    SELECT item_type, crop_master_id, lower(btrim(unit)) AS u, string_agg(item_name, ' / ') AS names
      FROM public.cooperative_inventory
     WHERE crop_master_id IS NOT NULL AND source_farmer_id IS NULL AND archived_at IS NULL
     GROUP BY 1, 2, 3 HAVING count(*) > 1
  LOOP
    RAISE EXCEPTION 'Two active items are the same crop + type + unit (%). Archive or merge one first, then run this again.', d.names;
  END LOOP;
END $$;
CREATE UNIQUE INDEX IF NOT EXISTS uq_inventory_crop_item
  ON public.cooperative_inventory (item_type, crop_master_id, lower(btrim(unit)))
  WHERE crop_master_id IS NOT NULL AND source_farmer_id IS NULL AND archived_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_inventory_crop_master ON public.cooperative_inventory (crop_master_id)
  WHERE crop_master_id IS NOT NULL;

-- 4. Supply Chain carries the classification -----------------------------------------------------
DO $$ BEGIN
  IF to_regprocedure('public._supply_chain_records_base(timestamptz,timestamptz)') IS NULL THEN
    ALTER FUNCTION public.get_supply_chain_records(timestamptz, timestamptz)
      RENAME TO _supply_chain_records_base;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public._supply_chain_records_base(timestamptz, timestamptz) FROM PUBLIC, anon, authenticated;

-- The wrapper's result type changes (two new columns), so the old public function is dropped first
-- (a re-run, or an earlier p24, may have left one).
DROP FUNCTION IF EXISTS public.get_supply_chain_records(timestamptz, timestamptz);
CREATE FUNCTION public.get_supply_chain_records(
  p_from timestamptz DEFAULT NULL,
  p_to   timestamptz DEFAULT NULL
)
RETURNS TABLE (
  record_key         text,
  stage              text,
  record_type        text,
  direction          text,
  occurred_at        timestamptz,
  is_confirmed       boolean,
  item_name          text,
  category           text,
  quantity           numeric,
  unit               text,
  inventory_id       uuid,
  item_source        text,
  from_name          text,
  from_role          text,
  to_name            text,
  to_role            text,
  farmer_name        text,
  program_name       text,
  reference_label    text,
  batch_number       text,
  fulfillment_method text,
  fulfillment_status text,
  ref_type           text,
  ref_id             uuid,
  item_type          text,
  crop_name          text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT b.*,
         -- Read live from Inventory. A Marketplace sale has no inventory item: it is the Farmer's own
         -- harvest, so it is Harvested Produce of the crop named on the sale.
         COALESCE(ci.item_type, CASE WHEN b.record_type = 'marketplace_sale' THEN 'harvested_produce' END),
         COALESCE(cm.crop_name, CASE WHEN b.record_type = 'marketplace_sale' THEN b.item_name END)
    FROM public._supply_chain_records_base(p_from, p_to) AS b
    LEFT JOIN public.cooperative_inventory ci ON ci.id = b.inventory_id
    LEFT JOIN public.crop_master cm ON cm.id = ci.crop_master_id;
$$;
REVOKE ALL ON FUNCTION public.get_supply_chain_records(timestamptz, timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_supply_chain_records(timestamptz, timestamptz) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECKS (read-only)
-- ============================================================
-- T1  Every item has a type; the split:
--     SELECT item_type, count(*) FROM cooperative_inventory GROUP BY 1 ORDER BY 1;
-- T2  Category stays independent of type (expect Seeds = seeds_seedlings, Harvest Stock = harvested_produce,
--     the rest non_crop):
--     SELECT category, item_type, count(*) FROM cooperative_inventory GROUP BY 1, 2 ORDER BY 1, 2;
-- T3  Crop-type items still NOT linked to a Crop Master crop (ambiguous / unmatched: link them in Inventory):
--     SELECT item_name, category, item_type FROM cooperative_inventory
--      WHERE item_type <> 'non_crop' AND crop_master_id IS NULL AND is_active;
-- T4  Each linked item with its crop (verify by eye):
--     SELECT ci.item_name, ci.item_type, cm.crop_name, cm.is_active
--       FROM cooperative_inventory ci JOIN crop_master cm ON cm.id = ci.crop_master_id ORDER BY 1;
-- T5  No non-crop item carries a crop, no crop type is on a name that is not its crop (expect 0 rows):
--     SELECT item_name FROM cooperative_inventory WHERE item_type = 'non_crop' AND crop_master_id IS NOT NULL;
-- T6  Stock and history untouched (compare with before: quantities and ledger rows are unchanged by this script):
--     SELECT count(*) AS items, sum(quantity_on_hand) AS stock, (SELECT count(*) FROM inventory_transactions) AS ledger
--       FROM cooperative_inventory;
-- T7  Supply Chain returns the type and crop (run as a Manager / Officer):
--     SELECT item_type, crop_name, count(*) FROM get_supply_chain_records() GROUP BY 1, 2 ORDER BY 1, 2;
-- ============================================================
