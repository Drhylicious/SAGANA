-- ============================================================
-- SAGANA — p39: no assistance while the decision is "Pending Cooperative Decision"
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p37. No data is changed.
--
-- While the LATEST decision on a Failed outcome is "Pending Cooperative Decision", the cooperative has not
-- decided yet, so the Farmer cannot be offered or send an assistance request. Staff can still choose any of the
-- other three decisions. Once a decision other than Closed or Pending is recorded, assistance is available
-- again as before; Closed ends it (p37).
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.program_failure_resolutions') IS NULL THEN
    RAISE EXCEPTION 'Apply p37 first.';
  END IF;
END $$;

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
  -- Not decided yet (no record counts as pending): nothing to offer until the cooperative decides.
  IF COALESCE(v_latest, 'pending_cooperative_decision') = 'pending_cooperative_decision' THEN
    RETURN 'undecided';
  END IF;
  IF EXISTS (SELECT 1 FROM program_assistance_requests
              WHERE program_member_id = p_member_id AND status = 'pending') THEN
    RETURN 'pending';
  END IF;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public._assistance_blocker(UUID, UUID) FROM PUBLIC, anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECKS
-- A1  Failed outcomes still undecided and what the assistance check answers for them (expect 'undecided'):
--     SELECT ui.full_name, public._assistance_blocker(pm.id, pm.farmer_id) AS blocker
--       FROM program_members pm LEFT JOIN user_information ui ON ui.user_id = pm.farmer_id
--      WHERE pm.distribution_outcome = 'failed'
--        AND COALESCE((SELECT f.resolution FROM program_failure_resolutions f WHERE f.program_member_id = pm.id
--                       ORDER BY f.created_at DESC LIMIT 1), 'pending_cooperative_decision') = 'pending_cooperative_decision';
