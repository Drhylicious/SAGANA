-- ============================================================
-- SAGANA — Officer permissions, script 27:
--   STAFF ACCOUNTABILITY SHOWS THE RIGHT PERSON, EVERY TIME
--
-- YOUR RULE: every change by a Manager or an Officer with Manage is recorded in Staff
-- Accountability, and each record says WHO did it, WHAT changed and WHEN.
--
-- TWO REAL GAPS FOUND IN THE AUDIT (your two check queries came back empty, so nothing
-- is wrong in your data today; this makes sure it cannot happen)
--
--   1. WHO RECORDED IT COULD BE NAMED BY THE CALLER.
--      record_loan_payment, issue_loan and adjust_inventory_stock take a "recorded by"
--      value from the app. A staff member could send someone else's id and the loan payment,
--      loan or stock movement would carry the wrong name.
--      FIX: when a staff member is the caller, the database uses the caller's own sign-in
--      identity and ignores the value sent. (Internal calls with no staff caller keep
--      whatever they were given.)
--
--   2. AUTOMATIC ROUTINES WERE BLAMED ON WHOEVER OPENED A SCREEN.
--      The app runs transition_overdue_loans, process_shelf_life, process_cooperative_shelf_life
--      and sync_monthly_contributions when a staff member opens a screen. The rows those routines
--      change (a loan becoming Overdue, a listing expiring, a monthly contribution being created)
--      were logged as if that staff member did it.
--      FIX: each routine is wrapped so that, while it runs, the audit trigger knows it is the
--      system working, not a person, and writes no staff line for it. The original body is kept
--      unchanged under the name _sagana_sys_<routine>. The wrapper keeps the same name, arguments,
--      permissions and result, so the cron jobs, the app and the Officer gate keep working.
--
-- Everything is read from YOUR LIVE database and changed in place. If a function does not look
-- as expected, that one is left unchanged and a NOTICE says so. Re-runnable.
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor.
-- ============================================================

-- ─── 1. Who recorded it = the signed-in staff member ─────────────────────────
DO $$
DECLARE
  r record;
  v_def text;
  v_new text;
  v_line text := E'\n  -- Staff Accountability: the recorder is the signed-in staff member, never a value sent by the app.\n'
              || E'  IF auth.uid() IS NOT NULL AND public.is_staff() THEN\n'
              || E'    p_recorded_by := auth.uid();\n'
              || E'  END IF;\n';
