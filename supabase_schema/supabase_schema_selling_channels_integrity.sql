-- ============================================================
-- SAGANA — Selling channels: decimal & inventory integrity
--
-- Found while tracing the four selling channels (Marketplace, Offer to
-- Cooperative, Informal Sale, DA-AMAD Market Linking) end to end with decimal
-- quantities and prices (0.45 kg, 12.50, 125.75 ...).
--
-- WHAT WAS ALREADY RIGHT (no change): every quantity and price column is
-- DECIMAL/NUMERIC(10,2) or wider, the order/offer totals are rounded to the
-- centavo by the database, and every reservation runs on NUMERIC.
--
-- WHAT THIS FILE FIXES
--   1. The batch's sold_kg / status are made to agree with what was really
--      sold. Informal sales and accepted cooperative offers reserved stock but
--      never counted as sold in the files in this repository, and a completed
--      order raised sold_kg without recomputing the batch status. A batch
--      whose stock was all sold informally therefore stayed "Reserved", and
--      Inventory's Sold figure left those sales out. One function,
--      reconcile_batch_sold(), now recomputes sold_kg (completed marketplace
--      orders + informal sales + accepted offers + completed DA-AMAD sales)
--      and the status from the batch's real history. It SETS the value, it
--      never adds to it, so it is correct whichever version of the other
--      functions is live and can never double count. Triggers call it when
--      an order completes, an informal sale is recorded, an offer is accepted
--      or a DA-AMAD sale completes.
--   2. Reserving stock checks that the batch is the caller's own, that the
--      quantity is above zero and has at most 2 decimals (a third decimal used
--      to be rounded silently by the column).
--   3. record_informal_sale validates its inputs (the amount, when given,
--      cannot be negative).
--   4. submit_ginger_for_sale checks the quantity: above zero, at most 2
--      decimals, and not more than the batch has available.
--   5. DA-AMAD Market Linking: a buyer cannot be recorded without an agreed
--      price and a quantity above zero, and a sale cannot be completed without
--      an agreed price (a completed sale at no price reported as PHP 0.00).
--
-- NOT CHANGED: Ginger's exclusivity (enforce_selling_channel and the
-- create_listing_with_reservation guard), prices, statuses, notifications and
-- every existing row. Nothing is deleted. Existing batches are recomputed only
-- when something happens to them; an optional, previewed catch-up for the
-- older ones is at the end of this file.
--
-- Not applied automatically. Run supabase_schema_harvest_batch_number_and_
-- units.sql first (this file uses the unit columns), then the PRE-FLIGHT
-- below, then this file, then supabase_schema_selling_channels_test.sql.
-- Safe to re-run.
-- ============================================================

-- ─── PRE-FLIGHT (read-only — run each by itself) ─────────────────────────
-- A. The unit column exists (expect 1 row):
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'informal_sales' AND column_name = 'unit';
-- B. Batches whose sold_kg disagrees with their real sales BEFORE this file
--    (this is the size of the problem; expect 0 rows if the live functions
--    were already fixed by hand):
--    SELECT b.id, b.batch_number, b.quantity_kg, b.available_kg, b.sold_kg, b.status,
--      COALESCE((SELECT sum(o.quantity_kg) FROM orders o JOIN marketplace_listings l ON l.id = o.listing_id
--                WHERE l.inventory_batch_id = b.id AND o.status = 'completed'), 0)
--    + COALESCE((SELECT sum(i.quantity_kg) FROM informal_sales i WHERE i.inventory_batch_id = b.id), 0)
--    + COALESCE((SELECT sum(c.confirmed_quantity_kg) FROM cooperative_purchase_offers c
--                WHERE c.inventory_batch_id = b.id AND c.status = 'confirmed'), 0)
--    + COALESCE((SELECT sum(m.confirmed_volume_kg) FROM market_linking_programs m
--                WHERE m.inventory_batch_id = b.id AND m.status = 'completed'), 0) AS real_sold_kg
--    FROM inventory_batches b
--    WHERE b.sold_kg IS DISTINCT FROM (
--      COALESCE((SELECT sum(o.quantity_kg) FROM orders o JOIN marketplace_listings l ON l.id = o.listing_id
--                WHERE l.inventory_batch_id = b.id AND o.status = 'completed'), 0)
--    + COALESCE((SELECT sum(i.quantity_kg) FROM informal_sales i WHERE i.inventory_batch_id = b.id), 0)
--    + COALESCE((SELECT sum(c.confirmed_quantity_kg) FROM cooperative_purchase_offers c
--                WHERE c.inventory_batch_id = b.id AND c.status = 'confirmed'), 0)
--    + COALESCE((SELECT sum(m.confirmed_volume_kg) FROM market_linking_programs m
--                WHERE m.inventory_batch_id = b.id AND m.status = 'completed'), 0));
-- C. Completed DA-AMAD sales with no price (these would report PHP 0.00):
--    SELECT id, farmer_id, crop_name, volume_kg, confirmed_volume_kg, price_per_kg
--    FROM market_linking_programs WHERE status = 'completed' AND COALESCE(price_per_kg, 0) <= 0;
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'informal_sales' AND column_name = 'unit') THEN
    RAISE EXCEPTION 'Run supabase_schema_harvest_batch_number_and_units.sql first (informal_sales.unit is missing).';
  END IF;
