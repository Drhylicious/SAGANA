-- ============================================================
-- SAGANA — Ginger / DA-AMAD Market Linking: reserved stock, recorded sales,
--          partial sales
--
-- HOW MARKET LINKING WORKS AFTER THIS FILE
--   * The Farmer submits a quantity of an exclusive-channel crop (Ginger). That
--     quantity is RESERVED on the batch at once (available_kg goes down), so it
--     cannot be sold twice through another channel.
--   * Manager/Officer finds an external buyer. When a real sale happens they
--     record it with record_market_linking_sale(): buyer, agreed price per
--     unit, quantity purchased, notes. The total (quantity x price, to the
--     centavo) is computed by the database. Each call is ONE sale.
--   * A sale uses up that much of the reservation and counts as sold on the
--     batch. If the request still has quantity left, it stays open for more
--     sales (80 submitted, 50 sold -> 50 sold, 30 still in the request). When
--     nothing is left it completes by itself.
--   * close_market_linking_request() ends a request early: the unsold part of
--     the reservation goes back to the Farmer's stock. A request with sales
--     becomes Completed (partly sold); one with none becomes Cancelled.
--     Cancelling a request releases its reservation too.
--   * The Farmer owns the crop and receives the payment. The sale is recorded
--     in market_linking_sales, never as Cooperative inventory or revenue.
--   * Sales History, Reports and the batch's Sold figure all read the one
--     ledger (market_linking_sales), so they cannot disagree.
--   * A Farmer needs the actual crop photo on the crop to submit (see
--     supabase_schema_crop_photos_selling_rules.sql — run that one first).
--
-- COMPATIBILITY
--   * Requests already in flight are NOT retroactively reserved (their
--     reserved_kg starts at 0): their first recorded sale takes the quantity
--     from the batch's available stock, exactly as completion used to.
--   * Every sale already completed is copied into the ledger (only those with
--     a quantity and a price above zero), so history and reports are unchanged.
--   * complete_market_linking() keeps its signature and meaning (record the
--     confirmed volume as one sale, then close the rest) so nothing calling it
--     breaks.
--
-- Nothing is deleted. Safe to re-run.
-- Not applied automatically: run in the Supabase SQL editor, in this order:
--   1. supabase_schema_crop_photos_selling_rules.sql
--   2. this file
--   3. supabase_schema_market_linking_partial_sales_test.sql
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.reconcile_batch_sold(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_selling_channels_integrity.sql first (reconcile_batch_sold is missing).';
  END IF;
  IF to_regprocedure('public.farmer_crop_photo_for_batch(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_crop_photos_selling_rules.sql first.';
  END IF;
END;
$$;

-- ═══ 1. Columns on the request ═════════════════════════════════════════════
ALTER TABLE public.market_linking_programs
  ADD COLUMN IF NOT EXISTS reserved_kg NUMERIC(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS sold_kg     NUMERIC(10,2) NOT NULL DEFAULT 0;

ALTER TABLE public.market_linking_programs
  DROP CONSTRAINT IF EXISTS market_linking_programs_reserved_sold_check;
ALTER TABLE public.market_linking_programs
  ADD CONSTRAINT market_linking_programs_reserved_sold_check
  CHECK (reserved_kg >= 0 AND sold_kg >= 0);

-- ═══ 2. The sales ledger ═══════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.market_linking_sales (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_id          UUID NOT NULL
                        REFERENCES public.market_linking_programs(id) ON DELETE RESTRICT,
  farmer_id           UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  inventory_batch_id  UUID REFERENCES public.inventory_batches(id) ON DELETE SET NULL,
  crop_name           TEXT NOT NULL,
  buyer_name          TEXT NOT NULL,
  buyer_contact       TEXT,
  -- Named like the request's own column so every report reads it the same way.
  confirmed_volume_kg NUMERIC(10,2) NOT NULL CHECK (confirmed_volume_kg > 0),
  price_per_kg        NUMERIC(10,2) NOT NULL CHECK (price_per_kg > 0),
  total_amount        NUMERIC(12,2) NOT NULL CHECK (total_amount >= 0),
  notes               TEXT,
  recorded_by         UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  completed_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS market_linking_sales_program_idx ON public.market_linking_sales (program_id);
CREATE INDEX IF NOT EXISTS market_linking_sales_farmer_idx  ON public.market_linking_sales (farmer_id, completed_at DESC);
CREATE INDEX IF NOT EXISTS market_linking_sales_batch_idx   ON public.market_linking_sales (inventory_batch_id);
CREATE INDEX IF NOT EXISTS market_linking_sales_date_idx    ON public.market_linking_sales (completed_at DESC);

ALTER TABLE public.market_linking_sales ENABLE ROW LEVEL SECURITY;

-- Read only. Sales are written by record_market_linking_sale() (below) and by
-- nothing else, so every sale passes the same checks.
DROP POLICY IF EXISTS "market_linking_sales: staff read" ON public.market_linking_sales;
CREATE POLICY "market_linking_sales: staff read"
  ON public.market_linking_sales FOR SELECT TO authenticated
  USING (public.is_staff());

DROP POLICY IF EXISTS "market_linking_sales: farmer reads own" ON public.market_linking_sales;
CREATE POLICY "market_linking_sales: farmer reads own"
  ON public.market_linking_sales FOR SELECT TO authenticated
  USING (farmer_id = auth.uid());

-- ═══ 3. Copy the sales that are already completed into the ledger ═══════════
INSERT INTO public.market_linking_sales (
  program_id, farmer_id, inventory_batch_id, crop_name, buyer_name, buyer_contact,
  confirmed_volume_kg, price_per_kg, total_amount, notes, completed_at
)
SELECT p.id, p.farmer_id, p.inventory_batch_id, p.crop_name,
       COALESCE(NULLIF(btrim(p.buyer_name), ''), 'Buyer'), p.buyer_contact,
       q.qty, p.price_per_kg, round(q.qty * p.price_per_kg, 2), p.notes,
       COALESCE(p.completed_at, p.updated_at, NOW())
FROM public.market_linking_programs p
CROSS JOIN LATERAL (
  SELECT COALESCE(p.confirmed_volume_kg, p.requested_volume_kg, p.volume_kg) AS qty
) q
WHERE p.status = 'completed'
  AND q.qty > 0 AND p.price_per_kg > 0
  AND NOT EXISTS (SELECT 1 FROM public.market_linking_sales s WHERE s.program_id = p.id);

UPDATE public.market_linking_programs p
   SET sold_kg = s.total
  FROM (SELECT program_id, sum(confirmed_volume_kg) AS total
          FROM public.market_linking_sales GROUP BY program_id) s
 WHERE s.program_id = p.id AND p.sold_kg = 0;

-- ═══ 4. The batch's Sold figure reads the ledger ════════════════════════════
-- Same function as supabase_schema_selling_channels_integrity.sql, with the
-- DA-AMAD part changed: the ledger's sales, plus any completed request that has
-- no ledger row (a completed sale with no price cannot be in the ledger).
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
    + COALESCE((SELECT sum(s.confirmed_volume_kg) FROM market_linking_sales s
                 WHERE s.inventory_batch_id = p_batch_id), 0)
    + COALESCE((SELECT sum(m.confirmed_volume_kg) FROM market_linking_programs m
                 WHERE m.inventory_batch_id = p_batch_id AND m.status = 'completed'
                   AND NOT EXISTS (SELECT 1 FROM market_linking_sales s2 WHERE s2.program_id = m.id)), 0);

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

CREATE OR REPLACE FUNCTION public.reconcile_after_market_linking_sale()
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

DROP TRIGGER IF EXISTS trg_market_linking_sales_reconcile ON public.market_linking_sales;
CREATE TRIGGER trg_market_linking_sales_reconcile
  AFTER INSERT OR UPDATE OF confirmed_volume_kg OR DELETE ON public.market_linking_sales
  FOR EACH ROW EXECUTE FUNCTION public.reconcile_after_market_linking_sale();

-- ═══ 5. Releasing a request's reservation ═══════════════════════════════════
-- Puts the request's still-reserved quantity back on the batch (never above
-- what the batch physically holds) and zeroes it on the request. Safe to call
-- twice: the second call finds nothing reserved.
CREATE OR REPLACE FUNCTION public._ml_release_reserved(p_program_id UUID)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prog market_linking_programs%ROWTYPE;
BEGIN
  SELECT * INTO v_prog FROM market_linking_programs WHERE id = p_program_id FOR UPDATE;
  IF NOT FOUND OR v_prog.reserved_kg <= 0 THEN
    RETURN 0;
  END IF;

  IF v_prog.inventory_batch_id IS NOT NULL THEN
    UPDATE inventory_batches
       SET available_kg = LEAST(quantity_kg - sold_kg, available_kg + v_prog.reserved_kg)
     WHERE id = v_prog.inventory_batch_id;
  END IF;

  UPDATE market_linking_programs SET reserved_kg = 0 WHERE id = p_program_id;
  PERFORM public.reconcile_batch_sold(v_prog.inventory_batch_id); -- recomputes the status
  RETURN v_prog.reserved_kg;
END;
$$;
REVOKE ALL ON FUNCTION public._ml_release_reserved(UUID) FROM PUBLIC, anon, authenticated;

-- Cancelling a request by any route releases its reservation.
CREATE OR REPLACE FUNCTION public.release_reservation_on_ml_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public._ml_release_reserved(NEW.id);
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_market_linking_release_on_cancel ON public.market_linking_programs;
CREATE TRIGGER trg_market_linking_release_on_cancel
  AFTER UPDATE OF status ON public.market_linking_programs
  FOR EACH ROW WHEN (NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.release_reservation_on_ml_cancel();

-- ═══ 6. The Farmer submits: the quantity is reserved ════════════════════════
-- Same function as supabase_schema_selling_channels_integrity.sql, plus the
-- reservation (and reserved_kg on the request). The actual-photo requirement is
-- enforced by the BEFORE INSERT trigger on the request.
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

  -- Checks owner, stock and decimals again under a row lock, then holds the
  -- quantity so no other channel can sell it.
  PERFORM public._apply_batch_reservation(p_inventory_batch_id, p_volume_kg);

  INSERT INTO market_linking_programs (
    farmer_id, crop_name, season_year, status, created_by,
    inventory_batch_id, volume_kg, reserved_kg, submitted_at, enrollment_id
  )
  VALUES (
    v_farmer_id, v_crop_name, EXTRACT(YEAR FROM NOW())::INT, 'submitted', v_farmer_id,
    p_inventory_batch_id, p_volume_kg, p_volume_kg, NOW(), v_enrollment_id
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$function$;

-- ═══ 7. Complete Sale: record one sale against a request ═══════════════════
CREATE OR REPLACE FUNCTION public.record_market_linking_sale(
  p_program_id    UUID,
  p_buyer_name    TEXT,
  p_buyer_contact TEXT,
  p_quantity_kg   NUMERIC,
  p_price_per_kg  NUMERIC,
  p_notes         TEXT DEFAULT NULL
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prog       market_linking_programs%ROWTYPE;
  v_batch      inventory_batches%ROWTYPE;
  v_remaining  NUMERIC;
  v_from_res   NUMERIC;
  v_extra      NUMERIC;
  v_new_sold   NUMERIC;
  v_done       BOOLEAN;
  v_sale_id    UUID;
  v_total      NUMERIC;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can record a Market Linking sale';
  END IF;

  IF p_buyer_name IS NULL OR btrim(p_buyer_name) = '' THEN
    RAISE EXCEPTION 'Enter the buyer''s name.';
  END IF;
  IF p_quantity_kg IS NULL OR p_quantity_kg <= 0 THEN
    RAISE EXCEPTION 'Enter the quantity purchased (greater than zero).';
  END IF;
  IF p_quantity_kg <> round(p_quantity_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the quantity.';
  END IF;
  IF p_price_per_kg IS NULL OR p_price_per_kg <= 0 THEN
    RAISE EXCEPTION 'Enter the agreed selling price (greater than zero).';
  END IF;
  IF p_price_per_kg <> round(p_price_per_kg, 2) THEN
    RAISE EXCEPTION 'Use at most 2 decimal places for the price.';
  END IF;

  SELECT * INTO v_prog FROM market_linking_programs WHERE id = p_program_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Market linking request not found';
  END IF;
  IF v_prog.status NOT IN ('submitted', 'buyer_found') THEN
    RAISE EXCEPTION 'This request is already closed (%), so no more sales can be recorded.', v_prog.status;
  END IF;
  IF v_prog.inventory_batch_id IS NULL THEN
    RAISE EXCEPTION 'This request is not linked to a harvest batch.';
  END IF;
  IF v_prog.volume_kg IS NULL THEN
    RAISE EXCEPTION 'This request has no submitted quantity.';
  END IF;

  v_remaining := v_prog.volume_kg - v_prog.sold_kg;
  IF p_quantity_kg > v_remaining THEN
    RAISE EXCEPTION 'That is more than this request has left (% remaining).', v_remaining;
  END IF;

  SELECT * INTO v_batch FROM inventory_batches WHERE id = v_prog.inventory_batch_id FOR UPDATE;
  IF NOT FOUND OR v_batch.farmer_id <> v_prog.farmer_id THEN
    RAISE EXCEPTION 'The batch does not belong to the farmer on this request.';
  END IF;

  -- The sale first uses what was reserved for this request. A request made
  -- before reservations existed has nothing reserved, so its sale is taken from
  -- the batch's available stock instead (never negative, never twice).
  v_from_res := LEAST(p_quantity_kg, v_prog.reserved_kg);
  v_extra    := p_quantity_kg - v_from_res;
  IF v_extra > 0 THEN
    IF v_extra > v_batch.available_kg THEN
      RAISE EXCEPTION 'Not enough stock left on the farmer''s batch (% available).', v_batch.available_kg;
    END IF;
    UPDATE inventory_batches SET available_kg = available_kg - v_extra WHERE id = v_batch.id;
  END IF;

  v_total := round(p_quantity_kg * p_price_per_kg, 2);
  INSERT INTO market_linking_sales (
    program_id, farmer_id, inventory_batch_id, crop_name, buyer_name, buyer_contact,
    confirmed_volume_kg, price_per_kg, total_amount, notes, recorded_by
  ) VALUES (
    v_prog.id, v_prog.farmer_id, v_prog.inventory_batch_id, v_prog.crop_name,
    btrim(p_buyer_name), NULLIF(btrim(COALESCE(p_buyer_contact, '')), ''),
    p_quantity_kg, p_price_per_kg, v_total, NULLIF(btrim(COALESCE(p_notes, '')), ''), auth.uid()
  ) RETURNING id INTO v_sale_id;

  v_new_sold := v_prog.sold_kg + p_quantity_kg;
  v_done     := v_new_sold >= v_prog.volume_kg;

  UPDATE market_linking_programs
     SET sold_kg             = v_new_sold,
         confirmed_volume_kg = v_new_sold,
         reserved_kg         = v_prog.reserved_kg - v_from_res,
         buyer_name          = btrim(p_buyer_name),
         buyer_contact       = COALESCE(NULLIF(btrim(COALESCE(p_buyer_contact, '')), ''), buyer_contact),
         price_per_kg        = p_price_per_kg,
         requested_volume_kg = COALESCE(requested_volume_kg, p_quantity_kg),
         notes               = COALESCE(NULLIF(btrim(COALESCE(p_notes, '')), ''), notes),
         buyer_found_at      = COALESCE(buyer_found_at, NOW()),
         status              = CASE WHEN v_done THEN 'completed' ELSE 'buyer_found' END,
         completed_at        = CASE WHEN v_done THEN NOW() ELSE completed_at END
   WHERE id = v_prog.id;

  -- A finished request holds nothing back (this only matters if the reservation
  -- and the sales ever disagreed).
  IF v_done THEN
    PERFORM public._ml_release_reserved(v_prog.id);
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_prog.farmer_id, 'system',
    CASE WHEN v_done THEN 'Ginger Sale Completed' ELSE 'Ginger Sale Recorded' END,

    p_quantity_kg || ' kg of ' || v_prog.crop_name || ' was sold to ' || btrim(p_buyer_name) ||
      ' at ' || p_price_per_kg || ' per kg (total ' || v_total || ').' ||
      CASE WHEN v_done THEN ''
           ELSE ' ' || (v_prog.volume_kg - v_new_sold) || ' kg is still in your request.' END,
    FALSE, NOW(), '/farmer/profile/market-linking'
  );

  RETURN v_sale_id;
END;
$$;
REVOKE ALL ON FUNCTION public.record_market_linking_sale(UUID, TEXT, TEXT, NUMERIC, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_market_linking_sale(UUID, TEXT, TEXT, NUMERIC, NUMERIC, TEXT) TO authenticated;

-- ═══ 8. Close a request early ═══════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.close_market_linking_request(
  p_program_id UUID,
  p_reason     TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prog     market_linking_programs%ROWTYPE;
  v_released NUMERIC;
  v_reason   TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can close a Market Linking request';
  END IF;

  SELECT * INTO v_prog FROM market_linking_programs WHERE id = p_program_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Market linking request not found';
  END IF;
  IF v_prog.status NOT IN ('submitted', 'buyer_found', 'requested') THEN
    RETURN; -- already closed: nothing to release twice
  END IF;

  v_released := public._ml_release_reserved(v_prog.id);

  IF v_prog.sold_kg > 0 THEN
    UPDATE market_linking_programs
       SET status = 'completed', completed_at = NOW(), notes = COALESCE(v_reason, notes)
     WHERE id = v_prog.id;
  ELSE
    UPDATE market_linking_programs
       SET status = 'cancelled', notes = COALESCE(v_reason, notes)
     WHERE id = v_prog.id;
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_prog.farmer_id, 'system',
    CASE WHEN v_prog.sold_kg > 0 THEN 'Market Linking Request Closed' ELSE 'Market Linking Request Cancelled' END,
    CASE WHEN v_prog.sold_kg > 0
         THEN v_prog.sold_kg || ' kg of ' || v_prog.crop_name || ' was sold.'
         ELSE 'Your ' || v_prog.crop_name || ' request was cancelled.' END ||
    CASE WHEN v_released > 0 THEN ' ' || v_released || ' kg is back in your stock.' ELSE '' END ||
    COALESCE(' Reason: ' || v_reason, ''),
    FALSE, NOW(), '/farmer/profile/market-linking'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.close_market_linking_request(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.close_market_linking_request(UUID, TEXT) TO authenticated;

-- ═══ 9. complete_market_linking(): same signature, new meaning underneath ═══
-- "Complete with this confirmed volume": record it as one sale, then close what
-- is left of the request (releasing the unsold reservation). With no volume it
-- is the old plain completion (needs the agreed price).
CREATE OR REPLACE FUNCTION public.complete_market_linking(
  p_id UUID,
  p_batch_id UUID DEFAULT NULL,
  p_confirmed_volume_kg NUMERIC DEFAULT NULL,
  p_buyer_name TEXT DEFAULT NULL,
  p_buyer_contact TEXT DEFAULT NULL,
  p_price_per_kg NUMERIC DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
) RETURNS VOID AS $$
DECLARE
  v_prog   market_linking_programs%ROWTYPE;
  v_batch_farmer UUID;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can complete market linking records';
  END IF;

  SELECT * INTO v_prog FROM market_linking_programs WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Market linking record not found';
  END IF;
  IF v_prog.status = 'completed' THEN
    RETURN; -- already completed: a retry never deducts twice
  END IF;

  IF p_batch_id IS NOT NULL AND p_batch_id IS DISTINCT FROM v_prog.inventory_batch_id THEN
    SELECT farmer_id INTO v_batch_farmer FROM inventory_batches WHERE id = p_batch_id;
    IF v_batch_farmer IS NULL THEN
      RAISE EXCEPTION 'Batch not found';
    END IF;
    IF v_batch_farmer <> v_prog.farmer_id THEN
      RAISE EXCEPTION 'Batch does not belong to the farmer on this market linking record';
    END IF;
    UPDATE market_linking_programs SET inventory_batch_id = p_batch_id WHERE id = p_id;
  END IF;

  IF p_confirmed_volume_kg IS NOT NULL AND p_confirmed_volume_kg > 0 THEN
    PERFORM public.record_market_linking_sale(
      p_id,
      COALESCE(NULLIF(btrim(COALESCE(p_buyer_name, '')), ''), v_prog.buyer_name, 'Buyer'),
      COALESCE(p_buyer_contact, v_prog.buyer_contact),
      p_confirmed_volume_kg,
      COALESCE(p_price_per_kg, v_prog.price_per_kg),
      p_notes
    );
    PERFORM public.close_market_linking_request(p_id, NULL); -- no-op if it completed itself
  ELSE
    PERFORM public._ml_release_reserved(p_id);
    UPDATE market_linking_programs
       SET status = 'completed',
           completed_at = NOW(),
           buyer_name = COALESCE(p_buyer_name, buyer_name),
           buyer_contact = COALESCE(p_buyer_contact, buyer_contact),
           price_per_kg = COALESCE(p_price_per_kg, price_per_kg),
           notes = COALESCE(p_notes, notes)
     WHERE id = p_id;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.complete_market_linking(UUID, UUID, NUMERIC, TEXT, TEXT, NUMERIC, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── PRE-FLIGHT (read-only; run before this file if you like) ────────────
-- Completed requests that cannot be copied into the ledger (no price or no
-- quantity) — they stay counted on their batch, but cannot appear in reports:
--    SELECT id, farmer_id, crop_name, volume_kg, confirmed_volume_kg, price_per_kg
--    FROM market_linking_programs
--    WHERE status = 'completed'
--      AND (COALESCE(price_per_kg, 0) <= 0
--           OR COALESCE(confirmed_volume_kg, requested_volume_kg, volume_kg, 0) <= 0);
--
-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. Objects exist (expect 4 functions + the table):
--    SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--      AND proname IN ('record_market_linking_sale','close_market_linking_request',
--                      '_ml_release_reserved','submit_ginger_for_sale');
--    SELECT count(*) FROM market_linking_sales;
-- 2. Every completed request with a price is in the ledger (expect 0 rows):
--    SELECT p.id FROM market_linking_programs p
--    WHERE p.status = 'completed' AND COALESCE(p.price_per_kg, 0) > 0
--      AND COALESCE(p.confirmed_volume_kg, p.requested_volume_kg, p.volume_kg, 0) > 0
--      AND NOT EXISTS (SELECT 1 FROM market_linking_sales s WHERE s.program_id = p.id);
-- 3. Then run supabase_schema_market_linking_partial_sales_test.sql (expect FAILED CHECKS: 0).
-- ───────────────────────────────────────────────────────────────────────────
