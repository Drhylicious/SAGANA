-- ─────────────────────────────────────────────────────────────────────────────
-- batch0_02_order_rejected_and_cancellation.sql
-- Batch 0 (0B + 0C + 0D) of the approved implementation plan.
--
-- Rejected and Cancelled become separate order statuses:
--   rejected  — the Admin/Officer rejected the order ("Reject Order").
--   cancelled — the Buyer or Farmer cancelled their own pending order.
--
-- Existing data: orders cancelled by the Admin with reason "reject" are
-- reclassified as rejected (approved decision 7). Their notes are kept, so
-- nothing is lost. Other cancelled orders are left as they are.
--
-- Not applied yet. Review this file before running it in Supabase.
-- Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── 0B. Allow the 'rejected' status ─────────────────────────────────────────
-- The original status check (supabase_schema_fixes.sql) allows only
-- pending/approved/completed/cancelled. Its name is not guaranteed, so every
-- check constraint on orders that mentions status is dropped first.
DO $$
DECLARE
  v_name TEXT;
BEGIN
  FOR v_name IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.orders'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) ILIKE '%status%'
  LOOP
    EXECUTE format('ALTER TABLE public.orders DROP CONSTRAINT %I', v_name);
  END LOOP;
END $$;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
  CHECK (status IN ('pending', 'approved', 'completed', 'cancelled', 'rejected'));

-- ─── 0B. Backfill: Admin rejections recorded as cancellations ────────────────
-- cancel_order stored the reason in orders.notes (see the live definition).
-- Only orders whose reason is exactly "reject" are reclassified.
UPDATE public.orders
SET status = 'rejected'
WHERE status = 'cancelled'
  AND notes = 'reject';

-- ─── 0D. cancel_order: Admin/Officer action is a rejection ───────────────────
-- The Admin/Officer's only cancel action is "Reject Order", so the status is
-- now 'rejected'. The Buyer and Farmer are notified with "Order Rejected".
-- Reservation release is unchanged from the live definition.
CREATE OR REPLACE FUNCTION public.cancel_order(p_order_id uuid, p_reason text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status      TEXT;
  v_listing_id  UUID;
  v_quantity_kg NUMERIC;
  v_buyer_id    UUID;
  v_farmer_id   UUID;
  v_crop_name   TEXT;
BEGIN
  IF NOT public.is_staff() AND NOT EXISTS (SELECT 1 FROM officer_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can reject orders';
  END IF;

  SELECT status, listing_id, quantity_kg
  INTO v_status, v_listing_id, v_quantity_kg
  FROM orders WHERE id = p_order_id FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Order cannot be rejected once approved — current status: %', v_status;
  END IF;

  SELECT buyer_id INTO v_buyer_id FROM orders WHERE id = p_order_id;
  SELECT crop_name, farmer_id INTO v_crop_name, v_farmer_id
  FROM marketplace_listings WHERE id = v_listing_id;

  UPDATE marketplace_listings
  SET remaining_kg = remaining_kg + v_quantity_kg,
      status = CASE WHEN status = 'sold' THEN 'approved' ELSE status END
  WHERE id = v_listing_id;

  UPDATE orders
  SET status = 'rejected', notes = COALESCE(p_reason, notes)
  WHERE id = p_order_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_buyer_id, 'order', 'Order Rejected',
    'Your order for ' || COALESCE(v_crop_name, 'produce') || ' was rejected.' ||
      CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END,
    FALSE, NOW(), '/buyer/orders'
  );

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_farmer_id, 'order', 'Order Rejected',
    'An order for your ' || COALESCE(v_crop_name, 'produce') || ' listing was rejected.' ||
      CASE WHEN p_reason IS NOT NULL THEN ' Reason: ' || p_reason ELSE '' END,
    FALSE, NOW(), '/farmer/marketplace'
  );
END;
$function$;

-- ─── 0C. cancel_my_order: Buyer or Farmer cancels their own pending order ────
-- The caller must be the buyer who placed the order (a Farmer who placed an
-- order is a buyer for that order). Only pending orders can be cancelled.
-- Staff are notified with the canceller's name; the listing's farmer is
-- notified. The buyer is not notified of their own action.
CREATE OR REPLACE FUNCTION public.cancel_my_order(p_order_id uuid, p_reason text DEFAULT NULL::text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_caller      UUID := auth.uid();
  v_status      TEXT;
  v_listing_id  UUID;
  v_quantity_kg NUMERIC;
  v_buyer_id    UUID;
  v_farmer_id   UUID;
  v_crop_name   TEXT;
  v_name        TEXT;
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

  SELECT crop_name, farmer_id INTO v_crop_name, v_farmer_id
  FROM marketplace_listings WHERE id = v_listing_id;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_caller;

  UPDATE marketplace_listings
  SET remaining_kg = remaining_kg + v_quantity_kg,
      status = CASE WHEN status = 'sold' THEN 'approved' ELSE status END
  WHERE id = v_listing_id;

  UPDATE orders
  SET status = 'cancelled', notes = COALESCE(p_reason, notes)
  WHERE id = p_order_id;

  PERFORM public.notify_staff(
    'order',
    'Order Cancelled by Buyer',
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
$function$;

GRANT EXECUTE ON FUNCTION public.cancel_my_order(uuid, text) TO authenticated;

-- ─── Verification (run after applying) ───────────────────────────────────────
--   select status, count(*) from orders group by status;                    -- rejected appears
--   select count(*) from orders where status = 'cancelled' and notes = 'reject';   -- expect 0
--   select proname from pg_proc where proname in ('cancel_order','cancel_my_order');   -- 2 rows