END;
$$;

-- ═══ 1. Reserving stock: owner, quantity above zero, at most 2 decimals ═════
-- Same behaviour and thresholds as before (see RESERVATION_MODEL_NOTES.md);
-- three checks added. A call without a signed-in user (the SQL editor) skips
-- only the owner check.
CREATE OR REPLACE FUNCTION public._apply_batch_reservation(
  p_batch_id UUID,
  p_quantity DECIMAL
) RETURNS VOID AS $$
DECLARE
  v_farmer_id     UUID;
  v_quantity_kg   DECIMAL;
  v_available_kg  DECIMAL;
  v_sold_kg       DECIMAL;
  v_new_available DECIMAL;
  v_new_status    TEXT;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Enter a quantity greater than zero.';
  END IF;
  IF p_quantity <> round(p_quantity, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the quantity.';
  END IF;

  SELECT farmer_id, quantity_kg, available_kg, sold_kg
    INTO v_farmer_id, v_quantity_kg, v_available_kg, v_sold_kg
    FROM public.inventory_batches
    WHERE id = p_batch_id
    FOR UPDATE; -- lock the row for the duration of this transaction

  IF NOT FOUND THEN
    RAISE EXCEPTION 'This batch was not found in your inventory.';
  END IF;
  IF auth.uid() IS NOT NULL AND v_farmer_id <> auth.uid() THEN
    RAISE EXCEPTION 'This batch was not found in your inventory.';
  END IF;

  IF v_available_kg < p_quantity THEN
    RAISE EXCEPTION 'Not enough available quantity in this batch.';
  END IF;

  v_new_available := v_available_kg - p_quantity;

  IF v_new_available <= 0 THEN
    v_new_status := CASE WHEN v_sold_kg >= v_quantity_kg THEN 'sold_out' ELSE 'reserved' END;
  ELSIF v_new_available < v_quantity_kg * 0.15 THEN
    v_new_status := 'low_stock';
  ELSE
    v_new_status := 'available';
  END IF;

  UPDATE public.inventory_batches
    SET available_kg = v_new_available, status = v_new_status
    WHERE id = p_batch_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ═══ 2. One place that knows how much of a batch is really sold ═════════════
CREATE OR REPLACE FUNCTION public.reconcile_batch_sold(p_batch_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_quantity NUMERIC;
  v_available NUMERIC;
  v_status   TEXT;
  v_sold     NUMERIC;
  v_new      TEXT;
BEGIN
  IF p_batch_id IS NULL THEN
    RETURN;
  END IF;

  SELECT quantity_kg, available_kg, status
    INTO v_quantity, v_available, v_status
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
                 WHERE c.inventory_batch_id = p_batch_id AND c.status = 'confirmed'), 0)
    + COALESCE((SELECT sum(m.confirmed_volume_kg) FROM market_linking_programs m
                 WHERE m.inventory_batch_id = p_batch_id AND m.status = 'completed'), 0);

  -- The same thresholds _apply_batch_reservation uses. A withdrawn batch stays
  -- withdrawn.
  v_new := CASE
    WHEN v_status = 'withdrawn' THEN v_status
    WHEN v_available <= 0 THEN CASE WHEN v_sold >= v_quantity THEN 'sold_out' ELSE 'reserved' END
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

