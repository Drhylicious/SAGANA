-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_phase2_notification_completeness.sql
-- Phase 2 — Database notification completeness.
--
-- Adds the notices the review found missing, and moves the reference-price
-- notice from the device into a database function. Everything here is written
-- as SECURITY DEFINER so that the notice is created regardless of who causes
-- it (for example, a buyer placing an order must still notify staff, and staff
-- may be blocked from writing other users' rows directly).
--
-- Covers:
--   1. Order placed                      → all active admins and officers
--   2. Account created by admin          → the new farmer or officer
--   3. Capital contribution recorded     → the farmer
--   4. Payout decision submitted         → all active admins and officers
--   5. Low stock / out of stock          → all active admins and officers
--   6. Ginger submitted for sale         → all active admins and officers
--   7. Ginger buyer found / sale done    → the farmer
--   8. Reference price update            → active farmers and buyers
--      (called as an RPC by the Admin/Officer app, replacing the device insert)
--
-- Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── Shared helper: notify every active admin and officer ───────────────────
CREATE OR REPLACE FUNCTION public.notify_staff(
  p_type TEXT,
  p_title TEXT,
  p_body TEXT,
  p_route TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ur.user_id, p_type, p_title, p_body, FALSE, NOW(), p_route
  FROM user_roles ur
  WHERE ur.role IN ('admin', 'officer')
    AND ur.status = 'active';
END;
$$;

-- Only trigger functions and the price RPC call this helper; keep it off the
-- client API so no user can send staff-wide notices directly.
REVOKE EXECUTE ON FUNCTION public.notify_staff(TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- ─── 1. Order placed → staff ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_notify_staff_order_placed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_crop TEXT;
BEGIN
  SELECT crop_name INTO v_crop FROM marketplace_listings WHERE id = NEW.listing_id;
  PERFORM public.notify_staff(
    'order',
    'New Order Placed',
    'A new order for ' || COALESCE(v_crop, 'produce') || ' was placed and is waiting for review.'
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_staff_order_placed ON orders;
CREATE TRIGGER trg_notify_staff_order_placed
  AFTER INSERT ON orders
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_staff_order_placed();

-- ─── 2. Account created by admin → the new farmer or officer ────────────────
CREATE OR REPLACE FUNCTION public.fn_notify_account_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.role IN ('farmer', 'officer') THEN
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      NEW.user_id,
      'system',
      'Account Created',
      'Your SAGANA account was created by the cooperative admin. Sign in with your temporary password and change it to continue.',
      FALSE,
      NOW(),
      NULL
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_account_created ON user_roles;
CREATE TRIGGER trg_notify_account_created
  AFTER INSERT ON user_roles
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_account_created();

-- ─── 3. Capital contribution recorded → the farmer ──────────────────────────
-- Mirrors the device notice that used to be sent by
-- CapitalContributionRepository.recordContribution (source 'member_payment').
CREATE OR REPLACE FUNCTION public.fn_notify_capital_recorded()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.source = 'member_payment' THEN
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      NEW.farmer_id,
      'capital',
      'Capital Contribution Recorded',
      'Your capital contribution of ₱' || TO_CHAR(NEW.amount, 'FM999999990.00') || ' was recorded.',
      FALSE,
      NOW(),
      '/farmer/profile/contribution'
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_capital_recorded ON capital_contribution_events;
CREATE TRIGGER trg_notify_capital_recorded
  AFTER INSERT ON capital_contribution_events
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_capital_recorded();

-- ─── 4. Payout decision submitted → staff ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_notify_staff_payout_requested()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name TEXT;
BEGIN
  IF OLD.payout_decision IS NULL AND NEW.payout_decision IS NOT NULL THEN
    SELECT full_name INTO v_name FROM user_information WHERE user_id = NEW.farmer_id;
    PERFORM public.notify_staff(
      'capital',
      'Payout Decision Submitted',
      COALESCE(v_name, 'A farmer') || ' submitted a Balik-Tangkilik payout decision for ' || NEW.year || ' that needs review.'
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_staff_payout_requested ON member_contributions;
CREATE TRIGGER trg_notify_staff_payout_requested
  AFTER UPDATE OF payout_decision ON member_contributions
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_staff_payout_requested();

-- ─── 5. Low stock / out of stock → staff ────────────────────────────────────
-- "Available" = on hand minus reserved. A notice fires only when the stock
-- crosses the threshold downward, not on every update below it.
CREATE OR REPLACE FUNCTION public.fn_notify_staff_stock()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new NUMERIC := NEW.quantity_on_hand - NEW.quantity_reserved;
  v_old NUMERIC := OLD.quantity_on_hand - OLD.quantity_reserved;
BEGIN
  IF v_new <= 0 AND v_old > 0 THEN
    PERFORM public.notify_staff(
      'stock_depleted',
      'Out of Stock: ' || NEW.item_name,
      NEW.item_name || ' is out of stock.'
    );
  ELSIF NEW.reorder_level > 0 AND v_new <= NEW.reorder_level AND v_old > NEW.reorder_level THEN
    PERFORM public.notify_staff(
      'low_stock',
      'Low Stock: ' || NEW.item_name,
      NEW.item_name || ' is running low (' || TO_CHAR(v_new, 'FM999999990.##') || ' ' || NEW.unit || ' available).'
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_staff_stock ON cooperative_inventory;
CREATE TRIGGER trg_notify_staff_stock
  AFTER UPDATE OF quantity_on_hand, quantity_reserved, reorder_level ON cooperative_inventory
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_staff_stock();

-- ─── 6–7. Ginger / Market Linking ──────────────────────────────────────────
-- 6: a farmer submitting Ginger for sale creates the row with status 'submitted'.
-- 7: buyer found and completed sale notify the farmer.
CREATE OR REPLACE FUNCTION public.fn_notify_market_linking()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF NEW.status = 'submitted' THEN
      PERFORM public.notify_staff(
        'listing',
        'Ginger Submitted for Sale',
        'A farmer submitted Ginger for sale through Market Linking.'
      );
    END IF;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.status = 'buyer_found' AND OLD.status IS DISTINCT FROM NEW.status THEN
      INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
      VALUES (
        NEW.farmer_id,
        'listing',
        'Buyer Found for Your Ginger',
        'A buyer has been found for your Ginger harvest through Market Linking.',
        FALSE,
        NOW(),
        '/farmer/profile/market-linking'
      );
    ELSIF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM NEW.status THEN
      INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
      VALUES (
        NEW.farmer_id,
        'listing',
        'Ginger Sale Completed',
        'Your Ginger sale through Market Linking has been completed.',
        FALSE,
        NOW(),
        '/farmer/profile/market-linking'
      );
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_market_linking_insert ON market_linking_programs;
CREATE TRIGGER trg_notify_market_linking_insert
  AFTER INSERT ON market_linking_programs
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_market_linking();

DROP TRIGGER IF EXISTS trg_notify_market_linking_update ON market_linking_programs;
CREATE TRIGGER trg_notify_market_linking_update
  AFTER UPDATE OF status ON market_linking_programs
  FOR EACH ROW EXECUTE FUNCTION public.fn_notify_market_linking();

-- ─── 8. Reference price update → active farmers and buyers (RPC) ───────────
-- Called by the Admin/Officer app after a price is saved. Replaces the device
-- insert, which was blocked for officers and whose failures were swallowed.
CREATE OR REPLACE FUNCTION public.notify_price_update(
  p_crop_name TEXT,
  p_new_price NUMERIC,
  p_unit TEXT
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  IF NOT (
    public.is_platform_admin(auth.uid())
    OR EXISTS (SELECT 1 FROM officer_profiles o WHERE o.user_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'Unauthorized: only admins or officers can announce price updates';
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ur.user_id,
    'price',
    'Price Update: ' || p_crop_name,
    'SP3 Admin updated the price of ' || p_crop_name || ' to ₱'
      || TO_CHAR(p_new_price, 'FM999999990.00') || '/' || p_unit || '. '
      || CASE
           WHEN ur.role = 'buyer' THEN 'Check the Prices tab for the latest market rates.'
           ELSE 'Check the Analytics tab for the latest market rates.'
         END,
    FALSE,
    NOW(),
    CASE WHEN ur.role = 'buyer' THEN '/buyer/prices' ELSE '/farmer/analytics' END
  FROM user_roles ur
  WHERE ur.role IN ('farmer', 'buyer')
    AND ur.status = 'active';

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.notify_price_update(TEXT, NUMERIC, TEXT) TO authenticated;
