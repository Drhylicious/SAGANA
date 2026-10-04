-- Pending Applicant (Batch 6): unlimited resubmission
--
-- Replaces the body of submit_application() so a rejected applicant can
-- resubmit without a limit. Changes, and nothing else:
--   - removed the "used all 3 attempts" cap;
--   - the status-event reason no longer says "of 3".
-- Kept as they were:
--   - the signature and return type (smallint = the attempt number just used),
--     so the app's call site does not change;
--   - application_attempts keeps incrementing, as the resubmission history;
--   - the status checks, the status change, and both notifications.
--
-- Based on the live definition in supabase_schema_phase7_tap_to_navigate.sql
-- (the latest file that defines submit_application).
--
-- Not applied automatically. Run it in the Supabase SQL editor, then run the
-- verification block at the end.

BEGIN;

CREATE OR REPLACE FUNCTION public.submit_application()
RETURNS smallint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid       UUID := auth.uid();
  v_status    TEXT;
  v_attempts  SMALLINT;
  v_full_name TEXT;
BEGIN
  SELECT status, application_attempts INTO v_status, v_attempts
  FROM user_roles WHERE user_id = v_uid
  FOR UPDATE;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'No membership record found';
  END IF;

  IF v_status NOT IN ('draft', 'rejected') THEN
    RAISE EXCEPTION 'Application cannot be submitted from status %', v_status;
  END IF;

  UPDATE user_roles
  SET status = 'pending',
      application_attempts = COALESCE(v_attempts, 0) + 1,
      rejection_reason = NULL,
      pending_acknowledgement = false
  WHERE user_id = v_uid;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (v_uid, v_status, 'pending',
          'Application submitted (attempt ' || (COALESCE(v_attempts, 0) + 1) || ')', v_uid);

  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (v_uid, 'member_pending', 'Application Submitted',
          'Your membership application has been sent to the SP3 Cooperative for review.',
          false);

  SELECT full_name INTO v_full_name FROM user_information WHERE user_id = v_uid;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT
    ap.user_id,
    'member_pending',
    'New Membership Application',
    COALESCE(v_full_name, 'A farmer') || ' submitted a membership application and needs review.',
    FALSE,
    NOW(),
    '/admin/farmers'
  FROM admin_profiles ap;

  RETURN (COALESCE(v_attempts, 0) + 1)::SMALLINT;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION (read-only) ────────────────────────────────
-- 1. Still one overload, same signature (expect 1 row, returns smallint):
--    SELECT pg_get_function_result(p.oid) AS returns, count(*) OVER () AS overloads
--    FROM pg_proc p
--    WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'submit_application';
--
-- 2. The cap text is gone from the body (expect 0):
--    SELECT count(*) FROM pg_proc
--    WHERE pronamespace = 'public'::regnamespace AND proname = 'submit_application'
--      AND (prosrc ILIKE '%application attempts%' OR prosrc ILIKE '%of 3)%');
--
-- 3. Resubmission past three attempts works on a test rejected applicant
--    (sign in as that user, then from the app's Home tab tap Resubmit; or):
--    SELECT application_attempts, status FROM user_roles WHERE user_id = '<test user id>';
--    -- expect application_attempts to keep rising past 3, status = 'pending'.
