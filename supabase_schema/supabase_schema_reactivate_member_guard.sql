-- reactivate_member: server-side guard (John Harvey investigation follow-up)
--
-- reactivate_member() set status = 'active' from whatever the previous status
-- was. Every sibling lifecycle RPC checks its precondition (approve_member
-- requires 'pending', and so on); this one did not. Calling it on a pending,
-- rejected, or draft account skipped approve_member() entirely: no
-- verification, no capital row, no registry link.
--
-- The fix adds the same kind of guard approve_member() has: only a suspended
-- member can be reactivated. Nothing else in the function changes. Signature
-- and grants are unchanged, so CREATE OR REPLACE is enough.
--
-- Not applied automatically. Run it in the Supabase SQL editor, or with
-- `supabase db query --linked -f`, then run the verification block below.

BEGIN;

CREATE OR REPLACE FUNCTION public.reactivate_member(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  -- Only a suspended member can be reactivated. Any other status must go
  -- through its own flow (approve_member for pending applicants).
  IF v_status <> 'suspended' THEN
    RAISE EXCEPTION 'Only a suspended member can be reactivated (current: %)', v_status;
  END IF;

  UPDATE user_roles
  SET status = 'active', suspension_reason = NULL
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, v_status, 'active', 'Reactivated by admin', auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
  VALUES (p_user_id, 'member_updated', 'Account Reactivated',
          'Your SP3 account has been reactivated. Welcome back!',
          false, '/farmer/profile');
END;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION (read-only) ────────────────────────────────
-- 1. One overload, and the guard text is in the body (expect 1 and 1):
--    SELECT count(*) AS overloads, bool_or(prosrc ILIKE '%Only a suspended member%') AS guarded
--    FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'reactivate_member';
--
-- 2. Behaviour (run as an admin in a transaction you roll back):
--    a pending or active target raises "Only a suspended member can be reactivated";
--    a suspended target is reactivated.
