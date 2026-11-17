-- ============================================================
-- SAGANA — p44: completion rules for Eligible for Reassessment, Referred for Loan Assessment and waiting members
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p42 and p43. No data is changed or deleted.
--
-- A Harvest Return program cannot be marked Completed while:
--   * a Failed case is "Eligible for Reassessment" and its second distribution has not started (a Farmer who is
--     waiting, or who has sent a request nobody approved yet). Once the second round exists it is an ordinary
--     member again: the existing rule "outcome awaited" holds the program until that round has its own outcome.
--     The way forward is to approve the Farmer's request or give another item: decisions are final, so there is
--     no "change it to Closed".
--   * a loan request sent from a Referred case is still Pending (staff decide it first).
-- And two cases ask for CONFIRMATION, but are allowed:
--   * a Referred case with no approved loan request (no request, or every request disapproved);
--   * a member still waiting for their item (To Distribute) in a distribution program.
-- complete_program(p_program_id, p_confirm_warnings) refuses them unless the caller confirms; the app shows the
-- warnings first. Nothing is created for the Farmer.
--
-- Also: a loan request cannot be linked to a program that is already Completed.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.program_completion_blockers(uuid)') IS NULL
     OR NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'loan_requests' AND column_name = 'program_member_id') THEN
    RAISE EXCEPTION 'Apply p32 and p42 first.';
  END IF;
END $$;

-- 1. The checklist (as p32, plus open_reassessments and pending_loan_requests)
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
  v_loanreq  integer := 0;
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
      -- Eligible for Reassessment and no second round yet (the failed round is closed when the next one starts).
      SELECT count(*) INTO v_reassess
        FROM program_members m
       WHERE m.program_id = p_program_id
         AND m.status = 'active'
         AND m.distribution_outcome = 'failed'
         AND (SELECT f.resolution FROM program_failure_resolutions f
               WHERE f.program_member_id = m.id
               ORDER BY f.created_at DESC LIMIT 1) = 'eligible_for_reassessment';
      -- A loan request from a Referred case that nobody has decided.
      SELECT count(*) INTO v_loanreq
        FROM loan_requests lr
        JOIN program_members m ON m.id = lr.program_member_id
       WHERE m.program_id = p_program_id AND lr.status = 'pending';
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
    'awaiting_outcome',     v_await,
    'open_returns',         v_returns,
    'pending_decisions',    v_pending,
    'open_reassessments',   v_reassess,
    'pending_loan_requests', v_loanreq,
    'open_orders',          v_orders,
    'allocated_stock',      v_stock
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.program_completion_blockers(uuid) FROM PUBLIC, anon, authenticated;

-- 2. The cases that need a confirmation (NOT in the checklist above: the checklist blocks, this only warns)
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
  -- Members still waiting for their item (distribution programs only: a Product Sales member gets none).
  SELECT count(*) INTO v_waiting
    FROM program_members m
    JOIN cooperative_programs p ON p.id = m.program_id
   WHERE m.program_id = p_program_id
     AND p.program_purpose = 'distribution'
     AND m.status = 'active'
     AND m.distributed_at IS NULL;
  -- Referred cases with no approved loan request (none sent, or all disapproved). A Pending request is a blocker.
  SELECT count(*) INTO v_n
    FROM program_members m
   WHERE m.program_id = p_program_id
     AND m.distribution_outcome = 'failed'
     AND (SELECT f.resolution FROM program_failure_resolutions f
           WHERE f.program_member_id = m.id
           ORDER BY f.created_at DESC LIMIT 1) = 'referred_for_loan_assessment'
     AND NOT EXISTS (SELECT 1 FROM loan_requests lr
                      WHERE lr.program_member_id = m.id AND lr.status = 'approved');
  RETURN jsonb_build_object('unapproved_referrals', v_n, 'waiting_members', v_waiting);
END;
$function$;
REVOKE ALL ON FUNCTION public.program_completion_warnings(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.program_completion_warnings(uuid) TO authenticated;

-- 3. Mark as Completed, with the confirmation (same rules as p17, plus the confirmation)
DROP FUNCTION IF EXISTS public.complete_program(uuid);
-- A first version of this script named the second argument p_confirm_unapproved; a re-run replaces it.
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
    RAISE EXCEPTION 'COMPLETION_CONFIRM_NEEDED: % referred Farmer(s) have no approved loan request and % member(s) are still waiting for an item. Confirm to complete the program.', v_w, v_waiting;
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

-- 4. A loan request cannot be linked to a Completed program (the card also hides the button).
CREATE OR REPLACE FUNCTION public._loan_request_program_not_completed()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.program_member_id IS NOT NULL AND EXISTS (
       SELECT 1 FROM program_members m JOIN cooperative_programs p ON p.id = m.program_id
        WHERE m.id = NEW.program_member_id AND p.status = 'completed') THEN
    RAISE EXCEPTION 'LOAN_REFERRAL_INVALID';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_loan_request_program_not_completed ON public.loan_requests;
CREATE TRIGGER trg_loan_request_program_not_completed
  BEFORE INSERT ON public.loan_requests
  FOR EACH ROW EXECUTE FUNCTION public._loan_request_program_not_completed();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECK 1 (expect 1 row, the 2-argument version only):
--   SELECT pg_get_function_identity_arguments(oid) FROM pg_proc
--    WHERE proname = 'complete_program' AND pronamespace = 'public'::regnamespace;
-- CHECK 2 (what each active program is waiting on):
--   SELECT cp.program_name, public.program_completion_blockers(cp.id) AS blockers
--     FROM cooperative_programs cp WHERE cp.status = 'active';