-- Informal sale recorded (or changed / removed)
CREATE OR REPLACE FUNCTION public.reconcile_after_informal_sale()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.reconcile_batch_sold(OLD.inventory_batch_id);
    RETURN OLD;
  END IF;
  PERFORM public.reconcile_batch_sold(NEW.inventory_batch_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_informal_sales_reconcile ON public.informal_sales;
CREATE TRIGGER trg_informal_sales_reconcile
  AFTER INSERT OR UPDATE OF quantity_kg OR DELETE ON public.informal_sales
  FOR EACH ROW EXECUTE FUNCTION public.reconcile_after_informal_sale();

-- Cooperative offer accepted
CREATE OR REPLACE FUNCTION public.reconcile_after_offer_confirmed()
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

DROP TRIGGER IF EXISTS trg_coop_offers_reconcile ON public.cooperative_purchase_offers;
CREATE TRIGGER trg_coop_offers_reconcile
  AFTER UPDATE OF status ON public.cooperative_purchase_offers
  FOR EACH ROW WHEN (NEW.status = 'confirmed' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.reconcile_after_offer_confirmed();

-- Marketplace order completed
CREATE OR REPLACE FUNCTION public.reconcile_after_order_completed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch UUID;
BEGIN
  SELECT inventory_batch_id INTO v_batch FROM marketplace_listings WHERE id = NEW.listing_id;
  PERFORM public.reconcile_batch_sold(v_batch);
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_reconcile ON public.orders;
CREATE TRIGGER trg_orders_reconcile
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.reconcile_after_order_completed();

-- DA-AMAD sale completed
CREATE OR REPLACE FUNCTION public.reconcile_after_market_linking_completed()
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

DROP TRIGGER IF EXISTS trg_market_linking_reconcile ON public.market_linking_programs;
CREATE TRIGGER trg_market_linking_reconcile
  AFTER UPDATE OF status ON public.market_linking_programs
  FOR EACH ROW WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.reconcile_after_market_linking_completed();

-- ═══ 3. Informal sale: validated inputs ═════════════════════════════════════
-- Same signature, same effect (reserve the stock, write the sale). The unit,
-- market type and Ginger-exclusivity triggers on informal_sales still run, and
-- sold_kg / status are now set by the reconcile trigger above.
CREATE OR REPLACE FUNCTION public.record_informal_sale(
  p_batch_id UUID,
  p_crop_name TEXT,
  p_quantity_kg DECIMAL,
  p_buyer_name TEXT,
  p_amount DECIMAL,
  p_notes TEXT
) RETURNS UUID AS $$
DECLARE
  v_sale_id UUID;
BEGIN
  IF p_amount IS NOT NULL AND p_amount < 0 THEN
    RAISE EXCEPTION 'The amount received cannot be negative.';
  END IF;
  IF p_amount IS NOT NULL AND p_amount <> round(p_amount, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the amount.';
  END IF;

  -- Checks the owner, the quantity (above zero, 2 decimals) and the stock.
  PERFORM public._apply_batch_reservation(p_batch_id, p_quantity_kg);

  INSERT INTO public.informal_sales (
    farmer_id, inventory_batch_id, crop_name, quantity_kg,
    buyer_name, amount, notes
  ) VALUES (
    auth.uid(), p_batch_id, p_crop_name, p_quantity_kg,
    p_buyer_name, p_amount, p_notes
  ) RETURNING id INTO v_sale_id;

  RETURN v_sale_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ═══ 4. Submitting Ginger to Market Linking: validated quantity ═════════════
-- Same behaviour as supabase_schema_market_rules_by_data.sql, plus the
-- quantity checks (it used to accept 0, a negative number or more than the
-- batch holds, and only failed later, at completion).
CREATE OR REPLACE FUNCTION public.submit_ginger_for_sale(p_inventory_batch_id uuid, p_volume_kg numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer_id UUID := auth.uid();
  v_enrollment_id UUID;
  v_new_id UUID;
  v_crop_name TEXT;
  v_excl TEXT;
  v_available NUMERIC;
BEGIN
  IF p_volume_kg IS NULL OR p_volume_kg <= 0 THEN
    RAISE EXCEPTION 'Enter a quantity greater than zero.';
  END IF;
  IF p_volume_kg <> round(p_volume_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the quantity.';
  END IF;

  SELECT id INTO v_enrollment_id
  FROM da_amad_enrollments
  WHERE farmer_id = v_farmer_id AND status = 'approved'
  ORDER BY reviewed_at DESC NULLS LAST
  LIMIT 1;

  IF v_enrollment_id IS NULL THEN
    RAISE EXCEPTION 'An approved Market Linking enrollment is required to submit a Ginger harvest';
  END IF;

  SELECT available_kg INTO v_available
  FROM inventory_batches
  WHERE id = p_inventory_batch_id AND farmer_id = v_farmer_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'That batch does not belong to you';
  END IF;
  IF p_volume_kg > v_available THEN
    RAISE EXCEPTION 'That is more than this batch has available (% left).', v_available;
  END IF;

  SELECT cm.crop_name, cm.exclusive_channel
    INTO v_crop_name, v_excl
  FROM inventory_batches ib
  JOIN farmer_crops fc ON fc.id = ib.crop_id
  JOIN crop_master cm ON cm.id = fc.crop_master_id
  WHERE ib.id = p_inventory_batch_id;

  IF v_excl IS DISTINCT FROM 'da_amad_market_linking' THEN
    RAISE EXCEPTION 'Only a Ginger harvest can be submitted through Market Linking';
  END IF;

  INSERT INTO market_linking_programs (
    farmer_id, crop_name, season_year, status, created_by,
    inventory_batch_id, volume_kg, submitted_at, enrollment_id
  )
  VALUES (
    v_farmer_id, v_crop_name, EXTRACT(YEAR FROM NOW())::INT, 'submitted', v_farmer_id,
    p_inventory_batch_id, p_volume_kg, NOW(), v_enrollment_id
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$function$;

-- ═══ 5. DA-AMAD: no buyer without a price and a quantity; no sale at no price ═
CREATE OR REPLACE FUNCTION public.guard_market_linking_sale()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'buyer_found' THEN
    IF NEW.price_per_kg IS NULL OR NEW.price_per_kg <= 0 THEN
      RAISE EXCEPTION 'Enter the agreed price per kg (greater than 0) before recording a buyer.';
    END IF;
    IF NEW.requested_volume_kg IS NULL OR NEW.requested_volume_kg <= 0 THEN
      RAISE EXCEPTION 'Enter the quantity the buyer wants (greater than 0) before recording a buyer.';
    END IF;
  ELSIF NEW.status = 'completed' THEN
    IF NEW.price_per_kg IS NULL OR NEW.price_per_kg <= 0 THEN
      RAISE EXCEPTION 'The agreed price per kg must be set (greater than 0) before a sale is completed.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_market_linking_guard_sale ON public.market_linking_programs;
CREATE TRIGGER trg_market_linking_guard_sale
  BEFORE UPDATE OF status ON public.market_linking_programs
  FOR EACH ROW EXECUTE FUNCTION public.guard_market_linking_sale();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. Objects exist (expect 5 triggers, 2 functions):
--    SELECT tgname FROM pg_trigger WHERE NOT tgisinternal AND tgname IN
--      ('trg_informal_sales_reconcile','trg_coop_offers_reconcile','trg_orders_reconcile',
--       'trg_market_linking_reconcile','trg_market_linking_guard_sale');
--    SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--      AND proname IN ('reconcile_batch_sold','guard_market_linking_sale');
-- 2. Then run supabase_schema_selling_channels_test.sql (expect FAILED CHECKS: 0).
--
-- ─── OPTIONAL CATCH-UP for batches sold BEFORE this file ─────────────────
-- Pre-flight query B shows which batches disagree. Review that list; if the
-- "real_sold_kg" column is what you expect, this recomputes them (each call
-- only changes sold_kg and status of that batch, nothing else):
--    SELECT public.reconcile_batch_sold(b.id) FROM inventory_batches b;
-- (As the SQL editor's role; the function is not callable by the app.)
-- Afterwards, pre-flight query B should return 0 rows.
-- ───────────────────────────────────────────────────────────────────────────
