-- ============================================================
-- SAGANA — Farmer Harvest Stock Management (Phase 1, Proposal #1)
--
-- One consistent stock model for a Farmer's harvest batch, across every selling
-- channel, with a movement history and a physical-receipt rule for hand-overs.
--
-- THE FOUR FIGURES OF A BATCH (inventory_batches)
--     quantity_kg   total harvested
--     available_kg  free to sell
--     reserved_kg   committed to an open listing / order / offer / DA-AMAD request
--     sold_kg       sold: only after a CONFIRMED completion
--     adjusted_kg   taken out by the Farmer's own "Update Quantity" (new)
--   available + reserved + sold + adjusted = quantity, always. reserved_kg used to
--   be a dead column (every report derived it); it is now kept true by a trigger.
--
-- WHEN STOCK MOVES (unchanged functions keep doing the reserving; this file adds
-- the rules around them)
--   Marketplace      listing created -> reserved; order cancelled/listing withdrawn
--                    -> released; sold ONLY when the consumer (Buyer or Farmer)
--                    confirms receipt (NEW confirm_order_received). The Manager /
--                    Officer approves; they no longer complete an order.
--   Offer to Coop    offer -> reserved. Price agreed -> status "approved" (NOT sold).
--                    Farmer delivers + photo (NEW deliver_cooperative_offer) ->
--                    "delivered". Manager/Officer confirms receipt (NEW
--                    confirm_cooperative_offer_receipt) -> "completed": THEN it is
--                    sold, the sale is settled, and the kg enter cooperative
--                    inventory (Harvest Stock). Nothing is added to cooperative
--                    inventory before that.
--   Informal Sale    reserved and sold in one step (record_informal_sale). The
--                    Farmer can no longer INSERT/UPDATE/DELETE the rows directly.
--   DA-AMAD (Ginger) unchanged: submit reserves, each Complete Sale sells only the
--                    sold part, unsold stays reserved until the request closes.
--
-- WHAT THIS FILE ADDS
--   1. inventory_batches.adjusted_kg; a guard trigger (no negative stock, sold +
--      available never above what was harvested) that also keeps reserved_kg true.
--   2. update_batch_available_quantity(): records the Farmer's reduction as
--      adjusted_kg (it used to look like a reservation forever).
--   3. reconcile_batch_sold(): same as supabase_schema_market_linking_partial_sales.sql
--      except an offer counts as sold when it is COMPLETED (not when accepted), and
--      the sold-out status accounts for adjusted stock.
--   4. stock_movements: the history ledger (who / what / how much / which channel and
--      reference / balances after). Written by a trigger on inventory_batches, so it
--      captures every path without rewriting any selling function. Read-only for
--      clients. Existing batches get one opening "harvested" row.
--   5. orders: received_at / received_by; a trigger that refuses any completion that
--      did not come from confirm_order_received() (so the old Manager complete_order
--      can no longer complete one) and refuses reopening a completed order.
--   6. cooperative_purchase_offers: statuses pending | approved | delivered |
--      completed | declined | cancelled; delivery/receipt columns;
--      accept_cooperative_offer() now approves (no settlement); the two new
--      functions above; history events 'delivered' and 'received'.
--      Offers that were already "confirmed" (settled before this file) become
--      "completed" untouched: their sale and sold figure already existed. No
--      cooperative inventory is invented for them.
--   7. informal_sales: Farmer read-only at table level.
--   8. Realtime publication for the tables the screens watch.
--
-- WHAT IT DELIBERATELY DOES NOT DO (no unconfirmed SP3 policy invented)
--   * No delivery workflow for Marketplace orders: who delivers and who uploads the
--     delivery photo is UNDEFINED. A delivery order is approved, then the consumer
--     confirms receipt, exactly like pickup. See the report's pending decisions.
--   * No auto-completion of an order the consumer never confirms; no cancelling an
--     offer after it is approved; no delivery disputes, returns, refunds or partial
--     acceptance of a delivered offer.
--   * No existing function body is replaced except accept_cooperative_offer,
--     update_batch_available_quantity and reconcile_batch_sold.
--
-- Run order (a fresh script, never an older copy of the files named here):
--   harvest_batch_number_and_units -> selling_channels_integrity ->
--   crop_photos_selling_rules -> market_linking_partial_sales ->
--   market_linking_buyer_cancellation -> coop_offer_negotiation -> THIS FILE ->
--   supabase_schema_farmer_stock_management_test.sql
-- Safe to re-run. Not applied automatically.
-- ============================================================

-- ─── PRE-FLIGHT (read-only; run each by itself and keep the result) ──────
-- A. Batches that already break the rule (expect 0 rows; any row is old bad data this
--    file will NOT block, but should be looked at):
--    SELECT id, batch_number, quantity_kg, available_kg, sold_kg
--    FROM inventory_batches WHERE available_kg + sold_kg > quantity_kg + 0.005;
-- B. Offers by status before the change:
--    SELECT status, count(*) FROM cooperative_purchase_offers GROUP BY 1;
-- C. Orders approved but never completed (these now wait for the consumer):
--    SELECT count(*) FROM orders WHERE status = 'approved';
-- D. Batches whose "reserved" (quantity - available - sold) differs from what is really
--    committed. Differences are usually old manual "Update Quantity" reductions:
--    SELECT b.batch_number, b.quantity_kg - b.available_kg - b.sold_kg AS derived_reserved,
--      COALESCE((SELECT sum(l.remaining_kg) FROM marketplace_listings l
--                WHERE l.inventory_batch_id=b.id AND l.status IN ('pending_review','approved')),0)
--    + COALESCE((SELECT sum(o.quantity_kg) FROM orders o JOIN marketplace_listings l ON l.id=o.listing_id
--                WHERE l.inventory_batch_id=b.id AND o.status IN ('pending','approved')),0)
--    + COALESCE((SELECT sum(c.offered_quantity_kg) FROM cooperative_purchase_offers c
--                WHERE c.inventory_batch_id=b.id AND c.status IN ('pending','confirmed')),0)
--    + COALESCE((SELECT sum(m.reserved_kg) FROM market_linking_programs m
--                WHERE m.inventory_batch_id=b.id),0) AS committed
--    FROM inventory_batches b ORDER BY 1;
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

-- ═══ 0. Things this file relies on ══════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='inventory_batches' AND column_name='unit') THEN
    RAISE EXCEPTION 'Run supabase_schema_harvest_batch_number_and_units.sql first (inventory_batches.unit is missing).';
  END IF;
  IF to_regprocedure('public.reconcile_batch_sold(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_selling_channels_integrity.sql first (reconcile_batch_sold is missing).';
  END IF;
  IF to_regclass('public.market_linking_sales') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_market_linking_partial_sales.sql first (market_linking_sales is missing).';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='cooperative_purchase_offers' AND column_name='agreed_price_per_kg') THEN
    RAISE EXCEPTION 'Run supabase_schema_coop_offer_negotiation.sql first (agreed_price_per_kg is missing).';
  END IF;
  IF to_regclass('public.cooperative_offer_events') IS NULL
     OR to_regclass('public.cooperative_inventory') IS NULL
     OR to_regclass('public.inventory_transactions') IS NULL THEN
    RAISE EXCEPTION 'cooperative_offer_events / cooperative_inventory / inventory_transactions is missing.';
  END IF;
  IF to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_staff() is missing. Run supabase_schema_role_based_staff_access.sql first.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='cooperative_inventory' AND column_name='source') THEN
    RAISE EXCEPTION 'Run supabase_schema_inventory_source.sql first (cooperative_inventory.source is missing).';
  END IF;
