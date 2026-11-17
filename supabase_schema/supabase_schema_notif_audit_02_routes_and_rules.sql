-- ============================================================================
-- Notification audit 02: every notification opens a screen, and the same
-- recipient rules apply to every notification, whichever function created it.
--
-- Found in the audit (live data):
--   * Many notifications have no route_on_tap, so tapping them does nothing:
--     New Join Request, Benefit Distributed, Join Request Approved, Program
--     Enrollment Approved, New Order Placed, Out of Stock / Low Stock, Overdue
--     Loan, Loan Payment Due Soon, New Listing Submitted, Ginger Submitted for
--     Sale, Market Linking requests and approvals, broadcasts, and more.
--   * A person could be notified of their own action (the actor of the call).
--   * Staff accounts that are not active could be notified.
--   * The same notification could be inserted twice within seconds.
--
-- Rather than edit ~60 functions (and risk reverting newer behaviour), one
-- BEFORE INSERT trigger on `notifications` applies the rules to every insert,
-- including functions added later:
--   1. a staff recipient (admin/officer) must be active;
--   2. never notify the person who performed the action (auth.uid()); scheduled
--      jobs and server calls have no auth.uid() and are unaffected;
--   3. an identical notification (same person, type, title, body) within a few
--      last 60 seconds is dropped;
--   4. a missing route_on_tap is filled from the type and recipient role.
-- A notification that already has a route keeps it.
--
-- Run once, in the Supabase SQL editor, after audit 01. Safe to re-run.
-- ============================================================================

-- 1. Default destination by recipient role, type and title -------------------
CREATE OR REPLACE FUNCTION public.notification_default_route(
  p_user_id uuid, p_type text, p_title text
) RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role TEXT;
BEGIN
  SELECT role INTO v_role FROM user_roles WHERE user_id = p_user_id LIMIT 1;

  IF v_role = 'farmer' THEN
    RETURN CASE
      WHEN p_title ILIKE 'Benefit Distributed%'            THEN '/farmer/profile/received-items'
      WHEN p_title ILIKE 'Join Request Closed%'            THEN '/farmer/profile/programs'
      WHEN p_type = 'program'                              THEN '/farmer/profile/programs/enrolled'
      WHEN p_type IN ('loan', 'loan_overdue')              THEN '/farmer/profile/loans'
      WHEN p_title ILIKE 'BOD Meeting%'                    THEN '/farmer/profile/loans'
      WHEN p_title ILIKE '%Market Linking%'
        OR p_title ILIKE 'Ginger%'
        OR p_title ILIKE '%Buyer%'
        OR p_title ILIKE 'Cancellation%'                   THEN '/farmer/profile/market-linking'
      WHEN p_title ILIKE 'Account Created%'
        OR p_type IN ('member_approved', 'member_rejected', 'member_updated')
                                                           THEN '/farmer/profile'
      WHEN p_type = 'cooperative_offer'                    THEN '/farmer/profile/cooperative-offers'
      WHEN p_type = 'order'                                THEN '/farmer/marketplace'
      WHEN p_type = 'listing'                              THEN '/farmer/marketplace'
      WHEN p_type = 'crop_request'                         THEN '/farmer/harvest/crops'
      WHEN p_type = 'capital'                              THEN '/farmer/profile/contribution'
      WHEN p_type = 'price'                                THEN '/farmer/analytics'
      WHEN p_type IN ('low_stock', 'stock_depleted')       THEN '/farmer/harvest/inventory'
      ELSE '/farmer/dashboard'
    END;
  ELSIF v_role = 'buyer' THEN
    RETURN CASE
      WHEN p_type = 'order' THEN '/buyer/orders'
      WHEN p_type = 'price' THEN '/buyer/prices'
      ELSE '/buyer/browse'
    END;
  ELSIF v_role IN ('admin', 'officer') THEN
    RETURN CASE
      WHEN p_type = 'listing_submitted'                    THEN '/admin/listings/pending'
      WHEN p_title ILIKE 'Harvest Loss%'                   THEN '/admin/reports'
      WHEN p_title ILIKE 'Ginger%'
        OR p_title ILIKE '%Market Linking%'                THEN '/admin/farmers/market-linking'
      WHEN p_type = 'listing'                              THEN '/admin/listings/pending'
      WHEN p_title ILIKE 'New Join Request%'
        OR p_title ILIKE 'New Program Enrollment%'         THEN '/admin/programs/enrollment-requests'
      WHEN p_title ILIKE 'New Program Purchase%'           THEN '/admin/marketplace/orders'
      WHEN p_type = 'program'                              THEN '/admin/programs'
      WHEN p_type = 'order'                                THEN '/admin/marketplace/orders'
      WHEN p_title ILIKE 'New Loan Request%'               THEN '/admin/loans/requests'
      WHEN p_type IN ('loan', 'loan_overdue')
        OR p_title ILIKE 'BOD Meeting%'                    THEN '/admin/loans'
      WHEN p_type IN ('low_stock', 'stock_depleted')       THEN '/admin/inventory'
      WHEN p_type = 'cooperative_offer'                    THEN '/admin/marketplace/offer-to-cooperative'
      WHEN p_type = 'crop_request'                         THEN '/admin/crops/requests'
      WHEN p_type IN ('member_pending', 'member_registered', 'member_updated')
                                                           THEN '/admin/farmers'
      WHEN p_title ILIKE 'Account Created%'                THEN '/admin/profile'
      ELSE '/admin/dashboard'
    END;
  END IF;

  RETURN NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.notification_default_route(uuid, text, text) FROM PUBLIC;

-- 2. The rules, applied to every insert --------------------------------------
CREATE OR REPLACE FUNCTION public.notifications_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role   TEXT;
  v_status TEXT;
BEGIN
  SELECT role, status INTO v_role, v_status
  FROM user_roles WHERE user_id = NEW.user_id LIMIT 1;

  -- 1. A Manager/Officer account that is not active cannot act on it.
  IF v_role IN ('admin', 'officer') AND COALESCE(v_status, '') <> 'active' THEN
    RETURN NULL;
  END IF;

  -- 2. Notifications are for other people. What a person did themselves is in
  --    their Recent Activity.
  IF auth.uid() IS NOT NULL AND NEW.user_id = auth.uid() THEN
    RETURN NULL;
  END IF;

  -- 3. The same notification twice within 5 seconds is one notification.
  IF EXISTS (
    SELECT 1 FROM notifications n
    WHERE n.user_id = NEW.user_id
      AND n.type = NEW.type
      AND n.title = NEW.title
      AND n.body = NEW.body
      AND n.created_at > NOW() - INTERVAL '5 seconds'
  ) THEN
    RETURN NULL;
  END IF;

  -- 4. Every notification opens a screen.
  IF NEW.route_on_tap IS NULL OR btrim(NEW.route_on_tap) = '' THEN
    NEW.route_on_tap := public.notification_default_route(NEW.user_id, NEW.type, NEW.title);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notifications_before_insert ON public.notifications;
CREATE TRIGGER trg_notifications_before_insert
  BEFORE INSERT ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.notifications_before_insert();

-- 3. Existing notifications without a route get one too ------------------------
UPDATE public.notifications n
SET route_on_tap = public.notification_default_route(n.user_id, n.type, n.title)
WHERE (n.route_on_tap IS NULL OR btrim(n.route_on_tap) = '')
  AND public.notification_default_route(n.user_id, n.type, n.title) IS NOT NULL;
