-- ============================================================
-- SAGANA — p36: a Farmer can REQUEST another distribution after "Eligible for Reassessment"
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p33. Nothing existing is changed.
--
--   * The Farmer is notified when the decision "Eligible for Reassessment" is recorded.
--   * The Farmer then sends a request (a note is required) from My Programs. No new enrollment or re-approval.
--   * Staff can only APPROVE it: the Farmer was already deemed eligible, so there is no decline. Approving starts
--     the next distribution round (the same action as "Give another item") and links it to the request.
--   * One pending request per failed round. A request is refused unless the Farmer's failed outcome has
--     "Eligible for Reassessment" as its latest decision, the program is still active, and no next round exists.
--   * Nothing is reserved or taken from Inventory by a request or an approval: stock is used only when the new
--     item is actually distributed.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public.redistribute_program_member(uuid,text)') IS NULL THEN
    RAISE EXCEPTION 'Apply p33 first.';
  END IF;
END $$;

CREATE TABLE IF NOT EXISTS public.program_redistribution_requests (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  program_member_id UUID NOT NULL REFERENCES public.program_members(id),   -- the failed round
  program_id        UUID NOT NULL REFERENCES public.cooperative_programs(id),
  farmer_id         UUID NOT NULL,
  note              TEXT NOT NULL,
  status            TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved')),
  requested_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  approved_by       UUID,
  approved_by_name  TEXT,
  approved_by_role  TEXT,
  approved_at       TIMESTAMPTZ,
  new_member_id     UUID REFERENCES public.program_members(id)             -- the round it started
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_redistribution_one_pending
  ON public.program_redistribution_requests (program_member_id) WHERE status = 'pending';

ALTER TABLE public.program_redistribution_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "redistribution_requests: farmer reads own" ON public.program_redistribution_requests;
CREATE POLICY "redistribution_requests: farmer reads own" ON public.program_redistribution_requests
  FOR SELECT USING (farmer_id = auth.uid());
DROP POLICY IF EXISTS "redistribution_requests: staff read" ON public.program_redistribution_requests;
CREATE POLICY "redistribution_requests: staff read" ON public.program_redistribution_requests
  FOR SELECT USING (public.is_staff());

-- Staff changes are kept in the Accountability Log, like the other program records.
DO $$ BEGIN
  IF to_regprocedure('public.audit_staff_change()') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.program_redistribution_requests;
    CREATE TRIGGER trg_audit_staff_change
      AFTER INSERT OR UPDATE OR DELETE ON public.program_redistribution_requests
      FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change('programs', '');
  END IF;
END $$;

-- 1. The Farmer is told the moment "Eligible for Reassessment" is recorded.
CREATE OR REPLACE FUNCTION public._notify_eligible_for_reassessment()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE v_prog TEXT;
BEGIN
  SELECT program_name INTO v_prog FROM cooperative_programs WHERE id = NEW.program_id;
  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (NEW.farmer_id, 'program', 'Eligible for Another Distribution',
          'Your earlier outcome in ' || COALESCE(v_prog, 'the program') || ' was reviewed and you are eligible for ' ||
            'another distribution. You can request it from My Programs; you do not need to join again.',
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'eligible notice failed: %', SQLERRM;     -- a notice must never block the decision
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_notify_eligible_for_reassessment ON public.program_failure_resolutions;
CREATE TRIGGER trg_notify_eligible_for_reassessment
  AFTER INSERT ON public.program_failure_resolutions
  FOR EACH ROW WHEN (NEW.resolution = 'eligible_for_reassessment')
  EXECUTE FUNCTION public._notify_eligible_for_reassessment();

-- 2. The Farmer sends the request.
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
    NULL);
  RETURN v_id;
END;
$function$;
REVOKE ALL ON FUNCTION public.request_program_redistribution(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_program_redistribution(UUID, TEXT) TO authenticated;

-- 3. Staff approve it. There is no decline: the Farmer was already deemed eligible.
CREATE OR REPLACE FUNCTION public.approve_program_redistribution(p_request_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_req  program_redistribution_requests%ROWTYPE;
  v_new  UUID;
  v_name TEXT;
  v_role TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can approve this request.';
  END IF;
  SELECT * INTO v_req FROM program_redistribution_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROGRAM_NOT_FOUND: Request not found.';
  END IF;
  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'REDISTRIBUTE_NOT_ALLOWED: This request was already approved.';
  END IF;

  -- Starts the next round (it re-checks that the decision is still Eligible for Reassessment and the program is active).
  v_new := public.redistribute_program_member(v_req.program_member_id, 'Requested by the Farmer: ' || v_req.note);

  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();
  UPDATE program_redistribution_requests
     SET status = 'approved', approved_by = auth.uid(), approved_by_name = v_name, approved_by_role = v_role,
         approved_at = NOW(), new_member_id = v_new
   WHERE id = p_request_id;
  RETURN v_new;
END;
$function$;
REVOKE ALL ON FUNCTION public.approve_program_redistribution(UUID) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_program_redistribution(UUID) TO authenticated;

DO $$ BEGIN
  IF to_regclass('public.staff_permission_targets') IS NOT NULL THEN
    INSERT INTO public.staff_permission_targets (kind, name, module)
    VALUES ('rpc', 'approve_program_redistribution', 'dashboard')
    ON CONFLICT (kind, name) DO NOTHING;
  END IF;
END $$;

-- 4. If staff start the next round themselves ("Give another item"), the Farmer's pending request for that
--    failed round is closed as approved, so it never stays "waiting" after the new round exists.
CREATE OR REPLACE FUNCTION public._close_request_when_round_starts()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_name TEXT;
  v_role TEXT;
BEGIN
  SELECT a_name, a_role INTO v_name, v_role FROM public._outcome_actor();
  UPDATE program_redistribution_requests
     SET status = 'approved', approved_by = auth.uid(), approved_by_name = v_name, approved_by_role = v_role,
         approved_at = NOW(), new_member_id = NEW.id
   WHERE program_member_id = NEW.previous_member_id AND status = 'pending';
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_close_request_when_round_starts ON public.program_members;
CREATE TRIGGER trg_close_request_when_round_starts
  AFTER INSERT ON public.program_members
  FOR EACH ROW WHEN (NEW.previous_member_id IS NOT NULL)
  EXECUTE FUNCTION public._close_request_when_round_starts();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECKS
-- Z1  Table, functions and triggers exist (expect 1 + 2 + 1 rows):
--     SELECT to_regclass('public.program_redistribution_requests');
--     SELECT proname FROM pg_proc WHERE proname IN ('request_program_redistribution', 'approve_program_redistribution');
--     SELECT tgname FROM pg_trigger WHERE tgname = 'trg_notify_eligible_for_reassessment' AND NOT tgisinternal;
-- Z2  Every request, who asked, who approved and when:
--     SELECT ui.full_name, r.status, r.note, r.requested_at, r.approved_by_name, r.approved_by_role, r.approved_at
--       FROM program_redistribution_requests r LEFT JOIN user_information ui ON ui.user_id = r.farmer_id ORDER BY r.requested_at DESC;
-- Z3  Never two pending requests for one failed round (expect 0 rows):
--     SELECT program_member_id FROM program_redistribution_requests WHERE status = 'pending' GROUP BY 1 HAVING count(*) > 1;
