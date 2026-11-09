-- ============================================================
-- SAGANA — Program Management rework, PHASE 9:
--          OUTCOME DECISIONS MADE DURING REVIEW, SETTINGS REMOVED
--
-- FOR YOUR REVIEW — NOT APPLIED. Run it in the Supabase SQL editor only after you
-- have checked it. One transaction. Needs p3, p6 and p7 (already applied).
--
-- WHY
--   You decided that nothing about a case is set in advance. The Manager or
--   Officer decides during the outcome review itself:
--     * SUCCESSFUL  -> after the field verification, the reviewer enters the
--                      quantity and unit the Farmer must return; that creates the
--                      Harvest Return record.
--     * FAILED      -> after the field verification, the reviewer picks one of the
--                      four cooperative decisions (with a note).
--   And the three optional settings (underreporting tolerance, assistance request
--   limit, assistance deadline) are removed.
--
-- WHAT IT CHANGES
--   1. finalize_program_outcome()  new signature: also takes the return quantity /
--      unit (Successful, Harvest Return programs: REQUIRED) or the resolution and
--      its note (Failed). It still refuses to finalize until the evidence is
--      reviewed AND the Officer's field verification is done.
--      The old 3-argument version is dropped (it would otherwise keep creating a
--      return from the program's fixed quantity).
--   2. _program_open_return()  now uses the quantity/unit the reviewer entered.
--      It no longer computes the underreporting flag.
--   3. _program_open_resolution()  records the reviewer's decision (not an
--      automatic default) when an outcome is finalized as Failed.
--   4. record_failed_resolution()  the note is required for the three decisions
--      and optional for "Pending Cooperative Decision".
--   5. submit_program_outcome_report()  every detail is required: date planted,
--      harvest date (Successful) / date it failed (Failed), as well as the rest.
--      The area planted is no longer asked for.
--   6. get_program_outcome_reports()  also says whether a harvest return applies.
--   7. Settings removed: set_underreport_tolerance(), set_assistance_setting() and
--      get_program_settings() are dropped. _assistance_blocker() and
--      submit_assistance_request() no longer apply a limit or a deadline.
--      Only the duplicate guard stays: one PENDING request per failed outcome.
--
-- WHAT IT DOES NOT TOUCH (nothing historical is lost)
--   * Existing program_returns, receipts, events and resolutions stay exactly as
--     they are, including returns already opened from a program's quantity.
--     Columns underreport_flag / reported_quantity / verified_quantity stay (the
--     flag simply stops being set).
--   * The table program_settings and its rows stay (nothing reads them any more).
--     To remove them later, once you are sure:  DROP TABLE public.program_settings;
--   * Area columns on program_outcome_reports stay for old reports.
--   * Loans, inventory, Product Sales and every other table.
--
-- NEW CODE-PREFIXED ERRORS: RETURN_QUANTITY, ASSIST_PENDING
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.finalize_program_outcome(uuid,text,text)') IS NULL
     AND to_regprocedure('public.finalize_program_outcome(uuid,text,text,numeric,text,text,text)') IS NULL THEN
    RAISE EXCEPTION 'finalize_program_outcome() was not found; apply p3 and p6 first.';
  END IF;
  IF to_regclass('public.program_returns') IS NULL OR to_regclass('public.program_assistance_requests') IS NULL THEN
    RAISE EXCEPTION 'Apply the p6 and p7 scripts first.';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1. Remove the old versions first
-- ════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.finalize_program_outcome(UUID, TEXT, TEXT);
DROP FUNCTION IF EXISTS public._program_open_return(UUID);
DROP FUNCTION IF EXISTS public._program_open_resolution(UUID);
DROP FUNCTION IF EXISTS public.set_underreport_tolerance(NUMERIC);
DROP FUNCTION IF EXISTS public.set_assistance_setting(TEXT, NUMERIC);
DROP FUNCTION IF EXISTS public.get_program_settings();

