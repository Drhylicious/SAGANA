-- ============================================================
-- SAGANA — p33: a second distribution after "Eligible for Reassessment"
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run. Run after p32.
-- Built on the proposed approach while the cooperative's policy is still open: it is easy to tighten later.
--
-- HOW IT WORKS
--   * A Failed outcome whose LATEST decision is "Eligible for Reassessment" can be given another item by a
--     Manager or Officer ("Give another item", note required). The Farmer does not ask again.
--   * It is a NEW distribution record (round 2, 3 ...), not a continuation. The failed round is kept exactly
--     as it is (outcome, report, decision, history) and is marked "completed". The new round starts at
--     "To Distribute" and then follows the normal steps: distribute, outcome report, review, verification,
--     final decision, return.
--   * Nothing is taken from Inventory here: stock is used only when the new item is actually distributed.
--   * Only one round is ever active per Farmer and program, so member counts stay correct.
--
-- DATABASE
--   1. program_members.round_no and previous_member_id (the failed round it follows).
--   2. UNIQUE(program_id, farmer_id) becomes UNIQUE(program_id, farmer_id, round_no), plus a rule that only ONE
--      round can be active at a time. Existing rows are all round 1 and are unchanged.
--   3. redistribute_program_member(member, note): staff only; refuses unless the program is active and a Harvest
--      Return program, the outcome is Failed, the latest decision is Eligible for Reassessment, and no next
--      round exists yet. It notifies the Farmer.
-- ============================================================

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.program_failure_resolutions') IS NULL THEN
    RAISE EXCEPTION 'Apply p25 and p32 first.';
  END IF;
END $$;

-- 1. Columns
ALTER TABLE public.program_members ADD COLUMN IF NOT EXISTS round_no INTEGER NOT NULL DEFAULT 1;
ALTER TABLE public.program_members
  ADD COLUMN IF NOT EXISTS previous_member_id UUID REFERENCES public.program_members(id) ON DELETE SET NULL;

-- 2. One membership row per round, and only one ACTIVE round
DO $$
DECLARE c record;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
     WHERE conrelid = 'public.program_members'::regclass AND contype = 'u'
       AND (SELECT array_agg(a.attname::text ORDER BY a.attname)
              FROM pg_attribute a
             WHERE a.attrelid = conrelid AND a.attnum = ANY (conkey)) = ARRAY['farmer_id', 'program_id']
  LOOP
    EXECUTE format('ALTER TABLE public.program_members DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE public.program_members DROP CONSTRAINT IF EXISTS program_members_round_uq;
ALTER TABLE public.program_members
  ADD CONSTRAINT program_members_round_uq UNIQUE (program_id, farmer_id, round_no);
CREATE UNIQUE INDEX IF NOT EXISTS uq_program_members_one_active
  ON public.program_members (program_id, farmer_id) WHERE status = 'active';

-- 3. Give another item
CREATE OR REPLACE FUNCTION public.redistribute_program_member(
  p_member_id UUID,
  p_note      TEXT
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_old  program_members%ROWTYPE;
  v_p    cooperative_programs%ROWTYPE;
  v_note TEXT := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_res  TEXT;
  v_new  UUID;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'NOT_ALLOWED: Only a Manager or Officer can give another item.';
  END IF;
  IF v_note IS NULL THEN
    RAISE EXCEPTION 'REASON_REQUIRED: Write a note for this new distribution.';
  END IF;

  SELECT * INTO v_old FROM program_members WHERE id = p_member_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PROGRAM_NOT_FOUND: Program member not found.';
  END IF;
  SELECT * INTO v_p FROM cooperative_programs WHERE id = v_old.program_id;
  IF v_p.status = 'completed' THEN
    RAISE EXCEPTION 'PROGRAM_COMPLETED: This program is already completed.';
  END IF;
  IF v_p.program_purpose <> 'distribution' OR v_p.benefit_type IS DISTINCT FROM 'revenue_share' THEN
    RAISE EXCEPTION 'REDISTRIBUTE_NOT_ALLOWED: Only a Harvest Return program has outcomes to reassess.';
  END IF;
  IF v_old.status <> 'active' OR COALESCE(v_old.distribution_outcome, '') <> 'failed' THEN
    RAISE EXCEPTION 'REDISTRIBUTE_NOT_ALLOWED: Another item can only follow a Failed outcome.';
  END IF;
  SELECT f.resolution INTO v_res FROM program_failure_resolutions f
   WHERE f.program_member_id = v_old.id ORDER BY f.created_at DESC LIMIT 1;
  IF v_res IS DISTINCT FROM 'eligible_for_reassessment' THEN
    RAISE EXCEPTION 'REDISTRIBUTE_NOT_ALLOWED: The latest decision must be Eligible for Reassessment.';
  END IF;
  IF EXISTS (SELECT 1 FROM program_members WHERE previous_member_id = v_old.id) THEN
    RAISE EXCEPTION 'REDISTRIBUTE_NOT_ALLOWED: A new distribution was already started for this Farmer.';
  END IF;

  -- The failed round is kept as it is and closed; the next round starts at To Distribute.
  UPDATE program_members SET status = 'completed' WHERE id = v_old.id;
  INSERT INTO program_members (program_id, farmer_id, enrolled_at, status, notes, round_no, previous_member_id)
  VALUES (v_old.program_id, v_old.farmer_id, v_old.enrolled_at, 'active', v_note, v_old.round_no + 1, v_old.id)
  RETURNING id INTO v_new;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (v_old.farmer_id, 'program', 'Another Distribution',
          'The cooperative will give you another item in ' || COALESCE(v_p.program_name, 'the program') ||
            ' after your earlier outcome. You will be notified when it is handed to you.',
          FALSE, NOW(), '/farmer/profile/programs/enrolled');
  RETURN v_new;
END;
$function$;
REVOKE ALL ON FUNCTION public.redistribute_program_member(UUID, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.redistribute_program_member(UUID, TEXT) TO authenticated;

DO $$ BEGIN
  IF to_regclass('public.staff_permission_targets') IS NOT NULL THEN
    INSERT INTO public.staff_permission_targets (kind, name, module)
    VALUES ('rpc', 'redistribute_program_member', 'dashboard')
    ON CONFLICT (kind, name) DO NOTHING;
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- CHECKS
-- ============================================================
-- W1  New columns and rules exist (expect 2 columns, 1 constraint, 1 index):
--     SELECT column_name FROM information_schema.columns WHERE table_name = 'program_members' AND column_name IN ('round_no', 'previous_member_id');
--     SELECT conname FROM pg_constraint WHERE conname = 'program_members_round_uq';
--     SELECT indexname FROM pg_indexes WHERE indexname = 'uq_program_members_one_active';
-- W2  Every existing member is round 1 and nothing else changed (expect 0 rows):
--     SELECT id FROM program_members WHERE round_no <> 1 OR previous_member_id IS NOT NULL;
-- W3  After a real use: each Farmer's rounds in order, with what happened in each:
--     SELECT ui.full_name, pm.round_no, pm.status, pm.distributed_item_name, pm.quantity_given, pm.distribution_outcome, pm.previous_member_id
--       FROM program_members pm LEFT JOIN user_information ui ON ui.user_id = pm.farmer_id
--      ORDER BY pm.program_id, pm.farmer_id, pm.round_no;
-- W4  Never more than one active round per Farmer and program (expect 0 rows):
--     SELECT program_id, farmer_id FROM program_members WHERE status = 'active' GROUP BY 1, 2 HAVING count(*) > 1;
