-- ============================================================
-- SAGANA — p47: "Referred" now leads to ASSISTANCE (not a loan, nothing to repay), not to a loan request
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p46. No data is changed or deleted.
--
-- Until now a Farmer referred after a Failed outcome was sent to the normal Request a Loan (a real loan that is
-- repaid), and assistance was switched off (p41). Now:
--   * The decision "Referred" (stored as referred_for_loan_assessment; shown as "Referred for Assistance Assessment")
--     is the only one that lets the Farmer Request Assistance. Assistance has its own tables and never creates a debt,
--     a repayment, a due date or a loan.
--   * The assistance check (_assistance_blocker) answers for each decision:
--       Closed -> closed      Pending -> undecided      Eligible for Reassessment -> reassessment
--       Referred -> approved (one approved request is enough) | completed (program completed) | pending | limit |
--                   NULL (may ask; a Rejected or Cancelled request lets the Farmer ask again)
--   * The Farmer and staff notices for a referral say assistance, not loan.
--   * Completing a program: a Pending assistance request blocks it (staff decide it first); a Referred case with no
--     approved assistance request asks for confirmation (as p44 did for loan requests).
--
-- NOT TOUCHED: the normal Request a Loan, loan requests already made (including those linked by p42), stock rules,
-- and the assistance approval itself (it deducts stock and gives a reference, no debt).
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.program_completion_warnings(uuid)') IS NULL THEN
    RAISE EXCEPTION 'Apply p44 first.';
  END IF;
END $$;

-- 1. Who may ask for assistance
CREATE OR REPLACE FUNCTION public._assistance_blocker(p_member_id UUID, p_farmer UUID)
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_m      program_members%ROWTYPE;
  v_latest TEXT;
  v_max    NUMERIC;
  v_days   NUMERIC;
  v_count  INTEGER;
BEGIN
  SELECT * INTO v_m FROM program_members WHERE id = p_member_id;
  IF NOT FOUND OR v_m.farmer_id IS DISTINCT FROM p_farmer
     OR v_m.status <> 'active' OR COALESCE(v_m.distribution_outcome, '') <> 'failed' THEN
    RETURN 'not_eligible';
  END IF;
  SELECT f.resolution INTO v_latest FROM program_failure_resolutions f
   WHERE f.program_member_id = p_member_id ORDER BY f.created_at DESC LIMIT 1;
  IF v_latest = 'closed_no_further_obligation' THEN
    RETURN 'closed';
  END IF;
  IF COALESCE(v_latest, 'pending_cooperative_decision') = 'pending_cooperative_decision' THEN
    RETURN 'undecided';
  END IF;
  IF v_latest = 'eligible_for_reassessment' THEN
    RETURN 'reassessment';          -- the Farmer requests the same item again instead
  END IF;
  IF v_latest IS DISTINCT FROM 'referred_for_loan_assessment' THEN
    RETURN 'not_eligible';
  END IF;
  -- Referred: assistance is offered.
  IF EXISTS (SELECT 1 FROM cooperative_programs WHERE id = v_m.program_id AND status = 'completed') THEN
    RETURN 'completed';
  END IF;
  IF EXISTS (SELECT 1 FROM program_assistance_requests
              WHERE program_member_id = p_member_id AND status = 'approved') THEN
    RETURN 'approved';
  END IF;
  IF EXISTS (SELECT 1 FROM program_assistance_requests
              WHERE program_member_id = p_member_id AND status = 'pending') THEN
    RETURN 'pending';
  END IF;
  SELECT numeric_value INTO v_max  FROM program_settings WHERE key = 'assist_max_requests_per_failure';
  SELECT numeric_value INTO v_days FROM program_settings WHERE key = 'assist_request_window_days';
  IF v_max IS NOT NULL THEN
    SELECT count(*) INTO v_count FROM program_assistance_requests
     WHERE program_member_id = p_member_id AND status IN ('pending', 'approved');
    IF v_count >= v_max THEN RETURN 'limit'; END IF;
  END IF;
  IF v_days IS NOT NULL AND v_m.outcome_recorded_at IS NOT NULL
     AND NOW() > v_m.outcome_recorded_at + (v_days || ' days')::INTERVAL THEN
    RETURN 'limit';
  END IF;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public._assistance_blocker(UUID, UUID) FROM PUBLIC, anon, authenticated;

-- 2. The referral notices say assistance
CREATE OR REPLACE FUNCTION public._notify_loan_referral()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_name TEXT;
  v_prog TEXT;
