-- ============================================================
-- SAGANA — p35: the final outcome follows the field verification (database side)
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Adds one rule; the existing functions are not
-- replaced and nothing already finalized is touched (only a NEW finalization is checked).
--
--   Field verification CONFIRMS the report            -> the final outcome must be what the Farmer reported.
--   Field verification DISPUTES a reported FAILURE    -> the final outcome must be Successful (it did not fail).
--   Field verification DISPUTES a reported SUCCESS    -> the Manager chooses Successful (less than claimed) or
--                                                         Failed (nothing there).
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public._outcome_final_follows_verification()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.status = 'finalized' AND OLD.status IS DISTINCT FROM 'finalized' THEN
    IF NEW.verification_finding = 'confirms' AND NEW.final_outcome IS DISTINCT FROM NEW.reported_outcome THEN
      RAISE EXCEPTION 'OUTCOME_LOCKED: The field verification confirmed the Farmer''s report, so the final outcome is the one reported.';
    END IF;
    IF NEW.verification_finding = 'disputes' AND NEW.reported_outcome = 'failed'
       AND NEW.final_outcome IS DISTINCT FROM 'successful' THEN
      RAISE EXCEPTION 'OUTCOME_LOCKED: The field verification disputed the reported failure, so the final outcome is Successful.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_outcome_final_follows_verification ON public.program_outcome_reports;
CREATE TRIGGER trg_outcome_final_follows_verification
  BEFORE UPDATE ON public.program_outcome_reports
  FOR EACH ROW EXECUTE FUNCTION public._outcome_final_follows_verification();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECKS
-- Y1  The rule is installed (expect 1 row):
--     SELECT tgname FROM pg_trigger WHERE tgname = 'trg_outcome_final_follows_verification' AND NOT tgisinternal;
-- Y2  Finalized reports that do NOT follow the rule (information only; nothing is changed). Expect none created from now on:
--     SELECT id, reported_outcome, verification_finding, final_outcome FROM program_outcome_reports
--      WHERE status = 'finalized'
--        AND ((verification_finding = 'confirms' AND final_outcome IS DISTINCT FROM reported_outcome)
--          OR (verification_finding = 'disputes' AND reported_outcome = 'failed' AND final_outcome IS DISTINCT FROM 'successful'));
