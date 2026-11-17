-- ============================================================
-- supabase_schema_restrictions_05_close_on_auto_reactivation.sql
--
-- FEATURE RESTRICTIONS (5). Run after scripts 01-04.
--
-- Reactivating a suspended farmer closes the restrictions that were in force (they
-- stay in the history). Reactivating BY HAND already does this (script 02). This
-- closes the same gap for the daily job that reactivates a farmer when a timed
-- suspension runs out, so both ways of coming back behave the same.
--
-- The function below is the LIVE definition (which already contains script 02's
-- change that ends restrictions whose own end date passed) plus one statement.
-- Safe to re-run.
-- ============================================================

BEGIN;

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

    -- Reactivation by the end date closes the member's restrictions too (kept in
    -- the history), exactly as reactivating by hand does.
    UPDATE member_restrictions
    SET status = 'closed',
        closed_at = now(),
        close_reason = 'Member reactivated (suspension period ended)'
    WHERE member_id = v_row.user_id AND status = 'active';

    INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
    VALUES (v_row.user_id, 'suspended', 'active', 'Suspension period ended (automatic)', NULL);

    v_count := v_count + 1;
  END LOOP;

  -- Restrictions whose end date has passed are marked ended (they already stopped
  -- applying the moment the date passed; this only completes the history).
  UPDATE member_restrictions
  SET status = 'ended',
      closed_at = now(),
      close_reason = 'Period ended (automatic)'
  WHERE status = 'active' AND ends_at IS NOT NULL AND ends_at <= now();

  RETURN v_count;
END;
$function$
;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECK (read-only). Run on its own. Every row PASS.
-- ============================================================
SELECT 'automatic reactivation closes restrictions' AS check_name,
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname = 'reactivate_expired_suspensions' AND pronamespace = 'public'::regnamespace)
                 LIKE '%suspension period ended%'
             AND (SELECT prosrc FROM pg_proc WHERE proname = 'reactivate_expired_suspensions' AND pronamespace = 'public'::regnamespace)
                 LIKE '%Period ended (automatic)%'
            THEN 'PASS' ELSE 'FAIL' END AS result;