BEGIN
  SELECT full_name INTO v_name FROM user_information WHERE user_id = NEW.farmer_id;
  SELECT program_name INTO v_prog FROM cooperative_programs WHERE id = NEW.program_id;
  PERFORM public.notify_staff(
    'program',
    'Assistance Referral',
    COALESCE(v_name, 'A Farmer') || ' was referred for an assistance assessment after a failed outcome in ' ||
      COALESCE(v_prog, 'a program') || '. Nothing was created: the Farmer can now request assistance.',
    '/admin/loans/requests');
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (NEW.farmer_id, 'program', 'Assistance Referral',
          'The cooperative referred you for an assistance assessment. You may request assistance items from the ' ||
            'cooperative. This is not a loan: there is nothing to repay.',
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'assistance referral notice failed: %', SQLERRM;   -- a notice must never block the decision
  RETURN NEW;
END;
$$;

-- 3. The completion checklist (as p44, with assistance requests in place of loan requests)
CREATE OR REPLACE FUNCTION public.program_completion_blockers(p_program_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_p        cooperative_programs%ROWTYPE;
  v_await    integer := 0;
  v_returns  integer := 0;
  v_pending  integer := 0;
  v_reassess integer := 0;
  v_assist   integer := 0;
  v_orders   integer := 0;
  v_stock    integer := 0;
BEGIN
  SELECT * INTO v_p FROM cooperative_programs WHERE id = p_program_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  IF v_p.program_purpose = 'distribution' THEN
    IF v_p.benefit_type = 'revenue_share' THEN
      SELECT count(*) INTO v_await
        FROM program_members m
       WHERE m.program_id = p_program_id
         AND m.status = 'active'
         AND m.distributed_at IS NOT NULL
         AND COALESCE(m.distribution_outcome, 'pending') NOT IN ('thriving', 'failed');
      SELECT count(*) INTO v_returns
        FROM program_returns r
       WHERE r.program_id = p_program_id AND r.status IN ('pending', 'partial');
      SELECT count(*) INTO v_pending
        FROM program_members m
       WHERE m.program_id = p_program_id
         AND m.distribution_outcome = 'failed'
         AND (SELECT f.resolution FROM program_failure_resolutions f
               WHERE f.program_member_id = m.id
               ORDER BY f.created_at DESC LIMIT 1) = 'pending_cooperative_decision';
      SELECT count(*) INTO v_reassess
        FROM program_members m
       WHERE m.program_id = p_program_id
         AND m.status = 'active'
         AND m.distribution_outcome = 'failed'
         AND (SELECT f.resolution FROM program_failure_resolutions f
               WHERE f.program_member_id = m.id
               ORDER BY f.created_at DESC LIMIT 1) = 'eligible_for_reassessment';
      -- An assistance request from a Referred case that nobody has decided.
      SELECT count(*) INTO v_assist
        FROM program_assistance_requests a
       WHERE a.program_id = p_program_id AND a.status = 'pending';
    END IF;
  ELSE
    SELECT count(*) INTO v_orders
      FROM program_product_purchases p
     WHERE p.program_id = p_program_id
       AND p.status IN ('pending', 'approved', 'ready_for_pickup', 'out_for_delivery', 'delivered');
    SELECT count(*) INTO v_stock
      FROM program_products pp
     WHERE pp.program_id = p_program_id AND pp.stock_allocated > 0;
  END IF;

  RETURN jsonb_build_object(
    'awaiting_outcome',           v_await,
    'open_returns',               v_returns,
    'pending_decisions',          v_pending,
    'open_reassessments',         v_reassess,
    'pending_assistance_requests', v_assist,
    'open_orders',                v_orders,
    'allocated_stock',            v_stock
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.program_completion_blockers(uuid) FROM PUBLIC, anon, authenticated;

-- 4. The confirmation: Referred with no approved assistance request, and members still waiting for an item
CREATE OR REPLACE FUNCTION public.program_completion_warnings(p_program_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_n       integer := 0;
  v_waiting integer := 0;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can see this.';
  END IF;
  SELECT count(*) INTO v_waiting
    FROM program_members m
    JOIN cooperative_programs p ON p.id = m.program_id
   WHERE m.program_id = p_program_id
     AND p.program_purpose = 'distribution'
     AND m.status = 'active'
     AND m.distributed_at IS NULL;
  SELECT count(*) INTO v_n
    FROM program_members m
   WHERE m.program_id = p_program_id
     AND m.distribution_outcome = 'failed'
     AND (SELECT f.resolution FROM program_failure_resolutions f
           WHERE f.program_member_id = m.id
           ORDER BY f.created_at DESC LIMIT 1) = 'referred_for_loan_assessment'
     AND NOT EXISTS (SELECT 1 FROM program_assistance_requests a
                      WHERE a.program_member_id = m.id AND a.status = 'approved');
  RETURN jsonb_build_object('unapproved_referrals', v_n, 'waiting_members', v_waiting);
END;
$function$;
REVOKE ALL ON FUNCTION public.program_completion_warnings(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.program_completion_warnings(uuid) TO authenticated;

-- 5. Mark as Completed: same rules, the confirmation message says assistance
DROP FUNCTION IF EXISTS public.complete_program(uuid, boolean);
CREATE OR REPLACE FUNCTION public.complete_program(
  p_program_id       uuid,
  p_confirm_warnings boolean DEFAULT false
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_p        cooperative_programs%ROWTYPE;
  v_b        jsonb;
  v_w        integer;
  v_waiting  integer;
  v_declined integer := 0;
  r          RECORD;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can complete a program.';
  END IF;

  SELECT * INTO v_p FROM cooperative_programs WHERE id = p_program_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROGRAM_NOT_FOUND: Program not found.';
  END IF;
  IF v_p.status = 'completed' THEN
    RAISE EXCEPTION 'PROGRAM_COMPLETED: This program is already completed.';
  END IF;

  v_b := public.program_completion_blockers(p_program_id);
  IF EXISTS (SELECT 1 FROM jsonb_each_text(v_b) e WHERE e.value::int > 0) THEN
    RAISE EXCEPTION 'PROGRAM_NOT_READY: This program still has unfinished work: %', v_b::text;
  END IF;

  v_w       := COALESCE((public.program_completion_warnings(p_program_id) ->> 'unapproved_referrals')::int, 0);
  v_waiting := COALESCE((public.program_completion_warnings(p_program_id) ->> 'waiting_members')::int, 0);
  IF (v_w > 0 OR v_waiting > 0) AND NOT COALESCE(p_confirm_warnings, FALSE) THEN
    RAISE EXCEPTION 'COMPLETION_CONFIRM_NEEDED: % referred Farmer(s) have no approved assistance request and % member(s) are still waiting for an item. Confirm to complete the program.', v_w, v_waiting;
  END IF;

  FOR r IN
    SELECT id, farmer_id FROM program_enrollment_requests
     WHERE program_id = p_program_id AND status = 'pending'
     FOR UPDATE
  LOOP
    UPDATE program_enrollment_requests
       SET status = 'rejected', reviewed_by = auth.uid(), reviewed_at = NOW(),
           admin_notes = 'This program was completed and is no longer accepting members.'
     WHERE id = r.id;
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
    VALUES (r.farmer_id, 'program', 'Join Request Closed',
            'Your request to join ' || v_p.program_name ||
              ' was closed because the program was completed. You may join other open programs.',
            FALSE, NOW());
    v_declined := v_declined + 1;
  END LOOP;

  PERFORM set_config('sagana.completing_program', 'on', TRUE);
  UPDATE cooperative_programs SET status = 'completed' WHERE id = p_program_id;
  PERFORM set_config('sagana.completing_program', '', TRUE);

  RETURN v_declined;
END;
$function$;
REVOKE ALL ON FUNCTION public.complete_program(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_program(uuid, boolean) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECK 1 (what the assistance check answers for each Failed case; expect 'referred' cases NULL / pending / approved,
-- the others closed / undecided / reassessment):
--   SELECT f.resolution, public._assistance_blocker(pm.id, pm.farmer_id) AS blocker, count(*)
--     FROM program_members pm
--     JOIN LATERAL (SELECT x.resolution FROM program_failure_resolutions x WHERE x.program_member_id = pm.id
--                    ORDER BY x.created_at DESC LIMIT 1) f ON TRUE
--    WHERE pm.distribution_outcome = 'failed' AND pm.status = 'active' GROUP BY 1, 2 ORDER BY 1, 2;
-- CHECK 2 (the checklist now has pending_assistance_requests, not pending_loan_requests):
--   SELECT public.program_completion_blockers(id) FROM cooperative_programs WHERE status = 'active' LIMIT 1;
