-- ============================================================
-- SAGANA — Program Management rework, PHASE 8:
--          get_program_history() + harvest return, resolution and assistance events
--
-- FOR YOUR REVIEW — NOT APPLIED. Run it in the Supabase SQL editor only after
-- you have checked it. One transaction, safe to re-run.
--
-- WHAT IT DOES
--   Re-issues public.get_program_history(uuid) with EVERY existing branch kept
--   exactly as it is in the last version applied (the Phase 3 outcome-workflow
--   script, section 10), and adds events read from the new tables:
--     return_opened / return_adjusted / return_receipt / return_closed
--                         <- program_return_events (+ program_returns)
--     resolution_recorded <- program_failure_resolutions
--     assistance_requested / assistance_approved / assistance_rejected /
--     assistance_cancelled <- program_assistance_requests
--   Same signature, same columns, same staff-only check, same grants. Nothing is
--   written, deleted or changed in any table.
--
-- STEP 0 — LOOK AT THE LIVE DEFINITION FIRST (read-only; the repository copy is
-- the last one I can see, the live one is what counts):
--
--   SELECT pg_get_functiondef('public.get_program_history(uuid)'::regprocedure);
--
-- The guard below stops the script if the live function does not contain the
-- branches this script was written against. If it stops, send me the output of
-- the query above and I will rebuild the migration from it.
--
-- BEFORE / AFTER CHECK (also read-only; the count of OLD event types must not
-- drop). Run before and after, with any program id:
--
--   SELECT out_type, count(*) FROM public.get_program_history('<program id>') GROUP BY 1 ORDER BY 1;
-- ============================================================

BEGIN;

-- Guard: the live function must be the one this migration extends.
DO $$
DECLARE
  v_def TEXT;
  v_marker TEXT;
BEGIN
  IF to_regprocedure('public.get_program_history(uuid)') IS NULL THEN
    RAISE EXCEPTION 'get_program_history(uuid) does not exist; apply the Phase 5A and Phase 3 scripts first.';
  END IF;
  IF to_regclass('public.program_return_events') IS NULL
     OR to_regclass('public.program_failure_resolutions') IS NULL
     OR to_regclass('public.program_assistance_requests') IS NULL THEN
    RAISE EXCEPTION 'Apply the Proposal 12 (p6) and Phase 6 (p7) scripts first.';
  END IF;
  v_def := pg_get_functiondef('public.get_program_history(uuid)'::regprocedure);
  FOREACH v_marker IN ARRAY ARRAY[
    'program_created', 'program_updated', 'enrollment_requested', 'enrollment_declined',
    'member_enrolled', 'member_removed', 'benefit_distributed', 'outcome_recorded',
    'return_confirmed', 'converted_to_loan', 'activity_created', 'outcome_submitted',
    'outcome_reviewed', 'outcome_verified', 'outcome_finalized'
  ] LOOP
    IF position(v_marker IN v_def) = 0 THEN
      RAISE EXCEPTION 'The live get_program_history() has no "%" branch. It differs from the version this migration extends; stop and review.', v_marker;
    END IF;
  END LOOP;
  IF position('return_opened' IN v_def) > 0 THEN
    RAISE NOTICE 'get_program_history() already has the return events; it will simply be replaced with the same content.';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.get_program_history(p_program_id uuid)
