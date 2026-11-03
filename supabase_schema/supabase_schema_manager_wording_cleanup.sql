-- ============================================================
-- SAGANA — "Admin" → "Manager" in the error messages the database shows (cleanup)
--
-- APPROVED by you (N7). This finishes what supabase_schema_registration_09 started.
-- The live check on 2026-11 found:
--   * 4 functions whose messages still say "admin": approve_crop_request,
--     complete_market_linking, issue_loan, notify_price_update (they were
--     re-created by later scripts after step 17 ran).
--   * a grammar slip left by step 17 itself, "an Manager" (should be "a Manager"),
--     in confirm_payout_decision, reject_payout_decision, confirm_program_purchase
--     and loan_capital_eligibility.
--   * guard_crop_exclusive_channel says "can only be set by a database
--     administrator". That is NOT the cooperative Manager: it means the person who
--     runs the database, and it is shown to nobody in the app. It is left as it is
--     on purpose (changing it to "Manager" would be wrong).
--
-- WHAT THIS DOES
--   Reads each affected function's own live definition (pg_get_functiondef),
--   changes ONLY the wording inside the quoted text of its RAISE lines
--     Administrators/Administrator/Admins/Admin  ->  Managers/Manager/Managers/Manager
--     "an Manager"                                ->  "a Manager"
--   and re-creates it. The code, the role checks (role = 'admin' stays 'admin'),
--   the function's rights (SECURITY DEFINER, search path) and who may call it do
--   not change. A function with nothing to change is not touched.
--
-- LIMITS
--   * Only text directly inside a RAISE line. A message with an escaped quote ('')
--     before the word is listed by PREVIEW B for you to review.
--   * "database administrator" is never changed.
--   * It changes the live functions. The old migration files in the repository
--     still contain the old wording; re-running one of them would bring it back.
--
-- Not applied automatically. Run the PREVIEW, then this file, then verify.
-- Re-runnable: once changed, nothing matches any more.
-- ============================================================

-- ─── PREVIEW (read-only; run each by itself) ─────────────────────────────
-- A. Functions this file will re-create:
--    SELECT p.proname
--    FROM pg_proc p
--    WHERE p.pronamespace = 'public'::regnamespace AND p.prokind = 'f'
--      AND ( p.prosrc ~* 'RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*(?<!database )\m(?:admins?|administrators?)\M'
--         OR p.prosrc ~  'RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*\m[Aa]n Manager\M' )
--    ORDER BY 1;
--    -- expect about 8 on the 2026-11 database
-- B. Messages this file will NOT change (expect only guard_crop_exclusive_channel):
--    SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prokind = 'f'
--      AND prosrc ~* 'RAISE[^;]*\m(?:admins?|administrators?)\M'
--      AND prosrc !~* 'RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*(?<!database )\m(?:admins?|administrators?)\M';
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

CREATE OR REPLACE FUNCTION public._tmp_manager_wording_cleanup(p_def text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  d    text := p_def;
  prev text;
  i    integer := 0;
BEGIN
  LOOP
    prev := d;
    -- One pass replaces only the first match in each quoted text, so repeat.
    d := regexp_replace(d, '(RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*)(?<!database )\mAdministrators\M', '\1Managers', 'gi');
    d := regexp_replace(d, '(RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*)(?<!database )\mAdministrator\M',  '\1Manager',  'gi');
    d := regexp_replace(d, '(RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*)\mAdmins\M',                       '\1Managers', 'gi');
    d := regexp_replace(d, '(RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*)\mAdmin\M',                        '\1Manager',  'gi');
    -- "an Manager" -> "a Manager" (keeps the capital of "An").
    d := regexp_replace(d, '(RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*)\m([Aa])n Manager\M', '\1\2 Manager', 'g');
    i := i + 1;
    EXIT WHEN d = prev OR i > 25;
  END LOOP;
  RETURN d;
END;
$$;

DO $$
DECLARE
  r       record;
  v_old   text;
  v_new   text;
  v_count integer := 0;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.prokind = 'f'
      AND p.proname NOT IN ('_tmp_manager_wording_cleanup', '_tmp_manager_wording_in_raise', 'to_manager_wording')
      AND ( p.prosrc ~* 'RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*(?<!database )\m(?:admins?|administrators?)\M'
         OR p.prosrc ~  'RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*\m[Aa]n Manager\M' )
  LOOP
    v_old := pg_get_functiondef(r.oid);
    v_new := public._tmp_manager_wording_cleanup(v_old);
    IF v_new IS DISTINCT FROM v_old THEN
      EXECUTE v_new;
      v_count := v_count + 1;
    END IF;
  END LOOP;
  RAISE NOTICE 'Re-created % function(s) with Manager wording in their messages.', v_count;
END;
$$;

DROP FUNCTION public._tmp_manager_wording_cleanup(text);

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION (read-only) ────────────────────────────────
-- 1. No message says admin any more, except the database-administrator one:
--    SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prokind = 'f'
--      AND prosrc ~* 'RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*(?<!database )\m(?:admins?|administrators?)\M';
--    -- expect 0 rows
-- 2. No "an Manager" left:
--    SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prokind = 'f'
--      AND prosrc ~ '\m[Aa]n Manager\M';                                      -- expect 0 rows
-- 3. Role checks and rights are intact (the five functions keep SECURITY DEFINER):
--    SELECT proname, prosecdef FROM pg_proc WHERE pronamespace='public'::regnamespace
--      AND proname IN ('approve_crop_request','complete_market_linking','issue_loan','notify_price_update','confirm_payout_decision');
--    SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--      AND prosrc ILIKE '%role = ''admin''%';                                  -- still > 0
-- ─────────────────────────────────────────────────────────────────────────
