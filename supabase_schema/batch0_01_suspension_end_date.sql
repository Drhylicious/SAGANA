-- ─────────────────────────────────────────────────────────────────────────────
-- batch0_01_suspension_end_date.sql
-- Batch 0 (0A + 0K) of the approved implementation plan.
--
-- Adds an end date to suspensions and reactivates expired suspensions
-- automatically. Also removes the normal "Account Suspended" notice: a
-- suspension is an account-level restriction shown as a red dialog, not a
-- notification (approved decision 3).
--
-- Not applied yet. Review this file before running it in Supabase.
-- Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── 0A. End date column ─────────────────────────────────────────────────────
ALTER TABLE public.user_roles
  ADD COLUMN IF NOT EXISTS suspended_until timestamptz;

-- ─── 0K. suspend_member: optional end date, no notification ──────────────────
-- The signature changes (a third parameter is added), so the old two-argument
-- version is dropped first. Otherwise both would exist and calls with two
-- arguments would be ambiguous.
DROP FUNCTION IF EXISTS public.suspend_member(uuid, text);

CREATE OR REPLACE FUNCTION public.suspend_member(
  p_user_id uuid,
  p_reason text,
  p_suspended_until timestamptz DEFAULT NULL
)
RETURNS void
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
END;
$function$;

-- ─── 0K. reactivate_member: clears the end date as well ──────────────────────
CREATE OR REPLACE FUNCTION public.reactivate_member(p_user_id uuid)
RETURNS void
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
  SET status = 'active',
      suspension_reason = NULL,
      suspended_until = NULL
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, v_status, 'active', 'Reactivated by admin', auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
  VALUES (p_user_id, 'member_updated', 'Account Reactivated',
          'Your SP3 account has been reactivated. Welcome back!',
          false, '/farmer/profile');
END;
$function$;

-- ─── 0K. Automatic reactivation when the end date passes ─────────────────────
-- Called only by the scheduled job below. Reactivated accounts get no notice:
-- their login simply works again.
CREATE OR REPLACE FUNCTION public.reactivate_expired_suspensions()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_row RECORD;
  v_count INTEGER := 0;
BEGIN
  FOR v_row IN
    SELECT user_id
    FROM user_roles
    WHERE status = 'suspended'
      AND suspended_until IS NOT NULL
      AND suspended_until <= now()
    FOR UPDATE
  LOOP
    UPDATE user_roles
    SET status = 'active',
        suspension_reason = NULL,
        suspended_until = NULL
    WHERE user_id = v_row.user_id;

    INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
    VALUES (v_row.user_id, 'suspended', 'active', 'Suspension period ended (automatic)', NULL);

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$function$;

-- Scheduled daily, alongside the existing loan maintenance job.
-- Unschedule first so this file can be re-run safely.
DO $$
BEGIN
  PERFORM cron.unschedule('reactivate-expired-suspensions');
EXCEPTION WHEN OTHERS THEN
  NULL;
END $$;

SELECT cron.schedule(
  'reactivate-expired-suspensions',
  '10 0 * * *',
  $$ SELECT public.reactivate_expired_suspensions(); $$
);

-- ─── Verification (run after applying) ───────────────────────────────────────
--   select column_name from information_schema.columns where table_name = 'user_roles' and column_name = 'suspended_until';   -- 1 row
--   select proname, pg_get_function_identity_arguments(oid) from pg_proc where proname = 'suspend_member';                   -- 1 row (3 args)
--   select jobname, schedule from cron.job where jobname = 'reactivate-expired-suspensions';                                 -- 1 row
