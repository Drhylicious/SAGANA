-- ============================================================
-- SAGANA — Market Linking: separate Buyer Details from Complete Sale, and
--          cancellation that starts with the Farmer
--
-- Layered on supabase_schema_market_linking_partial_sales.sql (run that first).
--
-- STAGES (Manager/Officer)
--   1. Market Linking Request  — the Farmer submits a quantity (reserved).
--   2. Buyer Details           — save_market_linking_buyer_details(): the buyer's
--      name, contact number, optional e-mail and address, and NOTHING else. It
--      only records who the buyer is (status Buyer Found). It never sells,
--      never deducts stock, never completes anything.
--   3. Complete Sale           — record_market_linking_sale(): quantity purchased,
--      agreed price per kg, notes. The buyer comes from the saved Buyer Details
--      (a sale cannot be recorded until they exist). Only this step moves stock
--      to Sold. A part-purchase leaves the unsold quantity reserved for the
--      Farmer, untouched.
--   4. Completed               — the whole submitted quantity is sold.
--
-- CANCELLATION
--   * Only the Farmer starts it: request_market_linking_cancellation() — a reason
--     is required; the request then shows "Cancellation Requested".
--   * The Manager/Officer reviews it: respond_to_market_linking_cancellation()
--     approves it, or declines it WITH a reason. The Farmer is notified either way.
--   * Stock is released only when the cancellation is approved, and only the
--     unsold reserved quantity. Sales already recorded stay (a request with sales
--     becomes Completed; one with none becomes Cancelled).
--   * A fully sold request cannot be cancelled.
--   * Nobody else can cancel: the database refuses any other change to
--     'cancelled', and close_market_linking_request() is no longer callable by
--     the app.
--
-- Nothing is deleted. Existing completed sales and open requests are unchanged.
-- Not applied automatically: run in the Supabase SQL editor, then
-- supabase_schema_market_linking_partial_sales_test.sql (updated for this file).
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.record_market_linking_sale(uuid,text,text,numeric,numeric,text)') IS NULL
     AND to_regprocedure('public.record_market_linking_sale(uuid,numeric,numeric,text)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_market_linking_partial_sales.sql first.';
  END IF;
END;
$$;

-- ═══ 1. Columns ═════════════════════════════════════════════════════════════
ALTER TABLE public.market_linking_programs
  ADD COLUMN IF NOT EXISTS buyer_email               TEXT,
  ADD COLUMN IF NOT EXISTS buyer_address             TEXT,
  ADD COLUMN IF NOT EXISTS cancellation_status       TEXT,
  ADD COLUMN IF NOT EXISTS cancellation_reason       TEXT,
  ADD COLUMN IF NOT EXISTS cancellation_requested_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancellation_reviewed_by  UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS cancellation_reviewed_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancellation_review_notes TEXT;

ALTER TABLE public.market_linking_programs
  DROP CONSTRAINT IF EXISTS market_linking_programs_cancellation_status_check;
ALTER TABLE public.market_linking_programs
  ADD CONSTRAINT market_linking_programs_cancellation_status_check
  CHECK (cancellation_status IS NULL
         OR cancellation_status IN ('requested', 'approved', 'rejected', 'withdrawn'));

-- ═══ 2. Buyer Found needs only a buyer ══════════════════════════════════════
-- Before, recording a buyer also demanded a price and a quantity. Those belong to
-- Complete Sale now. A completed request still needs its agreed price.
CREATE OR REPLACE FUNCTION public.guard_market_linking_sale()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'buyer_found' THEN
    IF NEW.buyer_name IS NULL OR btrim(NEW.buyer_name) = '' THEN
      RAISE EXCEPTION 'Enter the buyer''s name before recording a buyer.';
    END IF;
  ELSIF NEW.status = 'completed' THEN
    IF NEW.price_per_kg IS NULL OR NEW.price_per_kg <= 0 THEN
      RAISE EXCEPTION 'The agreed price per kg must be set (greater than 0) before a sale is completed.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

-- ═══ 3. Only an approved cancellation can cancel ════════════════════════════
-- close_market_linking_request() (below) sets a flag for the length of its own
-- transaction; any other change of a request to 'cancelled' from a signed-in
-- account is refused. (The SQL editor, with no signed-in user, is not blocked.)
CREATE OR REPLACE FUNCTION public.guard_market_linking_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled'
     AND auth.uid() IS NOT NULL
     AND COALESCE(current_setting('sagana.ml_cancel_ok', true), '') <> '1' THEN
    RAISE EXCEPTION 'A Market Linking request can only be cancelled after the farmer asks and the cooperative approves.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_market_linking_guard_cancel ON public.market_linking_programs;
CREATE TRIGGER trg_market_linking_guard_cancel
  BEFORE UPDATE OF status ON public.market_linking_programs
  FOR EACH ROW EXECUTE FUNCTION public.guard_market_linking_cancel();

-- ═══ 4. Closing a request: internal only ═══════════════════════════════════
-- Releases the unsold reserved quantity. Not callable by the app any more: it is
-- used by an approved cancellation. Returns the quantity released.
DROP FUNCTION IF EXISTS public.close_market_linking_request(UUID, TEXT);

CREATE OR REPLACE FUNCTION public.close_market_linking_request(
  p_program_id UUID,
  p_reason     TEXT DEFAULT NULL,
  p_notify     BOOLEAN DEFAULT TRUE
) RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prog     market_linking_programs%ROWTYPE;
  v_released NUMERIC := 0;
  v_reason   TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  SELECT * INTO v_prog FROM market_linking_programs WHERE id = p_program_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Market linking request not found';
  END IF;
  IF v_prog.status NOT IN ('submitted', 'buyer_found', 'requested') THEN
    RETURN 0; -- already closed: nothing to release twice
  END IF;

  v_released := public._ml_release_reserved(v_prog.id);

  PERFORM set_config('sagana.ml_cancel_ok', '1', true);
  IF v_prog.sold_kg > 0 THEN
    UPDATE market_linking_programs
       SET status = 'completed', completed_at = NOW(), notes = COALESCE(v_reason, notes)
     WHERE id = v_prog.id;
  ELSE
    UPDATE market_linking_programs
       SET status = 'cancelled', notes = COALESCE(v_reason, notes)
     WHERE id = v_prog.id;
  END IF;
  PERFORM set_config('sagana.ml_cancel_ok', '0', true);

  IF p_notify THEN
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      v_prog.farmer_id, 'system',
      CASE WHEN v_prog.sold_kg > 0 THEN 'Market Linking Request Completed' ELSE 'Market Linking Request Cancelled' END,
      CASE WHEN v_prog.sold_kg > 0
           THEN v_prog.sold_kg || ' kg of ' || v_prog.crop_name || ' was sold.'
           ELSE 'Your ' || v_prog.crop_name || ' request was cancelled.' END ||
      CASE WHEN v_released > 0 THEN ' ' || v_released || ' kg is back in your stock.' ELSE '' END,
      FALSE, NOW(), '/farmer/profile/market-linking'
    );
  END IF;
  RETURN v_released;
