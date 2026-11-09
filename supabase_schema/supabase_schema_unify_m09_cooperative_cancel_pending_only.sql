-- ============================================================
-- SAGANA — Cooperative orders: the same cancel rule as Marketplace orders
--
-- FOR YOUR REVIEW — NOT APPLIED. Run it once in the Supabase SQL editor (after m01-m08), then
-- the CHECKS at the bottom. One transaction, safe to re-run.
--
-- THE RULE (confirmed)
--   Only the Farmer who placed the order can cancel it, and only while it is Pending. Once an
--   order is Approved it cannot be cancelled by anyone: it goes on to Ready for Pickup or Out
--   for Delivery. The Manager and Officers have no cancel, exactly as for a Marketplace order.
--
-- WHAT CHANGES (two functions, both defined in m04; nothing else is touched)
--   1. _program_orders_guard()      Approved, Ready for Pickup and Out for Delivery can no longer
--                                   become Cancelled; only Pending can.
--   2. cancel_program_purchase()    the staff branch is gone; the Farmer's own Pending cancel is
--                                   as before (reserved stock goes back, staff are told).
-- NOT CHANGED: tables, columns, policies, grants, orders already Cancelled, the payment rules.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public._program_orders_guard()
RETURNS trigger LANGUAGE plpgsql SET search_path TO 'public' AS $$
BEGIN
  IF (NEW.farmer_id, NEW.program_id, NEW.product_id, NEW.quantity, NEW.unit_price, NEW.total_amount,
      NEW.regular_unit_price, NEW.discount_percent, NEW.discount_amount, NEW.is_member_price,
      NEW.order_number, NEW.fulfillment_method)
     IS DISTINCT FROM
     (OLD.farmer_id, OLD.program_id, OLD.product_id, OLD.quantity, OLD.unit_price, OLD.total_amount,
      OLD.regular_unit_price, OLD.discount_percent, OLD.discount_amount, OLD.is_member_price,
      OLD.order_number, OLD.fulfillment_method) THEN
    RAISE EXCEPTION 'The price, quantity and method of an order cannot be changed.';
  END IF;
  IF OLD.payment_status = 'paid' AND (NEW.payment_status, NEW.paid_at, NEW.amount_collected)
       IS DISTINCT FROM (OLD.payment_status, OLD.paid_at, OLD.amount_collected) THEN
    RAISE EXCEPTION 'A recorded payment cannot be changed.';
  END IF;
  IF NEW.status IS DISTINCT FROM OLD.status THEN
    IF NOT (
         (OLD.status = 'pending'          AND NEW.status IN ('approved', 'cancelled'))
      OR (OLD.status = 'approved'         AND ((NEW.status = 'ready_for_pickup' AND OLD.fulfillment_method = 'pickup')
                                            OR (NEW.status = 'out_for_delivery' AND OLD.fulfillment_method = 'delivery')))
      OR (OLD.status = 'ready_for_pickup' AND NEW.status = 'completed')
      OR (OLD.status = 'out_for_delivery' AND NEW.status = 'delivered')
      OR (OLD.status = 'delivered'        AND NEW.status = 'completed')
    ) THEN
      RAISE EXCEPTION 'An order cannot move from % to %.', OLD.status, NEW.status;
    END IF;
    IF NEW.status = 'completed' THEN
      IF NEW.payment_status IS DISTINCT FROM 'paid' THEN
        RAISE EXCEPTION 'An order is completed only after the payment is recorded.';
      END IF;
      IF current_setting('sagana.program_order_rpc', true) IS DISTINCT FROM NEW.id::text THEN
        RAISE EXCEPTION 'An order is completed by the Farmer confirming receipt, or by staff with a reason and a photo.';
      END IF;
    END IF;
    IF NEW.status IN ('delivered') AND NEW.payment_status IS DISTINCT FROM 'paid' THEN
      RAISE EXCEPTION 'A delivery is handed over together with the cash payment.';
    END IF;
    IF NEW.status = 'cancelled' AND OLD.payment_status = 'paid' THEN
      RAISE EXCEPTION 'An order that was paid cannot be cancelled.';
    END IF;
  END IF;
  RETURN NEW;
END $$;

CREATE OR REPLACE FUNCTION public.cancel_program_purchase(p_purchase_id uuid, p_reason text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  o program_product_purchases%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;
  SELECT * INTO o FROM program_product_purchases WHERE id = p_purchase_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found.'; END IF;
  -- Like a Marketplace order: only the Farmer who placed it cancels it, and only while Pending.
  -- Staff (Manager or Officer) have no cancel: once approved, the order goes on to Ready for
  -- Pickup or Out for Delivery.
  IF o.farmer_id <> auth.uid() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only the Farmer who placed an order can cancel it, and only while it is Pending.';
  END IF;
  IF o.status <> 'pending' THEN RAISE EXCEPTION 'You can cancel an order only while it is Pending.'; END IF;

  UPDATE program_product_purchases
     SET status = 'cancelled', cancelled_at = NOW(), cancel_reason = NULLIF(btrim(COALESCE(p_reason, '')), ''),
         cancelled_by = auth.uid(), cancelled_by_role = 'farmer'
   WHERE id = o.id;
  -- The reserved stock goes back.
  UPDATE program_products SET stock_reserved = GREATEST(stock_reserved - o.quantity, 0) WHERE id = o.product_id;
  PERFORM public._pp_notify_staff('Order Cancelled', 'A Farmer cancelled the pending order ' || o.order_number || '.');
END $$;
REVOKE ALL ON FUNCTION public.cancel_program_purchase(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.cancel_program_purchase(uuid, text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECKS (read-only; run after the script)
-- ============================================================
-- C1  The guard no longer lists Cancelled after Approved / Ready / Out for Delivery. Read it:
--     SELECT pg_get_functiondef('public._program_orders_guard()'::regprocedure);
--     -- the "OLD.status = 'pending'" line is the ONLY one that mentions 'cancelled'.
-- C2  The function no longer has a staff branch (expect false):
--     SELECT pg_get_functiondef('public.cancel_program_purchase(uuid,text)'::regprocedure) ILIKE '%is_staff()%' AS has_staff_branch;
-- C3  In the app: as Manager, open an Approved Cooperative order: there is no Cancel button.
--     As the Farmer, a Pending order still has Cancel; an Approved one does not.
