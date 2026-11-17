-- ============================================================
-- SAGANA — p38: the outcome report follows one order (database side)
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Adds one rule; no function is replaced and no
-- existing record is changed.
--
--   1. Evidence Review is completed and submitted first.
--   2. Only then can the Field Verification be recorded: it is refused unless the evidence was VALIDATED.
--      (A report returned to the Farmer never gets a field verification; the Farmer's new report does.)
--   3. The Final Decision needs both, as before.
--
-- Only a NEW field verification is checked. Reports already verified before this rule keep their record.
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public._outcome_verify_after_review()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF OLD.verified_at IS NULL AND NEW.verified_at IS NOT NULL
     AND NEW.review_decision IS DISTINCT FROM 'validated' THEN
    RAISE EXCEPTION 'VERIFY_AFTER_REVIEW: Complete and submit the evidence review first. The field verification opens once the evidence is validated.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_outcome_verify_after_review ON public.program_outcome_reports;
CREATE TRIGGER trg_outcome_verify_after_review
  BEFORE UPDATE OF verified_at ON public.program_outcome_reports
  FOR EACH ROW EXECUTE FUNCTION public._outcome_verify_after_review();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECKS
-- V1  The rule is installed (expect 1 row):
--     SELECT tgname FROM pg_trigger WHERE tgname = 'trg_outcome_verify_after_review' AND NOT tgisinternal;
-- V2  Reports verified before the rule that were never validated (information only; nothing is changed):
--     SELECT id, review_decision, verified_at FROM program_outcome_reports
--      WHERE verified_at IS NOT NULL AND review_decision IS DISTINCT FROM 'validated';
