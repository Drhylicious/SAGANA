-- ============================================================
-- supabase_schema_registration_14_name_edit_verification.sql
--
-- CHECKS ONLY. NOTHING IS CHANGED OR SAVED. NO MIGRATION IS NEEDED FOR THIS STEP.
--
-- Script 12 already created the name columns and the trigger that validates the
-- parts and rebuilds full_name on every UPDATE. The Edit Profile screens now send
-- the four parts, and that trigger does the rest. These three queries confirm it.
--
-- HOW TO RUN: run script 12 first. Then, in the Supabase SQL editor, run each of
-- the three blocks below ON ITS OWN (select one block, press Run). The editor only
-- shows the result of the last statement, so do not run them all at once.
-- ============================================================


-- ─── BLOCK A — is script 12 in place? (run first) ──────────────────────────
-- Expect two rows, both PASS. If a row says FAIL, run script 12 and try again.

SELECT 'Name trigger exists and fires on UPDATE' AS check_name,
       CASE WHEN EXISTS (
              SELECT 1 FROM pg_trigger
              WHERE tgrelid = 'public.user_information'::regclass
                AND tgname  = 'trg_user_information_name_guard'
                AND NOT tgisinternal
                AND pg_get_triggerdef(oid) ILIKE '%INSERT OR UPDATE%'
            ) THEN 'PASS' ELSE 'FAIL - run script 12' END AS result
UNION ALL
SELECT 'Columns surname, first_name, middle_initial, suffix exist',
       CASE WHEN (
              SELECT count(*) FROM information_schema.columns
              WHERE table_schema = 'public' AND table_name = 'user_information'
                AND column_name IN ('surname', 'first_name', 'middle_initial', 'suffix')
            ) = 4 THEN 'PASS' ELSE 'FAIL - run script 12' END;


-- ─── BLOCK B — are the stored names consistent? (run after A passes) ───────
-- Reads only. PASS rows should say PASS; the INFO rows are counts for you.
--   * "one-line" accounts were created before the split. They are NOT changed;
--     their owners complete them in Edit Profile.

SELECT 'Accounts with a structured name vs one-line name, per role' AS check_name,
       'INFO' AS result,
       (SELECT string_agg(
                 role || ': ' || structured || ' structured, ' || one_line || ' one-line',
                 E'\n' ORDER BY role)
        FROM (
          SELECT r.role,
                 count(*) FILTER (WHERE ui.surname IS NOT NULL) AS structured,
                 count(*) FILTER (WHERE ui.surname IS NULL)     AS one_line
          FROM public.user_information ui
          JOIN public.user_roles r ON r.user_id = ui.user_id
          GROUP BY r.role
        ) per_role) AS detail
UNION ALL
SELECT 'Every structured name: full_name equals the name built from its parts',
       CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END,
       n || ' account(s) do not match'
FROM (
  SELECT count(*) AS n FROM public.user_information
  WHERE surname IS NOT NULL
    AND full_name IS DISTINCT FROM
        public.compose_full_name(first_name, middle_initial, surname, suffix)
) mismatched
UNION ALL
SELECT 'No account has only a surname or only a first name',
       CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END,
       n || ' account(s) with half a name'
FROM (
  SELECT count(*) AS n FROM public.user_information
  WHERE (surname IS NULL) <> (first_name IS NULL)
) half_names;


-- ─── BLOCK C — does an Edit Profile save work? (run after A passes) ────────
-- Does what Edit Profile does to one existing account, then undoes it.
-- IT ENDS WITH AN ERROR ON PURPOSE: the error is what rolls everything back, so
-- nothing is saved. Read the message:
--   "TEST PASSED (nothing was saved) ..."  -> working
--   "TEST FAILED (nothing was saved) ..."  -> something is wrong; send me the text

DO $$
DECLARE
  uid             uuid;
  built           text;
  short_rejected  boolean := false;
  suffix_rejected boolean := false;
BEGIN
  SELECT user_id INTO uid FROM public.user_information LIMIT 1;
  IF uid IS NULL THEN
    RAISE EXCEPTION 'TEST FAILED (nothing was saved): user_information has no rows to test with';
  END IF;

  -- 1. The four parts are saved; full_name is rebuilt from them by the trigger.
  UPDATE public.user_information
  SET surname = 'Sample', first_name = 'Test Name', middle_initial = 't', suffix = 'jr'
  WHERE user_id = uid
  RETURNING full_name INTO built;

  -- 2. A one-letter surname is rejected by the database.
  BEGIN
    UPDATE public.user_information SET surname = 'X', first_name = 'Juan' WHERE user_id = uid;
  EXCEPTION WHEN OTHERS THEN
    short_rejected := true;
  END;

  -- 3. A suffix that is not Jr., Sr., II, III, IV or V is rejected.
  BEGIN
    UPDATE public.user_information
    SET surname = 'Cruz', first_name = 'Juan', suffix = 'Esq' WHERE user_id = uid;
  EXCEPTION WHEN OTHERS THEN
    suffix_rejected := true;
  END;

  IF built IS DISTINCT FROM 'Test Name T. Sample Jr.'
     OR NOT short_rejected OR NOT suffix_rejected THEN
    RAISE EXCEPTION
      'TEST FAILED (nothing was saved): full_name became "%" (expected "Test Name T. Sample Jr."); one-letter surname rejected = %; bad suffix rejected = %',
      built, short_rejected, suffix_rejected;
  END IF;

  RAISE EXCEPTION
    'TEST PASSED (nothing was saved): the four parts produced full_name "%"; a one-letter surname and an invalid suffix were both rejected',
    built;
END
$$;
