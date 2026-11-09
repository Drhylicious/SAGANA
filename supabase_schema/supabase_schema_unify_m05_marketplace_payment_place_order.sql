-- ============================================================
-- SAGANA — Unified purchasing m05: Marketplace payment, staff-assisted completion, place_order
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after m01 - m04.
--
-- WHAT IT DOES (Marketplace orders; the Cooperative equivalents are in m04)
--   1. PAYMENT is cash collected (at the counter for Pickup, cash on delivery for Delivery),
--      recorded by staff in record_order_payment / record_order_handover. It is stored apart from
--      the fulfillment status. The amount must match what is due: the order total, plus the
--      delivery fee when this is the first handover of its delivery group (collected once).
--   2. A consumer can Confirm Receipt only AFTER the payment is recorded.
--   3. STAFF-ASSISTED COMPLETION: staff_complete_order() completes a handed-over, paid order on
--      the consumer's behalf, with a reason, a photo, the staff member's identity and the time.
--   4. Completion needs a recorded payment, and payment / completion fields can no longer be
--      written directly: only these functions can change them.
--   5. place_order() gains three OPTIONAL arguments (address id, request id, delivery group):
--        - request id: a retried checkout returns the same order (no second reservation).
--        - delivery group: when the Manager has switched Delivery on, a delivery order uses the
--          server-validated address and fee snapshot (Barangay Payanas only). While Delivery is
--          OFF, delivery orders behave exactly as before. Pickup is unchanged.
--      Everything else in place_order() (roles, status, quantity, own-listing, stock) is kept.
--   6. mark_order_delivered() is retired: a delivery is handed over together with the cash.
--
-- Buyers: ordering, the cart and pickup are unchanged. What changes for a Buyer is only
-- what the approved plan lists: Confirm Receipt waits for the recorded payment, staff can
-- assist completion, and delivery follows the new rules once the Manager switches them on.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.checkout_groups') IS NULL THEN RAISE EXCEPTION 'Run m03 first.'; END IF;
  IF to_regprocedure('public._pp_staff_guard()') IS NULL THEN RAISE EXCEPTION 'Run m04 first.'; END IF;
  IF to_regprocedure('public.reconcile_batch_sold(uuid)') IS NULL THEN RAISE EXCEPTION 'reconcile_batch_sold() is missing.'; END IF;
END $$;

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_fee_collected NUMERIC(10,2) NOT NULL DEFAULT 0;

-- ════════════════════════════════════════════════════════════
-- 1. The status rule: completion needs a recorded payment
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._orders_require_receipt()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_method TEXT;
BEGIN
  IF NEW.status IS NOT DISTINCT FROM OLD.status THEN
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

  -- Completion is the consumer's confirmation, or staff completing it with a reason and a photo.
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

-- Payment and completion records are written by the functions below, never directly.
CREATE OR REPLACE FUNCTION public._orders_payment_guard()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF (NEW.payment_status, NEW.paid_at, NEW.amount_collected, NEW.delivery_fee_collected, NEW.payment_recorded_by,
      NEW.completion_method, NEW.staff_completion_reason, NEW.staff_completion_photo_url, NEW.staff_completed_by,
      NEW.staff_completed_at)
     IS DISTINCT FROM
     (OLD.payment_status, OLD.paid_at, OLD.amount_collected, OLD.delivery_fee_collected, OLD.payment_recorded_by,
      OLD.completion_method, OLD.staff_completion_reason, OLD.staff_completion_photo_url, OLD.staff_completed_by,
      OLD.staff_completed_at)
     AND current_setting('sagana.order_payment', true) IS DISTINCT FROM NEW.id::text THEN
    RAISE EXCEPTION 'The payment and completion record of an order can only be changed through the app''s order actions.';
  END IF;
  IF OLD.payment_status = 'paid' AND (NEW.payment_status, NEW.paid_at, NEW.amount_collected)
     IS DISTINCT FROM (OLD.payment_status, OLD.paid_at, OLD.amount_collected) THEN
    RAISE EXCEPTION 'A recorded payment cannot be changed.';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_orders_payment_guard ON public.orders;
