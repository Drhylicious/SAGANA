-- ============================================================
-- SAGANA — Outcome review: the Manager OR an Officer can do every step
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Needs p3 and p9.
--
-- WHY
--   The field verification is no longer Officer-only, and the reviewer and the
--   verifier no longer have to be different people. The Manager or an Officer can
--   review the evidence, conduct and record the field verification, and make the
--   final decision, in any combination. Nobody is blocked by a rule about who did
--   the previous step.
--
-- WHAT STAYS (accountability)
--   * The system still records WHO reviewed (reviewed_by / _name / _role / _at),
--     WHO conducted the field verification (verified_by / _name / _role / _at, with the
--     visit date, the finding, the measured quantity and the note) and WHO made the
--     final decision (finalized_by / _name / _role / _at). The Staff Accountability
--     trail and the program History show them.
--   * A decision still needs BOTH the evidence review and the field verification first;
--     a Successful outcome still needs the quantity measured in the field.
--   * Finalizing still needs the return quantity (Successful, Harvest Return programs)
--     or one of the four decisions (Failed), as in p9.
--
-- WHAT IT CHANGES
--   1. Drops the CHECK constraint outcome_reviewer_is_not_verifier.
--   2. review_program_outcome(): no "a different person must review" check.
--   3. verify_program_outcome(): any Manager or Officer (was Officer only), and no
--      "a different person must verify" check.
--   4. finalize_program_outcome(): only the wording of one message changes.
--   Nothing existing is deleted or rewritten; every earlier report keeps its names.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.finalize_program_outcome(uuid,text,text,numeric,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'Apply the p9 script first.';
  END IF;
END $$;

ALTER TABLE public.program_outcome_reports
  DROP CONSTRAINT IF EXISTS outcome_reviewer_is_not_verifier;

CREATE OR REPLACE FUNCTION public.review_program_outcome(
  p_report_id UUID,
  p_decision  TEXT,
  p_note      TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   UUID := auth.uid();
  v_r     program_outcome_reports%ROWTYPE;
  v_note  TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_name  TEXT;
  v_role  TEXT;
  v_prog  TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can review an outcome report.';
  END IF;
  IF p_decision NOT IN ('validated', 'returned') THEN
    RAISE EXCEPTION 'The decision must be validated or returned.';
  END IF;

  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Outcome report not found.';
  END IF;
  IF v_r.status <> 'pending_validation' THEN
    RAISE EXCEPTION 'This report is no longer waiting for review (status: %).', v_r.status;
  END IF;
  IF v_r.review_decision IS NOT NULL THEN
    RAISE EXCEPTION 'The evidence on this report was already reviewed.';
  END IF;
  IF p_decision = 'returned' AND v_note IS NULL THEN
    RAISE EXCEPTION 'Explain what the Farmer needs to fix.';
  END IF;

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();

  UPDATE program_outcome_reports
     SET review_decision  = p_decision,
         reviewed_by      = v_uid,
         reviewed_by_name = v_name,
         reviewed_by_role = v_role,
         reviewed_at      = NOW(),
         review_note      = v_note,
         status           = CASE WHEN p_decision = 'returned' THEN 'returned' ELSE status END
   WHERE id = p_report_id;

  IF p_decision = 'returned' THEN
    SELECT program_name INTO v_prog FROM cooperative_programs WHERE id = v_r.program_id;
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (v_r.farmer_id, 'program', 'Outcome Report Returned',
            'Your outcome report for ' || COALESCE(v_prog, 'the program') ||
              ' needs more evidence: ' || v_note || ' Please submit a new report.',
            FALSE, NOW(), '/farmer/profile/programs/enrolled');
  END IF;
END;
$function$;
REVOKE ALL ON FUNCTION public.review_program_outcome(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.review_program_outcome(UUID, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.verify_program_outcome(
  p_report_id        UUID,
  p_finding          TEXT,
  p_verified_quantity NUMERIC,
  p_verified_unit    TEXT,
  p_field_visit_date DATE,
  p_note             TEXT,
  p_photo_paths      TEXT[]
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid   UUID := auth.uid();
  v_r     program_outcome_reports%ROWTYPE;
  v_name  TEXT;
  v_role  TEXT;
  v_path  TEXT;
BEGIN
  -- The Manager or an Officer conducts the field verification. Who did it is recorded.
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can record the field verification.';
  END IF;
  IF p_finding NOT IN ('confirms', 'disputes') THEN
    RAISE EXCEPTION 'The finding must be confirms or disputes.';
  END IF;
  IF p_note IS NULL OR btrim(p_note) = '' THEN
    RAISE EXCEPTION 'Write what you found during the field verification.';
  END IF;
  IF p_field_visit_date IS NULL THEN
    RAISE EXCEPTION 'Enter the date of the field visit.';
  END IF;
  IF p_field_visit_date > (NOW() AT TIME ZONE 'Asia/Manila')::DATE THEN
    RAISE EXCEPTION 'The field visit date cannot be in the future.';
  END IF;

  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Outcome report not found.';
  END IF;
  IF v_r.status <> 'pending_validation' THEN
    RAISE EXCEPTION 'This report is no longer waiting for verification (status: %).', v_r.status;
  END IF;
  IF v_r.verified_by IS NOT NULL THEN
    RAISE EXCEPTION 'The field verification for this report was already recorded.';
  END IF;
  -- A successful report is checked against what was actually measured.
  IF v_r.reported_outcome = 'successful'
     AND (p_verified_quantity IS NULL OR p_verified_quantity <= 0
          OR p_verified_unit IS NULL OR btrim(p_verified_unit) = '') THEN
    RAISE EXCEPTION 'Enter the quantity you measured in the field and its unit.';
  END IF;

  PERFORM public._outcome_check_paths(p_photo_paths, 0, 5);

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();

  UPDATE program_outcome_reports
     SET verification_finding = p_finding,
         verified_by          = v_uid,
         verified_by_name     = v_name,
         verified_by_role     = v_role,
         verified_at          = NOW(),
         field_visit_date     = p_field_visit_date,
         verified_quantity    = CASE WHEN v_r.reported_outcome = 'successful' THEN p_verified_quantity END,
         verified_unit        = CASE WHEN v_r.reported_outcome = 'successful' THEN btrim(p_verified_unit) END,
         verification_note    = btrim(p_note)
   WHERE id = p_report_id;

  FOREACH v_path IN ARRAY COALESCE(p_photo_paths, ARRAY[]::TEXT[]) LOOP
    INSERT INTO program_outcome_photos (report_id, uploaded_by, uploader_role, storage_path)
    VALUES (p_report_id, v_uid, 'staff', v_path);
  END LOOP;
END;
$function$;
REVOKE ALL ON FUNCTION public.verify_program_outcome(UUID, TEXT, NUMERIC, TEXT, DATE, TEXT, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_program_outcome(UUID, TEXT, NUMERIC, TEXT, DATE, TEXT, TEXT[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.finalize_program_outcome(
  p_report_id       UUID,
  p_final_outcome   TEXT,
  p_note            TEXT DEFAULT NULL,
  p_return_quantity NUMERIC DEFAULT NULL,   -- Successful, Harvest Return programs: required
  p_return_unit     TEXT DEFAULT NULL,
  p_resolution      TEXT DEFAULT NULL,      -- Failed: one of the four decisions
  p_resolution_note TEXT DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid  UUID := auth.uid();
  v_r    program_outcome_reports%ROWTYPE;
  v_p    cooperative_programs%ROWTYPE;
  v_note TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_rnote TEXT := NULLIF(btrim(COALESCE(p_resolution_note, '')), '');
  v_name TEXT;
  v_role TEXT;
  v_prog TEXT;
  v_returns BOOLEAN;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can finalize an outcome.';
  END IF;
  IF p_final_outcome NOT IN ('successful', 'failed') THEN
    RAISE EXCEPTION 'The final outcome must be successful or failed.';
  END IF;

  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Outcome report not found.';
  END IF;
  IF v_r.status = 'finalized' THEN
    RAISE EXCEPTION 'This outcome was already finalized.';
  END IF;
  IF v_r.status <> 'pending_validation' THEN
    RAISE EXCEPTION 'This report cannot be finalized (status: %).', v_r.status;
  END IF;
  -- Nothing is confirmed just because the Farmer submitted it: the evidence must
  -- be reviewed AND the field verification done first.
  IF v_r.review_decision IS DISTINCT FROM 'validated' THEN
    RAISE EXCEPTION 'The evidence must be reviewed and validated first.';
  END IF;
  IF v_r.verified_by IS NULL THEN
    RAISE EXCEPTION 'The field verification must be completed first.';
  END IF;
  IF (p_final_outcome <> v_r.reported_outcome OR v_r.verification_finding = 'disputes') AND v_note IS NULL THEN
    RAISE EXCEPTION 'Explain the decision: it differs from the report or the field verification disputed it.';
  END IF;

  SELECT * INTO v_p FROM cooperative_programs WHERE id = v_r.program_id;
  v_returns := (v_p.benefit_type = 'revenue_share');

  IF p_final_outcome = 'successful' AND v_returns THEN
    IF p_return_quantity IS NULL OR p_return_quantity <= 0 OR p_return_quantity <> round(p_return_quantity, 2)
       OR NULLIF(btrim(COALESCE(p_return_unit, '')), '') IS NULL THEN
      RAISE EXCEPTION 'RETURN_QUANTITY: Enter the quantity and unit the Farmer must return.';
    END IF;
  END IF;
  IF p_final_outcome = 'failed' THEN
    IF p_resolution IS NULL OR p_resolution NOT IN ('closed_no_further_obligation', 'eligible_for_reassessment',
                                                    'referred_for_loan_assessment', 'pending_cooperative_decision') THEN
      RAISE EXCEPTION 'RESOLUTION_INVALID: Choose one of the four decisions.';
    END IF;
    IF p_resolution <> 'pending_cooperative_decision' AND v_rnote IS NULL THEN
      RAISE EXCEPTION 'RESOLUTION_INVALID: A note is required for this decision.';
    END IF;
  END IF;

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();

  UPDATE program_outcome_reports
     SET status            = 'finalized',
         final_outcome     = p_final_outcome,
         finalized_by      = v_uid,
         finalized_by_name = v_name,
         finalized_by_role = v_role,
         finalized_at      = NOW(),
         final_note        = v_note
   WHERE id = p_report_id;

  UPDATE program_members
     SET distribution_outcome = CASE p_final_outcome WHEN 'successful' THEN 'thriving' ELSE 'failed' END,
         outcome_recorded_at  = NOW()
   WHERE id = v_r.program_member_id;

  IF p_final_outcome = 'successful' THEN
    IF v_returns THEN
      PERFORM public._program_open_return(p_report_id, p_return_quantity, p_return_unit);
    END IF;
  ELSE
    PERFORM public._program_open_resolution(p_report_id, p_resolution, v_rnote);
  END IF;

  v_prog := v_p.program_name;
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_r.farmer_id, 'program',
          CASE p_final_outcome WHEN 'successful' THEN 'Program Outcome: Successful' ELSE 'Program Outcome: Failed' END,
          'Your outcome for ' || COALESCE(v_prog, 'the program') || ' was confirmed as ' || p_final_outcome || '.',
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
END;
$function$;
REVOKE ALL ON FUNCTION public.finalize_program_outcome(UUID, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finalize_program_outcome(UUID, TEXT, TEXT, NUMERIC, TEXT, TEXT, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  The separation rule is gone (expect 0 rows):
--     SELECT conname FROM pg_constraint WHERE conname = 'outcome_reviewer_is_not_verifier';
-- V2  Verification is open to staff, not just Officers (expect true, false):
--     SELECT pg_get_functiondef('public.verify_program_outcome(uuid,text,numeric,text,date,text,text[])'::regprocedure) ILIKE '%is_staff()%',
--            pg_get_functiondef('public.verify_program_outcome(uuid,text,numeric,text,date,text,text[])'::regprocedure) ILIKE '%different person%';
-- V3  Who did each step is still stored (after a test report):
--     SELECT reviewed_by_name, reviewed_by_role, verified_by_name, verified_by_role, finalized_by_name, finalized_by_role
--       FROM program_outcome_reports ORDER BY submitted_at DESC LIMIT 5;
