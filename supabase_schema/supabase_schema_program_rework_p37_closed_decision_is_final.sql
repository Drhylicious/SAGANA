-- ============================================================
-- SAGANA — p37: "Closed: No Further Obligation" is final
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p36. No data is changed or deleted.
--
-- Closed means closed. Once the LATEST decision on a Failed outcome is "Closed: No Further Obligation":
--   * No assistance can be requested or approved for that case (the assistance check now answers "closed").
--   * No other decision can be recorded on it (so it can never become Eligible, Referred or Pending afterwards).
--   * Because it can no longer become Eligible, no second distribution or reassessment can follow: a request for
--     another distribution already needs the latest decision to be Eligible for Reassessment.
-- Cases already Closed are covered the moment this runs. A Farmer's own, ordinary Request a Loan is not tied to a
-- program case and is not affected.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.program_failure_resolutions') IS NULL THEN
    RAISE EXCEPTION 'Apply p25 and p36 first.';
  END IF;
END $$;

-- 1. Assistance: a closed case is not eligible (same function as p9, plus the closed check).
CREATE OR REPLACE FUNCTION public._assistance_blocker(p_member_id UUID, p_farmer UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m      program_members%ROWTYPE;
BEGIN
  SELECT * INTO v_m FROM program_members WHERE id = p_member_id;
  IF NOT FOUND OR v_m.farmer_id IS DISTINCT FROM p_farmer
     OR v_m.status <> 'active' OR COALESCE(v_m.distribution_outcome, '') <> 'failed' THEN
    RETURN 'not_eligible';
  END IF;
  IF (SELECT f.resolution FROM program_failure_resolutions f
       WHERE f.program_member_id = p_member_id
       ORDER BY f.created_at DESC LIMIT 1) = 'closed_no_further_obligation' THEN
    RETURN 'closed';
  END IF;
  IF EXISTS (SELECT 1 FROM program_assistance_requests
              WHERE program_member_id = p_member_id AND status = 'pending') THEN
    RETURN 'pending';
  END IF;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public._assistance_blocker(UUID, UUID) FROM PUBLIC, anon, authenticated;

-- 2. No new decision after Closed.
CREATE OR REPLACE FUNCTION public._failed_resolution_closed_is_final()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF (SELECT f.resolution FROM program_failure_resolutions f
       WHERE f.program_member_id = NEW.program_member_id
       ORDER BY f.created_at DESC LIMIT 1) = 'closed_no_further_obligation' THEN
    RAISE EXCEPTION 'RESOLUTION_LOCKED: This case is closed. No further decision, assistance, loan or reassessment can follow.';
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

-- CHECKS
-- C1  The rule is installed (expect 1 row):
--     SELECT tgname FROM pg_trigger WHERE tgname = 'trg_failed_resolution_closed_is_final' AND NOT tgisinternal;
-- C2  Closed cases and what the assistance check now answers for them (expect 'closed' for each):
--     SELECT ui.full_name, f.resolution, public._assistance_blocker(f.program_member_id, f.farmer_id) AS blocker
--       FROM (SELECT DISTINCT ON (program_member_id) * FROM program_failure_resolutions ORDER BY program_member_id, created_at DESC) f
--       LEFT JOIN user_information ui ON ui.user_id = f.farmer_id
--      WHERE f.resolution = 'closed_no_further_obligation';
