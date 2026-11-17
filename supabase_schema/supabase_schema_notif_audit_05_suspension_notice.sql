-- ============================================================================
-- Notification audit 05: a suspended member gets a notification.
--
-- Found in the audit: suspend_member (live definition) changes the account to
-- Suspended and records the status event, but sends no notification. The member
-- sees the suspension notice on their next app start, yet nothing is kept in
-- their Notifications. reactivate_member and restrict_member already notify.
--
-- This re-creates suspend_member EXACTLY as it is live today and adds one
-- notification to the member (Farmer or Buyer). Run once, in the SQL editor.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.suspend_member(
  p_user_id uuid, p_reason text, p_suspended_until timestamp with time zone DEFAULT NULL::timestamp with time zone
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT (is_platform_admin() OR (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()) AND EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = p_user_id AND r.role = 'buyer'))) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  -- Staff accounts are never suspended.
  IF EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = p_user_id AND r.role IN ('admin', 'officer')) THEN
    RAISE EXCEPTION 'Manager and Officer accounts cannot be suspended';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A suspension reason is required';
  END IF;
  IF p_suspended_until IS NOT NULL AND p_suspended_until <= now() THEN
    RAISE EXCEPTION 'The reactivation date must be in the future';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  UPDATE user_roles
  SET status = 'suspended',
      suspension_reason = trim(p_reason),
      suspended_until = p_suspended_until
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, v_status, 'suspended', trim(p_reason), auth.uid());

  -- route_on_tap is left empty: the notification trigger picks the member's
  -- profile screen for their role.
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    p_user_id, 'member_updated', 'Account Suspended',
    'Your SP3 account was suspended' ||
      CASE WHEN p_suspended_until IS NOT NULL
           THEN ' until ' || to_char(p_suspended_until AT TIME ZONE 'Asia/Manila', 'FMMonth DD, YYYY')
           ELSE '' END ||
      '. Reason: ' || trim(p_reason),
    FALSE, NOW()
  );
END;
$function$;
