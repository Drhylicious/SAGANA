-- ============================================================================
-- Audit 09: the duplicate rule must not hide a real notification.
--
-- Audit 02 drops an identical notification (same person, type, title, text)
-- inserted within 60 seconds. That removes accidental double inserts, but it
-- could also drop a real second notification whose text is the same: for example
-- two different Buyers ordering the same crop within a minute, or two Farmers
-- asking to join the same program ("A farmer asked to join X"). The accidental
-- duplicates found in the data were created by one call, so a few seconds is
-- enough.
--
-- 1. The window becomes 5 seconds.
-- 2. "New Order Placed" now names the order, so two orders never read the same.
--
-- Run once, in the Supabase SQL editor. Safe to re-run.
-- ============================================================================

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

  -- 5. An Officer is notified only for the tabs they can Manage.
  IF v_role = 'officer' THEN
    v_module := public.notification_staff_module(NEW.route_on_tap);
    IF v_module IS NOT NULL AND NOT public.staff_can_manage(v_module, NEW.user_id) THEN
      RETURN NULL;
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- "New Order Placed" with the order number (as live, plus the number).
CREATE OR REPLACE FUNCTION public.fn_notify_staff_order_placed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_crop TEXT;
BEGIN
  SELECT crop_name INTO v_crop FROM marketplace_listings WHERE id = NEW.listing_id;
  PERFORM public.notify_staff(
    'order',
    'New Order Placed',
    'A new order' || COALESCE(' ' || NEW.order_number, '') || ' for ' || COALESCE(v_crop, 'produce') ||
      ' was placed and is waiting for review.'
  );
  RETURN NEW;
END;
$function$;