CREATE TRIGGER trg_orders_payment_guard
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._orders_payment_guard();

-- ════════════════════════════════════════════════════════════
-- 2. Recording the cash (Manager, or an Officer with Marketplace = Manage)
-- ════════════════════════════════════════════════════════════
-- Pickup: the order is Ready for Pickup and the cash is taken at the counter. (Also used for an
-- older delivery order that was marked Delivered before payments were recorded.)
CREATE OR REPLACE FUNCTION public.record_order_payment(p_order_id uuid, p_amount numeric, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  o orders%ROWTYPE;
  v_role text; v_name text; v_fee numeric := 0; v_expected numeric;
BEGIN
  v_role := public._pp_staff_guard();
  SELECT * INTO o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found'; END IF;
  IF o.payment_status = 'paid' THEN RAISE EXCEPTION 'The payment of this order is already recorded.'; END IF;
  IF NOT ((COALESCE(o.fulfillment_method, 'pickup') = 'pickup'   AND o.status = 'ready_for_pickup')
       OR (o.fulfillment_method = 'delivery'                      AND o.status = 'delivered')) THEN
    RAISE EXCEPTION 'Record the payment once the order is Ready for Pickup (current status: %).', o.status;
  END IF;
  IF p_amount IS NULL OR p_amount <> round(p_amount, 2) THEN RAISE EXCEPTION 'Enter the amount collected.'; END IF;

  IF o.fulfillment_method = 'delivery' THEN
    v_fee := public._collect_group_fee(o.checkout_group_id, o.id, 'marketplace');
  END IF;
  v_expected := o.total_price + v_fee;
  IF round(p_amount, 2) <> v_expected THEN
    RAISE EXCEPTION 'AMOUNT_MISMATCH: The amount to collect is %. Check the cash received.', v_expected;
  END IF;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = auth.uid();
  PERFORM set_config('sagana.order_payment', o.id::text, true);
  UPDATE orders
     SET payment_status = 'paid', paid_at = NOW(), amount_collected = round(p_amount, 2),
         delivery_fee_collected = v_fee,
         payment_recorded_by = auth.uid(), payment_recorded_by_name = v_name, payment_recorded_by_role = v_role,
         payment_note = NULLIF(btrim(COALESCE(p_note, '')), '')
   WHERE id = o.id;
  PERFORM set_config('sagana.order_payment', '', true);

  PERFORM public._order_notify_consumer(o.id, 'Payment Recorded',
    'The payment for your order was recorded. Confirm receipt once you have your items.');
  RETURN jsonb_build_object('amount_collected', round(p_amount, 2), 'delivery_fee', v_fee);
END;
$$;

-- Delivery: handed over at the door with a photo, and the cash taken at the same time.
-- (For Pickup this is the same as record_order_payment.)
CREATE OR REPLACE FUNCTION public.record_order_handover(
  p_order_id uuid, p_amount numeric, p_photo_url text DEFAULT NULL, p_note text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  o orders%ROWTYPE;
  v_role text; v_name text; v_fee numeric := 0; v_expected numeric;
BEGIN
  v_role := public._pp_staff_guard();
  SELECT * INTO o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found'; END IF;
  IF COALESCE(o.fulfillment_method, 'pickup') = 'pickup' THEN
    RETURN public.record_order_payment(p_order_id, p_amount, p_note);
  END IF;
  IF o.payment_status = 'paid' THEN RAISE EXCEPTION 'The payment of this order is already recorded.'; END IF;
  IF o.status <> 'out_for_delivery' THEN
    RAISE EXCEPTION 'Record the handover once the order is Out for Delivery (current status: %).', o.status;
  END IF;
  IF p_photo_url IS NULL OR btrim(p_photo_url) = '' OR btrim(p_photo_url) NOT ILIKE 'http%' THEN
    RAISE EXCEPTION 'Upload a photo of the delivery first.';
  END IF;
  IF p_amount IS NULL OR p_amount <> round(p_amount, 2) THEN RAISE EXCEPTION 'Enter the amount collected.'; END IF;

  v_fee := public._collect_group_fee(o.checkout_group_id, o.id, 'marketplace');
  v_expected := o.total_price + v_fee;
  IF round(p_amount, 2) <> v_expected THEN
    RAISE EXCEPTION 'AMOUNT_MISMATCH: The amount to collect is %. Check the cash received.', v_expected;
  END IF;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = auth.uid();
  PERFORM set_config('sagana.order_payment', o.id::text, true);
  UPDATE orders
     SET status = 'delivered', delivered_at = NOW(), fulfilled_by = auth.uid(),
         delivery_photo_url = btrim(p_photo_url), delivery_evidence_note = NULLIF(btrim(COALESCE(p_note, '')), ''),
         payment_status = 'paid', paid_at = NOW(), amount_collected = round(p_amount, 2),
         delivery_fee_collected = v_fee,
         payment_recorded_by = auth.uid(), payment_recorded_by_name = v_name, payment_recorded_by_role = v_role,
         payment_note = NULLIF(btrim(COALESCE(p_note, '')), '')
   WHERE id = o.id;
  PERFORM set_config('sagana.order_payment', '', true);

  PERFORM public._order_notify_consumer(o.id, 'Order Handed Over',
    'Your order was handed over and the payment recorded. Check it, then tap Confirm Receipt.');
  RETURN jsonb_build_object('amount_collected', round(p_amount, 2), 'delivery_fee', v_fee);
END;
$$;

-- A delivery is handed over together with the cash, so the old "Delivered" step alone is retired.
CREATE OR REPLACE FUNCTION public.mark_order_delivered(p_order_id UUID, p_photo_url TEXT, p_note TEXT DEFAULT NULL)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RAISE EXCEPTION 'UPDATE_REQUIRED: A delivery is now recorded together with the cash payment (Record Handover). Please update the app.';
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 3. Completing
-- ════════════════════════════════════════════════════════════
-- What happens after ANY completion: the sold figure, the listing, the notices.
CREATE OR REPLACE FUNCTION public._order_after_completion(p_order_id uuid, p_by_staff boolean)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  o orders%ROWTYPE; l marketplace_listings%ROWTYPE; v_name text;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order_id;
  SELECT * INTO l FROM marketplace_listings WHERE id = o.listing_id FOR UPDATE;

  -- Sold = what completed orders add up to (sets the figure, never adds to it).
  PERFORM public.reconcile_batch_sold(l.inventory_batch_id);
  IF l.remaining_kg <= 0 THEN
    UPDATE marketplace_listings SET status = 'sold' WHERE id = l.id AND status <> 'sold';
  END IF;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = o.buyer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (l.farmer_id, 'order', 'Order Completed',
          CASE WHEN p_by_staff THEN 'The cooperative completed the order of ' ELSE COALESCE(v_name, 'The buyer') || ' confirmed receiving ' END ||
            o.quantity_kg || ' ' || COALESCE(o.unit, 'kg') || ' of your ' || COALESCE(l.crop_name, 'produce') || '.',
          FALSE, NOW(), '/farmer/marketplace');

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ur.user_id, 'order', 'Order Completed',
         CASE WHEN p_by_staff THEN 'Staff completed the order of ' ELSE COALESCE(v_name, 'The buyer') || ' confirmed receiving ' END ||
           o.quantity_kg || ' ' || COALESCE(o.unit, 'kg') || ' of ' || COALESCE(l.crop_name, 'produce') || '.',
         FALSE, NOW(), '/admin/marketplace/orders'
  FROM user_roles ur WHERE ur.role IN ('admin', 'officer');
END;
$$;
REVOKE ALL ON FUNCTION public._order_after_completion(uuid, boolean) FROM PUBLIC, anon, authenticated;

-- The consumer confirms receipt (only after the payment is recorded).
CREATE OR REPLACE FUNCTION public.confirm_order_received(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  o orders%ROWTYPE; v_method TEXT;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT * INTO o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND OR o.buyer_id IS DISTINCT FROM auth.uid() THEN RAISE EXCEPTION 'Order not found'; END IF;
  IF o.status = 'completed' THEN RAISE EXCEPTION 'You already confirmed receiving this order.'; END IF;

  v_method := COALESCE(o.fulfillment_method, 'pickup');
  IF v_method = 'pickup' AND o.status <> 'ready_for_pickup' THEN
    RAISE EXCEPTION 'You can confirm receipt once the order is Ready for Pickup (current status: %).', o.status;
  END IF;
  IF v_method = 'delivery' AND o.status <> 'delivered' THEN
    RAISE EXCEPTION 'You can confirm receipt once the order is Delivered (current status: %).', o.status;
  END IF;
  IF o.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'PAYMENT_NOT_RECORDED: You can confirm receipt after the cooperative records your payment.';
  END IF;

  PERFORM set_config('sagana.order_receipt', o.id::text, true);
  PERFORM set_config('sagana.order_payment', o.id::text, true);
  UPDATE orders
     SET status = 'completed', received_at = NOW(), received_by = auth.uid(), completion_method = 'consumer'
   WHERE id = o.id;
  PERFORM set_config('sagana.order_receipt', '', true);
  PERFORM set_config('sagana.order_payment', '', true);

  PERFORM public._order_after_completion(o.id, false);
END;
$$;
REVOKE ALL ON FUNCTION public.confirm_order_received(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.confirm_order_received(UUID) TO authenticated;

-- Staff complete it on the consumer's behalf: reason, photo, identity and time are all recorded.
CREATE OR REPLACE FUNCTION public.staff_complete_order(p_order_id uuid, p_reason text, p_photo_url text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  o orders%ROWTYPE; v_role text; v_name text; v_method text;
BEGIN
  v_role := public._pp_staff_guard();
  IF p_reason IS NULL OR length(btrim(p_reason)) < 5 THEN RAISE EXCEPTION 'Write the reason (at least a few words).'; END IF;
  IF p_photo_url IS NULL OR btrim(p_photo_url) = '' OR btrim(p_photo_url) NOT ILIKE 'http%' THEN
    RAISE EXCEPTION 'Upload a photo as proof first.';
  END IF;
  SELECT * INTO o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found'; END IF;
  IF o.status = 'completed' THEN RAISE EXCEPTION 'This order is already completed.'; END IF;
  IF o.payment_status <> 'paid' THEN
    RAISE EXCEPTION 'PAYMENT_NOT_RECORDED: Record the cash payment and the handover first.';
  END IF;
  v_method := COALESCE(o.fulfillment_method, 'pickup');
  IF NOT ((v_method = 'pickup' AND o.status = 'ready_for_pickup') OR (v_method = 'delivery' AND o.status = 'delivered')) THEN
    RAISE EXCEPTION 'This order cannot be completed yet (current status: %).', o.status;
  END IF;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = auth.uid();
  PERFORM set_config('sagana.order_receipt', o.id::text, true);
  PERFORM set_config('sagana.order_payment', o.id::text, true);
  UPDATE orders
     SET status = 'completed', completion_method = 'staff',
         staff_completion_reason = btrim(p_reason), staff_completion_photo_url = btrim(p_photo_url),
         staff_completed_by = auth.uid(), staff_completed_by_name = v_name, staff_completed_by_role = v_role,
         staff_completed_at = NOW()
   WHERE id = o.id;
  PERFORM set_config('sagana.order_receipt', '', true);
  PERFORM set_config('sagana.order_payment', '', true);

  PERFORM public._order_after_completion(o.id, true);
  PERFORM public._order_notify_consumer(o.id, 'Order Completed', 'Your order was marked completed by the cooperative staff.');
END;
$$;
REVOKE ALL ON FUNCTION public.record_order_payment(uuid, numeric, text)            FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_order_handover(uuid, numeric, text, text)     FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.staff_complete_order(uuid, text, text)               FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_order_payment(uuid, numeric, text)         TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_order_handover(uuid, numeric, text, text)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.staff_complete_order(uuid, text, text)            TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 4. place_order(): optional address id / request id / delivery group
-- ════════════════════════════════════════════════════════════
-- The old 10-argument version is replaced (not overloaded): a call with the old arguments still
-- works, because the three new ones are optional.
DROP FUNCTION IF EXISTS public.place_order(uuid, numeric, text, text, double precision, double precision, text, text, text, text);

CREATE OR REPLACE FUNCTION public.place_order(
  p_listing_id              UUID,
  p_quantity_kg             NUMERIC,
  p_fulfillment_method      TEXT DEFAULT 'pickup',
  p_delivery_address        TEXT DEFAULT NULL,
  p_delivery_latitude       DOUBLE PRECISION DEFAULT NULL,
  p_delivery_longitude      DOUBLE PRECISION DEFAULT NULL,
  p_delivery_contact_number TEXT DEFAULT NULL,
  p_delivery_notes          TEXT DEFAULT NULL,
  p_delivery_recipient_name TEXT DEFAULT NULL,
  p_delivery_label          TEXT DEFAULT NULL,
  p_request_id              UUID DEFAULT NULL,
  p_group_id                UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_buyer_id      UUID := auth.uid();
  v_caller_role   TEXT;
  v_caller_status TEXT;
  v_farmer_id     UUID;
  v_price_per_kg  NUMERIC;
  v_remaining     NUMERIC;
  v_order_id      UUID;
  v_rules_on      BOOLEAN := FALSE;
  g               checkout_groups%ROWTYPE;
BEGIN
  IF v_buyer_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT role, status INTO v_caller_role, v_caller_status FROM user_roles WHERE user_id = v_buyer_id;
  IF v_caller_role IS NULL OR v_caller_role NOT IN ('buyer', 'farmer') THEN
    RAISE EXCEPTION 'Only buyer or farmer accounts can place marketplace orders';
  END IF;
  IF v_caller_status != 'active' THEN
    RAISE EXCEPTION 'Your account has been suspended by the SP3 Administrator. Please contact the cooperative for assistance.';
  END IF;

  IF p_quantity_kg IS NULL OR p_quantity_kg <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero';
  END IF;

  IF p_fulfillment_method NOT IN ('pickup', 'delivery') THEN
    RAISE EXCEPTION 'fulfillment_method must be pickup or delivery';
  END IF;

  -- A retry of the same checkout line returns the same order: no second reservation.
  IF p_request_id IS NOT NULL THEN
    PERFORM pg_advisory_xact_lock(hashtextextended(v_buyer_id::text || p_request_id::text, 51));
    SELECT id INTO v_order_id FROM orders WHERE buyer_id = v_buyer_id AND request_id = p_request_id;
    IF FOUND THEN RETURN v_order_id; END IF;
  END IF;

  IF p_fulfillment_method = 'delivery' THEN
    SELECT (delivery_enabled AND COALESCE(array_length(public._delivery_missing(), 1), 0) = 0)
      INTO v_rules_on FROM delivery_settings WHERE id;
    IF v_rules_on THEN
      -- The new rules: the address and fee come from the server-side snapshot, never from typed text.
      IF p_group_id IS NULL THEN
        RAISE EXCEPTION 'GROUP_REQUIRED: Choose a saved delivery address first.';
      END IF;
      SELECT * INTO g FROM checkout_groups WHERE id = p_group_id AND buyer_id = v_buyer_id;
      IF NOT FOUND THEN
        RAISE EXCEPTION 'GROUP_REQUIRED: The delivery address was not found. Choose it again.';
      END IF;
    ELSE
      IF p_delivery_address IS NULL OR trim(p_delivery_address) = '' THEN
        RAISE EXCEPTION 'A delivery address is required when choosing delivery';
      END IF;
      IF p_delivery_contact_number IS NULL OR trim(p_delivery_contact_number) = '' THEN
        RAISE EXCEPTION 'A contact number is required when choosing delivery';
      END IF;
    END IF;
  END IF;

  SELECT farmer_id, price_per_kg, remaining_kg
  INTO v_farmer_id, v_price_per_kg, v_remaining
  FROM marketplace_listings
  WHERE id = p_listing_id AND status = 'approved'
  FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Listing is no longer available';
  END IF;
  IF v_farmer_id = v_buyer_id THEN
    RAISE EXCEPTION 'You cannot place an order on your own listing';
  END IF;
  IF v_remaining < p_quantity_kg THEN
    RAISE EXCEPTION 'Not enough stock available. Only % kg remaining.', v_remaining;
  END IF;

  UPDATE marketplace_listings
  SET remaining_kg = remaining_kg - p_quantity_kg
  WHERE id = p_listing_id;

  INSERT INTO orders (
    listing_id, farmer_id, buyer_id, quantity_kg, price_per_kg, total_price, status,
    fulfillment_method, delivery_address, delivery_latitude, delivery_longitude,
    delivery_contact_number, delivery_notes, delivery_recipient_name, delivery_label,
    request_id, checkout_group_id
  )
  VALUES (
    p_listing_id, v_farmer_id, v_buyer_id, p_quantity_kg, v_price_per_kg,
    p_quantity_kg * v_price_per_kg, 'pending',
    p_fulfillment_method,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.address_line      ELSE p_delivery_address END,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.latitude          ELSE p_delivery_latitude END,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.longitude         ELSE p_delivery_longitude END,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.contact_number    ELSE p_delivery_contact_number END,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.delivery_notes    ELSE p_delivery_notes END,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.recipient_name    ELSE p_delivery_recipient_name END,
    CASE WHEN p_fulfillment_method <> 'delivery' THEN NULL WHEN v_rules_on THEN g.address_label     ELSE p_delivery_label END,
    p_request_id,
    CASE WHEN p_fulfillment_method = 'delivery' AND v_rules_on THEN g.id ELSE NULL END
  )
  RETURNING id INTO v_order_id;

  RETURN v_order_id;
END;
$$;
REVOKE ALL ON FUNCTION public.place_order(uuid, numeric, text, text, double precision, double precision, text, text, text, text, uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_order(uuid, numeric, text, text, double precision, double precision, text, text, text, text, uuid, uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 5. Officer permission registry
-- ════════════════════════════════════════════════════════════
INSERT INTO public.staff_permission_targets (kind, name, module) VALUES
  ('rpc', 'record_order_payment',  'marketplace'),
  ('rpc', 'record_order_handover', 'marketplace'),
  ('rpc', 'staff_complete_order',  'marketplace')
ON CONFLICT (kind, name) DO UPDATE SET module = EXCLUDED.module;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  One place_order, twelve arguments (the old one is gone):
--     SELECT oid::regprocedure FROM pg_proc WHERE proname = 'place_order' AND pronamespace = 'public'::regnamespace;
-- V2  The order functions exist and are not open to anonymous users:
--     SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--      AND proname IN ('record_order_payment','record_order_handover','staff_complete_order','confirm_order_received');
-- V3  No Marketplace order can be completed without a payment (try as the owner; expect an error):
--     -- UPDATE orders SET status = 'completed' WHERE status = 'ready_for_pickup';   (inside a rolled-back test only)
-- V4  An order Ready for Pickup / Delivered before this script now needs its payment recorded:
--     SELECT order_number, status, fulfillment_method, payment_status FROM orders
--      WHERE status IN ('ready_for_pickup', 'delivered');
