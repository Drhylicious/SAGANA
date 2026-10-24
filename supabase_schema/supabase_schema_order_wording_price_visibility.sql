-- ============================================================
-- SAGANA — Order wording, Cooperative price visibility, live market-type updates
--
-- Requires supabase_schema_market_rules_by_data.sql (it provides
-- can_view_market_type()). This file stops with a clear message if that script
-- has not been run.
--
--   1. ORDER WORDING (Buyer, Farmer, Manager notifications)
--        "Pending Review" -> "Pending Order"      "Rejected" -> "Disapproved"
--      The stored order status values ('pending', 'rejected') do NOT change;
--      only the words people read. Notices are written by several database
--      functions, so (as for the Manager wording in registration step 6) the
--      wording is applied as each order notice is stored, by a trigger, and
--      existing order notices are re-worded once. Only these exact phrases are
--      touched, so a Manager's typed reason is never altered.
--
--   2. COOPERATIVE PRICES HIDDEN FROM BUYERS
--      * price_records: a restrictive read policy, same rule as listings
--        (can_view_market_type). Buyers read Public Market prices only;
--        Farmers and Staff read both.
--      * notify_price_update(): a price notice for a market Buyers cannot see
--        is no longer sent to Buyers. New optional argument p_price_type; the
--        old 4-argument version is replaced (the app passes the new argument).
--        If the type is not given, Buyers are NOT notified (the safe default).
--
--   3. LIVE MARKET-TYPE UPDATES
--      market_types and selling_channels join the realtime publication so the
--      app can refresh its copy without a restart or a new sign-in.
--
-- Not applied automatically. Run in the Supabase SQL editor, then run the
-- verification block at the end.
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF to_regprocedure('public.can_view_market_type(text, uuid)') IS NULL THEN
    RAISE EXCEPTION 'Run supabase_schema_market_rules_by_data.sql first (can_view_market_type() is missing).';
  END IF;
END;
$$;

-- ═══ 1. ORDER WORDING ═══════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.notifications_order_wording()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.type = 'order' THEN
    NEW.title := CASE NEW.title
      WHEN 'Order Rejected'       THEN 'Order Disapproved'
      WHEN 'Order Pending Review' THEN 'Pending Order'
      ELSE NEW.title
    END;
    -- First occurrence only, so any reason the Manager typed after it is left alone.
    NEW.body := regexp_replace(NEW.body, ' was rejected\.', ' was disapproved.');
    NEW.body := regexp_replace(NEW.body, 'is pending review\.', 'is now a pending order.');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notifications_order_wording ON public.notifications;
CREATE TRIGGER trg_notifications_order_wording
  BEFORE INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.notifications_order_wording();

-- Re-word the order notices already sent (stored text only; nothing deleted).
UPDATE public.notifications
SET title = CASE title
      WHEN 'Order Rejected'       THEN 'Order Disapproved'
      WHEN 'Order Pending Review' THEN 'Pending Order'
      ELSE title
    END,
    body = regexp_replace(
             regexp_replace(body, ' was rejected\.', ' was disapproved.'),
             'is pending review\.', 'is now a pending order.')
WHERE type = 'order'
  AND (title IN ('Order Rejected', 'Order Pending Review')
       OR body ~ ' was rejected\.' OR body ~ 'is pending review\.');

-- ═══ 2. COOPERATIVE PRICES HIDDEN FROM BUYERS ═══════════════════════════

DROP POLICY IF EXISTS "price_records: restricted markets hidden from buyers"
  ON public.price_records;
CREATE POLICY "price_records: restricted markets hidden from buyers"
  ON public.price_records
  AS RESTRICTIVE
  FOR SELECT
  TO authenticated
  USING (public.can_view_market_type(price_type));

-- Live body from batch9_01_decision_notices.sql, with one new argument and a
-- recipient rule: Buyers only hear about prices in markets they can see.
DROP FUNCTION IF EXISTS public.notify_price_update(TEXT, NUMERIC, TEXT, NUMERIC);

