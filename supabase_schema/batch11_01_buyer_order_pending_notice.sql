-- batch11_01_buyer_order_pending_notice.sql
--
-- Buyer is notified when an order reaches Pending Review (the order is placed
-- and waiting for the Admin/Officer). Decision confirmed by the user.
--
-- Staff are already notified on insert by trg_notify_staff_order_placed
-- (supabase_schema_phase2_notification_completeness.sql). This adds the matching
-- notice to the person who placed the order. Like the staff notice, it fires
-- on every order insert, so it covers Buyer and Farmer placers alike.
--
-- Run once in the Supabase SQL editor. Safe to re-run.

CREATE OR REPLACE FUNCTION public.fn_notify_buyer_order_pending()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_crop TEXT;
  v_role TEXT;
  v_route TEXT;
BEGIN
  SELECT crop_name INTO v_crop FROM marketplace_listings WHERE id = NEW.listing_id;

  -- A farmer placing an order as a consumer is routed to the farmer order list.
  SELECT role INTO v_role FROM user_roles WHERE user_id = NEW.buyer_id;
  v_route := CASE WHEN v_role = 'farmer' THEN '/farmer/orders' ELSE '/buyer/orders' END;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    NEW.buyer_id,
    'order',
    'Order Pending Review',
    'Your order for ' || COALESCE(v_crop, 'produce') || ' was placed and is pending review.',
    FALSE,
    NOW(),
    v_route
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_buyer_order_pending ON orders;
CREATE TRIGGER trg_notify_buyer_order_pending
  AFTER INSERT ON orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_buyer_order_pending();

-- ─── Verification ──────────────────────────────────────────────────────────
-- select tgname from pg_trigger where tgname = 'trg_notify_buyer_order_pending';  -- 1 row
