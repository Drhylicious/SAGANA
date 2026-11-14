-- ═══════════════════════════════════════════════════════════════════════════
-- SAGANA · Cooperative shelf life c03 · Harvest Return + Loan Item Catalog
-- ═══════════════════════════════════════════════════════════════════════════
-- Run AFTER c02 (supabase_schema_coop_shelf_life_c02_distribution_continuity.sql).
-- One transaction. Safe to run more than once.
--
-- HARVEST RETURN
--   How it already works (unchanged): when a Harvest Return outcome is
--   Successful, the Farmer's harvest is recorded WITHOUT the quantity owed to the
--   cooperative, so the return portion is never in the Farmer's sellable stock.
--   That harvest counts down from its actual harvest date (s01). A Failed
--   outcome records no harvest, so there is no countdown.
--
--   What this adds: produce the cooperative RECEIVES as a return keeps that
--   countdown. Its stock lot takes the end date of the Farmer's batch for the
--   same program item (which reflects the real harvest date and any change the
--   Farmer made); when there is no such batch, it counts from the harvest date
--   on the outcome report. It never restarts on the day it is received.
--   Planting Materials and Non-Crop Items that come back are not affected:
--   Planting Materials start their Storage Life on receipt (c01), Non-Crop
--   Items are not tracked.
--
-- LOAN ITEM CATALOG
--   The catalog follows the Inventory item. An item on hold (reached its end
--   date, not inspected) is not offered to Farmers; it returns by itself once
--   Check Produce confirms it. c01 already refuses publishing it and issuing a
--   loan from it. An archived Inventory item was already left out of the
--   Farmer's list, and publishing it again is already refused.
--
-- WHAT THIS ADDS
--   trg_program_return_receipts_shelf_life   (program_return_receipts AFTER INSERT)
--   list_loanable_items()                    one condition added IN PLACE
--
-- NOT CHANGED: no function is rewritten. The return receipt, the outcome
-- workflow and the loan request workflow run exactly as before.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.cooperative_stock_lots') IS NULL
     OR to_regprocedure('public._coop_item_on_hold(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_coop_shelf_life_c01_inventory_lots.sql first.';
  END IF;
  IF to_regclass('public.program_return_receipts') IS NULL OR to_regclass('public.program_returns') IS NULL THEN
    RAISE EXCEPTION 'The Harvest Return tables are missing (program rework p6).';
  END IF;
END;
$$;

-- ═══ 1. A received return keeps the harvest's countdown ═══════════════════
CREATE OR REPLACE FUNCTION public._program_return_receipt_shelf_life()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_lot    cooperative_stock_lots%ROWTYPE;
  v_ret    program_returns%ROWTYPE;
  v_type   TEXT;
  v_start  DATE;
  v_end    DATE;
  v_date   DATE;
BEGIN
  -- The lot c01 made for this receipt's stock-in.
  SELECT l.* INTO v_lot
  FROM inventory_transactions t
  JOIN cooperative_stock_lots l ON l.inventory_transaction_id = t.id
  WHERE t.reference_id = NEW.id AND t.reference_type = 'program_return'
  LIMIT 1;
  IF NOT FOUND THEN
    RETURN NULL;                                  -- not a tracked item
  END IF;

  SELECT item_type INTO v_type FROM cooperative_inventory WHERE id = v_lot.inventory_id;
  IF v_type IS DISTINCT FROM 'harvested_produce' THEN
    RETURN NULL;                                  -- Storage Life starts on receipt
  END IF;

  SELECT * INTO v_ret FROM program_returns WHERE id = NEW.return_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- The Farmer's own batch for this program item: same harvest, same countdown.
  SELECT s.starts_on, s.expires_on INTO v_start, v_end
  FROM harvest_records hr
  JOIN inventory_batches b ON b.harvest_record_id = hr.id
  JOIN batch_shelf_life s  ON s.batch_id = b.id
  WHERE hr.source_program_member_id = v_ret.program_member_id
    AND s.expires_on IS NOT NULL
  ORDER BY hr.created_at DESC
  LIMIT 1;

  IF v_end IS NULL THEN
    -- No batch (for example the whole harvest was returned): the harvest date
    -- on the outcome report.
    SELECT r.harvest_date INTO v_date FROM program_outcome_reports r WHERE r.id = v_ret.outcome_report_id;
    IF v_date IS NULL THEN
      RETURN NULL;                                -- nothing to continue from: keeps the receipt date
    END IF;
    v_start := v_date;
    v_end   := v_date + v_lot.life_days;
  END IF;

  UPDATE cooperative_stock_lots
     SET starts_on = v_start, expires_on = v_end, source = 'returned', updated_at = NOW()
   WHERE id = v_lot.id;
  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public._program_return_receipt_shelf_life() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_program_return_receipts_shelf_life ON public.program_return_receipts;
CREATE TRIGGER trg_program_return_receipts_shelf_life
  AFTER INSERT ON public.program_return_receipts
  FOR EACH ROW EXECUTE FUNCTION public._program_return_receipt_shelf_life();

-- ═══ 2. Farmers are not offered an item that is on hold ═══════════════════
-- One condition is added to the live list_loanable_items(); nothing else in it
-- changes. Skipped with a notice if its text is not what is expected.
DO $$
DECLARE
  d TEXT;
BEGIN
  IF to_regprocedure('public.list_loanable_items()') IS NULL THEN
    RAISE NOTICE 'list_loanable_items() was not found; the Farmer loan catalog was not changed.';
    RETURN;
  END IF;
  SELECT pg_get_functiondef('public.list_loanable_items()'::regprocedure) INTO d;
  IF d LIKE '%_coop_item_on_hold%' THEN
    RETURN;                                       -- already added
  END IF;
  IF d NOT LIKE '%WHERE lim.is_loan_eligible AND ci.is_active%' THEN
    RAISE NOTICE 'list_loanable_items() was not patched (its text differs). An item on hold still cannot be loaned, but Farmers may still see it listed.';
    RETURN;
  END IF;
  d := replace(d,
    'WHERE lim.is_loan_eligible AND ci.is_active',
    'WHERE lim.is_loan_eligible AND ci.is_active AND NOT public._coop_item_on_hold(ci.id)');
  EXECUTE d;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ═══ Checks (run after the script) ════════════════════════════════════════
-- 1. The trigger exists (expect 1 row):
--      SELECT tgname FROM pg_trigger WHERE tgname = 'trg_program_return_receipts_shelf_life';
--
-- 2. The Farmer loan catalog skips items on hold (expect true):
--      SELECT pg_get_functiondef('public.list_loanable_items()'::regprocedure) LIKE '%_coop_item_on_hold%';
--
-- 3. After recording a Harvest Return of produce, its lot starts on the harvest
--    date, not on the day it was received:
--      SELECT i.item_name, l.source, l.starts_on, l.expires_on, l.remaining
--      FROM cooperative_stock_lots l JOIN cooperative_inventory i ON i.id = l.inventory_id
--      WHERE l.source = 'returned' ORDER BY l.created_at DESC LIMIT 5;