RETURNS TABLE (
  out_at       timestamptz,
  out_type     text,
  out_actor    text,
  out_role     text,
  out_subject  text,
  out_details  jsonb
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Only a Manager or Officer can read a program history';
  END IF;

  RETURN QUERY
  WITH
  prog AS (SELECT * FROM cooperative_programs WHERE id = p_program_id),
  mem AS (
    SELECT pm.id, pm.enrolled_at, pm.farmer_id, ui.full_name
    FROM program_members pm
    LEFT JOIN user_information ui ON ui.user_id = pm.farmer_id
    WHERE pm.program_id = p_program_id
  ),
  act AS (SELECT a.id FROM program_activities a WHERE a.program_id = p_program_id),
  trail AS (
    SELECT l.* FROM admin_activity_log l
    WHERE l.source = 'db'
      AND (
        (l.table_name = 'cooperative_programs' AND l.record_id = p_program_id::text)
        OR (l.table_name = 'program_members'
            AND (l.record_id IN (SELECT m.id::text FROM mem m)
                 OR l.new_values ->> 'program_id' = p_program_id::text
                 OR l.old_values ->> 'program_id' = p_program_id::text))
        OR (l.table_name = 'program_activities'
            AND (l.record_id IN (SELECT a.id::text FROM act a)
                 OR l.new_values ->> 'program_id' = p_program_id::text
                 OR l.old_values ->> 'program_id' = p_program_id::text))
      )
  ),
  rep AS (
    SELECT r.*, ui.full_name AS farmer_name
    FROM program_outcome_reports r
    LEFT JOIN user_information ui ON ui.user_id = r.farmer_id
    WHERE r.program_id = p_program_id
  )

  SELECT p.created_at, 'program_created'::text, ui.full_name, ur.role, NULL::text,
         jsonb_build_object('name', p.program_name)
  FROM prog p
  LEFT JOIN user_information ui ON ui.user_id = p.created_by
  LEFT JOIN user_roles ur ON ur.user_id = p.created_by

  UNION ALL
  SELECT t.created_at, 'program_updated', t.actor_name, t.actor_role, NULL,
         jsonb_build_object('old', t.old_values, 'new', t.new_values)
  FROM trail t WHERE t.table_name = 'cooperative_programs' AND t.operation = 'updated'

  UNION ALL
  SELECT r.submitted_at, 'enrollment_requested', ui.full_name, 'farmer', ui.full_name, '{}'::jsonb
  FROM program_enrollment_requests r
  LEFT JOIN user_information ui ON ui.user_id = r.farmer_id
  WHERE r.program_id = p_program_id

  UNION ALL
  SELECT r.reviewed_at, 'enrollment_declined', sui.full_name, sur.role, fui.full_name,
         jsonb_build_object('note', r.admin_notes)
  FROM program_enrollment_requests r
  LEFT JOIN user_information fui ON fui.user_id = r.farmer_id
  LEFT JOIN user_information sui ON sui.user_id = r.reviewed_by
  LEFT JOIN user_roles sur ON sur.user_id = r.reviewed_by
  WHERE r.program_id = p_program_id AND r.status = 'rejected' AND r.reviewed_at IS NOT NULL

  UNION ALL
  SELECT t.created_at, 'member_enrolled', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('re_enrolled', false)
  FROM trail t WHERE t.table_name = 'program_members' AND t.operation = 'created'

  UNION ALL
  SELECT m.enrolled_at, 'member_enrolled', NULL, NULL, m.full_name,
         jsonb_build_object('re_enrolled', false, 'actor_unrecorded', true)
  FROM mem m
  WHERE NOT EXISTS (
    SELECT 1 FROM trail t
    WHERE t.table_name = 'program_members' AND t.operation = 'created' AND t.record_id = m.id::text)

  UNION ALL
  SELECT t.created_at, 'member_enrolled', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('re_enrolled', true)
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated' AND t.new_values ->> 'status' = 'active'

  UNION ALL
  SELECT t.created_at, 'member_removed', t.actor_name, t.actor_role, t.reference_label, '{}'::jsonb
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated' AND t.new_values ->> 'status' = 'withdrawn'

  UNION ALL
  SELECT t.created_at, 'benefit_distributed', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('quantity', t.new_values -> 'quantity_given',
                            'item', t.new_values ->> 'distributed_item_name')
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated'
    AND t.new_values ? 'distributed_at' AND t.new_values ->> 'distributed_at' IS NOT NULL

  UNION ALL
  -- Outcomes recorded BEFORE the evidence workflow (no report exists for them).
  SELECT t.created_at, 'outcome_recorded', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('outcome', t.new_values ->> 'distribution_outcome')
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated'
    AND t.new_values ? 'distribution_outcome'
    AND NOT EXISTS (SELECT 1 FROM program_outcome_reports r
                    WHERE r.program_member_id::text = t.record_id AND r.status = 'finalized')

  UNION ALL
  SELECT t.created_at, 'return_confirmed', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('amount', t.new_values -> 'amount_returned')
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated'
    AND t.new_values ? 'settled_at' AND t.new_values ->> 'settled_at' IS NOT NULL

  UNION ALL
  SELECT t.created_at, 'converted_to_loan', t.actor_name, t.actor_role, t.reference_label, '{}'::jsonb
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated'
    AND t.new_values ? 'converted_loan_id' AND t.new_values ->> 'converted_loan_id' IS NOT NULL

  UNION ALL
  SELECT t.created_at,
         CASE t.operation WHEN 'created' THEN 'activity_created'
                          WHEN 'updated' THEN 'activity_updated' ELSE 'activity_deleted' END,
         t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('old', t.old_values, 'new', t.new_values)
  FROM trail t WHERE t.table_name = 'program_activities'

  -- ── Outcome workflow (read from the report rows themselves) ──
  UNION ALL
  SELECT r.submitted_at, 'outcome_submitted', r.farmer_name, 'farmer', r.farmer_name,
         jsonb_build_object('outcome', r.reported_outcome)
  FROM rep r

  UNION ALL
  SELECT r.reviewed_at, 'outcome_reviewed', r.reviewed_by_name, r.reviewed_by_role, r.farmer_name,
         jsonb_build_object('decision', r.review_decision, 'note', r.review_note)
  FROM rep r WHERE r.reviewed_at IS NOT NULL

  UNION ALL
  SELECT r.verified_at, 'outcome_verified', r.verified_by_name, r.verified_by_role, r.farmer_name,
         jsonb_build_object('finding', r.verification_finding, 'note', r.verification_note,
                            'quantity', r.verified_quantity, 'unit', r.verified_unit)
  FROM rep r WHERE r.verified_at IS NOT NULL

  UNION ALL
  SELECT r.finalized_at, 'outcome_finalized', r.finalized_by_name, r.finalized_by_role, r.farmer_name,
         jsonb_build_object('outcome', r.final_outcome, 'reported', r.reported_outcome, 'note', r.final_note)
  FROM rep r WHERE r.finalized_at IS NOT NULL

  -- ── NEW: harvest return (from the return's own immutable event log) ──
  UNION ALL
  SELECT e.created_at,
         CASE e.event_type WHEN 'created'  THEN 'return_opened'
                           WHEN 'adjusted' THEN 'return_adjusted'
                           WHEN 'receipt'  THEN 'return_receipt'
                           ELSE 'return_closed' END,
         e.actor_name, e.actor_role, pr.farmer_name,
         jsonb_build_object('crop', pr.crop_name, 'unit', pr.unit,
                            'quantity', e.quantity, 'before', e.quantity_before,
                            'after', e.quantity_after, 'reason', e.reason)
  FROM program_return_events e
  JOIN program_returns pr ON pr.id = e.return_id
  WHERE pr.program_id = p_program_id

  -- ── NEW: Failed-outcome resolution (the automatic default has no actor) ──
  UNION ALL
  SELECT f.created_at, 'resolution_recorded', f.decided_by_name, f.decided_by_role, fui.full_name,
         jsonb_build_object('resolution', f.resolution, 'note', f.note, 'default', f.decided_by IS NULL)
  FROM program_failure_resolutions f
  LEFT JOIN user_information fui ON fui.user_id = f.farmer_id
  WHERE f.program_id = p_program_id

  -- ── NEW: failed-program assistance (separate from loans) ──
  UNION ALL
  SELECT a.created_at, 'assistance_requested', a.farmer_name, 'farmer', a.farmer_name,
         jsonb_build_object('request_number', a.request_number,
                            'items', COALESCE((SELECT string_agg(i.quantity::text || ' ' || i.unit || ' ' || i.item_name, ', ' ORDER BY i.item_name)
                                                 FROM program_assistance_items i WHERE i.request_id = a.id), ''))
  FROM program_assistance_requests a
  WHERE a.program_id = p_program_id

  UNION ALL
  SELECT a.reviewed_at,
         CASE a.status WHEN 'approved' THEN 'assistance_approved' ELSE 'assistance_rejected' END,
         a.reviewed_by_name, a.reviewed_by_role, a.farmer_name,
         jsonb_build_object('request_number', a.request_number,
                            'reference', a.assistance_reference, 'note', a.review_note)
  FROM program_assistance_requests a
  WHERE a.program_id = p_program_id AND a.reviewed_at IS NOT NULL AND a.status IN ('approved', 'rejected')

  UNION ALL
  SELECT a.cancelled_at, 'assistance_cancelled', a.farmer_name, 'farmer', a.farmer_name,
         jsonb_build_object('request_number', a.request_number)
  FROM program_assistance_requests a
  WHERE a.program_id = p_program_id AND a.cancelled_at IS NOT NULL

  ORDER BY 1 DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_program_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_program_history(uuid) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  The function is staff-only, same columns, and now knows the new events:
--     SELECT pg_get_functiondef('public.get_program_history(uuid)'::regprocedure) ILIKE '%return_opened%' AS has_returns,
--            pg_get_functiondef('public.get_program_history(uuid)'::regprocedure) ILIKE '%assistance_requested%' AS has_assistance,
--            pg_get_functiondef('public.get_program_history(uuid)'::regprocedure) ILIKE '%is_staff()%' AS staff_only;
-- V2  No old event type disappeared (compare with the "before" run):
--     SELECT out_type, count(*) FROM public.get_program_history('<program id>') GROUP BY 1 ORDER BY 1;
-- V3  Grants are unchanged (authenticated only, not anon/PUBLIC):
--     SELECT grantee, privilege_type FROM information_schema.routine_privileges
--      WHERE routine_name = 'get_program_history' ORDER BY 1;
