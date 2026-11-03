-- ============================================================
-- SAGANA — Marketplace order fulfillment workflow (Pickup + Delivery)
--
--   PICKUP    pending -> approved -> ready_for_pickup -> completed
--   DELIVERY  pending -> approved -> out_for_delivery -> delivered -> completed
--             (or cancelled, by the consumer, while still pending)
--
--   Consumer (Buyer or Farmer)  places the order, cancels it while PENDING, and
--                               confirms receipt: only from Ready for Pickup
--                               (pickup) or Delivered (delivery).
--   Manager / Officer           approves, then records each fulfillment step by
--                               hand: Ready for Pickup, Out for Delivery, Mark as
--                               Delivered (a photo is REQUIRED). They record the
--                               progress; nothing assumes they carry the order.
--   No "Preparing" status. No Manager rejection (unchanged).
--
-- STOCK (unchanged rules, now guarded by the status flow)
--   The listing's remaining kg drops when the order is placed and returns only if
--   the consumer cancels it while pending. The batch's SOLD figure rises only when
--   the order is COMPLETED, by the existing reconcile trigger, exactly once: a
--   completed order is terminal and confirming twice is refused.
--
-- WHAT THIS FILE CHANGES
--   1. orders: ready_at, out_for_delivery_at, delivered_at, delivery_photo_url,
--      delivery_evidence_note, fulfilled_by; the status CHECK now lists the 7 statuses;
--      a CHECK that a delivered order carries its photo.
--   2. _orders_require_receipt() (the trigger already on orders): the ONLY allowed
--      status moves are the ones in the diagram above, per fulfillment method, and
--      "completed" is still reachable only through confirm_order_received().
--      Anything else (for example the old Manager complete_order, or approved ->
--      completed) is refused with a clear message.
--   3. NEW mark_order_ready_for_pickup(), mark_order_out_for_delivery(),
--      mark_order_delivered(order, photo_url, note): Manager / Officer only.
--   4. confirm_order_received(): now needs Ready for Pickup (pickup order) or
--      Delivered (delivery order).
--   5. Notifications to the consumer at every step, routed to the right screen
--      for a Buyer or for a Farmer.
--
-- ORDERS ALREADY APPROVED when this runs stay "approved": the Manager / Officer
-- now records Ready for Pickup or Out for Delivery for them. A pickup / delivery
-- order with no recorded method is treated as pickup.
--
-- Run supabase_schema_farmer_stock_management.sql first. Safe to re-run.
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ──────────────────────────────────────────────
-- A. Orders by status and method (these will keep working):
--    SELECT status, COALESCE(fulfillment_method,'(none)') AS method, count(*)
--    FROM orders GROUP BY 1,2 ORDER BY 1,2;
-- B. Orders in statuses this file would reject (expect 0 rows):
--    SELECT id, status FROM orders
--    WHERE status NOT IN ('pending','approved','completed','cancelled');
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.confirm_order_received(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_farmer_stock_management.sql first (confirm_order_received is missing).';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema='public' AND table_name='orders' AND column_name='fulfillment_method') THEN
    RAISE EXCEPTION 'orders.fulfillment_method is missing (checkout fulfillment script).';
  END IF;
  IF to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_staff() is missing.';
  END IF;
END;
$$;

-- ═══ 1. Columns and the status rule ═════════════════════════════════════
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS ready_at            TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS out_for_delivery_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivered_at        TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS delivery_photo_url  TEXT,
  ADD COLUMN IF NOT EXISTS delivery_evidence_note       TEXT,
  ADD COLUMN IF NOT EXISTS fulfilled_by        UUID REFERENCES auth.users(id) ON DELETE SET NULL;

DO $$
DECLARE c RECORD;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.orders'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%status%'
      AND pg_get_constraintdef(oid) ILIKE '%pending%'
  LOOP
    EXECUTE format('ALTER TABLE public.orders DROP CONSTRAINT %I', c.conname);
  END LOOP;
END;
$$;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
  CHECK (status IN ('pending', 'approved', 'ready_for_pickup', 'out_for_delivery',
                    'delivered', 'completed', 'cancelled'));

-- A delivered order always carries its photo evidence.
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_delivered_needs_photo;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_delivered_needs_photo
  CHECK (status <> 'delivered' OR (delivery_photo_url IS NOT NULL AND btrim(delivery_photo_url) <> ''));

-- ═══ 2. The only legal status moves ═════════════════════════════════════
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

  -- Completion is the consumer's confirmation and nothing else.
  IF NEW.status = 'completed'
     AND current_setting('sagana.order_receipt', true) IS DISTINCT FROM NEW.id::text THEN
    RAISE EXCEPTION 'An order is completed when the buyer confirms they received it.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_orders_require_receipt ON public.orders;
CREATE TRIGGER trg_orders_require_receipt
  BEFORE UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._orders_require_receipt();

-- ═══ 3. Notification helper ═════════════════════════════════════════════
-- Tells the consumer (Buyer or Farmer) and opens the right orders screen.
CREATE OR REPLACE FUNCTION public._order_notify_consumer(p_order_id UUID, p_title TEXT, p_body TEXT)
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT o.buyer_id, 'order', p_title, p_body, FALSE, NOW(),
         CASE WHEN EXISTS (SELECT 1 FROM user_roles ur WHERE ur.user_id = o.buyer_id AND ur.role = 'farmer')
              THEN '/farmer/profile/orders' ELSE '/buyer/orders' END
  FROM orders o WHERE o.id = p_order_id;
$$;
REVOKE ALL ON FUNCTION public._order_notify_consumer(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- ═══ 4. Manager / Officer: record the fulfillment steps ═════════════════
CREATE OR REPLACE FUNCTION public.mark_order_ready_for_pickup(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o orders%ROWTYPE;
  v_crop TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can update an order''s fulfillment.';
  END IF;
  SELECT * INTO o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF o.status = 'ready_for_pickup' THEN
    RAISE EXCEPTION 'This order is already marked Ready for Pickup.';
  END IF;
  IF COALESCE(o.fulfillment_method, 'pickup') <> 'pickup' THEN
    RAISE EXCEPTION 'This is a delivery order. Use Out for Delivery instead.';
  END IF;
  IF o.status <> 'approved' THEN
    RAISE EXCEPTION 'Only an approved order can be marked Ready for Pickup (current status: %).', o.status;
  END IF;

  UPDATE orders
     SET status = 'ready_for_pickup', ready_at = NOW(), fulfilled_by = auth.uid()
   WHERE id = o.id;

  SELECT crop_name INTO v_crop FROM marketplace_listings WHERE id = o.listing_id;
  PERFORM public._order_notify_consumer(o.id, 'Order Ready for Pickup',
    'Your order for ' || COALESCE(v_crop, 'produce') ||
    ' is ready. Collect it at Barangay Payanas, then tap Confirm Receipt.');
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_order_out_for_delivery(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o orders%ROWTYPE;
  v_crop TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can update an order''s fulfillment.';
  END IF;
  SELECT * INTO o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF o.status = 'out_for_delivery' THEN
    RAISE EXCEPTION 'This order is already marked Out for Delivery.';
  END IF;
  IF COALESCE(o.fulfillment_method, 'pickup') <> 'delivery' THEN
    RAISE EXCEPTION 'This is a pickup order. Use Ready for Pickup instead.';
  END IF;
  IF o.status <> 'approved' THEN
    RAISE EXCEPTION 'Only an approved order can be marked Out for Delivery (current status: %).', o.status;
  END IF;

  UPDATE orders
     SET status = 'out_for_delivery', out_for_delivery_at = NOW(), fulfilled_by = auth.uid()
   WHERE id = o.id;

  SELECT crop_name INTO v_crop FROM marketplace_listings WHERE id = o.listing_id;
  PERFORM public._order_notify_consumer(o.id, 'Order Out for Delivery',
    'Your order for ' || COALESCE(v_crop, 'produce') || ' is out for delivery.');
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_order_delivered(
  p_order_id  UUID,
  p_photo_url TEXT,
  p_note      TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o orders%ROWTYPE;
  v_crop TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can update an order''s fulfillment.';
  END IF;
  SELECT * INTO o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF o.status = 'delivered' THEN
    RAISE EXCEPTION 'This order is already marked Delivered.';
  END IF;
  IF o.status <> 'out_for_delivery' THEN
    RAISE EXCEPTION 'Only an order that is Out for Delivery can be marked Delivered (current status: %).', o.status;
  END IF;
  IF p_photo_url IS NULL OR btrim(p_photo_url) = '' OR btrim(p_photo_url) NOT ILIKE 'http%' THEN
    RAISE EXCEPTION 'Upload a photo of the delivery first.';
  END IF;

  UPDATE orders
     SET status = 'delivered', delivered_at = NOW(), fulfilled_by = auth.uid(),
         delivery_photo_url = btrim(p_photo_url), delivery_evidence_note = NULLIF(btrim(p_note), '')
   WHERE id = o.id;

  SELECT crop_name INTO v_crop FROM marketplace_listings WHERE id = o.listing_id;
  PERFORM public._order_notify_consumer(o.id, 'Order Delivered',
    'Your order for ' || COALESCE(v_crop, 'produce') ||
    ' was delivered. Check it, then tap Confirm Receipt.');
END;
$$;

REVOKE ALL ON FUNCTION public.mark_order_ready_for_pickup(UUID)         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_order_out_for_delivery(UUID)         FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_order_delivered(UUID, TEXT, TEXT)    FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_order_ready_for_pickup(UUID)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_order_out_for_delivery(UUID)      TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_order_delivered(UUID, TEXT, TEXT) TO authenticated;

-- ═══ 5. Consumer: confirm receipt only when it is really ready / delivered ══
CREATE OR REPLACE FUNCTION public.confirm_order_received(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o         orders%ROWTYPE;
  l         marketplace_listings%ROWTYPE;
  v_method  TEXT;
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

  v_method := COALESCE(o.fulfillment_method, 'pickup');
  IF v_method = 'pickup' AND o.status <> 'ready_for_pickup' THEN
    RAISE EXCEPTION 'You can confirm receipt once the order is Ready for Pickup (current status: %).', o.status;
  END IF;
  IF v_method = 'delivery' AND o.status <> 'delivered' THEN
    RAISE EXCEPTION 'You can confirm receipt once the order is Delivered (current status: %).', o.status;
  END IF;

  SELECT * INTO l FROM marketplace_listings WHERE id = o.listing_id FOR UPDATE;

  PERFORM set_config('sagana.order_receipt', o.id::text, true);
  UPDATE orders
     SET status = 'completed', received_at = NOW(), received_by = auth.uid()
   WHERE id = o.id;
  PERFORM set_config('sagana.order_receipt', '', true);

  -- Sold = what completed orders add up to (sets the figure, never adds to it).
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

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. Status rule has 7 values:
--    SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'orders_status_check';
-- 2. Functions exist (expect 4 rows):
--    SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--      AND proname IN ('mark_order_ready_for_pickup','mark_order_out_for_delivery',
--                      'mark_order_delivered','confirm_order_received');
-- 3. No delivered order lacks a photo (expect 0):
--    SELECT count(*) FROM orders WHERE status='delivered' AND delivery_photo_url IS NULL;
-- 4. Sold figures still agree with completed orders (expect 0 rows):
--    SELECT b.batch_number FROM inventory_batches b
--    WHERE b.sold_kg < COALESCE((SELECT sum(o.quantity_kg) FROM orders o
--          JOIN marketplace_listings l ON l.id=o.listing_id
--          WHERE l.inventory_batch_id=b.id AND o.status='completed'),0) - 0.005;
-- ─────────────────────────────────────────────────────────────────────────
