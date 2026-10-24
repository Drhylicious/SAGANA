-- ============================================================
-- SAGANA — Registration refactor, step 9: "Admin" → "Manager" in the error
-- messages the database shows people
--
-- Messages such as "Unauthorized: only admins can approve orders" or "Your
-- account has been suspended by the SP3 Administrator" are written inside
-- database functions. This file finds every function in the public schema
-- whose RAISE EXCEPTION / NOTICE / WARNING text contains the whole words
-- Admin, Admins, Administrator or Administrators (any letter case), and
-- re-creates that function with ONLY that wording changed to Manager /
-- Managers. Nothing else in a function changes: the code, the role checks
-- ('admin' stays 'admin'), the function's rights (SECURITY DEFINER, search
-- path) and who may call it.
--
-- HOW. Each function's own definition is read back from the database
-- (pg_get_functiondef), the wording inside the quoted text of its RAISE lines
-- is replaced, and the result is run as CREATE OR REPLACE FUNCTION. Existing
-- GRANTs and the function's owner are kept by CREATE OR REPLACE. Functions
-- with no such message are not touched.
--
-- SCOPE LIMITS
--   * Only text directly inside a RAISE line is changed. A role comparison
--     such as  role = 'admin'  is never touched.
--   * A message that contains an escaped quote ('') before the word is left
--     for you to review (listed by the preview query below).
--   * This changes the live functions only. The old migration files in the
--     repository still contain the old wording; re-running one of them would
--     bring it back.
--
-- Not applied automatically. Run the PREVIEW, then this file, then verify.
-- ============================================================

-- ─── PREVIEW (read-only) ─────────────────────────────────────────────────
-- A. The functions that will be re-created, and how many RAISE lines mention
--    the words (expect roughly 40 to 60 functions):
--    SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args,
--           (SELECT count(*) FROM regexp_matches(p.prosrc,
--              'RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*\m(?:admins?|administrators?)\M', 'gi')) AS lines
--    FROM pg_proc p
--    WHERE p.pronamespace = 'public'::regnamespace AND p.prokind = 'f'
--      AND p.prosrc ~* 'RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*\m(?:admins?|administrators?)\M'
--    ORDER BY p.proname;
-- B. Anything left that this file will NOT change (expect none, or review):
--    SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prokind = 'f'
--      AND prosrc ~* 'RAISE[^;]*\m(?:admins?|administrators?)\M'
--      AND prosrc !~* 'RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*\m(?:admins?|administrators?)\M';
-- ────────────────────────────────────────────────────────────────────────

BEGIN;

-- Rewrites the wording inside the quoted text of RAISE lines of one function
-- definition. Repeats until nothing changes, because one pass replaces only
-- the first match in each quoted text.
CREATE OR REPLACE FUNCTION public._tmp_manager_wording_in_raise(p_def text)
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
    d := regexp_replace(d, '(RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*)\mAdministrators\M', '\1Managers', 'gi');
    d := regexp_replace(d, '(RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*)\mAdministrator\M',  '\1Manager',  'gi');
    d := regexp_replace(d, '(RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*)\mAdmins\M',         '\1Managers', 'gi');
    d := regexp_replace(d, '(RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*)\mAdmin\M',          '\1Manager',  'gi');
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
      AND p.proname NOT IN ('_tmp_manager_wording_in_raise', 'to_manager_wording')
      AND p.prosrc ~* 'RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*\m(?:admins?|administrators?)\M'
  LOOP
    v_old := pg_get_functiondef(r.oid);
    v_new := public._tmp_manager_wording_in_raise(v_old);
    IF v_new IS DISTINCT FROM v_old THEN
      EXECUTE v_new;
      v_count := v_count + 1;
    END IF;
  END LOOP;
  RAISE NOTICE 'Re-created % function(s) with Manager wording in their messages.', v_count;
END;
$$;

DROP FUNCTION public._tmp_manager_wording_in_raise(text);

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION ────────────────────────────────────────────
-- 1. No RAISE line mentions admin any more (expect 0 rows; review any listed
--    by PREVIEW query B):
--    SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND prokind = 'f'
--      AND prosrc ~* 'RAISE\s+(?:EXCEPTION|NOTICE|WARNING)\s+''[^'']*\m(?:admins?|administrators?)\M';
--
-- 2. Role checks are intact (expect rows: the role literal is still there):
--    SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--      AND prosrc ILIKE '%role = ''admin''%';
--
-- 3. A function keeps its rights (compare with before; SECURITY DEFINER = true):
--    SELECT proname, prosecdef, proconfig FROM pg_proc
--    WHERE pronamespace='public'::regnamespace AND proname IN ('approve_order','place_order','issue_loan');
--
-- 4. Behaviour: as a Buyer/Farmer, try an action only a Manager may do through
--    the API; the error text must say "Manager", not "admin".
-- ============================================================
