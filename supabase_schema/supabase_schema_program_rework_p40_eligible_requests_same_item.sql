-- ============================================================
-- SAGANA — p40: "Eligible for Reassessment" is a request for the SAME item, not assistance
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p39 and p36. No data is changed.
--
--   1. Assistance is not offered while the latest decision is "Eligible for Reassessment". That decision has its own
--      path: the Farmer requests the same item again (the request for another distribution of p36), and staff
--      approve it. The assistance check now answers "reassessment" for it.
--   2. A new distribution round remembers which item it is for: program_members.requested_item_id is filled from
--      the failed round's item when the round starts, so staff see (and the Distribute form pre-selects) the same
--      item the Farmer asked for. Staff can still change it before distributing.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.program_redistribution_requests') IS NULL THEN
    RAISE EXCEPTION 'Apply p36 first.';
  END IF;
END $$;

-- 1. The assistance check (as p39, plus Eligible for Reassessment)
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
  IF COALESCE(v_latest, 'pending_cooperative_decision') = 'pending_cooperative_decision' THEN
    RETURN 'undecided';
  END IF;
  IF v_latest = 'eligible_for_reassessment' THEN
    RETURN 'reassessment';          -- the Farmer requests the same item again instead
  END IF;
  IF EXISTS (SELECT 1 FROM program_assistance_requests
              WHERE program_member_id = p_member_id AND status = 'pending') THEN
    RETURN 'pending';
  END IF;
  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public._assistance_blocker(UUID, UUID) FROM PUBLIC, anon, authenticated;

-- 2. The next round remembers the item it is for
ALTER TABLE public.program_members
  ADD COLUMN IF NOT EXISTS requested_item_id UUID REFERENCES public.cooperative_inventory(id) ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION public._program_members_remember_requested_item()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.previous_member_id IS NOT NULL AND NEW.requested_item_id IS NULL THEN
    SELECT p.inventory_item_id INTO NEW.requested_item_id
      FROM program_members p WHERE p.id = NEW.previous_member_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_program_members_remember_requested_item ON public.program_members;
CREATE TRIGGER trg_program_members_remember_requested_item
  BEFORE INSERT ON public.program_members
  FOR EACH ROW WHEN (NEW.previous_member_id IS NOT NULL)
  EXECUTE FUNCTION public._program_members_remember_requested_item();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- CHECKS
-- E1  Cases marked Eligible for Reassessment: the assistance check answers 'reassessment' (expect that for each):
--     SELECT ui.full_name, public._assistance_blocker(pm.id, pm.farmer_id) AS blocker
--       FROM program_members pm LEFT JOIN user_information ui ON ui.user_id = pm.farmer_id
--      WHERE pm.distribution_outcome = 'failed'
--        AND (SELECT f.resolution FROM program_failure_resolutions f WHERE f.program_member_id = pm.id
--              ORDER BY f.created_at DESC LIMIT 1) = 'eligible_for_reassessment';
-- E2  After a second round starts: the item it is for (expect the failed round's item):
--     SELECT ui.full_name, pm.round_no, ci.item_name AS requested_item FROM program_members pm
--       JOIN cooperative_inventory ci ON ci.id = pm.requested_item_id LEFT JOIN user_information ui ON ui.user_id = pm.farmer_id;
