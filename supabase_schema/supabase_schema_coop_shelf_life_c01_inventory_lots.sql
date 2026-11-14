-- ═══════════════════════════════════════════════════════════════════════════
-- SAGANA · Cooperative shelf life c01 · Storage Life, stock lots, hold, checks
-- ═══════════════════════════════════════════════════════════════════════════
-- Run AFTER s04 (supabase_schema_shelf_life_s04_shelf_life_required.sql).
-- One transaction. Safe to run more than once.
--
-- THE RULES
--   Harvested Produce  uses the crop's SHELF LIFE   (crop_master.shelf_life_days)
--   Planting Materials uses the crop's STORAGE LIFE (crop_master.storage_life_days, new)
--   Non-Crop Item      is not tracked.
--   (Item Type codes are unchanged: 'seeds_seedlings' is now only LABELLED
--    "Planting Materials" in the app.)
--
--   • Every stock-in of a tracked item is its own LOT with its own end date.
--   • Produce received through Offer to Cooperative KEEPS the Farmer batch's end
--     date (including any change the Farmer made). The countdown never resets.
--   • Produce added by hand counts from its harvest date when one is given,
--     otherwise from the day it is added. Planting Materials count from the day
--     they enter the inventory.
--   • Stock going out always comes from the lot that ends first.
--   • One day before a lot ends, the Manager and the Officers who have Manage on
--     Dashboard are told to inspect it.
--   • On its end date a lot is ON HOLD: while an item has such a lot, it cannot be
--     distributed, loaned, sold through Product Sales or published to the Loan
--     Item Catalog. Nothing is discounted or sold automatically.
--   • Check Produce: "still good" gives the lot new remaining days and lifts the
--     hold; "rotten" records a quantity as Rotten/Lost and takes it out of stock.
--
-- WHAT THIS ADDS
--   crop_master.storage_life_days
--   cooperative_stock_lots                      one row per stock-in
--   trg_coop_lots_hold   (inventory_transactions BEFORE INSERT)  refuses stock-out on hold
--   trg_coop_lots_apply  (inventory_transactions AFTER INSERT)   makes / consumes lots
--   trg_loan_items_shelf_hold (loan_items_master)                refuses publishing on hold
--   confirm_coop_lot_still_good(lot, days)
--   report_coop_lot_rotten(lot, quantity, note)
--   process_cooperative_shelf_life()            the daily inspection notices (+ pg_cron)
--   adjust_cooperative_stock()                  one condition widened in place (section 8b)
--
-- NOT CHANGED: no existing function is rewritten (one condition in
-- adjust_cooperative_stock is widened in place, see 8b). Stock quantities, the stock
-- ledger, the receipt of an offer, distribution, loans and Product Sales work as
-- before; they are only refused while the item is on hold.
--
-- EXISTING STOCK: each tracked item that has stock gets one lot whose countdown
-- starts today, so nothing is on hold on day one.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.batch_shelf_life') IS NULL OR to_regprocedure('public._ph_today()') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_shelf_life_s01_foundation.sql first.';
  END IF;
  IF to_regclass('public.cooperative_harvest_batches') IS NULL
     OR to_regprocedure('public.adjust_cooperative_stock(uuid,numeric,text,uuid,text,date,text)') IS NULL THEN
    RAISE EXCEPTION 'The cooperative harvest inventory script (cooperative_harvest_phase2) must be applied first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='cooperative_inventory' AND column_name='item_type')
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='cooperative_inventory' AND column_name='crop_master_id') THEN
    RAISE EXCEPTION 'cooperative_inventory.item_type / crop_master_id are missing (program rework p20 and p24).';
  END IF;
  IF to_regprocedure('public.staff_can_manage(text,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Run the officer permissions scripts first (staff_can_manage is missing).';
  END IF;
END;
$$;

-- ═══ 1. Storage Life of a crop's planting materials ═══════════════════════
ALTER TABLE public.crop_master
  ADD COLUMN IF NOT EXISTS storage_life_days INTEGER
    CHECK (storage_life_days IS NULL OR storage_life_days BETWEEN 1 AND 36500);

COMMENT ON COLUMN public.crop_master.storage_life_days IS
  'Storage Life in days: how long this crop''s planting materials (seeds, seedlings) stay '
  'usable in cooperative storage. Used by cooperative inventory only. NULL = not set.';

-- ═══ 2. Lots ══════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.cooperative_stock_lots (
  id                       UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  inventory_id             UUID          NOT NULL REFERENCES public.cooperative_inventory(id) ON DELETE CASCADE,
  -- The stock-in that made this lot (NULL for the one-time lot of existing stock).
  inventory_transaction_id UUID          UNIQUE,
  source                   TEXT          NOT NULL DEFAULT 'manual'
                           CHECK (source IN ('offer', 'manual', 'returned', 'existing')),
  -- The Farmer batch the produce came from (Offer to Cooperative).
  source_batch_id          UUID,
  unit                     TEXT          NOT NULL,
  quantity                 NUMERIC(12,2) NOT NULL CHECK (quantity > 0),
  remaining                NUMERIC(12,2) NOT NULL CHECK (remaining >= 0),
  rotten_quantity          NUMERIC(12,2) NOT NULL DEFAULT 0 CHECK (rotten_quantity >= 0),
  life_days                INTEGER       NOT NULL,
  starts_on                DATE          NOT NULL,
  expires_on               DATE          NOT NULL,
  -- The end date the staff were last reminded about (one notice per end date).
  notified_for             DATE,
  checked_at               TIMESTAMPTZ,
  checked_by               UUID,
  created_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at               TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_coop_stock_lots_item
  ON public.cooperative_stock_lots (inventory_id, expires_on, created_at);

ALTER TABLE public.cooperative_stock_lots ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cooperative_stock_lots: staff read" ON public.cooperative_stock_lots;
CREATE POLICY "cooperative_stock_lots: staff read" ON public.cooperative_stock_lots
  FOR SELECT TO authenticated USING (public.is_staff());
-- No write policy: lots are written only by the functions below.
GRANT SELECT ON public.cooperative_stock_lots TO authenticated;

-- The life (days) that applies to an inventory item, or NULL when it is not tracked.
CREATE OR REPLACE FUNCTION public._coop_item_life_days(p_inventory_id UUID)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE i.item_type
           WHEN 'harvested_produce' THEN cm.shelf_life_days
           WHEN 'seeds_seedlings'   THEN cm.storage_life_days
         END
  FROM cooperative_inventory i
  JOIN crop_master cm ON cm.id = i.crop_master_id
  WHERE i.id = p_inventory_id;
$$;
REVOKE ALL ON FUNCTION public._coop_item_life_days(UUID) FROM PUBLIC, anon, authenticated;

-- On hold: a lot with stock left has reached its end date and was not inspected.
CREATE OR REPLACE FUNCTION public._coop_item_on_hold(p_inventory_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM cooperative_stock_lots l
    WHERE l.inventory_id = p_inventory_id
      AND l.remaining > 0
      AND l.expires_on <= public._ph_today());
$$;
REVOKE ALL ON FUNCTION public._coop_item_on_hold(UUID) FROM PUBLIC, anon, authenticated;

-- ═══ 3. No stock leaves an item on hold ═══════════════════════════════════
-- Recording a loss (written_off) and correcting the count (adjustment) stay
-- allowed; every other stock-out (loan, distribution, sale) is refused.
CREATE OR REPLACE FUNCTION public._coop_lots_hold_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name TEXT;
BEGIN
  IF NEW.quantity >= 0 OR NEW.transaction_type IN ('written_off', 'adjustment') THEN
    RETURN NEW;
  END IF;
  IF public._coop_item_on_hold(NEW.inventory_id) THEN
    SELECT item_name INTO v_name FROM cooperative_inventory WHERE id = NEW.inventory_id;
    RAISE EXCEPTION 'COOP_SHELF_HOLD: % has reached its end date and must be inspected first. Open Inventory Management and use Check Produce.',
      COALESCE(v_name, 'This item');
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._coop_lots_hold_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_coop_lots_hold ON public.inventory_transactions;
CREATE TRIGGER trg_coop_lots_hold
  BEFORE INSERT ON public.inventory_transactions
  FOR EACH ROW EXECUTE FUNCTION public._coop_lots_hold_guard();

-- ═══ 4. Stock in makes a lot; stock out uses the lot that ends first ══════
CREATE OR REPLACE FUNCTION public._coop_lots_apply()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days    INTEGER;
  v_type    TEXT;
  v_unit    TEXT;
  v_today   DATE := public._ph_today();
  v_start   DATE;
  v_end     DATE;
  v_source  TEXT := 'manual';
  hb        cooperative_harvest_batches%ROWTYPE;
  v_left    NUMERIC;
  v_take    NUMERIC;
  v_first   UUID;
  l         RECORD;
BEGIN
  v_days := public._coop_item_life_days(NEW.inventory_id);
  IF v_days IS NULL THEN
    RETURN NULL;                                  -- not a tracked item
  END IF;
  SELECT item_type, unit INTO v_type, v_unit FROM cooperative_inventory WHERE id = NEW.inventory_id;

  -- ── Stock in ──
  IF NEW.quantity > 0 THEN
    v_start := v_today;
    v_end   := v_today + v_days;

    IF v_type = 'harvested_produce' THEN
      SELECT * INTO hb FROM cooperative_harvest_batches WHERE inventory_transaction_id = NEW.id;
      IF FOUND THEN
        IF hb.offer_id IS NOT NULL THEN
          v_source := 'offer';
        END IF;
        -- The Farmer batch's own countdown continues: same start, same end.
        v_end := NULL;
        IF hb.source_batch_id IS NOT NULL THEN
          SELECT s.starts_on, s.expires_on INTO v_start, v_end
          FROM batch_shelf_life s
          WHERE s.batch_id = hb.source_batch_id AND s.expires_on IS NOT NULL;
        END IF;
        IF v_end IS NULL THEN
          -- No Farmer countdown to continue: count from the harvest date.
          v_start := COALESCE(hb.harvest_date, v_today);
          v_end   := v_start + v_days;
        END IF;
      END IF;
    END IF;
    IF NEW.transaction_type = 'returned' THEN
      v_source := 'returned';
    END IF;

    INSERT INTO cooperative_stock_lots (
      inventory_id, inventory_transaction_id, source, source_batch_id, unit,
      quantity, remaining, life_days, starts_on, expires_on)
    VALUES (
      NEW.inventory_id, NEW.id, v_source, hb.source_batch_id, COALESCE(v_unit, 'kg'),
      NEW.quantity, NEW.quantity, v_days, COALESCE(v_start, v_today), COALESCE(v_end, v_today + v_days))
    ON CONFLICT (inventory_transaction_id) DO NOTHING;
    RETURN NULL;
  END IF;

  -- ── Stock out ──
  v_left := -NEW.quantity;
  IF v_left <= 0 THEN
    RETURN NULL;
  END IF;
  -- A loss recorded through Check Produce names the lot it belongs to.
  v_first := NULLIF(current_setting('sagana.coop_lot', true), '')::UUID;

  FOR l IN
    SELECT id, remaining FROM cooperative_stock_lots
    WHERE inventory_id = NEW.inventory_id AND remaining > 0
    ORDER BY (id = v_first) DESC NULLS LAST, expires_on, created_at
    FOR UPDATE
  LOOP
    EXIT WHEN v_left <= 0;
    v_take := LEAST(l.remaining, v_left);
    UPDATE cooperative_stock_lots
       SET remaining = remaining - v_take, updated_at = NOW()
     WHERE id = l.id;
    v_left := v_left - v_take;
  END LOOP;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._coop_lots_apply() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_coop_lots_apply ON public.inventory_transactions;
CREATE TRIGGER trg_coop_lots_apply
  AFTER INSERT ON public.inventory_transactions
  FOR EACH ROW EXECUTE FUNCTION public._coop_lots_apply();

-- ═══ 5. An item on hold cannot be published to the Loan Item Catalog ══════
CREATE OR REPLACE FUNCTION public._loan_items_shelf_hold_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.inventory_item_id IS NULL OR NOT COALESCE(NEW.is_loan_eligible, FALSE) THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND COALESCE(OLD.is_loan_eligible, FALSE) THEN
    RETURN NEW;                                   -- already published: not a new publish
  END IF;
  IF public._coop_item_on_hold(NEW.inventory_item_id) THEN
    RAISE EXCEPTION 'COOP_SHELF_HOLD: This item has reached its end date and must be inspected before it can be published. Use Check Produce in Inventory Management.';
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._loan_items_shelf_hold_guard() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_loan_items_shelf_hold ON public.loan_items_master;
CREATE TRIGGER trg_loan_items_shelf_hold
  BEFORE INSERT OR UPDATE OF is_loan_eligible ON public.loan_items_master
  FOR EACH ROW EXECUTE FUNCTION public._loan_items_shelf_hold_guard();

-- ═══ 6. Check Produce: still good ═════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.confirm_coop_lot_still_good(p_lot_id UUID, p_days INTEGER)
RETURNS DATE
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot cooperative_stock_lots%ROWTYPE;
  v_end DATE;
BEGIN
  IF NOT public.is_staff() OR NOT public.staff_can_manage('dashboard', auth.uid()) THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only the Manager or an Officer with Manage access to Dashboard can inspect inventory.';
  END IF;
  IF p_days IS NULL OR p_days < 1 OR p_days > 36500 THEN
    RAISE EXCEPTION 'Enter the remaining days as a whole number of at least 1.';
  END IF;

  SELECT * INTO v_lot FROM cooperative_stock_lots WHERE id = p_lot_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This stock was not found. Refresh and try again.';
  END IF;
  IF v_lot.remaining <= 0 THEN
    RAISE EXCEPTION 'This stock has none left to inspect.';
  END IF;

  v_end := public._ph_today() + p_days;
  UPDATE cooperative_stock_lots
     SET expires_on = v_end, life_days = p_days, notified_for = NULL,
         checked_at = NOW(), checked_by = auth.uid(), updated_at = NOW()
   WHERE id = p_lot_id;

  INSERT INTO cooperative_inventory_history (inventory_id, action, actor_id, actor_name, quantity_change, unit, details)
  VALUES (v_lot.inventory_id, 'shelf_confirmed', auth.uid(), public._coop_person_name(auth.uid()), NULL, v_lot.unit,
          jsonb_build_object('lot_id', p_lot_id, 'days', p_days, 'previous_end', v_lot.expires_on, 'new_end', v_end));
  RETURN v_end;
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_coop_lot_still_good(UUID, INTEGER) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_coop_lot_still_good(UUID, INTEGER) TO authenticated;

-- ═══ 7. Check Produce: rotten / lost ══════════════════════════════════════
-- Takes the quantity out of stock through the existing stock function (so the
-- ledger, the history and the totals stay right) and records it on the lot.
CREATE OR REPLACE FUNCTION public.report_coop_lot_rotten(p_lot_id UUID, p_quantity NUMERIC, p_note TEXT DEFAULT NULL)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot    cooperative_stock_lots%ROWTYPE;
  v_result NUMERIC;
BEGIN
  IF NOT public.is_staff() OR NOT public.staff_can_manage('dashboard', auth.uid()) THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only the Manager or an Officer with Manage access to Dashboard can inspect inventory.';
  END IF;

  SELECT * INTO v_lot FROM cooperative_stock_lots WHERE id = p_lot_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This stock was not found. Refresh and try again.';
  END IF;
  IF p_quantity IS NULL OR p_quantity <= 0 OR p_quantity <> round(p_quantity, 2) THEN
    RAISE EXCEPTION 'Enter the rotten quantity as a number greater than zero, with at most 2 decimal places.';
  END IF;
  IF p_quantity > v_lot.remaining THEN
    RAISE EXCEPTION 'Only % % of this stock is left.', v_lot.remaining, v_lot.unit;
  END IF;

  -- The stock-out below is taken from THIS lot (see _coop_lots_apply).
  PERFORM set_config('sagana.coop_lot', p_lot_id::TEXT, TRUE);
  v_result := public.adjust_cooperative_stock(
    v_lot.inventory_id, -p_quantity, 'written_off', gen_random_uuid(),
    COALESCE(NULLIF(btrim(p_note), ''), 'Rotten/Lost (Check Produce)'), NULL, NULL);
  PERFORM set_config('sagana.coop_lot', '', TRUE);

  UPDATE cooperative_stock_lots
     SET rotten_quantity = rotten_quantity + p_quantity,
         checked_at = NOW(), checked_by = auth.uid(), updated_at = NOW()
   WHERE id = p_lot_id;
  RETURN v_result;
END;
$$;
REVOKE ALL ON FUNCTION public.report_coop_lot_rotten(UUID, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_coop_lot_rotten(UUID, NUMERIC, TEXT) TO authenticated;

-- ═══ 8. The daily inspection notice (one day before the end date) ═════════
CREATE OR REPLACE FUNCTION public.process_cooperative_shelf_life()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_today DATE := public._ph_today();
  v_sent  INTEGER := 0;
  l       RECORD;
BEGIN
  FOR l IN
    SELECT lot.id, lot.remaining, lot.unit, lot.expires_on, i.item_name, i.item_type
    FROM cooperative_stock_lots lot
    JOIN cooperative_inventory i ON i.id = lot.inventory_id
    WHERE lot.remaining > 0
      AND lot.expires_on <= v_today + 1
      AND lot.notified_for IS DISTINCT FROM lot.expires_on
      AND i.is_active AND i.archived_at IS NULL
    FOR UPDATE OF lot
  LOOP
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap, route_extra)
    SELECT r.user_id, 'low_stock',
           'Inspect ' || l.item_name,
           CASE WHEN l.expires_on > v_today
                THEN l.remaining || ' ' || l.unit || ' of ' || l.item_name || ' reaches its ' ||
                     CASE WHEN l.item_type = 'seeds_seedlings' THEN 'storage life' ELSE 'shelf life' END ||
                     ' tomorrow. Inspect it and use Check Produce in Inventory Management.'
                ELSE l.remaining || ' ' || l.unit || ' of ' || l.item_name || ' has reached its ' ||
                     CASE WHEN l.item_type = 'seeds_seedlings' THEN 'storage life' ELSE 'shelf life' END ||
                     ' and is on hold. Inspect it and use Check Produce in Inventory Management.'
           END,
           FALSE, NOW(), '/admin/inventory', l.id::TEXT
    FROM (SELECT DISTINCT ur.user_id FROM user_roles ur
          WHERE ur.role IN ('admin', 'officer')
            AND public.staff_can_manage('dashboard', ur.user_id)) r;

    UPDATE cooperative_stock_lots SET notified_for = l.expires_on, updated_at = NOW() WHERE id = l.id;
    v_sent := v_sent + 1;
  END LOOP;
  RETURN v_sent;
END;
$$;
REVOKE ALL ON FUNCTION public.process_cooperative_shelf_life() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.process_cooperative_shelf_life() TO authenticated;

-- ═══ 8b. A harvest date for EVERY Harvested Produce item added by hand ════
-- adjust_cooperative_stock() keeps the harvest date of a manual stock-in only
-- for the 'Harvest Stock' category. Produce is decided by the Item Type, whatever
-- its Category, so that one condition is widened IN PLACE in the live function.
-- Nothing else in the function changes; it is skipped (with a notice) if the
-- live text is not what is expected.
DO $$
DECLARE
  d TEXT;
BEGIN
  SELECT pg_get_functiondef('public.adjust_cooperative_stock(uuid,numeric,text,uuid,text,date,text)'::regprocedure) INTO d;
  IF d LIKE '%i.item_type = ''harvested_produce''%' THEN
    RETURN;                                       -- already widened
  END IF;
  IF d NOT LIKE '%p_quantity > 0 AND i.category = ''Harvest Stock''%' THEN
    RAISE NOTICE 'adjust_cooperative_stock was not patched (its text differs). Manual produce outside the Harvest Stock category will count from the day it is added.';
    RETURN;
  END IF;
  d := replace(d,
    'p_quantity > 0 AND i.category = ''Harvest Stock''',
    'p_quantity > 0 AND (i.category = ''Harvest Stock'' OR i.item_type = ''harvested_produce'')');
  EXECUTE d;
END;
$$;

-- ═══ 9. Existing stock: one lot per tracked item, counting from today ═════
INSERT INTO cooperative_stock_lots (inventory_id, source, unit, quantity, remaining, life_days, starts_on, expires_on)
SELECT i.id, 'existing', COALESCE(i.unit, 'kg'), i.quantity_on_hand, i.quantity_on_hand,
       public._coop_item_life_days(i.id), public._ph_today(),
       public._ph_today() + public._coop_item_life_days(i.id)
FROM cooperative_inventory i
WHERE i.quantity_on_hand > 0
  AND i.is_active AND i.archived_at IS NULL
  AND public._coop_item_life_days(i.id) IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM cooperative_stock_lots l WHERE l.inventory_id = i.id);

COMMIT;

-- ═══ 10. Daily schedule (same time as the Farmer pass) ════════════════════
DO $$
BEGIN
  CREATE EXTENSION IF NOT EXISTS pg_cron;
  PERFORM cron.schedule(
    'run-daily-coop-shelf-life',
    '10 16 * * *',
    $cron$ SELECT public.process_cooperative_shelf_life(); $cron$
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'pg_cron scheduling skipped (likely unavailable on this plan): %', SQLERRM;
END;
$$;

NOTIFY pgrst, 'reload schema';

-- ═══ Checks (run after the script) ════════════════════════════════════════
-- 1. Objects exist (expect 1 column, 3 triggers, 3 functions):
--      SELECT column_name FROM information_schema.columns
--       WHERE table_name = 'crop_master' AND column_name = 'storage_life_days';
--      SELECT tgname FROM pg_trigger WHERE tgname IN
--        ('trg_coop_lots_hold', 'trg_coop_lots_apply', 'trg_loan_items_shelf_hold');
--      SELECT proname FROM pg_proc WHERE proname IN
--        ('confirm_coop_lot_still_good', 'report_coop_lot_rotten', 'process_cooperative_shelf_life');
--
-- 2. Lots made for the existing stock, and nothing on hold on day one:
--      SELECT i.item_name, i.item_type, l.remaining, l.unit, l.expires_on
--      FROM cooperative_stock_lots l JOIN cooperative_inventory i ON i.id = l.inventory_id
--      ORDER BY l.expires_on;
--
-- 3. Each item's lots add up to its stock (expect 0 rows; a row means stock moved
--    outside the ledger and that item's lots need a look):
--      SELECT i.item_name, i.quantity_on_hand, COALESCE(sum(l.remaining), 0) AS in_lots
--      FROM cooperative_inventory i
--      JOIN cooperative_stock_lots l ON l.inventory_id = i.id
--      GROUP BY i.id, i.item_name, i.quantity_on_hand
--      HAVING abs(i.quantity_on_hand - COALESCE(sum(l.remaining), 0)) > 0.005;
--
-- 4. Tracked-type items that are NOT tracked because the crop has no value yet:
--      SELECT i.item_name, i.item_type, cm.crop_name, cm.shelf_life_days, cm.storage_life_days
--      FROM cooperative_inventory i JOIN crop_master cm ON cm.id = i.crop_master_id
--      WHERE i.is_active AND i.archived_at IS NULL
--        AND public._coop_item_life_days(i.id) IS NULL
--        AND i.item_type IN ('harvested_produce', 'seeds_seedlings');
--
-- 5. The schedule (1 row; none means pg_cron is unavailable):
--      SELECT jobname, schedule, active FROM cron.job WHERE jobname = 'run-daily-coop-shelf-life';
