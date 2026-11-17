-- ============================================================
-- SAGANA — p43: every Final Decision is final (Closed, Referred for Loan Assessment, Eligible for Reassessment)
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p37. No data is changed or deleted.
--
-- Once the Outcome Review ends in a Final Decision, it stays. After this script, once the LATEST decision on a Failed
-- outcome is any of:
--   * Closed: No Further Obligation        (already so since p37),
--   * Referred for Loan Assessment         (new),
--   * Eligible for Reassessment            (new),
-- no other decision can be recorded on it. "Eligible for Reassessment" still leads somewhere: the Farmer's request
-- for another distribution (p36), or staff giving another item, starts the next round, which has its own Outcome
-- Review. "Pending Cooperative Decision" is the only decision that can still be replaced: it is the state waiting
-- for the Final Decision.
--
-- Cases already Referred or Eligible are covered the moment this runs. The Farmer's loan request, its approval and the program
-- link of p42 are not affected.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public._failed_resolution_closed_is_final()') IS NULL THEN
    RAISE EXCEPTION 'Apply p37 first.';
  END IF;
END $$;

-- Same function and trigger as p37 (trg_failed_resolution_closed_is_final), now covering Referred as well.
CREATE OR REPLACE FUNCTION public._failed_resolution_closed_is_final()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_latest TEXT;
BEGIN
  SELECT f.resolution INTO v_latest FROM program_failure_resolutions f
   WHERE f.program_member_id = NEW.program_member_id
   ORDER BY f.created_at DESC LIMIT 1;
  IF v_latest = 'closed_no_further_obligation' THEN
    RAISE EXCEPTION 'RESOLUTION_LOCKED: This case is closed. No further decision, assistance, loan or reassessment can follow.';
  END IF;
  IF v_latest IN ('referred_for_loan_assessment', 'eligible_for_reassessment') THEN
    RAISE EXCEPTION 'RESOLUTION_FINAL: This decision is final and can no longer be changed.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_failed_resolution_closed_is_final ON public.program_failure_resolutions;
CREATE TRIGGER trg_failed_resolution_closed_is_final
  BEFORE INSERT ON public.program_failure_resolutions
  FOR EACH ROW EXECUTE FUNCTION public._failed_resolution_closed_is_final();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECK (the rule is installed; expect 1 row):
--   SELECT tgname FROM pg_trigger WHERE tgname = 'trg_failed_resolution_closed_is_final' AND NOT tgisinternal;
-- CHECK (cases that are now final):
--   SELECT ui.full_name, f.resolution
--     FROM (SELECT DISTINCT ON (program_member_id) * FROM program_failure_resolutions ORDER BY program_member_id, created_at DESC) f
--     LEFT JOIN user_information ui ON ui.user_id = f.farmer_id
--    WHERE f.resolution IN ('closed_no_further_obligation', 'referred_for_loan_assessment', 'eligible_for_reassessment');
