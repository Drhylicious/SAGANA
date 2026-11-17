-- ============================================================================
-- Notification audit 04: Officers receive a staff notification only when they
-- have MANAGE access to the tab it belongs to. View Only Officers do not.
--
-- The Manager (admin) always receives them. Officer access is View Only or
-- Manage per tab (Dashboard, Members, Marketplace, Loans, Reports), set in
-- officer_permissions and read through staff_can_manage(module, user).
--
-- Which tab a notification belongs to is decided by where tapping it goes
-- (route_on_tap), using the same feature-to-tab assignment as the permission
-- gate (staff_permission_targets):
--   Dashboard    programs, crop requests, inventory and stock, prices
--   Members      member applications and accounts
--   Marketplace  listings, orders, offers, cooperative product orders, Market Linking
--   Loans        loan requests, assistance requests, loan payments, overdue loans
--   Reports      reports (e.g. harvest loss)
-- A notification that belongs to no tab (broadcasts, "Account Created", anything
-- that falls back to the Dashboard) goes to every active Officer.
--
-- This replaces notifications_before_insert() from audit 02 with the same four
-- rules plus this one. Safe to re-run.
-- ============================================================================

-- 1. Route -> permission tab ---------------------------------------------------
CREATE OR REPLACE FUNCTION public.notification_staff_module(p_route text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_route IS NULL                                   THEN NULL
    WHEN p_route = '/admin/dashboard'                      THEN NULL   -- generic fallback
    WHEN p_route LIKE '/admin/loans%'                      THEN 'loans'
    WHEN p_route LIKE '/admin/farmers/market-linking%'     THEN 'marketplace'
    WHEN p_route LIKE '/admin/farmers%'
      OR p_route LIKE '/admin/members%'
      OR p_route LIKE '/admin/buyers%'                     THEN 'members'
    WHEN p_route LIKE '/admin/marketplace%'
      OR p_route LIKE '/admin/listings%'                   THEN 'marketplace'
    WHEN p_route LIKE '/admin/programs%'
      OR p_route LIKE '/admin/crops%'
      OR p_route LIKE '/admin/inventory%'
      OR p_route LIKE '/admin/prices%'                     THEN 'dashboard'
    WHEN p_route LIKE '/admin/reports%'                    THEN 'reports'
    ELSE NULL
  END;
$$;

-- 2. The insert rules, now including the Officer permission ---------------------
CREATE OR REPLACE FUNCTION public.notifications_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role   TEXT;
  v_status TEXT;
  v_module TEXT;
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

  -- 5. An Officer is notified only for the tabs they can Manage. View Only
  --    Officers can open the screens but are not asked to act on them.
  IF v_role = 'officer' THEN
    v_module := public.notification_staff_module(NEW.route_on_tap);
    IF v_module IS NOT NULL AND NOT public.staff_can_manage(v_module, NEW.user_id) THEN
      RETURN NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- (The trigger trg_notifications_before_insert from audit 02 already calls this
-- function; replacing the function is enough.)

-- 3. OPTIONAL cleanup of notifications a View Only Officer already received -----
-- Not run automatically: it deletes history. Review the count first, then run
-- the DELETE only if you want those removed.
--
-- SELECT count(*) FROM notifications n
-- JOIN user_roles r ON r.user_id = n.user_id AND r.role = 'officer'
-- WHERE public.notification_staff_module(n.route_on_tap) IS NOT NULL
--   AND NOT public.staff_can_manage(public.notification_staff_module(n.route_on_tap), n.user_id);
--
-- DELETE FROM notifications n
-- USING user_roles r
-- WHERE r.user_id = n.user_id AND r.role = 'officer'
--   AND public.notification_staff_module(n.route_on_tap) IS NOT NULL
--   AND NOT public.staff_can_manage(public.notification_staff_module(n.route_on_tap), n.user_id);
