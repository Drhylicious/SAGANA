-- ============================================================================
-- SAGANA — Shelf-Life & Rotten/Lost Cross-Channel Synchronization (s06)
--
-- Fixes Item 1 across all selling channels (Marketplace, Offer to Cooperative,
-- DA-AMAD Market Linking, and Informal Sale):
--   1. Adds rotten_at / rotten_kg on listing_shelf_life so listings finalized as
--      Rotten/Lost carry an explicit terminal spoilage marker (never Sold Out +
--      Discounted, and never resurrected by order cancellation).
--   2. Hardens _batch_shelf_life_sell_guard() so expired batches (expires_on <
--      today) and finalized-rotten batches cannot be committed through ANY
--      channel (Marketplace, Offer to Cooperative, DA-AMAD, Informal Sale)
--      until inspected/confirmed usable in Manage Inventory.
--   3. Replaces report_batch_rotten(p_batch_id, p_note) to:
--        - Auto-cancel unfulfilled Marketplace orders (pending, approved,
--          ready_for_pickup, out_for_delivery — before handover/delivered),
--          notify affected buyers and staff, and move listings to terminal
--          status (sold if delivered/completed orders exist, else withdrawn)
--          with rotten_at stamped and discount flags cleared.
--        - Auto-cancel open/undelivered Cooperative Offers (pending, approved),
--          log cooperative_offer_events, and notify staff.
--        - Close/cancel unsold DA-AMAD Market Linking reservations
--          (reserved_kg > 0) and reconcile all remaining uncompleted batch
--          stock into adjusted_kg + batch_shelf_life.spoiled_kg.
--   4. Updates _orders_require_receipt() and _coop_offer_status_flow() to
--      permit cancelling unfulfilled orders / undelivered offers ONLY when
--      sagana.shelf_rotten = 'on' inside report_batch_rotten().
--   5. Hardens cancel_my_order(), _release_batch_reservation(), and
--      _ml_release_reserved() so cancelling an order, offer, or DA-AMAD
--      request NEVER revives rotten or expired stock back onto Marketplace or
--      available_kg.
--   6. Hardens _orders_shelf_life_guard() to block new orders if a listing is
--      rotten or its batch is past shelf life.
--
-- NOT APPLIED AUTOMATICALLY. Run manually in the Supabase SQL Editor.
-- Safe to re-run (transactional, idempotent).
-- ============================================================================

BEGIN;

-- ─── 1. Schema additions on listing_shelf_life ─────────────────────────────
ALTER TABLE public.listing_shelf_life
  ADD COLUMN IF NOT EXISTS rotten_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rotten_kg NUMERIC(10,2) NOT NULL DEFAULT 0;

-- ─── 2. Permit rotten-triggered cancellation in order & offer state triggers ─
CREATE OR REPLACE FUNCTION public._orders_require_receipt()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_method TEXT;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'cancelled'
     AND OLD.status IN ('pending', 'approved', 'ready_for_pickup', 'out_for_delivery')
     AND COALESCE(current_setting('sagana.shelf_rotten', true), '') = 'on' THEN
    RETURN NEW;
  END IF;

  v_method := COALESCE(NEW.fulfillment_method, 'pickup');

  IF NOT (
       (OLD.status = 'pending'          AND NEW.status IN ('approved', 'cancelled'))
    OR (OLD.status = 'approved'         AND NEW.status = 'ready_for_pickup'  AND v_method = 'pickup')
    OR (OLD.status = 'approved'         AND NEW.status = 'out_for_delivery'  AND v_method = 'delivery')
    OR (OLD.status = 'out_for_delivery' AND NEW.status = 'delivered')
    OR (OLD.status = 'ready_for_pickup' AND NEW.status = 'completed'         AND v_method = 'pickup')
    OR (OLD.status = 'delivered'        AND NEW.status = 'completed')
  ) THEN
    RAISE EXCEPTION 'An order cannot move from % to % (% order).', OLD.status, NEW.status, v_method;
  END IF;

  IF NEW.status = 'completed' THEN
    IF current_setting('sagana.order_receipt', true) IS DISTINCT FROM NEW.id::text THEN
      RAISE EXCEPTION 'An order is completed when the buyer confirms they received it (or staff complete it with a reason and a photo).';
    END IF;
    IF NEW.payment_status IS DISTINCT FROM 'paid' THEN
      RAISE EXCEPTION 'PAYMENT_NOT_RECORDED: An order is completed only after the payment is recorded.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._coop_offer_status_flow()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  IF NEW.status = 'cancelled'
     AND OLD.status IN ('pending', 'approved')
     AND COALESCE(current_setting('sagana.shelf_rotten', true), '') = 'on' THEN
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

