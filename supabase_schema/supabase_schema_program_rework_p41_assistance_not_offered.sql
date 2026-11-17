-- ============================================================
-- SAGANA — p41: Failed-Program Assistance is switched off until the cooperative confirms a policy
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p40. No data is changed or deleted.
--
-- Agreed: after a Failed outcome, "Referred for Loan Assessment" offers only the normal Request a Loan (a real loan
-- that is repaid). Free assistance is not offered for ANY of the four decisions until the cooperative decides its
-- policy. The assistance check now answers "not_offered" for every Failed outcome, so the Farmer sees no button and the
-- database refuses a new assistance request.
--
-- NOT TOUCHED: assistance requests already made or approved, their stock ledger entries and references. Staff can
-- still review any request that is already pending. Nothing is deleted: this only stops NEW requests, and it is
-- reversed by running p40 again.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regprocedure('public._assistance_blocker(uuid,uuid)') IS NULL THEN
    RAISE EXCEPTION 'Apply p40 first.';
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
  v_m program_members%ROWTYPE;
BEGIN
  SELECT * INTO v_m FROM program_members WHERE id = p_member_id;
  IF NOT FOUND OR v_m.farmer_id IS DISTINCT FROM p_farmer
     OR v_m.status <> 'active' OR COALESCE(v_m.distribution_outcome, '') <> 'failed' THEN
    RETURN 'not_eligible';
  END IF;
  -- Free assistance has no confirmed policy: it is not offered after any decision.
  RETURN 'not_offered';
END;
$function$;
REVOKE ALL ON FUNCTION public._assistance_blocker(UUID, UUID) FROM PUBLIC, anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECK (every Failed outcome answers 'not_offered'; expect no other value):
--   SELECT public._assistance_blocker(pm.id, pm.farmer_id) AS blocker, count(*)
--     FROM program_members pm WHERE pm.distribution_outcome = 'failed' AND pm.status = 'active' GROUP BY 1;