CREATE OR REPLACE FUNCTION public.notify_price_update(
  p_crop_name TEXT,
  p_new_price NUMERIC,
  p_unit TEXT,
  p_previous_price NUMERIC DEFAULT NULL,
  p_price_type TEXT DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
  v_change TEXT;
  v_buyers_see BOOLEAN;
BEGIN
  IF NOT (
    public.is_platform_admin(auth.uid())
    OR EXISTS (SELECT 1 FROM officer_profiles o WHERE o.user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can announce price updates';
  END IF;

  IF p_previous_price IS NOT NULL AND p_previous_price = p_new_price THEN
    RETURN 0;
  END IF;

  -- Buyers are told only when the market's prices are visible to Buyers.
  -- An unknown type is treated as "not visible".
  v_buyers_see := COALESCE(
    (SELECT mt.buyer_visible FROM market_types mt WHERE mt.code = p_price_type),
    FALSE
  );

  v_change := CASE
    WHEN p_previous_price IS NULL THEN
      'set the reference price of ' || p_crop_name || ' to ₱' ||
        TO_CHAR(p_new_price, 'FM999999990.00') || '/' || p_unit
    WHEN p_new_price > p_previous_price THEN
      'increased the price of ' || p_crop_name || ' from ₱' ||
        TO_CHAR(p_previous_price, 'FM999999990.00') || ' to ₱' ||
        TO_CHAR(p_new_price, 'FM999999990.00') || '/' || p_unit
    ELSE
      'decreased the price of ' || p_crop_name || ' from ₱' ||
        TO_CHAR(p_previous_price, 'FM999999990.00') || ' to ₱' ||
        TO_CHAR(p_new_price, 'FM999999990.00') || '/' || p_unit
  END;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ur.user_id,
    'price',
    'Price Update: ' || p_crop_name,
    'SP3 Admin ' || v_change || '. ' ||
      CASE
        WHEN ur.role = 'buyer' THEN 'Check the Prices tab for the latest market rates.'
        ELSE 'Check the Analytics tab for the latest market rates.'
      END,
    FALSE,
    NOW(),
    CASE WHEN ur.role = 'buyer' THEN '/buyer/prices' ELSE '/farmer/analytics' END
  FROM user_roles ur
  WHERE ur.status = 'active'
    AND (ur.role = 'farmer' OR (ur.role = 'buyer' AND v_buyers_see));

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_price_update(TEXT, NUMERIC, TEXT, NUMERIC, TEXT)
  TO authenticated;

-- ═══ 3. LIVE MARKET-TYPE UPDATES ════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                 WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'market_types') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.market_types;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables
                 WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'selling_channels') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.selling_channels;
  END IF;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION ────────────────────────────────────────────
-- 1. Objects exist (expect 1 trigger, 1 policy, 1 five-argument function, 2 publication rows):
--    SELECT tgname FROM pg_trigger WHERE tgname='trg_notifications_order_wording';
--    SELECT policyname, permissive FROM pg_policies WHERE tablename='price_records'
--      AND policyname LIKE '%hidden from buyers';                          -- RESTRICTIVE
--    SELECT oid::regprocedure FROM pg_proc WHERE proname='notify_price_update';
--    SELECT tablename FROM pg_publication_tables WHERE pubname='supabase_realtime'
--      AND tablename IN ('market_types','selling_channels');
--
-- 2. Existing order notices re-worded (expect 0 rows):
--    SELECT id, title FROM notifications WHERE type='order'
--      AND (title IN ('Order Rejected','Order Pending Review') OR body ~ ' was rejected\.');
--
-- 3. Wording trigger (expect "Order Disapproved" / "... was disapproved. Reason: it was rejected before"); nothing kept:
--    BEGIN;
--      INSERT INTO notifications (user_id, type, title, body, is_read)
--      SELECT user_id, 'order', 'Order Rejected',
--             'Your order for Tomato was rejected. Reason: it was rejected before', FALSE
--      FROM user_roles WHERE role='buyer' LIMIT 1
--      RETURNING title, body;
--    ROLLBACK;
--
-- 4. A Buyer reads Public Market prices only (replace the id with a buyer, e.g. amane):
--    BEGIN;
--      SELECT set_config('request.jwt.claims',
--        json_build_object('sub','<BUYER_USER_ID>','role','authenticated')::text, true);
--      SET LOCAL ROLE authenticated;
--      SELECT price_type, count(*) FROM public.price_records GROUP BY 1;   -- expect open_market only
--    ROLLBACK;
--    Repeat with an active farmer: expect open_market AND sp3_cooperative.
--
-- 5. Price notice recipients (nothing kept): a Cooperative price update must not reach Buyers.
--    BEGIN;
--      SELECT set_config('request.jwt.claims',
--        json_build_object('sub','<MANAGER_USER_ID>','role','authenticated')::text, true);
--      SET LOCAL ROLE authenticated;
--      SELECT public.notify_price_update('Palay', 30, 'kg', 25, 'sp3_cooperative');  -- = number of active FARMERS
--      SELECT public.notify_price_update('Tomato', 60, 'kg', 55, 'open_market');      -- = active farmers + buyers
--    ROLLBACK;
--
-- 6. admin_update_listing_price uses the LISTING's market type. As the Manager
--    (nothing kept; replace the ids with a live Cooperative listing and a live Public listing):
--    BEGIN;
--      SELECT set_config('request.jwt.claims',
--        json_build_object('sub','<MANAGER_USER_ID>','role','authenticated')::text, true);
--      SET LOCAL ROLE authenticated;
--      SELECT public.admin_update_listing_price('<COOPERATIVE_LISTING_ID>'::uuid, 21);  -- succeeds
--      SELECT public.admin_update_listing_price('<PUBLIC_LISTING_ID>'::uuid, 21);        -- error: "Only Cooperative Market listings ..."
--    ROLLBACK;
-- ============================================================
