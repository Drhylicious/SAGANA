-- ============================================================
-- SAGANA — Officer access to Marketplace order approval and fulfillment
--
-- A Manager (admin) and an Officer share the order workflow:
--     approve  ->  Ready for Pickup / Out for Delivery  ->  Mark as Delivered
-- The repository's SQL history holds two versions of approve_order(): one that
-- checks admin_profiles only (an Officer would be refused with "only admins can
-- approve orders") and one that also allows Officers. Which one is live depends on
-- what was run last, so this file makes it certain.
--
-- WHAT THIS FILE DOES
--   1. approve_order(): the same behaviour as before (pending -> approved, once,
--      with a notice to the consumer and to the seller Farmer) for ANY staff role
--      (Manager or Officer, via is_staff()). The notice now reads for the order's
--      method and no longer says "being prepared" (there is no Preparing status),
--      and a Farmer consumer is sent to their own My Orders screen.
--   2. Grants EXECUTE on approve_order and on the three fulfillment functions to
--      signed-in users (each one re-checks the role itself).
--   3. Makes sure staff can READ what the order screens read: orders, and the
--      names / phones of the people who ordered. Adds a read-only policy only when
--      none exists for staff on that table; never removes or loosens a write rule.
--
-- WHAT IT DOES NOT CHANGE: rejection (there is none), cancellation (the consumer,
-- while pending), completion (the consumer's confirmation only), stock.
--
-- Run supabase_schema_order_fulfillment_workflow.sql first.
-- Then run supabase_schema_officer_order_access_test.sql. Safe to re-run.
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ──────────────────────────────────────────────
-- A. Who is an Officer, and are they in user_roles (what is_staff() reads)?
--    SELECT r.user_id, r.role, r.status FROM user_roles r WHERE r.role = 'officer';
-- B. Which version of approve_order is live (look for "is_staff" in the text):
--    SELECT pg_get_functiondef(p.oid) FROM pg_proc p
--    WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'approve_order';
-- C. Policies on orders and user_information that mention staff:
--    SELECT tablename, policyname, cmd, qual FROM pg_policies
--    WHERE tablename IN ('orders', 'user_information') ORDER BY 1, 2;
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_staff() is missing.';
  END IF;
  IF to_regprocedure('public._order_notify_consumer(uuid, text, text)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_order_fulfillment_workflow.sql first (_order_notify_consumer is missing).';
  END IF;
END;
$$;

-- ═══ 1. approve_order for a Manager or an Officer ═══════════════════════
CREATE OR REPLACE FUNCTION public.approve_order(p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o        orders%ROWTYPE;
  v_crop   TEXT;
  v_method TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can approve orders';
  END IF;

  SELECT * INTO o FROM orders WHERE id = p_order_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Already moved on (approved, cancelled, ...): nothing to do, not an error.
  IF o.status <> 'pending' THEN
    RETURN FALSE;
  END IF;

  UPDATE orders SET status = 'approved' WHERE id = o.id;

  SELECT crop_name INTO v_crop FROM marketplace_listings WHERE id = o.listing_id;
  v_method := COALESCE(o.fulfillment_method, 'pickup');

  PERFORM public._order_notify_consumer(o.id, 'Order Approved',
    'Your order for ' || COALESCE(v_crop, 'produce') || ' has been approved. You will be told when it is ' ||
    CASE WHEN v_method = 'delivery' THEN 'out for delivery.' ELSE 'ready for pickup.' END);

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    o.farmer_id, 'order', 'Order Approved',
    'An order for your ' || COALESCE(v_crop, 'produce') || ' listing has been approved.',
    FALSE, NOW(), '/farmer/marketplace'
  );

  RETURN TRUE;
END;
$$;

-- ═══ 2. Who may call the order functions (each re-checks the role itself) ═══
REVOKE ALL ON FUNCTION public.approve_order(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_order(UUID)                      TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_order_ready_for_pickup(UUID)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_order_out_for_delivery(UUID)        TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_order_delivered(UUID, TEXT, TEXT)   TO authenticated;

-- ═══ 3. Staff can read what the order screens show ══════════════════════
-- Orders: the existing "Admin full access to orders" policy normally covers staff.
-- Add a read-only one only if nothing on orders mentions is_staff().
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies
                 WHERE schemaname = 'public' AND tablename = 'orders'
                   AND qual ILIKE '%is_staff%') THEN
    CREATE POLICY "orders: staff reads all"
      ON public.orders FOR SELECT TO authenticated
      USING (public.is_staff());
  END IF;

  -- The order detail shows the consumer's name, phone and photo.
  IF to_regclass('public.user_information') IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM pg_policies
       WHERE schemaname = 'public' AND tablename = 'user_information'
         AND cmd IN ('SELECT', 'ALL') AND qual ILIKE '%is_staff%') THEN
    CREATE POLICY "user_information: staff reads"
      ON public.user_information FOR SELECT TO authenticated
      USING (public.is_staff());
  END IF;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. approve_order allows staff (expect true):
--    SELECT pg_get_functiondef(p.oid) ILIKE '%is_staff()%' FROM pg_proc p
--    WHERE p.pronamespace='public'::regnamespace AND p.proname='approve_order';
-- 2. Every Officer is in user_roles (expect 0 rows; a row here is an Officer the
--    database does not recognise as staff):
--    SELECT o.user_id FROM officer_profiles o
--    WHERE NOT EXISTS (SELECT 1 FROM user_roles r WHERE r.user_id = o.user_id AND r.role = 'officer');
-- ─────────────────────────────────────────────────────────────────────────