END;
$$;

-- ═══ 1. The batch: adjusted stock, a guard, and a truthful reserved_kg ════
ALTER TABLE public.inventory_batches
  ADD COLUMN IF NOT EXISTS adjusted_kg NUMERIC(10,2) NOT NULL DEFAULT 0
    CHECK (adjusted_kg >= 0);

COMMENT ON COLUMN public.inventory_batches.adjusted_kg IS
  'Quantity the Farmer took out with Update Quantity (spoilage, own use ...). '
  'available + reserved + sold + adjusted = quantity.';

CREATE OR REPLACE FUNCTION public._inventory_batch_stock_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_over_new NUMERIC;
  v_over_old NUMERIC := 0;
BEGIN
  IF NEW.available_kg < 0 THEN
    RAISE EXCEPTION 'Not enough available quantity in this batch.';
  END IF;
  IF NEW.sold_kg < 0 OR NEW.adjusted_kg < 0 THEN
    RAISE EXCEPTION 'A batch cannot hold a negative sold or adjusted quantity.';
  END IF;

  -- Available + sold + adjusted may never be MORE than was harvested. Only a change
  -- that makes it worse is refused, so a batch with old bad data can still be used.
  v_over_new := NEW.available_kg + NEW.sold_kg + NEW.adjusted_kg - NEW.quantity_kg;
  IF TG_OP = 'UPDATE' THEN
    v_over_old := OLD.available_kg + OLD.sold_kg + OLD.adjusted_kg - OLD.quantity_kg;
  END IF;
  IF v_over_new > 0.005 AND v_over_new > v_over_old + 0.005 THEN
    RAISE EXCEPTION 'The available and sold quantity of a batch cannot be more than was harvested.';
  END IF;

  NEW.reserved_kg := GREATEST(
    round(NEW.quantity_kg - NEW.available_kg - NEW.sold_kg - NEW.adjusted_kg, 2), 0);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_inventory_batches_stock_guard ON public.inventory_batches;
CREATE TRIGGER trg_inventory_batches_stock_guard
  BEFORE INSERT OR UPDATE ON public.inventory_batches
  FOR EACH ROW EXECUTE FUNCTION public._inventory_batch_stock_guard();

-- Make the stored reserved_kg true for every existing batch (touches only the rows
-- where it differs).
UPDATE public.inventory_batches
   SET reserved_kg = GREATEST(round(quantity_kg - available_kg - sold_kg - adjusted_kg, 2), 0)
 WHERE reserved_kg IS DISTINCT FROM
       GREATEST(round(quantity_kg - available_kg - sold_kg - adjusted_kg, 2), 0);

-- ═══ 2. "Update Quantity" is an adjustment, not a reservation ═════════════
-- Same rules as supabase_schema_update_batch_quantity_reservation_guard_v2.sql (the
-- value may only go down, never below zero), plus: the reduction is recorded as
-- adjusted_kg, and an emptied batch with nothing committed reads "sold out".
CREATE OR REPLACE FUNCTION public.update_batch_available_quantity(
  p_batch_id UUID,
  p_new_available_kg DECIMAL
) RETURNS VOID AS $$
DECLARE
  v_farmer_id    UUID;
  v_quantity_kg  DECIMAL;
  v_available_kg DECIMAL;
  v_sold_kg      DECIMAL;
  v_adjusted_kg  DECIMAL;
  v_new_adjusted DECIMAL;
  v_new_status   TEXT;