-- ─── 3. Cross-channel shelf-life guard on batch commits ────────────────────
-- Applies uniformly to Marketplace, Offer to Cooperative, Informal Sale, and
-- DA-AMAD Market Linking whenever stock moves out of available_kg.
CREATE OR REPLACE FUNCTION public._batch_shelf_life_sell_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_committed NUMERIC;
  v_s         batch_shelf_life%ROWTYPE;
BEGIN
  IF COALESCE(current_setting('sagana.shelf_rotten', true), '') = 'on' THEN
    RETURN NEW;
  END IF;

  v_committed := (NEW.quantity_kg - OLD.quantity_kg)
               - (NEW.available_kg - OLD.available_kg)
               - (NEW.adjusted_kg - OLD.adjusted_kg);

  IF v_committed >= 0.005 THEN
    SELECT * INTO v_s FROM batch_shelf_life WHERE batch_id = NEW.id;
    IF FOUND THEN
      IF v_s.hold THEN
        RAISE EXCEPTION 'SHELF_LIFE_HOLD: This harvest was recorded after its shelf life had already passed. Check the produce and confirm it is still good in Manage Inventory before selling it.';
      END IF;
      IF v_s.expires_on IS NOT NULL AND v_s.expires_on < public._ph_today() THEN
        RAISE EXCEPTION 'SHELF_LIFE_EXPIRED: This harvest is past its shelf life. Check the produce and confirm it is still good in Manage Inventory before selling it.';
      END IF;
      IF v_s.spoiled_at IS NOT NULL AND OLD.available_kg <= 0 THEN
        RAISE EXCEPTION 'SHELF_LIFE_ROTTEN: This harvest has already been recorded as rotten or lost.';
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._batch_shelf_life_sell_guard() FROM PUBLIC, anon, authenticated;

-- ─── 4. Order insert shelf-life guard ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public._orders_shelf_life_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_batch_id UUID;
BEGIN
  IF NEW.listing_id IS NOT NULL THEN
    IF public._listing_shelf_unavailable(NEW.listing_id) THEN
      RAISE EXCEPTION 'This listing is currently unavailable. Please choose another listing.';
    END IF;

    IF EXISTS (
      SELECT 1 FROM listing_shelf_life x
      WHERE x.listing_id = NEW.listing_id AND x.rotten_at IS NOT NULL
    ) THEN
      RAISE EXCEPTION 'This listing is no longer available because the harvest was recorded as rotten or lost.';
    END IF;

    SELECT ml.inventory_batch_id INTO v_batch_id
    FROM marketplace_listings ml WHERE ml.id = NEW.listing_id;

    IF v_batch_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM batch_shelf_life s
      WHERE s.batch_id = v_batch_id
        AND (s.hold OR (s.expires_on IS NOT NULL AND s.expires_on < public._ph_today()))
    ) THEN
      RAISE EXCEPTION 'This listing is currently unavailable while its harvest shelf life is being verified.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
REVOKE ALL ON FUNCTION public._orders_shelf_life_guard() FROM PUBLIC, anon, authenticated;

