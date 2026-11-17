-- ============================================================
-- SAGANA — p45: the Programs tab of Farmer Details shows what the Farmer sees (read-only), and the staff notice links
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p44. No data is changed or deleted.
--
--   1. get_farmer_programs_view(p_farmer_id): staff only. The same facts the Farmer's My Programs screen is built
--      from (outcome reports, harvest returns, the latest decision per case, requests for another distribution and
--      the loan request sent from a referral), for ONE Farmer. Read-only.
--   2. The staff notice "Request for Another Distribution" now opens the Program Management list (it had no link).
--      Same function as p36 with the link added; nothing else in it changes.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.request_program_redistribution(uuid,text)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'loan_requests' AND column_name = 'program_member_id') THEN
    RAISE EXCEPTION 'Apply p36 and p42 first.';
  END IF;
END $$;

-- 1. The Farmer's programs, as staff see them (no staff identities, like the Farmer's own copy).
CREATE OR REPLACE FUNCTION public.get_farmer_programs_view(p_farmer_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can see this.';
  END IF;
  RETURN jsonb_build_object(
    -- Same shape as get_my_outcome_reports()
    'reports', COALESCE((
      SELECT jsonb_agg(x.j ORDER BY x.submitted_at DESC)
      FROM (
        SELECT r.submitted_at,
               jsonb_build_object(
                 'id', r.id,
                 'program_member_id', r.program_member_id,
                 'program_id', r.program_id,
                 'reported_outcome', r.reported_outcome,
                 'status', r.status,
                 'submitted_at', r.submitted_at,
                 'return_note', CASE WHEN r.status = 'returned' THEN r.review_note END,
                 'final_outcome', r.final_outcome,
                 'finalized_at', r.finalized_at,
                 'review_done', r.review_decision = 'validated',
                 'verification_done', r.verified_by IS NOT NULL,
                 'photo_count', (SELECT count(*) FROM program_outcome_photos p
                                  WHERE p.report_id = r.id AND p.uploader_role = 'farmer')
               ) AS j
        FROM program_outcome_reports r
        WHERE r.farmer_id = p_farmer_id
      ) x), '[]'::jsonb),
    -- Same shape as get_my_program_returns()
    'returns', jsonb_build_object(
      'returns', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                 'id', r.id, 'program_id', r.program_id, 'program_member_id', r.program_member_id,
                 'crop_name', r.crop_name, 'unit', r.unit,
                 'due_quantity', r.due_quantity, 'received_quantity', r.received_quantity,
                 'status', r.status, 'created_at', r.created_at) ORDER BY r.created_at DESC)
        FROM program_returns r WHERE r.farmer_id = p_farmer_id), '[]'::jsonb),
      'resolutions', COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
                 'program_member_id', x.program_member_id, 'program_id', x.program_id,
                 'resolution', x.resolution))
        FROM (SELECT DISTINCT ON (f.program_member_id) f.*
                FROM program_failure_resolutions f WHERE f.farmer_id = p_farmer_id
               ORDER BY f.program_member_id, f.created_at DESC) x), '[]'::jsonb)
    ),
    -- The Farmer's request for another distribution, per failed round
    'redistribution', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('program_member_id', q.program_member_id, 'status', q.status))
      FROM program_redistribution_requests q WHERE q.farmer_id = p_farmer_id), '[]'::jsonb),
    -- The latest loan request sent from each referral (a Cancelled one is left out, as on the Farmer's card)
    'loan_requests', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'program_member_id', y.program_member_id, 'request_id', y.id,
               'request_no', y.request_no, 'status', y.status))
      FROM (SELECT DISTINCT ON (lr.program_member_id) lr.*
              FROM loan_requests lr
             WHERE lr.farmer_id = p_farmer_id AND lr.program_member_id IS NOT NULL AND lr.status <> 'cancelled'
             ORDER BY lr.program_member_id, lr.requested_at DESC) y), '[]'::jsonb)
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.get_farmer_programs_view(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_farmer_programs_view(UUID) TO authenticated;

-- 2. The staff notice opens the Program Management list. Same function as p36, with the link.
CREATE OR REPLACE FUNCTION public.request_program_redistribution(p_member_id UUID, p_note TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid  UUID := auth.uid();
  v_m    program_members%ROWTYPE;
  v_p    cooperative_programs%ROWTYPE;
  v_note TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_res  TEXT;
  v_id   UUID;
  v_name TEXT;
BEGIN
  IF v_uid IS NULL OR NOT EXISTS (SELECT 1 FROM user_roles WHERE user_id = v_uid AND role = 'farmer' AND status = 'active') THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only an active cooperative member can request another distribution.';
  END IF;
  IF v_note IS NULL THEN
    RAISE EXCEPTION 'REASON_REQUIRED: Write a note for your request.';
  END IF;
  SELECT * INTO v_m FROM program_members WHERE id = p_member_id FOR UPDATE;
  IF NOT FOUND OR v_m.farmer_id IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'PROGRAM_NOT_FOUND: Program enrollment not found.';
  END IF;
  SELECT * INTO v_p FROM cooperative_programs WHERE id = v_m.program_id;
  IF v_p.status = 'completed' THEN
    RAISE EXCEPTION 'PROGRAM_COMPLETED: This program is already completed.';
  END IF;
  IF v_m.status <> 'active' OR COALESCE(v_m.distribution_outcome, '') <> 'failed' THEN
    RAISE EXCEPTION 'REDISTRIBUTE_NOT_ALLOWED: Another distribution can only follow a Failed outcome.';
  END IF;
  SELECT f.resolution INTO v_res FROM program_failure_resolutions f
   WHERE f.program_member_id = v_m.id ORDER BY f.created_at DESC LIMIT 1;
  IF v_res IS DISTINCT FROM 'eligible_for_reassessment' THEN
    RAISE EXCEPTION 'REDISTRIBUTE_NOT_ALLOWED: The cooperative has not marked you as eligible for reassessment.';
  END IF;
  IF EXISTS (SELECT 1 FROM program_members WHERE previous_member_id = v_m.id)
     OR EXISTS (SELECT 1 FROM program_redistribution_requests WHERE program_member_id = v_m.id) THEN
    RAISE EXCEPTION 'REDISTRIBUTE_NOT_ALLOWED: A request for another distribution was already sent.';
  END IF;

  INSERT INTO program_redistribution_requests (program_member_id, program_id, farmer_id, note)
  VALUES (v_m.id, v_m.program_id, v_uid, v_note) RETURNING id INTO v_id;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_uid;
  PERFORM public.notify_staff(
    'program', 'Request for Another Distribution',
    COALESCE(v_name, 'A Farmer') || ' asked for another distribution in ' || COALESCE(v_p.program_name, 'a program') ||
      '. They were marked Eligible for Reassessment: open the program to approve it.',
    '/admin/programs');
  RETURN v_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.request_program_redistribution(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_program_redistribution(UUID, TEXT) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECK (as staff; replace the id with a Farmer who has programs; expect reports/returns/redistribution/loan_requests):
--   SELECT public.get_farmer_programs_view('<farmer user id>');