-- ════════════════════════════════════════════════════════════
-- 2. The Harvest Return is opened with what the reviewer decided
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._program_open_return(
  p_report_id UUID,
  p_quantity  NUMERIC,
  p_unit      TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_r    program_outcome_reports%ROWTYPE;
  v_p    cooperative_programs%ROWTYPE;
  v_crop TEXT;
  v_name TEXT;
  v_id   UUID;
BEGIN
  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id;
  SELECT * INTO v_p FROM cooperative_programs   WHERE id = v_r.program_id;
  IF v_p.benefit_type IS DISTINCT FROM 'revenue_share' OR v_p.return_crop_id IS NULL THEN
    RETURN NULL;                       -- not a Harvest Return program
  END IF;
  SELECT id INTO v_id FROM program_returns WHERE program_member_id = v_r.program_member_id;
  IF FOUND THEN RETURN v_id; END IF;

  SELECT crop_name INTO v_crop FROM crop_master WHERE id = v_p.return_crop_id;
  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_r.farmer_id;

  INSERT INTO program_returns (
    program_id, program_member_id, farmer_id, farmer_name, outcome_report_id,
    crop_id, crop_name, unit, original_quantity, due_quantity,
    reported_quantity, verified_quantity, underreport_flag
  ) VALUES (
    v_r.program_id, v_r.program_member_id, v_r.farmer_id, v_name, v_r.id,
    v_p.return_crop_id, COALESCE(v_crop, 'Crop'), btrim(p_unit),
    p_quantity, p_quantity,
    v_r.quantity_harvested, v_r.verified_quantity, FALSE
  ) RETURNING id INTO v_id;

  INSERT INTO program_return_events (return_id, event_type, quantity_after, actor_id, actor_name, actor_role)
  SELECT v_id, 'created', p_quantity, auth.uid(), a_name, a_role FROM public._outcome_actor();

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_r.farmer_id, 'program', 'Harvest Return Due',
          'Your outcome for ' || v_p.program_name || ' was confirmed as successful after the field verification. '
            || 'You are to return ' || p_quantity || ' ' || btrim(p_unit) || ' ' || COALESCE(v_crop, '') ||
            ' to the cooperative.',
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
  RETURN v_id;
END;
$function$;
REVOKE ALL ON FUNCTION public._program_open_return(UUID, NUMERIC, TEXT) FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 3. The Failed decision is the reviewer's, with a note
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public._program_open_resolution(
  p_report_id  UUID,
  p_resolution TEXT,
  p_note       TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_r    program_outcome_reports%ROWTYPE;
  v_name TEXT;
  v_role TEXT;
BEGIN
  SELECT * INTO v_r FROM program_outcome_reports WHERE id = p_report_id;
  IF EXISTS (SELECT 1 FROM program_failure_resolutions WHERE program_member_id = v_r.program_member_id) THEN
    RETURN;
  END IF;
  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();
  INSERT INTO program_failure_resolutions
    (program_member_id, program_id, farmer_id, outcome_report_id, resolution, note,
     decided_by, decided_by_name, decided_by_role)
  VALUES (v_r.program_member_id, v_r.program_id, v_r.farmer_id, v_r.id,
          COALESCE(p_resolution, 'pending_cooperative_decision'),
          NULLIF(btrim(COALESCE(p_note, '')), ''), auth.uid(), v_name, v_role);
END;
$function$;
REVOKE ALL ON FUNCTION public._program_open_resolution(UUID, TEXT, TEXT) FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 4. finalize_program_outcome(): the decision is made here, after verification
-- ════════════════════════════════════════════════════════════
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
    RAISE EXCEPTION 'An Officer must complete the field verification first.';
  END IF;
  IF (p_final_outcome <> v_r.reported_outcome OR v_r.verification_finding = 'disputes') AND v_note IS NULL THEN
    RAISE EXCEPTION 'Explain the decision: it differs from the report or the field verification disputed it.';
  END IF;

  SELECT * INTO v_p FROM cooperative_programs WHERE id = v_r.program_id;
  v_returns := (v_p.benefit_type = 'revenue_share' AND v_p.return_crop_id IS NOT NULL);

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

-- ════════════════════════════════════════════════════════════
-- 5. Changing a decision later: the note is required for the three decisions
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.record_failed_resolution(
  p_program_member_id UUID,
  p_resolution        TEXT,
  p_note              TEXT
) RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m    program_members%ROWTYPE;
  v_note TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_name TEXT;
  v_role TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can record a resolution.';
  END IF;
  IF p_resolution NOT IN ('closed_no_further_obligation', 'eligible_for_reassessment',
                          'referred_for_loan_assessment', 'pending_cooperative_decision') THEN
    RAISE EXCEPTION 'RESOLUTION_INVALID: Choose one of the listed resolutions.';
  END IF;
  IF p_resolution <> 'pending_cooperative_decision' AND v_note IS NULL THEN
    RAISE EXCEPTION 'RESOLUTION_INVALID: A note is required for this decision.';
  END IF;
  SELECT * INTO v_m FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  IF NOT FOUND OR COALESCE(v_m.distribution_outcome, '') <> 'failed' THEN
    RAISE EXCEPTION 'RESOLUTION_INVALID: Only a Failed outcome has a resolution.';
  END IF;

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();
  -- Appended, never edited: the previous decision stays in the history.
  INSERT INTO program_failure_resolutions
    (program_member_id, program_id, farmer_id, outcome_report_id, resolution, note,
     decided_by, decided_by_name, decided_by_role)
  SELECT v_m.id, v_m.program_id, v_m.farmer_id,
         (SELECT r.id FROM program_outcome_reports r
           WHERE r.program_member_id = v_m.id AND r.status = 'finalized'
           ORDER BY r.finalized_at DESC NULLS LAST LIMIT 1),
         p_resolution, v_note, auth.uid(), v_name, v_role;
END;
$function$;
REVOKE ALL ON FUNCTION public.record_failed_resolution(UUID, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_failed_resolution(UUID, TEXT, TEXT) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 6. Farmer report: every detail required (same signature as before)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.submit_program_outcome_report(
  p_program_member_id UUID,
  p_outcome           TEXT,
  p_explanation       TEXT,
  p_planted_date      DATE,
  p_harvest_date      DATE,
  p_quantity          NUMERIC,
  p_unit              TEXT,
  p_area              NUMERIC,
  p_area_unit         TEXT,
  p_failure_cause     TEXT,
  p_failure_date      DATE,
  p_photo_paths       TEXT[]
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid     UUID := auth.uid();
  v_member  program_members%ROWTYPE;
  v_program cooperative_programs%ROWTYPE;
  v_id      UUID;
  v_path    TEXT;
  v_farmer  TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'You must be signed in.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = v_uid AND role = 'farmer' AND status = 'active') THEN
    RAISE EXCEPTION 'Only an active cooperative member can report an outcome.';
  END IF;

  SELECT * INTO v_member FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  IF NOT FOUND OR v_member.farmer_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'Program enrollment not found.';
  END IF;
  IF v_member.status <> 'active' THEN
    RAISE EXCEPTION 'Only an active member can report an outcome.';
  END IF;
  IF v_member.distributed_at IS NULL THEN
    RAISE EXCEPTION 'You can report an outcome after you have received the program item.';
  END IF;

  SELECT * INTO v_program FROM cooperative_programs WHERE id = v_member.program_id;
  IF v_program.program_purpose <> 'distribution' THEN
    RAISE EXCEPTION 'Outcomes are reported for distribution programs only.';
  END IF;

  IF EXISTS (SELECT 1 FROM program_outcome_reports
              WHERE program_member_id = p_program_member_id AND status <> 'returned') THEN
    RAISE EXCEPTION 'An outcome report for this program is already in progress or finished.';
  END IF;
  -- Earlier recorded (legacy) outcome with no report: not reported again.
  IF v_member.distribution_outcome IN ('thriving', 'failed') THEN
    RAISE EXCEPTION 'An outcome was already recorded for this program.';
  END IF;

  IF p_outcome NOT IN ('successful', 'failed') THEN
    RAISE EXCEPTION 'Choose Successful or Failed.';
  END IF;
  IF p_explanation IS NULL OR btrim(p_explanation) = '' THEN
    RAISE EXCEPTION 'Write your explanation.';
  END IF;
  IF p_outcome = 'successful' AND (p_quantity IS NULL OR p_quantity <= 0 OR p_unit IS NULL OR btrim(p_unit) = '') THEN
    RAISE EXCEPTION 'Enter the quantity harvested and its unit.';
  END IF;
  IF p_outcome = 'failed' AND (p_failure_cause IS NULL OR btrim(p_failure_cause) = '') THEN
    RAISE EXCEPTION 'Describe what caused the failure.';
  END IF;
  -- Every detail is required (the area planted is no longer asked for).
  IF p_planted_date IS NULL THEN
    RAISE EXCEPTION 'Enter the date planted.';
  END IF;
  IF p_outcome = 'successful' AND p_harvest_date IS NULL THEN
    RAISE EXCEPTION 'Enter the harvest date.';
  END IF;
  IF p_outcome = 'failed' AND p_failure_date IS NULL THEN
    RAISE EXCEPTION 'Enter the date it failed.';
  END IF;
  IF p_planted_date IS NOT NULL AND p_harvest_date IS NOT NULL AND p_harvest_date < p_planted_date THEN
    RAISE EXCEPTION 'The harvest date cannot be before the planting date.';
  END IF;

  PERFORM public._outcome_check_paths(p_photo_paths, 1, 5);

  INSERT INTO program_outcome_reports (
    program_member_id, program_id, farmer_id, reported_outcome, explanation,
    planted_date, harvest_date, quantity_harvested, quantity_unit, area_planted, area_unit,
    failure_cause, failure_date
  ) VALUES (
    p_program_member_id, v_member.program_id, v_uid, p_outcome, btrim(p_explanation),
    p_planted_date, p_harvest_date,
    CASE WHEN p_outcome = 'successful' THEN p_quantity END,
    CASE WHEN p_outcome = 'successful' THEN btrim(p_unit) END,
    p_area, CASE WHEN p_area IS NOT NULL THEN p_area_unit END,
    CASE WHEN p_outcome = 'failed' THEN btrim(p_failure_cause) END,
    CASE WHEN p_outcome = 'failed' THEN p_failure_date END
  ) RETURNING id INTO v_id;

  FOREACH v_path IN ARRAY p_photo_paths LOOP
    INSERT INTO program_outcome_photos (report_id, uploaded_by, uploader_role, storage_path)
    VALUES (v_id, v_uid, 'farmer', v_path);
  END LOOP;

  SELECT full_name INTO v_farmer FROM user_information WHERE user_id = v_uid;
  PERFORM public.notify_staff(
    'program',
    'Program Outcome Report',
    COALESCE(v_farmer, 'A farmer') || ' reported a ' || p_outcome || ' outcome for ' ||
      COALESCE(v_program.program_name, 'a program') || '. It is waiting for review and field verification.',
    '/admin/programs/outcomes'
  );

  RETURN v_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.submit_program_outcome_report(UUID, TEXT, TEXT, DATE, DATE, NUMERIC, TEXT, NUMERIC, TEXT, TEXT, DATE, TEXT[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_program_outcome_report(UUID, TEXT, TEXT, DATE, DATE, NUMERIC, TEXT, NUMERIC, TEXT, TEXT, DATE, TEXT[]) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 7. Staff list: says whether a harvest return applies to the program
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.get_program_outcome_reports(p_program_id UUID DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can read outcome reports.';
  END IF;
  RETURN (
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.submitted_at DESC), '[]'::jsonb)
    FROM (
      SELECT r.submitted_at,
             to_jsonb(r) || jsonb_build_object(
               'program_name', cp.program_name,
               'is_harvest_return', (cp.benefit_type = 'revenue_share' AND cp.return_crop_id IS NOT NULL),
               'return_crop_name', (SELECT cm.crop_name FROM crop_master cm WHERE cm.id = cp.return_crop_id),
               'farmer_name', ui.full_name,
               'item_name', pm.distributed_item_name,
               'quantity_given', pm.quantity_given,
               'distributed_at', pm.distributed_at,
               'photos', COALESCE((SELECT jsonb_agg(jsonb_build_object(
                                     'id', ph.id, 'path', ph.storage_path, 'by', ph.uploader_role)
                                   ORDER BY ph.created_at)
                                   FROM program_outcome_photos ph WHERE ph.report_id = r.id), '[]'::jsonb)
             ) AS j
      FROM program_outcome_reports r
      JOIN cooperative_programs cp ON cp.id = r.program_id
      LEFT JOIN program_members pm ON pm.id = r.program_member_id
      LEFT JOIN user_information ui ON ui.user_id = r.farmer_id
      WHERE p_program_id IS NULL OR r.program_id = p_program_id
    ) x
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.get_program_outcome_reports(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_program_outcome_reports(UUID) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 8. Assistance: no limit and no deadline; only the duplicate guard remains
-- ════════════════════════════════════════════════════════════
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
  IF EXISTS (SELECT 1 FROM program_assistance_requests
              WHERE program_member_id = p_member_id AND status = 'pending') THEN
    RETURN 'pending';
  END IF;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public._assistance_blocker(UUID, UUID) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.submit_assistance_request(
  p_program_member_id UUID,
  p_items             JSONB,
  p_message           TEXT DEFAULT NULL
) RETURNS TABLE (new_request_id UUID, new_request_no TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid     UUID := auth.uid();
  v_m       program_members%ROWTYPE;
  v_block   TEXT;
  v_item    JSONB;
  v_inv     UUID;
  v_qty     NUMERIC;
  v_ci      RECORD;
  v_seen    UUID[] := ARRAY[]::UUID[];
  v_id      UUID := gen_random_uuid();
  v_no      TEXT;
  v_name    TEXT;
  v_prog    TEXT;
BEGIN
  IF v_uid IS NULL OR NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = v_uid AND role = 'farmer' AND status = 'active') THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only an active Farmer can request assistance.';
  END IF;

  -- Lock the member row so two taps cannot both pass the checks.
  SELECT * INTO v_m FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  v_block := public._assistance_blocker(p_program_member_id, v_uid);
  IF v_block = 'pending' THEN
    RAISE EXCEPTION 'ASSIST_PENDING: A request for this program is already waiting for review.';
  ELSIF v_block IS NOT NULL THEN
    RAISE EXCEPTION 'ASSIST_NOT_ELIGIBLE: Assistance can be requested for a program outcome that failed.';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0
     OR jsonb_array_length(p_items) > 20 THEN
    RAISE EXCEPTION 'ASSIST_ITEMS: Choose between 1 and 20 items.';
  END IF;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_uid;
  SELECT program_name INTO v_prog FROM cooperative_programs WHERE id = v_m.program_id;
  v_no := public.next_loan_request_reference(NOW());

  INSERT INTO program_assistance_requests
    (id, request_number, program_id, program_member_id, farmer_id, farmer_name, message)
  VALUES (v_id, v_no, v_m.program_id, v_m.id, v_uid, v_name, NULLIF(btrim(COALESCE(p_message, '')), ''));

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_inv := NULLIF(v_item->>'inventoryItemId', '')::UUID;
    v_qty := (v_item->>'quantity')::NUMERIC;
    IF v_inv IS NULL OR v_qty IS NULL OR v_qty <= 0 OR v_qty <> round(v_qty, 2) OR v_inv = ANY (v_seen) THEN
      RAISE EXCEPTION 'ASSIST_ITEMS: Each item needs a quantity greater than zero, and can be chosen once.';
    END IF;
    v_seen := v_seen || v_inv;

    SELECT ci.item_name, ci.unit, ci.quantity_on_hand, ci.quantity_reserved, lim.unit_price
      INTO v_ci
      FROM loan_items_master lim
      JOIN cooperative_inventory ci ON ci.id = lim.inventory_item_id
     WHERE lim.inventory_item_id = v_inv AND lim.is_loan_eligible AND ci.is_active AND ci.archived_at IS NULL;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'ASSIST_ITEMS: One of the items is not available for assistance.';
    END IF;
    IF v_ci.quantity_on_hand - v_ci.quantity_reserved < v_qty THEN
      RAISE EXCEPTION 'ASSIST_ITEMS: % does not have enough stock.', v_ci.item_name;
    END IF;

    INSERT INTO program_assistance_items (request_id, inventory_item_id, item_name, unit, quantity, unit_price)
    VALUES (v_id, v_inv, v_ci.item_name, v_ci.unit, v_qty, v_ci.unit_price);
  END LOOP;

  PERFORM public.notify_staff('program', 'Assistance Request',
    COALESCE(v_name, 'A Farmer') || ' asked for assistance after the ' || COALESCE(v_prog, 'program') ||
      ' outcome (' || v_no || ').', '/admin/loans/requests');

  RETURN QUERY SELECT v_id, v_no;
END;
$function$;
REVOKE ALL ON FUNCTION public.submit_assistance_request(UUID, JSONB, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.submit_assistance_request(UUID, JSONB, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only; run each by itself AFTER applying)
-- ============================================================
-- V1  The new finalize signature exists and the old one is gone (expect 1 row, 7 args):
--     SELECT pg_get_function_identity_arguments(oid) FROM pg_proc
--      WHERE proname = 'finalize_program_outcome' AND pronamespace = 'public'::regnamespace;
-- V2  The three settings functions are gone (expect 0 rows):
--     SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--      AND proname IN ('set_underreport_tolerance','set_assistance_setting','get_program_settings');
-- V3  Finalizing still needs the review and the field verification (expect true, true):
--     SELECT pg_get_functiondef(p.oid) ILIKE '%evidence must be reviewed%' AND pg_get_functiondef(p.oid) ILIKE '%field verification first%',
--            pg_get_functiondef(p.oid) ILIKE '%RETURN_QUANTITY%'
--       FROM pg_proc p WHERE p.proname = 'finalize_program_outcome' AND p.pronamespace = 'public'::regnamespace;
-- V4  Nothing historical changed (compare with the counts you had before):
--     SELECT status, count(*) FROM program_returns GROUP BY 1;
--     SELECT resolution, count(*) FROM program_failure_resolutions GROUP BY 1;
--     SELECT count(*) FROM program_assistance_requests;
-- V5  Product Sales: farmers (enrolled or not) may read available products of ACTIVE sales programs
--     (expect 1 row each; this came from the p4 script and is NOT changed here):
--     SELECT policyname FROM pg_policies WHERE tablename = 'program_products'  AND policyname = 'program_products: farmers read available';
--     SELECT policyname FROM pg_policies WHERE tablename = 'cooperative_inventory' AND policyname = 'cooperative_inventory: farmers read sales program items';