-- ─── 5. Harden reservation release helpers against expired/rotten stock ────
CREATE OR REPLACE FUNCTION public._release_batch_reservation(
  p_batch_id UUID,
  p_quantity NUMERIC
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  b              inventory_batches%ROWTYPE;
  s              batch_shelf_life%ROWTYPE;
  v_new_avail    NUMERIC;
  v_new_adjusted NUMERIC;
  v_new_status   TEXT;
BEGIN
  IF p_batch_id IS NULL OR COALESCE(p_quantity, 0) <= 0 THEN
    RETURN;
  END IF;

  SELECT * INTO b FROM public.inventory_batches WHERE id = p_batch_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  SELECT * INTO s FROM public.batch_shelf_life WHERE batch_id = p_batch_id FOR UPDATE;

  -- If the batch was already recorded rotten with no remaining available stock,
  -- released reservations become loss adjustments instead of sellable stock.
  IF FOUND AND s.spoiled_at IS NOT NULL AND b.available_kg <= 0 THEN
    PERFORM set_config('sagana.shelf_rotten', 'on', true);
    v_new_adjusted := LEAST(b.quantity_kg - b.sold_kg, b.adjusted_kg + p_quantity);
    v_new_status := CASE
      WHEN b.sold_kg + v_new_adjusted >= b.quantity_kg THEN 'sold_out'
      ELSE 'reserved'
    END;
    UPDATE public.inventory_batches
       SET adjusted_kg = v_new_adjusted,
           status      = v_new_status
     WHERE id = b.id;

    UPDATE public.stock_movements
       SET note = 'Returned reservation written off (batch recorded rotten)'
     WHERE batch_id = b.id AND txid = txid_current() AND movement_type = 'adjusted';

    UPDATE public.batch_shelf_life
       SET spoiled_kg = spoiled_kg + p_quantity,
           spoiled_at = NOW(),
           updated_at = NOW()
     WHERE batch_id = b.id;
    PERFORM set_config('sagana.shelf_rotten', 'off', true);
    RETURN;
  END IF;

  v_new_avail := LEAST(b.quantity_kg - b.sold_kg - b.adjusted_kg, b.available_kg + p_quantity);
  v_new_status := CASE
    WHEN v_new_avail <= 0 THEN
      CASE WHEN b.sold_kg + b.adjusted_kg >= b.quantity_kg THEN 'sold_out' ELSE 'reserved' END
    WHEN v_new_avail < b.quantity_kg * 0.15 THEN 'low_stock'
    ELSE 'available'
  END;

  UPDATE public.inventory_batches
     SET available_kg = v_new_avail, status = v_new_status
   WHERE id = b.id;

  -- Returned stock that is already past expiry must be held until inspected.
  IF FOUND AND s.expires_on IS NOT NULL AND s.expires_on < public._ph_today() AND NOT s.hold THEN
    UPDATE public.batch_shelf_life
       SET hold = TRUE, updated_at = NOW()
     WHERE batch_id = b.id;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public._release_batch_reservation(UUID, NUMERIC) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._release_batch_reservation(UUID, NUMERIC) TO service_role;

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
    PERFORM public._release_batch_reservation(v_prog.inventory_batch_id, v_prog.reserved_kg);
  END IF;

  UPDATE market_linking_programs SET reserved_kg = 0 WHERE id = p_program_id;
  PERFORM public.reconcile_batch_sold(v_prog.inventory_batch_id);
  RETURN v_prog.reserved_kg;
END;
$$;
REVOKE ALL ON FUNCTION public._ml_release_reserved(UUID) FROM PUBLIC, anon, authenticated;

-- ─── 6. Harden cancel_my_order against resurrecting rotten/expired listings ─
CREATE OR REPLACE FUNCTION public.cancel_my_order(
  p_order_id UUID,
  p_reason   TEXT DEFAULT NULL::TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller      UUID := auth.uid();
  v_status      TEXT;
  v_listing_id  UUID;
  v_quantity_kg NUMERIC;
  v_buyer_id    UUID;
  v_farmer_id   UUID;
  v_batch_id    UUID;
  v_crop_name   TEXT;
  v_name        TEXT;
  v_role        TEXT;
  v_rotten      BOOLEAN := FALSE;
  v_expired     BOOLEAN := FALSE;
  v_b_avail     NUMERIC := 0;
  v_b_qty       NUMERIC := 0;
  v_b_sold      NUMERIC := 0;
  v_b_adj       NUMERIC := 0;
  v_new_adj     NUMERIC;
BEGIN
  SELECT status, listing_id, quantity_kg, buyer_id
  INTO v_status, v_listing_id, v_quantity_kg, v_buyer_id
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_buyer_id IS DISTINCT FROM v_caller THEN
    RAISE EXCEPTION 'You can only cancel your own order';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending order can be cancelled (current: %)', v_status;
  END IF;

  SELECT role INTO v_role FROM user_roles WHERE user_id = v_caller;

  SELECT ml.crop_name, ml.farmer_id, ml.inventory_batch_id
    INTO v_crop_name, v_farmer_id, v_batch_id
  FROM marketplace_listings ml WHERE ml.id = v_listing_id FOR UPDATE;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_caller;

  IF EXISTS (
    SELECT 1 FROM listing_shelf_life x
    WHERE x.listing_id = v_listing_id AND x.rotten_at IS NOT NULL
  ) THEN
    v_rotten := TRUE;
  END IF;

  IF v_batch_id IS NOT NULL THEN
    SELECT b.available_kg, b.quantity_kg, b.sold_kg, b.adjusted_kg
      INTO v_b_avail, v_b_qty, v_b_sold, v_b_adj
    FROM inventory_batches b WHERE b.id = v_batch_id FOR UPDATE;

    IF EXISTS (
      SELECT 1 FROM batch_shelf_life s
      WHERE s.batch_id = v_batch_id
        AND s.spoiled_at IS NOT NULL
        AND COALESCE(v_b_avail, 0) <= 0
    ) THEN
      v_rotten := TRUE;
    END IF;

    IF EXISTS (
      SELECT 1 FROM batch_shelf_life s
      WHERE s.batch_id = v_batch_id
        AND (s.hold OR (s.expires_on IS NOT NULL AND s.expires_on < public._ph_today()))
    ) THEN
      v_expired := TRUE;
    END IF;
  END IF;

  IF v_rotten THEN
    -- Keep listing closed / remaining_kg = 0 and write off the cancelled order quantity.
    PERFORM set_config('sagana.shelf_rotten', 'on', true);

    UPDATE marketplace_listings
    SET volume_kg = GREATEST(volume_kg - v_quantity_kg, 0.01),
        remaining_kg = 0,
        status = CASE
          WHEN EXISTS (SELECT 1 FROM orders o2
                       WHERE o2.listing_id = v_listing_id
                         AND o2.id <> p_order_id
                         AND o2.status IN ('delivered', 'completed'))
            THEN 'sold'
          ELSE 'withdrawn'
        END
    WHERE id = v_listing_id;

    INSERT INTO listing_shelf_life (listing_id, farmer_id, unavailable, unavailable_since,
                                    discount_applied_on, discount_percent, pre_discount_price,
                                    rotten_at, rotten_kg)
    VALUES (v_listing_id, v_farmer_id, FALSE, NULL, NULL, NULL, NULL, NOW(), v_quantity_kg)
    ON CONFLICT (listing_id) DO UPDATE
      SET unavailable = FALSE,
          unavailable_since = NULL,
          discount_applied_on = NULL,
          discount_percent = NULL,
          pre_discount_price = NULL,
          rotten_at = COALESCE(listing_shelf_life.rotten_at, NOW()),
          rotten_kg = listing_shelf_life.rotten_kg + v_quantity_kg,
          updated_at = NOW();

    IF v_batch_id IS NOT NULL THEN
      v_new_adj := LEAST(v_b_qty - v_b_sold, v_b_adj + v_quantity_kg);
      UPDATE inventory_batches
         SET adjusted_kg = v_new_adj,
             status = CASE WHEN v_b_sold + v_new_adj >= v_b_qty THEN 'sold_out' ELSE 'reserved' END
       WHERE id = v_batch_id;

      UPDATE stock_movements
         SET note = 'Cancelled order written off (batch recorded rotten)'
       WHERE batch_id = v_batch_id AND txid = txid_current() AND movement_type = 'adjusted';

      UPDATE batch_shelf_life
         SET spoiled_kg = spoiled_kg + v_quantity_kg,
             spoiled_at = NOW(),
             updated_at = NOW()
       WHERE batch_id = v_batch_id;
    END IF;
    PERFORM set_config('sagana.shelf_rotten', 'off', true);
  ELSE
    UPDATE marketplace_listings
    SET remaining_kg = remaining_kg + v_quantity_kg,
        status = CASE WHEN status = 'sold' THEN 'approved' ELSE status END
    WHERE id = v_listing_id;

    -- If the batch is already past expiry, keep the listing hidden until verified.
    IF v_expired THEN
      INSERT INTO listing_shelf_life (listing_id, farmer_id, unavailable, unavailable_since)
      VALUES (v_listing_id, v_farmer_id, TRUE, NOW())
      ON CONFLICT (listing_id) DO UPDATE
        SET unavailable = TRUE,
            unavailable_since = COALESCE(listing_shelf_life.unavailable_since, NOW()),
            updated_at = NOW();
    END IF;
  END IF;

  UPDATE orders
  SET status = 'cancelled',
      notes = COALESCE(p_reason, notes),
      cancelled_by = CASE WHEN v_role = 'farmer' THEN 'farmer' ELSE 'buyer' END
  WHERE id = p_order_id;

  PERFORM public.notify_staff(
    'order',
    'Order Cancelled by ' || CASE WHEN v_role = 'farmer' THEN 'Farmer' ELSE 'Buyer' END,
    COALESCE(v_name, 'A buyer') || ' cancelled a pending order for ' || COALESCE(v_crop_name, 'produce') || '.' ||
      CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'order', 'Order Cancelled',
    COALESCE(v_name, 'A buyer') || ' cancelled their order for your ' || COALESCE(v_crop_name, 'produce') || ' listing.' ||
      CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END,
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$$;
REVOKE ALL ON FUNCTION public.cancel_my_order(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_my_order(UUID, TEXT) TO authenticated;

-- ─── 7. Canonical report_batch_rotten synchronizing all selling channels ────
CREATE OR REPLACE FUNCTION public.report_batch_rotten(
  p_batch_id UUID,
  p_note     TEXT DEFAULT NULL
) RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid               UUID := auth.uid();
  v_role              TEXT;
  v_status            TEXT;
  b                   inventory_batches%ROWTYPE;
  l                   marketplace_listings%ROWTYPE;
  o                   RECORD;
  cpo                 RECORD;
  ml                  RECORD;
  v_released          NUMERIC := 0;
  v_in_flight_kg      NUMERIC := 0;
  v_listing_cancel_kg NUMERIC := 0;
  v_listing_rotten_kg NUMERIC := 0;
  v_kept_kg           NUMERIC := 0;
  v_loss              NUMERIC := 0;
  v_adjusted          NUMERIC := 0;
  v_name              TEXT;
  v_buyer_role        TEXT;
  v_buyer_route       TEXT;
  v_cancelled_orders  INTEGER := 0;
  v_cancelled_offers  INTEGER := 0;
  v_cancelled_ml      INTEGER := 0;
  v_note_clean        TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_extra_parts       TEXT[] := ARRAY[]::TEXT[];
  v_staff_body        TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  SELECT role, status INTO v_role, v_status FROM user_roles WHERE user_id = v_uid;
  IF v_role IS DISTINCT FROM 'farmer' OR v_status IS DISTINCT FROM 'active' THEN
    RAISE EXCEPTION 'Only an active Farmer account can report a loss.';
  END IF;

  SELECT * INTO b FROM inventory_batches WHERE id = p_batch_id AND farmer_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This batch was not found in your inventory.';
  END IF;

  PERFORM set_config('sagana.shelf_rotten', 'on', true);

  -- 1) Marketplace listings & unfulfilled orders (pending, approved, ready_for_pickup, out_for_delivery).
  --    Orders already handed over (delivered) or completed remain intact.
  FOR l IN
    SELECT * FROM marketplace_listings
    WHERE inventory_batch_id = b.id
      AND status IN ('pending_review', 'approved', 'sold')
    FOR UPDATE
  LOOP
    v_listing_cancel_kg := 0;

    FOR o IN
      SELECT ord.id, ord.buyer_id, ord.quantity_kg, ord.order_number, ord.payment_status
      FROM orders ord
      WHERE ord.listing_id = l.id
        AND ord.status IN ('pending', 'approved', 'ready_for_pickup', 'out_for_delivery')
      FOR UPDATE
    LOOP
      UPDATE orders
         SET status       = 'cancelled',
             cancelled_by = 'farmer',
             notes        = COALESCE(v_note_clean, 'Cancelled: this product is no longer available because it was recorded as Rotten/Lost. Please order a different product.')
       WHERE id = o.id;

      v_listing_cancel_kg := v_listing_cancel_kg + o.quantity_kg;
      v_cancelled_orders  := v_cancelled_orders + 1;

      SELECT ur.role INTO v_buyer_role FROM user_roles ur WHERE ur.user_id = o.buyer_id LIMIT 1;
      v_buyer_route := CASE
        WHEN v_buyer_role = 'farmer' THEN '/farmer/profile/orders/detail'
        ELSE '/buyer/orders/detail'
      END;

      INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap, route_extra)
      VALUES (
        o.buyer_id,
        'order',
        'Order Cancelled — Produce Unavailable',
        'Your order ' || COALESCE(o.order_number, '') ||
          CASE WHEN COALESCE(o.order_number, '') <> '' THEN ' ' ELSE '' END ||
          'for ' || b.crop_name || ' (' || o.quantity_kg || ' ' || COALESCE(b.unit, 'kg') ||
          ') is no longer available and was cancelled because the product was recorded as Rotten/Lost. Please order a different product.' ||
          CASE WHEN o.payment_status = 'paid' THEN ' Please contact the cooperative regarding your recorded payment.' ELSE '' END,
        FALSE,
        NOW(),
        v_buyer_route,
        o.id::text
      );
    END LOOP;

    v_listing_rotten_kg := l.remaining_kg + v_listing_cancel_kg;

    IF l.status IN ('pending_review', 'approved') OR v_listing_rotten_kg > 0 THEN
      SELECT COALESCE(SUM(ord.quantity_kg), 0)
        INTO v_kept_kg
      FROM orders ord
      WHERE ord.listing_id = l.id
        AND ord.status IN ('delivered', 'completed');

      -- Cancel any pending edit or shelf-life review requests for this listing.
      UPDATE listing_edit_requests
         SET status        = 'cancelled',
             reviewed_at   = NOW(),
             review_reason = 'Cancelled: harvest was recorded as rotten/lost.'
       WHERE listing_id = l.id AND status = 'pending';

      IF v_kept_kg > 0 THEN
        UPDATE marketplace_listings
           SET status       = 'sold',
               volume_kg    = v_kept_kg,
               remaining_kg = 0
         WHERE id = l.id;
      ELSE
        UPDATE marketplace_listings
           SET status       = 'withdrawn',
               remaining_kg = 0
         WHERE id = l.id;
      END IF;

      INSERT INTO listing_shelf_life (
        listing_id, farmer_id, unavailable, unavailable_since,
        discount_applied_on, discount_percent, pre_discount_price,
        rotten_at, rotten_kg
      )
      VALUES (
        l.id, v_uid, FALSE, NULL,
        NULL, NULL, NULL,
        NOW(), v_listing_rotten_kg
      )
      ON CONFLICT (listing_id) DO UPDATE
        SET unavailable         = FALSE,
            unavailable_since   = NULL,
            discount_applied_on = NULL,
            discount_percent    = NULL,
            pre_discount_price  = NULL,
            rotten_at           = NOW(),
            rotten_kg           = listing_shelf_life.rotten_kg + v_listing_rotten_kg,
            updated_at          = NOW();

      v_released := v_released + v_listing_rotten_kg;
    END IF;
  END LOOP;

  -- 2) Offer to Cooperative: cancel open/undelivered offers (pending, approved).
  --    Offers already delivered or completed stay intact.
  FOR cpo IN
    SELECT * FROM cooperative_purchase_offers
    WHERE inventory_batch_id = b.id
      AND status IN ('pending', 'approved')
    FOR UPDATE
  LOOP
    UPDATE cooperative_purchase_offers
       SET status       = 'cancelled',
           admin_notes  = COALESCE(v_note_clean, 'Cancelled: harvest was recorded as rotten/lost by the farmer.'),
           confirmed_at = COALESCE(confirmed_at, NOW())
     WHERE id = cpo.id;

    INSERT INTO cooperative_offer_events
      (offer_id, round, action, actor_role, actor_id, price_per_kg, quantity_kg, note)
    VALUES
      (cpo.id, cpo.negotiation_round, 'cancelled', 'farmer', v_uid,
       NULLIF(COALESCE(cpo.agreed_price_per_kg, cpo.current_price_per_kg, cpo.asking_price_per_kg), 0),
       cpo.offered_quantity_kg,
       COALESCE(v_note_clean, 'Harvest recorded as rotten/lost.'));

    v_released         := v_released + cpo.offered_quantity_kg;
    v_cancelled_offers := v_cancelled_offers + 1;
  END LOOP;

  -- 3) DA-AMAD Market Linking: close/cancel unsold reserved_kg before status trigger fires.
  FOR ml IN
    SELECT * FROM market_linking_programs
    WHERE inventory_batch_id = b.id
      AND status IN ('requested', 'submitted', 'buyer_found')
      AND reserved_kg > 0
    FOR UPDATE
  LOOP
    v_released     := v_released + ml.reserved_kg;
    v_cancelled_ml := v_cancelled_ml + 1;

    IF COALESCE(ml.sold_kg, 0) > 0 THEN
      UPDATE market_linking_programs
         SET reserved_kg  = 0,
             status       = 'completed',
             completed_at = COALESCE(completed_at, NOW()),
             notes        = COALESCE(v_note_clean, 'Remaining unsold quantity recorded as rotten/lost.')
       WHERE id = ml.id;
    ELSE
      UPDATE market_linking_programs
         SET reserved_kg          = 0,
             status               = 'cancelled',
             cancellation_status  = 'approved',
             cancellation_reason  = COALESCE(v_note_clean, 'Harvest recorded as rotten/lost by the farmer.'),
             cancellation_reviewed_at = NOW()
       WHERE id = ml.id;
    END IF;
  END LOOP;

  -- 4) Reconcile batch loss against uncompleted physical stock, protecting any
  --    stock already handed over (delivered, awaiting final completion/receipt)
  --    while recovering any orphan reserved_kg left behind by old records.
  SELECT COALESCE(SUM(ord.quantity_kg), 0)
    INTO v_in_flight_kg
  FROM orders ord
  JOIN marketplace_listings lst ON lst.id = ord.listing_id
  WHERE lst.inventory_batch_id = b.id
    AND ord.status = 'delivered';

  v_in_flight_kg := v_in_flight_kg + COALESCE((
    SELECT SUM(co.offered_quantity_kg)
    FROM cooperative_purchase_offers co
    WHERE co.inventory_batch_id = b.id
      AND co.status = 'delivered'
  ), 0);

  v_loss := round(
    GREATEST(b.quantity_kg - b.sold_kg - b.adjusted_kg - v_in_flight_kg, 0),
    2
  );
  IF v_loss <= 0 THEN
    PERFORM set_config('sagana.shelf_rotten', 'off', true);
    RAISE EXCEPTION 'Nothing is left in this batch to report as a loss.';
  END IF;

  v_adjusted := b.adjusted_kg + v_loss;
  UPDATE inventory_batches
     SET available_kg = 0,
         adjusted_kg  = v_adjusted,
         status       = CASE WHEN b.sold_kg + v_adjusted >= b.quantity_kg THEN 'sold_out' ELSE 'reserved' END
   WHERE id = b.id;

  UPDATE stock_movements
     SET note = 'Reported as rotten (loss)'
   WHERE batch_id = b.id AND txid = txid_current() AND movement_type = 'adjusted';

  INSERT INTO batch_shelf_life (batch_id, farmer_id, spoiled_kg, spoiled_at, hold)
  VALUES (b.id, v_uid, v_loss, NOW(), FALSE)
  ON CONFLICT (batch_id) DO UPDATE
    SET spoiled_kg   = batch_shelf_life.spoiled_kg + EXCLUDED.spoiled_kg,
        spoiled_at   = NOW(),
        hold         = FALSE,
        notified_for = batch_shelf_life.expires_on,
        updated_at   = NOW();

  PERFORM public._shelf_life_event(b.id, 'reported_rotten', NULL, v_loss, NULL, NULL, NULL, NULL, NULL, v_note_clean);

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_uid;

  IF v_cancelled_orders > 0 THEN
    v_extra_parts := array_append(v_extra_parts, v_cancelled_orders || ' order(s)');
  END IF;
  IF v_cancelled_offers > 0 THEN
    v_extra_parts := array_append(v_extra_parts, v_cancelled_offers || ' cooperative offer(s)');
  END IF;
  IF v_cancelled_ml > 0 THEN
    v_extra_parts := array_append(v_extra_parts, v_cancelled_ml || ' Market Linking request(s)');
  END IF;

  v_staff_body := COALESCE(v_name, 'A farmer') || ' reported ' || v_loss || ' ' || COALESCE(b.unit, 'kg') || ' of ' ||
    b.crop_name || ' (' || b.batch_number || ') as rotten. It is recorded as a loss.';
  IF cardinality(v_extra_parts) > 0 THEN
    v_staff_body := v_staff_body || ' Auto-cancelled ' || array_to_string(v_extra_parts, ', ') || '.';
  END IF;

  PERFORM public.notify_staff('listing', 'Harvest Loss Reported', v_staff_body, '/admin/reports');

  PERFORM set_config('sagana.shelf_rotten', 'off', true);
  RETURN v_loss;
END;
$$;
REVOKE ALL ON FUNCTION public.report_batch_rotten(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.report_batch_rotten(UUID, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