BEGIN
  SELECT farmer_id, quantity_kg, available_kg, sold_kg, adjusted_kg
    INTO v_farmer_id, v_quantity_kg, v_available_kg, v_sold_kg, v_adjusted_kg
    FROM public.inventory_batches
    WHERE id = p_batch_id
    FOR UPDATE;

  IF v_quantity_kg IS NULL THEN
    RAISE EXCEPTION 'Batch not found';
  END IF;
  IF auth.uid() IS NOT NULL AND v_farmer_id <> auth.uid() THEN
    RAISE EXCEPTION 'This batch was not found in your inventory.';
  END IF;
  IF p_new_available_kg IS NULL OR p_new_available_kg < 0 THEN
    RAISE EXCEPTION 'Available quantity cannot be negative';
  END IF;
  IF p_new_available_kg <> round(p_new_available_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the quantity.';
  END IF;
  IF p_new_available_kg > v_available_kg THEN
    RAISE EXCEPTION 'Available quantity (%) cannot exceed the current available amount of % kg. Increasing available stock isn''t supported here — % kg of this batch is committed to an active listing, cooperative offer, or market linking reservation, and is restored automatically when that reservation ends.',
      p_new_available_kg, v_available_kg, (v_quantity_kg - v_sold_kg - v_adjusted_kg - v_available_kg);
  END IF;

  v_new_adjusted := v_adjusted_kg + (v_available_kg - p_new_available_kg);

  IF p_new_available_kg <= 0 THEN
    v_new_status := CASE WHEN v_quantity_kg - v_sold_kg - v_new_adjusted <= 0 THEN 'sold_out' ELSE 'reserved' END;
  ELSIF p_new_available_kg < v_quantity_kg * 0.15 THEN
    v_new_status := 'low_stock';
  ELSE
    v_new_status := 'available';
  END IF;

  UPDATE public.inventory_batches
     SET available_kg = p_new_available_kg,
         adjusted_kg  = v_new_adjusted,
         status       = v_new_status
   WHERE id = p_batch_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.update_batch_available_quantity(UUID, DECIMAL) TO authenticated;

-- ═══ 3. One place that knows what is really sold ══════════════════════════
-- Identical to supabase_schema_market_linking_partial_sales.sql, with two changes:
-- an offer is sold when it is COMPLETED (receipt confirmed), and a batch with
-- nothing left to sell or commit reads "sold out" even if part of it was adjusted.
CREATE OR REPLACE FUNCTION public.reconcile_batch_sold(p_batch_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_quantity  NUMERIC;
  v_available NUMERIC;
  v_adjusted  NUMERIC;
  v_status    TEXT;
  v_sold      NUMERIC;
  v_new       TEXT;
BEGIN
  IF p_batch_id IS NULL THEN
    RETURN;
  END IF;

  SELECT quantity_kg, available_kg, adjusted_kg, status
    INTO v_quantity, v_available, v_adjusted, v_status
  FROM inventory_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  v_sold :=
      COALESCE((SELECT sum(o.quantity_kg) FROM orders o
                  JOIN marketplace_listings l ON l.id = o.listing_id
                 WHERE l.inventory_batch_id = p_batch_id AND o.status = 'completed'), 0)
    + COALESCE((SELECT sum(i.quantity_kg) FROM informal_sales i
                 WHERE i.inventory_batch_id = p_batch_id), 0)
    + COALESCE((SELECT sum(c.confirmed_quantity_kg) FROM cooperative_purchase_offers c
                 WHERE c.inventory_batch_id = p_batch_id AND c.status = 'completed'), 0)
    + COALESCE((SELECT sum(s.confirmed_volume_kg) FROM market_linking_sales s
                 WHERE s.inventory_batch_id = p_batch_id), 0)
    + COALESCE((SELECT sum(m.confirmed_volume_kg) FROM market_linking_programs m
                 WHERE m.inventory_batch_id = p_batch_id AND m.status = 'completed'
                   AND NOT EXISTS (SELECT 1 FROM market_linking_sales s2 WHERE s2.program_id = m.id)), 0);

  v_new := CASE
    WHEN v_status = 'withdrawn' THEN v_status
    WHEN v_available <= 0 THEN CASE WHEN v_sold + v_adjusted >= v_quantity THEN 'sold_out' ELSE 'reserved' END
    WHEN v_available < v_quantity * 0.15 THEN 'low_stock'
    ELSE 'available'
  END;

  UPDATE inventory_batches
     SET sold_kg = v_sold, status = v_new
   WHERE id = p_batch_id
     AND (sold_kg IS DISTINCT FROM v_sold OR status IS DISTINCT FROM v_new);
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_batch_sold(UUID) FROM PUBLIC, anon, authenticated;

-- ═══ 4. The stock movement history ════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.stock_movements (
  id              UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id        UUID          NOT NULL REFERENCES public.inventory_batches(id) ON DELETE CASCADE,
  farmer_id       UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  -- harvested      the batch was recorded (or, for old batches, the opening balance)
  -- reserved       available -> reserved (listing, offer, DA-AMAD request)
  -- released       reserved -> available (cancelled, declined, withdrawn, closed)
  -- sold           reserved -> sold (confirmed completion only)
  -- sale_reversed  a sale record was removed or corrected
  -- adjusted       taken out by the Farmer's Update Quantity
  -- adjustment_reversed / quantity_changed   corrections
  movement_type   TEXT          NOT NULL CHECK (movement_type IN (
                    'harvested', 'reserved', 'released', 'sold', 'sale_reversed',
                    'adjusted', 'adjustment_reversed', 'quantity_changed')),
  -- Which selling channel caused it. NULL for harvest and manual adjustments.
  channel         TEXT          CHECK (channel IN (
                    'marketplace', 'cooperative_offer', 'informal_sale', 'market_linking')),
  reference_type  TEXT,
  reference_id    UUID,
  quantity        NUMERIC(10,2) NOT NULL CHECK (quantity >= 0),
  unit            TEXT,
  available_after NUMERIC(10,2) NOT NULL,
  reserved_after  NUMERIC(10,2) NOT NULL,
  sold_after      NUMERIC(10,2) NOT NULL,
  adjusted_after  NUMERIC(10,2) NOT NULL DEFAULT 0,
  actor_id        UUID,
  note            TEXT,
  txid            BIGINT        NOT NULL DEFAULT txid_current(),
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

-- Rows written in one transaction would share one NOW(), so "newest first" needs a
-- real order: the time is the clock's (not the transaction's) and seq breaks any tie.
ALTER TABLE public.stock_movements ALTER COLUMN created_at SET DEFAULT clock_timestamp();
ALTER TABLE public.stock_movements ADD COLUMN IF NOT EXISTS seq BIGINT GENERATED ALWAYS AS IDENTITY;

CREATE INDEX IF NOT EXISTS idx_stock_movements_batch  ON public.stock_movements (batch_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_movements_farmer ON public.stock_movements (farmer_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_movements_ref    ON public.stock_movements (reference_type, reference_id);

ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "stock_movements: farmer reads own" ON public.stock_movements;
CREATE POLICY "stock_movements: farmer reads own"
  ON public.stock_movements FOR SELECT TO authenticated
  USING (farmer_id = auth.uid());

DROP POLICY IF EXISTS "stock_movements: staff reads all" ON public.stock_movements;
CREATE POLICY "stock_movements: staff reads all"
  ON public.stock_movements FOR SELECT TO authenticated
  USING (public.is_staff());

-- History is written by the trigger below and nowhere else.
REVOKE ALL ON public.stock_movements FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.stock_movements TO authenticated;

-- Every change to a batch's figures writes its movement(s). Because it watches the
-- batch itself, it records every path (listing, order, offer, informal sale, DA-AMAD,
-- manual adjustment) without those functions having to know about it.
CREATE OR REPLACE FUNCTION public._log_stock_movement()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  d_avail NUMERIC;
  d_sold  NUMERIC;
  d_adj   NUMERIC;
  d_qty   NUMERIC;
  v_moved NUMERIC;
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO stock_movements (batch_id, farmer_id, movement_type, reference_type, reference_id,
                                 quantity, unit, available_after, reserved_after, sold_after,
                                 adjusted_after, actor_id, created_at)
    VALUES (NEW.id, NEW.farmer_id, 'harvested', 'harvest_record', NEW.harvest_record_id,
            NEW.quantity_kg, NEW.unit, NEW.available_kg, NEW.reserved_kg, NEW.sold_kg,
            NEW.adjusted_kg, auth.uid(), NOW());
    RETURN NULL;
  END IF;

  d_avail := NEW.available_kg - OLD.available_kg;
  d_sold  := NEW.sold_kg      - OLD.sold_kg;
  d_adj   := NEW.adjusted_kg  - OLD.adjusted_kg;
  d_qty   := NEW.quantity_kg  - OLD.quantity_kg;
  -- Kg that went from available into reserved (negative: back to available).
  v_moved := d_qty - d_avail - d_adj;

  IF abs(d_qty) >= 0.005 THEN
    PERFORM public._insert_stock_movement(NEW, 'quantity_changed', abs(d_qty));
  END IF;
  IF d_sold >= 0.005 THEN
    PERFORM public._insert_stock_movement(NEW, 'sold', d_sold);
  ELSIF d_sold <= -0.005 THEN
    PERFORM public._insert_stock_movement(NEW, 'sale_reversed', -d_sold);
  END IF;
  IF d_adj >= 0.005 THEN
    PERFORM public._insert_stock_movement(NEW, 'adjusted', d_adj);
  ELSIF d_adj <= -0.005 THEN
    PERFORM public._insert_stock_movement(NEW, 'adjustment_reversed', -d_adj);
  END IF;
  IF v_moved >= 0.005 THEN
    PERFORM public._insert_stock_movement(NEW, 'reserved', v_moved);
  ELSIF v_moved <= -0.005 THEN
    PERFORM public._insert_stock_movement(NEW, 'released', -v_moved);
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public._insert_stock_movement(
  p_batch public.inventory_batches, p_type TEXT, p_qty NUMERIC
) RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO stock_movements (batch_id, farmer_id, movement_type, quantity, unit,
                               available_after, reserved_after, sold_after, adjusted_after, actor_id)
  VALUES (p_batch.id, p_batch.farmer_id, p_type, p_qty, p_batch.unit,
          p_batch.available_kg, p_batch.reserved_kg, p_batch.sold_kg, p_batch.adjusted_kg, auth.uid());
$$;
REVOKE ALL ON FUNCTION public._insert_stock_movement(public.inventory_batches, TEXT, NUMERIC) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._log_stock_movement() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_inventory_batches_log_movement ON public.inventory_batches;
CREATE TRIGGER trg_inventory_batches_log_movement
  AFTER INSERT OR UPDATE ON public.inventory_batches
  FOR EACH ROW EXECUTE FUNCTION public._log_stock_movement();

-- Which channel / record caused the movements of this transaction. The selling
-- tables call this from AFTER triggers (named trg_zz_* so they run after the
-- reconcile triggers). It only fills movements that have no channel yet.
CREATE OR REPLACE FUNCTION public._claim_stock_movements(
  p_batch UUID, p_channel TEXT, p_ref_type TEXT, p_ref UUID
) RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE stock_movements
     SET channel = p_channel, reference_type = p_ref_type, reference_id = p_ref
   WHERE batch_id = p_batch
     AND txid = txid_current()
     AND channel IS NULL
     AND movement_type <> 'harvested';
$$;
REVOKE ALL ON FUNCTION public._claim_stock_movements(UUID, TEXT, TEXT, UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._claim_movements_listing() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public._claim_stock_movements(NEW.inventory_batch_id, 'marketplace', 'listing', NEW.id);
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_zz_listings_stock_claim ON public.marketplace_listings;
CREATE TRIGGER trg_zz_listings_stock_claim
  AFTER INSERT OR UPDATE ON public.marketplace_listings
  FOR EACH ROW EXECUTE FUNCTION public._claim_movements_listing();

CREATE OR REPLACE FUNCTION public._claim_movements_order() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_batch UUID;
BEGIN
  SELECT inventory_batch_id INTO v_batch FROM marketplace_listings WHERE id = NEW.listing_id;
  PERFORM public._claim_stock_movements(v_batch, 'marketplace', 'order', NEW.id);
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_zz_orders_stock_claim ON public.orders;
CREATE TRIGGER trg_zz_orders_stock_claim
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public._claim_movements_order();

CREATE OR REPLACE FUNCTION public._claim_movements_offer() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public._claim_stock_movements(NEW.inventory_batch_id, 'cooperative_offer', 'offer', NEW.id);
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_zz_offers_stock_claim ON public.cooperative_purchase_offers;
CREATE TRIGGER trg_zz_offers_stock_claim
  AFTER INSERT OR UPDATE ON public.cooperative_purchase_offers
  FOR EACH ROW EXECUTE FUNCTION public._claim_movements_offer();

CREATE OR REPLACE FUNCTION public._claim_movements_informal() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public._claim_stock_movements(OLD.inventory_batch_id, 'informal_sale', 'informal_sale', OLD.id);
  ELSE
    PERFORM public._claim_stock_movements(NEW.inventory_batch_id, 'informal_sale', 'informal_sale', NEW.id);
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_zz_informal_stock_claim ON public.informal_sales;
CREATE TRIGGER trg_zz_informal_stock_claim
  AFTER INSERT OR UPDATE OR DELETE ON public.informal_sales
  FOR EACH ROW EXECUTE FUNCTION public._claim_movements_informal();

CREATE OR REPLACE FUNCTION public._claim_movements_market_linking() RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_TABLE_NAME = 'market_linking_sales' THEN
    PERFORM public._claim_stock_movements(NEW.inventory_batch_id, 'market_linking', 'market_linking_sale', NEW.id);
  ELSE
    PERFORM public._claim_stock_movements(NEW.inventory_batch_id, 'market_linking', 'market_linking_request', NEW.id);
  END IF;
  RETURN NULL;
END;
$$;
DROP TRIGGER IF EXISTS trg_zz_market_linking_stock_claim ON public.market_linking_programs;
CREATE TRIGGER trg_zz_market_linking_stock_claim
  AFTER INSERT OR UPDATE ON public.market_linking_programs
  FOR EACH ROW EXECUTE FUNCTION public._claim_movements_market_linking();
DROP TRIGGER IF EXISTS trg_zz_market_linking_sales_stock_claim ON public.market_linking_sales;
CREATE TRIGGER trg_zz_market_linking_sales_stock_claim
  AFTER INSERT ON public.market_linking_sales
  FOR EACH ROW EXECUTE FUNCTION public._claim_movements_market_linking();

-- Opening balance for batches that existed before this history began. The balances
-- on that row are the CURRENT ones, and it says so.
INSERT INTO public.stock_movements (batch_id, farmer_id, movement_type, reference_type, reference_id,
                                    quantity, unit, available_after, reserved_after, sold_after,
                                    adjusted_after, note, created_at)
SELECT b.id, b.farmer_id, 'harvested', 'harvest_record', b.harvest_record_id,
       b.quantity_kg, b.unit, b.available_kg, b.reserved_kg, b.sold_kg, b.adjusted_kg,
       'Opening balance: history starts here; the balances shown are the ones at that time.',
       b.created_at
FROM public.inventory_batches b
WHERE NOT EXISTS (SELECT 1 FROM public.stock_movements m WHERE m.batch_id = b.id);

-- ═══ 5. Marketplace: the consumer confirms receipt ═══════════════════════
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS received_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

-- An order becomes "completed" in exactly one way, and a completed order never
-- reopens. This also stops the previous Manager "complete_order" from completing
-- one (it fails with the message below and rolls back whole, including its sold_kg
-- change), without having to replace that function.
CREATE OR REPLACE FUNCTION public._orders_require_receipt()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status = 'completed' AND NEW.status IS DISTINCT FROM 'completed' THEN
    RAISE EXCEPTION 'A completed order cannot be changed.';
  END IF;
  IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' THEN
    IF current_setting('sagana.order_receipt', true) IS DISTINCT FROM NEW.id::text THEN
      RAISE EXCEPTION 'An order is completed when the buyer confirms they received it.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_require_receipt ON public.orders;
CREATE TRIGGER trg_orders_require_receipt
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._orders_require_receipt();

-- NOTE: supabase_schema_order_fulfillment_workflow.sql REPLACES both this function
-- (it then also needs Ready for Pickup / Delivered) and _orders_require_receipt()
-- above. Always run that file AFTER this one, including after a re-run of this one.
CREATE OR REPLACE FUNCTION public.confirm_order_received(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o         orders%ROWTYPE;
  l         marketplace_listings%ROWTYPE;
  v_name    TEXT;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR o.buyer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF o.status = 'completed' THEN
    RAISE EXCEPTION 'You already confirmed receiving this order.';
  END IF;
  IF o.status <> 'approved' THEN
    RAISE EXCEPTION 'Only an approved order can be confirmed as received (current status: %).', o.status;
  END IF;

  SELECT * INTO l FROM marketplace_listings WHERE id = o.listing_id FOR UPDATE;

  PERFORM set_config('sagana.order_receipt', o.id::text, true);
  UPDATE orders
     SET status = 'completed', received_at = NOW(), received_by = auth.uid()
   WHERE id = o.id;
  PERFORM set_config('sagana.order_receipt', '', true);

  -- Sold = what completed orders add up to (sets the figure, never adds to it, so
  -- it cannot double count even if the reconcile trigger already ran).
  PERFORM public.reconcile_batch_sold(l.inventory_batch_id);

  IF l.remaining_kg <= 0 THEN
    UPDATE marketplace_listings SET status = 'sold' WHERE id = l.id AND status <> 'sold';
  END IF;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = auth.uid();

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (l.farmer_id, 'order', 'Order Completed',
          COALESCE(v_name, 'The buyer') || ' confirmed receiving ' || o.quantity_kg || ' ' ||
            COALESCE(o.unit, 'kg') || ' of your ' || COALESCE(l.crop_name, 'produce') || '.',
          FALSE, NOW(), '/farmer/marketplace');

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ur.user_id, 'order', 'Order Completed',
         COALESCE(v_name, 'The buyer') || ' confirmed receiving ' || o.quantity_kg || ' ' ||
           COALESCE(o.unit, 'kg') || ' of ' || COALESCE(l.crop_name, 'produce') || '.',
         FALSE, NOW(), '/admin/marketplace/orders'
  FROM user_roles ur WHERE ur.role IN ('admin', 'officer');
END;
$$;

REVOKE ALL ON FUNCTION public.confirm_order_received(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_order_received(UUID) TO authenticated;

-- ═══ 6. Offer to Cooperative: approve -> deliver -> confirm receipt ═══════
ALTER TABLE public.cooperative_purchase_offers
  ADD COLUMN IF NOT EXISTS approved_at         TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_photo_url  TEXT,
  ADD COLUMN IF NOT EXISTS delivery_note       TEXT,
  ADD COLUMN IF NOT EXISTS delivered_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS received_at         TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS received_by         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS receipt_note        TEXT,
  ADD COLUMN IF NOT EXISTS coop_inventory_id   UUID REFERENCES public.cooperative_inventory(id) ON DELETE SET NULL;

-- The status rule. Replace every status CHECK (its generated name is not reliable).
DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.cooperative_purchase_offers'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%status%'
      AND pg_get_constraintdef(oid) ILIKE '%pending%'
  LOOP
    EXECUTE format('ALTER TABLE public.cooperative_purchase_offers DROP CONSTRAINT %I', c.conname);
  END LOOP;
END;
$$;

-- Old "confirmed" offers were settled when they were accepted (sale written, sold
-- counted). They are completed as far as the books go; keep them that way.
DROP TRIGGER IF EXISTS trg_coop_offers_reconcile ON public.cooperative_purchase_offers;
UPDATE public.cooperative_purchase_offers
   SET status = 'completed', received_at = COALESCE(received_at, confirmed_at)
 WHERE status = 'confirmed';

ALTER TABLE public.cooperative_purchase_offers
  ADD CONSTRAINT cooperative_purchase_offers_status_check
  CHECK (status IN ('pending', 'approved', 'delivered', 'completed', 'declined', 'cancelled'));

CREATE OR REPLACE FUNCTION public.reconcile_after_offer_completed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.reconcile_batch_sold(NEW.inventory_batch_id);
  RETURN NULL;
END;
$$;

CREATE TRIGGER trg_coop_offers_reconcile
  AFTER UPDATE OF status ON public.cooperative_purchase_offers
  FOR EACH ROW WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.reconcile_after_offer_completed();

-- Only these moves are possible, and an offer is never un-completed.
CREATE OR REPLACE FUNCTION public._coop_offer_status_flow()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;
  IF NOT (
       (OLD.status = 'pending'   AND NEW.status IN ('approved', 'declined', 'cancelled'))
    OR (OLD.status = 'approved'  AND NEW.status = 'delivered')
    OR (OLD.status = 'delivered' AND NEW.status = 'completed')
  ) THEN
    RAISE EXCEPTION 'An offer cannot move from % to %.', OLD.status, NEW.status;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_coop_offers_status_flow ON public.cooperative_purchase_offers;
CREATE TRIGGER trg_coop_offers_status_flow
  BEFORE UPDATE OF status ON public.cooperative_purchase_offers
  FOR EACH ROW EXECUTE FUNCTION public._coop_offer_status_flow();

-- History events: add 'delivered' and 'received'.
DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.cooperative_offer_events'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%action%'
      AND pg_get_constraintdef(oid) ILIKE '%offered%'
  LOOP
    EXECUTE format('ALTER TABLE public.cooperative_offer_events DROP CONSTRAINT %I', c.conname);
  END LOOP;
END;
$$;
ALTER TABLE public.cooperative_offer_events
  ADD CONSTRAINT cooperative_offer_events_action_check
  CHECK (action IN ('offered', 'countered', 'accepted', 'declined', 'cancelled', 'delivered', 'received'));

-- A delivery is counted into cooperative inventory once, ever.
CREATE UNIQUE INDEX IF NOT EXISTS uq_inventory_tx_offer_receipt
  ON public.inventory_transactions (reference_id)
  WHERE transaction_type = 'harvest_received' AND reference_type = 'cooperative_offer';

-- 6a. Price agreed: ACCEPTED (stored as status 'approved'). Nothing is sold, settled or added to inventory yet.
-- Same checks and signature as supabase_schema_coop_offer_negotiation.sql.
CREATE OR REPLACE FUNCTION public.accept_cooperative_offer(
  p_offer_id        UUID,
  p_expected_round  INTEGER,
  p_note            TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer   RECORD;
  v_side    TEXT;
  v_qty     NUMERIC;
  v_amount  NUMERIC;
  v_staff   UUID;
  v_name    TEXT;
BEGIN
  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cooperative offer not found.';
  END IF;

  v_side := CASE
    WHEN auth.uid() = v_offer.farmer_id THEN 'farmer'
    WHEN public.is_staff() THEN 'cooperative'
  END;
  IF v_side IS NULL THEN
    RAISE EXCEPTION 'You are not allowed to respond to this offer.';
  END IF;
  IF v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'This negotiation is already closed.';
  END IF;
  IF p_expected_round IS DISTINCT FROM v_offer.negotiation_round THEN
    RAISE EXCEPTION 'This offer was updated. Please refresh and review the latest price.';
  END IF;
  IF v_side = v_offer.last_proposed_by THEN
    RAISE EXCEPTION 'You proposed the latest price. The other side has to accept it.';
  END IF;
  IF v_offer.current_price_per_kg IS NULL THEN
    RAISE EXCEPTION 'No price has been proposed yet. Propose a price first.';
  END IF;

  v_qty    := v_offer.offered_quantity_kg;
  v_amount := round(v_offer.current_price_per_kg * v_qty, 2);

  IF v_side = 'cooperative' THEN
    v_staff := auth.uid();
  ELSE
    SELECT actor_id INTO v_staff
    FROM cooperative_offer_events
    WHERE offer_id = p_offer_id AND actor_role = 'cooperative' AND actor_id IS NOT NULL
    ORDER BY created_at DESC, id DESC
    LIMIT 1;
  END IF;

  UPDATE cooperative_purchase_offers
  SET status                = 'approved',
      confirmed_quantity_kg = v_qty,
      confirmed_amount      = v_amount,
      agreed_price_per_kg   = v_offer.current_price_per_kg,
      confirmed_by          = v_staff,
      confirmed_at          = NOW(),
      approved_at           = NOW()
  WHERE id = p_offer_id;

  INSERT INTO cooperative_offer_events
    (offer_id, round, action, actor_role, actor_id, price_per_kg, quantity_kg, note)
  VALUES
    (p_offer_id, v_offer.negotiation_round, 'accepted', v_side, auth.uid(),
     v_offer.current_price_per_kg, v_qty, NULLIF(btrim(p_note), ''));

  IF v_side = 'cooperative' THEN
    PERFORM public._coop_offer_notify_farmer(
      v_offer.farmer_id,
      'Cooperative Accepted Your Offer',
      'SP3 accepted your ' || v_qty || ' kg ' || v_offer.crop_name || ' at ' ||
        public._coop_offer_peso(v_offer.current_price_per_kg) || '/kg (total ' ||
        public._coop_offer_peso(v_amount) || '). Deliver it to the cooperative and upload a photo.'
    );
  ELSE
    SELECT full_name INTO v_name FROM user_information WHERE user_id = v_offer.farmer_id;
    PERFORM public._coop_offer_notify_staff(
      'Farmer Accepted the Price',
      COALESCE(v_name, 'A farmer') || ' accepted ' || public._coop_offer_peso(v_offer.current_price_per_kg) ||
        '/kg for ' || v_qty || ' kg ' || v_offer.crop_name || '. Waiting for the delivery.'
    );
  END IF;

  RETURN p_offer_id;
END;
$$;
REVOKE ALL ON FUNCTION public.accept_cooperative_offer(UUID, INTEGER, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_cooperative_offer(UUID, INTEGER, TEXT) TO authenticated;

-- 6b. The Farmer delivers and uploads the photo evidence.
CREATE OR REPLACE FUNCTION public.deliver_cooperative_offer(
  p_offer_id  UUID,
  p_photo_url TEXT,
  p_note      TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer RECORD;
  v_name  TEXT;
BEGIN
  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND OR v_offer.farmer_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'Cooperative offer not found.';
  END IF;
  IF v_offer.status = 'delivered' THEN
    RAISE EXCEPTION 'You already marked this offer as delivered.';
  END IF;
  IF v_offer.status <> 'approved' THEN
    RAISE EXCEPTION 'Only an accepted offer can be marked as delivered (current status: %).', v_offer.status;
  END IF;
  IF p_photo_url IS NULL OR btrim(p_photo_url) = '' OR btrim(p_photo_url) NOT ILIKE 'http%' THEN
    RAISE EXCEPTION 'Upload a photo of the delivery first.';
  END IF;

  UPDATE cooperative_purchase_offers
     SET status = 'delivered',
         delivery_photo_url = btrim(p_photo_url),
         delivery_note = NULLIF(btrim(p_note), ''),
         delivered_at = NOW()
   WHERE id = p_offer_id;

  INSERT INTO cooperative_offer_events
    (offer_id, round, action, actor_role, actor_id, price_per_kg, quantity_kg, note)
  VALUES
    (p_offer_id, v_offer.negotiation_round, 'delivered', 'farmer', auth.uid(),
     v_offer.agreed_price_per_kg, v_offer.offered_quantity_kg, NULLIF(btrim(p_note), ''));

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_offer.farmer_id;
  PERFORM public._coop_offer_notify_staff(
    'Cooperative Delivery to Confirm',
    COALESCE(v_name, 'A farmer') || ' delivered ' || v_offer.offered_quantity_kg || ' kg ' ||
      v_offer.crop_name || '. Check it and confirm receipt.'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.deliver_cooperative_offer(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.deliver_cooperative_offer(UUID, TEXT, TEXT) TO authenticated;

-- 6c. The delivered kg become cooperative stock (Harvest Stock), once.
CREATE OR REPLACE FUNCTION public._coop_receive_harvest(p_offer_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer RECORD;
  v_item  UUID;
  v_unit  TEXT;
BEGIN
  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id;
  v_unit := COALESCE(NULLIF(btrim(v_offer.unit), ''), 'kg');

  SELECT id INTO v_item
  FROM cooperative_inventory
  WHERE category = 'Harvest Stock'
    AND lower(item_name) = lower(v_offer.crop_name)
    AND lower(unit) = lower(v_unit)
    AND is_active
  ORDER BY created_at
  LIMIT 1
  FOR UPDATE;

  IF v_item IS NULL THEN
    INSERT INTO cooperative_inventory (item_name, category, unit, quantity_on_hand, source, created_by)
    VALUES (v_offer.crop_name, 'Harvest Stock', v_unit, 0,
            'Farmer deliveries (Offer to Cooperative)', auth.uid())
    RETURNING id INTO v_item;
  END IF;

  UPDATE cooperative_inventory
     SET quantity_on_hand = quantity_on_hand + v_offer.confirmed_quantity_kg,
         last_restocked_at = NOW()
   WHERE id = v_item;

  INSERT INTO inventory_transactions
    (inventory_id, transaction_type, quantity, reference_id, reference_type, notes, recorded_by)
  VALUES
    (v_item, 'harvest_received', v_offer.confirmed_quantity_kg, p_offer_id, 'cooperative_offer',
     'Received from a farmer: Offer to Cooperative', auth.uid());

  RETURN v_item;
END;
$$;
REVOKE ALL ON FUNCTION public._coop_receive_harvest(UUID) FROM PUBLIC, anon, authenticated;

-- 6d. The Manager / Officer confirms the physical receipt: completes the offer,
-- settles the sale, counts the kg as sold, moves them into cooperative inventory.
CREATE OR REPLACE FUNCTION public.confirm_cooperative_offer_receipt(
  p_offer_id UUID,
  p_note     TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_offer RECORD;
  v_tx    UUID;
  v_item  UUID;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only the cooperative can confirm a delivery.';
  END IF;

  SELECT * INTO v_offer FROM cooperative_purchase_offers WHERE id = p_offer_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cooperative offer not found.';
  END IF;
  IF v_offer.status = 'completed' THEN
    RAISE EXCEPTION 'This delivery was already confirmed.';
  END IF;
  IF v_offer.status <> 'delivered' THEN
    RAISE EXCEPTION 'Only a delivered offer can be confirmed as received (current status: %).', v_offer.status;
  END IF;
  IF v_offer.member_sales_transaction_id IS NOT NULL THEN
    RAISE EXCEPTION 'This offer was already settled.';
  END IF;

  INSERT INTO member_sales_transactions (
    farmer_id, crop_name, crop_type, quantity_kg, amount, sale_date, recorded_by
  ) VALUES (
    v_offer.farmer_id, v_offer.crop_name, lower(v_offer.crop_name),
    v_offer.confirmed_quantity_kg, v_offer.confirmed_amount, CURRENT_DATE, auth.uid()
  ) RETURNING id INTO v_tx;

  v_item := public._coop_receive_harvest(p_offer_id);

  UPDATE cooperative_purchase_offers
     SET status = 'completed',
         member_sales_transaction_id = v_tx,
         received_at = NOW(),
         received_by = auth.uid(),
         receipt_note = NULLIF(btrim(p_note), ''),
         coop_inventory_id = v_item
   WHERE id = p_offer_id;

  INSERT INTO cooperative_offer_events
    (offer_id, round, action, actor_role, actor_id, price_per_kg, quantity_kg, note)
  VALUES
    (p_offer_id, v_offer.negotiation_round, 'received', 'cooperative', auth.uid(),
     v_offer.agreed_price_per_kg, v_offer.confirmed_quantity_kg, NULLIF(btrim(p_note), ''));

  PERFORM public.reconcile_batch_sold(v_offer.inventory_batch_id);

  PERFORM public._coop_offer_notify_farmer(
    v_offer.farmer_id,
    'Delivery Confirmed',
    'SP3 confirmed receiving your ' || v_offer.confirmed_quantity_kg || ' kg ' || v_offer.crop_name ||
      '. The sale of ' || public._coop_offer_peso(v_offer.confirmed_amount) || ' is recorded.'
  );

  RETURN v_tx;
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_cooperative_offer_receipt(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_cooperative_offer_receipt(UUID, TEXT) TO authenticated;

-- ═══ 7. Informal sales: written only through record_informal_sale ═════════
-- A Farmer deleting or editing a sale row directly would change Sold without the
-- reservation that went with it. Reads are unchanged; the app only reads this table
-- and records sales through the function.
DROP POLICY IF EXISTS "informal_sales: farmer manages own" ON public.informal_sales;
DROP POLICY IF EXISTS "informal_sales: farmer reads own" ON public.informal_sales;
CREATE POLICY "informal_sales: farmer reads own"
  ON public.informal_sales FOR SELECT
  USING (auth.uid() = farmer_id);

-- ═══ 8. Live screens ══════════════════════════════════════════════════════
DO $$
DECLARE t TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    FOREACH t IN ARRAY ARRAY['inventory_batches', 'stock_movements', 'cooperative_purchase_offers', 'orders'] LOOP
      IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                     WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = t) THEN
        EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', t);
      END IF;
    END LOOP;
  END IF;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. Every batch adds up (expect 0 rows):
--    SELECT batch_number, quantity_kg, available_kg, reserved_kg, sold_kg, adjusted_kg
--    FROM inventory_batches
--    WHERE abs(available_kg + reserved_kg + sold_kg + adjusted_kg - quantity_kg) > 0.005;
-- 2. Every batch has history (expect 0):
--    SELECT count(*) FROM inventory_batches b
--    WHERE NOT EXISTS (SELECT 1 FROM stock_movements m WHERE m.batch_id = b.id);
-- 3. Offers by status (no 'confirmed' left):
--    SELECT status, count(*) FROM cooperative_purchase_offers GROUP BY 1;
-- 4. Nothing was counted into cooperative inventory twice (expect 0 rows):
--    SELECT reference_id, count(*) FROM inventory_transactions
--    WHERE transaction_type='harvest_received' AND reference_type='cooperative_offer'
--    GROUP BY 1 HAVING count(*) > 1;
-- 5. The completion rule is in place (expect 2 rows):
--    SELECT tgname FROM pg_trigger WHERE tgname IN ('trg_orders_require_receipt','trg_coop_offers_status_flow');
-- 6. Informal sales are read-only for the Farmer (expect one SELECT policy):
--    SELECT policyname, cmd FROM pg_policies WHERE tablename='informal_sales';
-- ─────────────────────────────────────────────────────────────────────────