BEGIN
  IF to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'public.is_staff() is missing.';
  END IF;
  FOR r IN
    SELECT p.oid, p.oid::regprocedure AS sig, p.proname
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname IN ('record_loan_payment', 'issue_loan', 'adjust_inventory_stock')
      AND pg_get_function_arguments(p.oid) ILIKE '%p_recorded_by%'
  LOOP
    v_def := pg_get_functiondef(r.oid);
    IF position('Staff Accountability: the recorder is the signed-in' IN v_def) > 0 THEN
      RAISE NOTICE '% already forces the recorder; unchanged.', r.sig;
      CONTINUE;
    END IF;
    -- First top-level BEGIN of the body (after any DECLARE section).
    v_new := regexp_replace(v_def, E'(\\n\\s*BEGIN\\s*\\n)', '\1' || replace(v_line, '\', '\\'));
    IF v_new = v_def OR position('p_recorded_by := auth.uid()' IN v_new) = 0 THEN
      RAISE NOTICE '% has no body BEGIN I can anchor on; left unchanged.', r.sig;
      CONTINUE;
    END IF;
    EXECUTE v_new;
    RAISE NOTICE '% now records the signed-in staff member.', r.sig;
  END LOOP;
END $$;

-- ─── 2. The audit trigger skips work the system does on its own ──────────────
DO $$
DECLARE
  r record;
  v_def text;
  v_new text;
  v_found boolean := false;
BEGIN
  FOR r IN
    SELECT p.oid, p.oid::regprocedure AS sig
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace
      AND p.proname = 'audit_staff_change' AND p.pronargs = 0
  LOOP
    v_found := true;
    v_def := pg_get_functiondef(r.oid);
    IF position('sagana.system_action' IN v_def) > 0 THEN
      RAISE NOTICE 'audit_staff_change already knows system actions; unchanged.';
      CONTINUE;
    END IF;
    v_new := regexp_replace(
      v_def,
      E'(IF v_uid IS NULL THEN\\s+RETURN COALESCE\\(NEW, OLD\\);\\s+END IF;)',
      E'\\1\n  -- A routine the system runs by itself (see script 27): no staff member did this, so no staff line.\n'
        || E'  IF COALESCE(current_setting(''sagana.system_action'', true), '''') = ''on'' THEN\n'
        || E'    RETURN COALESCE(NEW, OLD);\n'
        || E'  END IF;'
    );
    IF v_new = v_def OR position('sagana.system_action' IN v_new) = 0 THEN
      RAISE EXCEPTION 'audit_staff_change does not have the expected "IF v_uid IS NULL" block. Nothing changed; send me this function.';
    END IF;
    EXECUTE v_new;
    RAISE NOTICE 'audit_staff_change now skips automatic routines.';
  END LOOP;
  IF NOT v_found THEN
    RAISE EXCEPTION 'audit_staff_change() was not found.';
  END IF;
END $$;

-- ─── 3. Wrap the four automatic routines ─────────────────────────────────────
DO $$
DECLARE
  v_name text;
  v_oid oid;
  v_args text;
  v_result text;
  v_call text;
  v_core text;
BEGIN
  FOREACH v_name IN ARRAY ARRAY['transition_overdue_loans', 'process_shelf_life',
                                'process_cooperative_shelf_life', 'sync_monthly_contributions']
  LOOP
    SELECT p.oid INTO v_oid
    FROM pg_proc p
    WHERE p.pronamespace = 'public'::regnamespace AND p.proname = v_name
    ORDER BY p.pronargs LIMIT 1;
    IF v_oid IS NULL THEN
      RAISE NOTICE '% was not found; skipped.', v_name;
      CONTINUE;
    END IF;
    IF position('sagana.system_action' IN pg_get_functiondef(v_oid)) > 0 THEN
      RAISE NOTICE '% is already wrapped; unchanged.', v_name;
      CONTINUE;
    END IF;
    v_args := pg_get_function_arguments(v_oid);
    v_result := pg_get_function_result(v_oid);
    v_core := '_sagana_sys_' || v_name;
    IF v_args = '' THEN
      v_call := '';
    ELSIF v_name = 'sync_monthly_contributions' AND v_args LIKE 'p_today date%' THEN
      v_call := 'p_today';
    ELSE
      RAISE NOTICE '% has arguments I do not recognise (%); left unchanged.', v_name, v_args;
      CONTINUE;
    END IF;

    -- The original keeps its body under a private name; nobody signed in may call it directly.
    EXECUTE format('ALTER FUNCTION %s RENAME TO %I', v_oid::regprocedure, v_core);
    EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC, anon, authenticated',
                   v_core, regexp_replace(v_args, ' DEFAULT [^,]*', '', 'g'));

    -- The wrapper: same name, arguments and result. It marks the transaction as "system work"
    -- only while the routine runs, then clears the mark.
    EXECUTE format($f$
      CREATE FUNCTION public.%1$I(%2$s)
      RETURNS %3$s
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path TO 'public'
      AS $body$
      DECLARE
        v_out %3$s;
      BEGIN
        PERFORM set_config('sagana.system_action', 'on', true);
        v_out := public.%4$I(%5$s);
        PERFORM set_config('sagana.system_action', 'off', true);
        RETURN v_out;
      END;
      $body$
    $f$, v_name, v_args, v_result, v_core, v_call);

    EXECUTE format('REVOKE ALL ON FUNCTION public.%I(%s) FROM PUBLIC, anon',
                   v_name, regexp_replace(v_args, ' DEFAULT [^,]*', '', 'g'));
    EXECUTE format('GRANT EXECUTE ON FUNCTION public.%I(%s) TO authenticated',
                   v_name, regexp_replace(v_args, ' DEFAULT [^,]*', '', 'g'));
    RAISE NOTICE '% is now marked as system work while it runs.', v_name;
  END LOOP;
END $$;

-- ============================================================
-- CHECKS (read-only; paste the results back if anything looks off)
-- ============================================================

-- A. Which functions now force the recorder, and which routines are wrapped (expect 3 + 4 rows).
SELECT p.proname,
       CASE WHEN pg_get_functiondef(p.oid) LIKE '%p_recorded_by := auth.uid()%' THEN 'recorder forced'
            WHEN pg_get_functiondef(p.oid) LIKE '%sagana.system_action%' THEN 'wrapped as system work'
            ELSE 'NOT CHANGED' END AS state
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN ('record_loan_payment', 'issue_loan', 'adjust_inventory_stock',
                    'transition_overdue_loans', 'process_shelf_life',
                    'process_cooperative_shelf_life', 'sync_monthly_contributions')
ORDER BY p.proname;

-- B. The audit trigger knows about system work (expect one row: true).
SELECT pg_get_functiondef(p.oid) LIKE '%sagana.system_action%' AS audit_trigger_skips_system_work
FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'audit_staff_change';