END;
$$;
REVOKE ALL ON FUNCTION public.close_market_linking_request(UUID, TEXT, BOOLEAN) FROM PUBLIC, anon, authenticated;

-- ═══ 5. Stage 2 — Buyer Details (buyer information only) ════════════════════
CREATE OR REPLACE FUNCTION public.save_market_linking_buyer_details(
  p_program_id    UUID,
  p_buyer_name    TEXT,
  p_buyer_contact TEXT,
  p_buyer_email   TEXT DEFAULT NULL,
  p_buyer_address TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prog market_linking_programs%ROWTYPE;
  v_name TEXT    := NULLIF(btrim(COALESCE(p_buyer_name, '')), '');
  v_tel  TEXT    := NULLIF(btrim(COALESCE(p_buyer_contact, '')), '');
  v_mail TEXT    := NULLIF(btrim(COALESCE(p_buyer_email, '')), '');
  v_addr TEXT    := NULLIF(btrim(COALESCE(p_buyer_address, '')), '');
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can save buyer details';
  END IF;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'Enter the buyer''s full name.';
  END IF;
  IF v_tel IS NULL THEN
    RAISE EXCEPTION 'Enter the buyer''s contact number.';
  END IF;
  IF v_mail IS NOT NULL AND v_mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN
    RAISE EXCEPTION 'Enter a valid e-mail address, or leave it blank.';
  END IF;

  SELECT * INTO v_prog FROM market_linking_programs WHERE id = p_program_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Market linking request not found';
  END IF;
  IF v_prog.status NOT IN ('submitted', 'buyer_found') THEN
    RAISE EXCEPTION 'This request is already closed (%), so the buyer details cannot be changed.', v_prog.status;
  END IF;

  -- Buyer information only: no quantity, price or stock is touched here.
  UPDATE market_linking_programs
     SET buyer_name     = v_name,
         buyer_contact  = v_tel,
         buyer_email    = v_mail,
         buyer_address  = v_addr,
         buyer_found_at = COALESCE(buyer_found_at, NOW()),
         status         = 'buyer_found'
   WHERE id = v_prog.id;
END;
$$;
REVOKE ALL ON FUNCTION public.save_market_linking_buyer_details(UUID, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.save_market_linking_buyer_details(UUID, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- ═══ 6. Stage 3 — Complete Sale ═════════════════════════════════════════════
-- The buyer is the one saved in Buyer Details; this records only the
-- transaction: quantity purchased, agreed price per kg, notes.
DROP FUNCTION IF EXISTS public.record_market_linking_sale(UUID, TEXT, TEXT, NUMERIC, NUMERIC, TEXT);

CREATE OR REPLACE FUNCTION public.record_market_linking_sale(
  p_program_id   UUID,
  p_quantity_kg  NUMERIC,
  p_price_per_kg NUMERIC,
  p_notes        TEXT DEFAULT NULL
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
  IF v_prog.buyer_name IS NULL OR btrim(v_prog.buyer_name) = '' THEN
    RAISE EXCEPTION 'Save the buyer''s details before completing the sale.';
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

  -- The sale first uses what was reserved for this request. A request made before
  -- reservations existed has nothing reserved, so its sale comes from the batch's
  -- available stock instead (never negative, never twice).
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
    btrim(v_prog.buyer_name), NULLIF(btrim(COALESCE(v_prog.buyer_contact, '')), ''),
    p_quantity_kg, p_price_per_kg, v_total, NULLIF(btrim(COALESCE(p_notes, '')), ''), auth.uid()
  ) RETURNING id INTO v_sale_id;

  v_new_sold := v_prog.sold_kg + p_quantity_kg;
  v_done     := v_new_sold >= v_prog.volume_kg;

  UPDATE market_linking_programs
     SET sold_kg             = v_new_sold,
         confirmed_volume_kg = v_new_sold,
         reserved_kg         = v_prog.reserved_kg - v_from_res,
         price_per_kg        = p_price_per_kg,
         requested_volume_kg = COALESCE(requested_volume_kg, p_quantity_kg),
         notes               = COALESCE(NULLIF(btrim(COALESCE(p_notes, '')), ''), notes),
         buyer_found_at      = COALESCE(buyer_found_at, NOW()),
         status              = CASE WHEN v_done THEN 'completed' ELSE 'buyer_found' END,
         completed_at        = CASE WHEN v_done THEN NOW() ELSE completed_at END,
         -- A cancellation still waiting on a request that is now fully sold has
         -- nothing left to cancel.
         cancellation_status = CASE WHEN v_done AND cancellation_status = 'requested'
                                    THEN 'withdrawn' ELSE cancellation_status END
   WHERE id = v_prog.id;

  IF v_done THEN
    PERFORM public._ml_release_reserved(v_prog.id);
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_prog.farmer_id, 'system',
    CASE WHEN v_done THEN 'Ginger Sale Completed' ELSE 'Ginger Sale Recorded' END,
    p_quantity_kg || ' kg of ' || v_prog.crop_name || ' was sold to ' || btrim(v_prog.buyer_name) ||
      ' at ' || p_price_per_kg || ' per kg (total ' || v_total || ').' ||
      CASE WHEN v_done THEN ''
           ELSE ' ' || (v_prog.volume_kg - v_new_sold) || ' kg is still in your request.' END,
    FALSE, NOW(), '/farmer/profile/market-linking'
  );

  RETURN v_sale_id;
END;
$$;
REVOKE ALL ON FUNCTION public.record_market_linking_sale(UUID, NUMERIC, NUMERIC, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_market_linking_sale(UUID, NUMERIC, NUMERIC, TEXT) TO authenticated;

-- ═══ 7. complete_market_linking(): records the sale, nothing more ═══════════
-- Kept so anything that still calls it keeps working: it saves the buyer (if
-- given) and records the confirmed volume as one sale. It no longer closes the
-- rest of the request (that is a cancellation, and starts with the Farmer), and
-- a plain "complete without a sale" is no longer possible.
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
  v_prog market_linking_programs%ROWTYPE;
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
  IF p_confirmed_volume_kg IS NULL OR p_confirmed_volume_kg <= 0 THEN
    RAISE EXCEPTION 'Use Complete Sale: enter the quantity purchased and the agreed price.';
  END IF;

  IF p_buyer_name IS NOT NULL AND btrim(p_buyer_name) <> '' THEN
    UPDATE market_linking_programs
       SET buyer_name = btrim(p_buyer_name),
           buyer_contact = COALESCE(NULLIF(btrim(COALESCE(p_buyer_contact, '')), ''), buyer_contact)
     WHERE id = p_id;
  END IF;

  PERFORM public.record_market_linking_sale(
    p_id, p_confirmed_volume_kg, COALESCE(p_price_per_kg, v_prog.price_per_kg), p_notes
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

GRANT EXECUTE ON FUNCTION public.complete_market_linking(UUID, UUID, NUMERIC, TEXT, TEXT, NUMERIC, TEXT) TO authenticated;

-- ═══ 8. Farmer: Request Cancellation ═══════════════════════════════════════
CREATE OR REPLACE FUNCTION public.request_market_linking_cancellation(
  p_program_id UUID,
  p_reason     TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prog   market_linking_programs%ROWTYPE;
  v_reason TEXT := NULLIF(btrim(COALESCE(p_reason, '')), '');
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Please sign in.';
  END IF;
  IF v_reason IS NULL THEN
    RAISE EXCEPTION 'Tell us why you want to cancel this request.';
  END IF;

  SELECT * INTO v_prog FROM market_linking_programs
   WHERE id = p_program_id AND farmer_id = auth.uid() FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Market linking request not found';
  END IF;
  IF v_prog.status NOT IN ('submitted', 'buyer_found') THEN
    RAISE EXCEPTION 'This request is already closed (%), so it cannot be cancelled.', v_prog.status;
  END IF;
  IF v_prog.volume_kg IS NOT NULL AND v_prog.sold_kg >= v_prog.volume_kg THEN
    RAISE EXCEPTION 'This request is fully sold, so it cannot be cancelled.';
  END IF;
  IF v_prog.cancellation_status = 'requested' THEN
    RAISE EXCEPTION 'You already asked to cancel this request. Please wait for the review.';
  END IF;

  UPDATE market_linking_programs
     SET cancellation_status       = 'requested',
         cancellation_reason       = v_reason,
         cancellation_requested_at = NOW(),
         cancellation_reviewed_by  = NULL,
         cancellation_reviewed_at  = NULL,
         cancellation_review_notes = NULL
   WHERE id = v_prog.id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ap.user_id, 'system', 'Market Linking Cancellation Requested',
         'A farmer asked to cancel a ' || v_prog.crop_name || ' request (' ||
           (COALESCE(v_prog.volume_kg, 0) - v_prog.sold_kg) || ' kg unsold). Reason: ' || v_reason,
         FALSE, NOW(), '/admin/farmers/market-linking'
    FROM public.user_roles ap WHERE ap.role IN ('admin', 'officer');
END;
$$;
REVOKE ALL ON FUNCTION public.request_market_linking_cancellation(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_market_linking_cancellation(UUID, TEXT) TO authenticated;

-- ═══ 9. Manager/Officer: approve or decline the cancellation ═══════════════
CREATE OR REPLACE FUNCTION public.respond_to_market_linking_cancellation(
  p_program_id UUID,
  p_approve    BOOLEAN,
  p_notes      TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prog     market_linking_programs%ROWTYPE;
  v_notes    TEXT := NULLIF(btrim(COALESCE(p_notes, '')), '');
  v_released NUMERIC;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can review a cancellation';
  END IF;

  SELECT * INTO v_prog FROM market_linking_programs WHERE id = p_program_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Market linking request not found';
  END IF;
  IF v_prog.cancellation_status IS DISTINCT FROM 'requested' THEN
    RAISE EXCEPTION 'There is no cancellation request waiting for review on this request.';
  END IF;
  IF NOT p_approve AND v_notes IS NULL THEN
    RAISE EXCEPTION 'Give a reason for declining the cancellation.';
  END IF;

  IF p_approve THEN
    -- Releases only what is still reserved and unsold. Sales stay recorded.
    v_released := public.close_market_linking_request(v_prog.id, v_prog.cancellation_reason, FALSE);
    UPDATE market_linking_programs
       SET cancellation_status       = 'approved',
           cancellation_reviewed_by  = auth.uid(),
           cancellation_reviewed_at  = NOW(),
           cancellation_review_notes = v_notes
     WHERE id = v_prog.id;

    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      v_prog.farmer_id, 'system', 'Cancellation Approved',
      CASE WHEN v_prog.sold_kg > 0
           THEN 'Your ' || v_prog.crop_name || ' request was closed. The ' || v_prog.sold_kg || ' kg already sold stays recorded.'
           ELSE 'Your ' || v_prog.crop_name || ' request was cancelled.' END ||
      CASE WHEN v_released > 0 THEN ' ' || v_released || ' kg is back in your stock.' ELSE '' END,
      FALSE, NOW(), '/farmer/profile/market-linking'
    );
  ELSE
    UPDATE market_linking_programs
       SET cancellation_status       = 'rejected',
           cancellation_reviewed_by  = auth.uid(),
           cancellation_reviewed_at  = NOW(),
           cancellation_review_notes = v_notes
     WHERE id = v_prog.id;

    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      v_prog.farmer_id, 'system', 'Cancellation Declined',
      'Your request to cancel the ' || v_prog.crop_name || ' request was declined. Reason: ' || v_notes,
      FALSE, NOW(), '/farmer/profile/market-linking'
    );
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.respond_to_market_linking_cancellation(UUID, BOOLEAN, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.respond_to_market_linking_cancellation(UUID, BOOLEAN, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. New functions exist (expect 4 rows) and the old 6-argument sale function is gone:
--    SELECT proname, pronargs FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--      AND proname IN ('save_market_linking_buyer_details','record_market_linking_sale',
--                      'request_market_linking_cancellation','respond_to_market_linking_cancellation');
-- 2. The app can no longer call close_market_linking_request (expect false):
--    SELECT has_function_privilege('authenticated', 'public.close_market_linking_request(uuid,text,boolean)', 'EXECUTE');
-- 3. Then run supabase_schema_market_linking_partial_sales_test.sql (expect FAILED CHECKS: 0)
--    and supabase_schema_selling_channels_test.sql (expect FAILED CHECKS: 0).
-- ───────────────────────────────────────────────────────────────────────────
