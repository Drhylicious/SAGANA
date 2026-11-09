-- ============================================================
-- SAGANA — One-time clean-up: remove three EMPTY programs
--
-- FOR YOUR REVIEW — NOT APPLIED. Run it in the Supabase SQL editor after you have
-- checked the PREVIEW below. One transaction: it either removes all three or nothing.
--
-- REMOVES (by exact name)
--   Organic Farming Assistance Program
--   Government Seed Distribution
--   Government Fertilizer Distribution
--
-- KEEPS EVERYTHING ELSE. Every other program, every enrolled member, every enrollment
-- request, outcome report, return, purchase and History row of the other programs is
-- untouched. (Your audit showed members only in Livestock Dispersal, Peanut Cookies and
-- Peanut Seed Distribution: those are not touched.)
--
-- WHY IT NEEDS TO TURN A GUARD OFF
--   Since the completion rules, the database refuses ALL program deletions
--   (PROGRAM_NO_DELETE). This script switches that guard off for this one statement,
--   inside the same transaction, and switches it back on straight away. If anything goes
--   wrong the whole transaction is rolled back and the guard is exactly as it was.
--
-- SAFETY CHECKS (the script stops, changing nothing, if any of them fails)
--   * exactly three programs match those names;
--   * none of the three has ANY member row (active, withdrawn or completed), purchase,
--     outcome report, return, failure resolution or assistance request;
--   * none has an APPROVED enrollment request (that would mean someone really was enrolled).
--   Any pending or rejected enrollment requests, products and activities that belong ONLY
--   to these three programs are removed with them (the database removes them automatically);
--   the preview shows how many.
-- ============================================================

-- PREVIEW — run this first, by itself (read-only). Every count should be 0 except possibly
-- requests / products / activities. Anything else means: STOP and tell me.
SELECT cp.program_name, cp.program_purpose, cp.status,
       (SELECT count(*) FROM program_members m WHERE m.program_id = cp.id)                       AS members,
       (SELECT count(*) FROM program_enrollment_requests r WHERE r.program_id = cp.id)           AS requests,
       (SELECT count(*) FROM program_enrollment_requests r WHERE r.program_id = cp.id AND r.status = 'approved') AS approved_requests,
       (SELECT count(*) FROM program_product_purchases p WHERE p.program_id = cp.id)             AS purchases,
       (SELECT count(*) FROM program_outcome_reports o WHERE o.program_id = cp.id)               AS outcome_reports,
       (SELECT count(*) FROM program_returns x WHERE x.program_id = cp.id)                       AS returns,
       (SELECT count(*) FROM program_assistance_requests a WHERE a.program_id = cp.id)           AS assistance,
       (SELECT count(*) FROM program_products pp WHERE pp.program_id = cp.id)                   AS products
  FROM cooperative_programs cp
 WHERE cp.program_name IN ('Organic Farming Assistance Program',
                           'Government Seed Distribution',
                           'Government Fertilizer Distribution')
 ORDER BY cp.program_name;

-- THE REMOVAL — run this after the preview looks right.
BEGIN;

DO $$
DECLARE
  v_ids   UUID[];
  v_names TEXT;
BEGIN
  SELECT array_agg(id), string_agg(program_name, ', ' ORDER BY program_name)
    INTO v_ids, v_names
    FROM cooperative_programs
   WHERE program_name IN ('Organic Farming Assistance Program',
                          'Government Seed Distribution',
                          'Government Fertilizer Distribution');

  IF COALESCE(array_length(v_ids, 1), 0) <> 3 THEN
    RAISE EXCEPTION 'Expected exactly 3 matching programs, found %. Nothing was changed.',
      COALESCE(array_length(v_ids, 1), 0);
  END IF;

  IF EXISTS (SELECT 1 FROM program_members WHERE program_id = ANY (v_ids)) THEN
    RAISE EXCEPTION 'One of these programs has member rows. Nothing was changed.';
  END IF;
  IF EXISTS (SELECT 1 FROM program_enrollment_requests WHERE program_id = ANY (v_ids) AND status = 'approved') THEN
    RAISE EXCEPTION 'One of these programs has an approved enrollment request. Nothing was changed.';
  END IF;
  IF EXISTS (SELECT 1 FROM program_product_purchases WHERE program_id = ANY (v_ids))
     OR EXISTS (SELECT 1 FROM program_outcome_reports WHERE program_id = ANY (v_ids))
     OR EXISTS (SELECT 1 FROM program_returns WHERE program_id = ANY (v_ids))
     OR EXISTS (SELECT 1 FROM program_failure_resolutions WHERE program_id = ANY (v_ids))
     OR EXISTS (SELECT 1 FROM program_assistance_requests WHERE program_id = ANY (v_ids)) THEN
    RAISE EXCEPTION 'One of these programs has purchases, outcomes, returns or assistance records. Nothing was changed.';
  END IF;

  -- Switch the delete guard off for this one statement, then straight back on.
  EXECUTE 'ALTER TABLE public.cooperative_programs DISABLE TRIGGER trg_protect_program_from_delete';
  DELETE FROM public.cooperative_programs WHERE id = ANY (v_ids);
  EXECUTE 'ALTER TABLE public.cooperative_programs ENABLE TRIGGER trg_protect_program_from_delete';

  RAISE NOTICE 'Removed 3 programs: %', v_names;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  The three are gone and the other programs are all still there:
--     SELECT program_name, status FROM cooperative_programs ORDER BY program_name;
-- V2  The delete guard is on again (expect enabled = 'O'):
--     SELECT tgname, tgenabled FROM pg_trigger WHERE tgname = 'trg_protect_program_from_delete';
-- V3  Nothing of the kept programs changed (same counts as your audit: 6 enrolled members):
--     SELECT count(*) FROM program_members WHERE status = 'active';
