-- ============================================================
-- SAGANA — Program Management rework, PHASE 5A
--   Program creation rules, Incomplete programs, per-program History,
--   Farmer-safe Activities, and a repair of distribute_program_benefit().
--
-- Written from the LIVE definitions returned by supabase_schema_program_rework_preflight.sql
-- (not from older repository copies). NOT APPLIED — run it yourself in the
-- Supabase SQL editor, then run the verification block at the bottom.
--
-- WHAT THIS CHANGES
--   1. cooperative_programs gets four columns:
--        distribution_item_id  the ONE inventory item the program distributes
--        return_crop_id        (Harvest Return) crop the farmer returns, from crop_master
--        return_quantity       (Harvest Return) agreed quantity
--        return_unit           (Harvest Return) unit
--      Existing rows keep NULL here. Nothing is back-filled or invented.
--   2. "Incomplete" is COMPUTED, never stored (status keeps its 3 values):
--        program_missing_fields(program)  lists what a DISTRIBUTION program lacks.
--        Product Sales programs are deliberately NOT covered (out of scope for now).
--   3. A trigger enforces the required fields for signed-in staff:
--        INSERT  every required field must be filled.
--        UPDATE  a field that is filled cannot be emptied; a legacy program that is
--                missing fields can still be edited (status, etc.) without being
--                forced to complete everything at once.
--      Statements run with no signed-in user (SQL editor, migrations) are not blocked.
--   4. distribute_program_benefit() is REPLACED (same signature). The live version:
--        - has NO staff check (any signed-in account could deduct stock),
--        - does not stop a member being distributed to twice.
--      The new version requires staff, an active member, one distribution per
--      member, a configured program item (BLOCKS new distributions until set),
--      and that exactly that item is distributed. Stock, ledger and the farmer
--      notice are unchanged.
--   5. get_program_history(program) — ONE staff-readable history per program,
--      READING the existing accountability trail (admin_activity_log 'db' rows,
--      written by trg_audit_staff_change) plus farmer-originated rows from their own
--      tables. No second history table is created and nothing is copied.
--      Managers AND Officers can read it; Farmers cannot.
--   6. get_my_program_activities() — what an enrolled Farmer may see (no staff
--      identity). The blanket "any signed-in user reads every activity" policy
--      is dropped; Farmers now read activities only through that function.
--
-- NOT CHANGED here (later phases): outcomes, produce return, failed-program loan
-- conversion (convert_program_distribution_to_loan stays as it is until Phase 5B/6).
-- ============================================================

-- ─── PRE-FLIGHT (read-only, run first) ─────────────────────────────────────
-- crop_master.id must be a uuid (expect: uuid):
--   SELECT data_type FROM information_schema.columns
--   WHERE table_schema='public' AND table_name='crop_master' AND column_name='id';
-- ────────────────────────────────────────────────────────────────────────────

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. New columns
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.cooperative_programs
  ADD COLUMN IF NOT EXISTS distribution_item_id UUID
    REFERENCES public.cooperative_inventory(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS return_crop_id UUID
    REFERENCES public.crop_master(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS return_quantity NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS return_unit TEXT;

ALTER TABLE public.cooperative_programs
  DROP CONSTRAINT IF EXISTS cooperative_programs_return_quantity_check;
ALTER TABLE public.cooperative_programs
  ADD CONSTRAINT cooperative_programs_return_quantity_check
  CHECK (return_quantity IS NULL OR return_quantity > 0);

COMMENT ON COLUMN public.cooperative_programs.distribution_item_id IS
  'The single cooperative_inventory item this Distribution program hands out. '
  'NULL = Incomplete (legacy program): new distributions are blocked until set.';
COMMENT ON COLUMN public.cooperative_programs.return_crop_id IS
  'Harvest Return programs: the crop (crop_master) the farmer returns to the cooperative.';
COMMENT ON COLUMN public.cooperative_programs.return_quantity IS
  'Harvest Return programs: the quantity the cooperative expects back, in return_unit. '
  'Set by the cooperative per program; never a fixed rule or a percentage.';

-- ════════════════════════════════════════════════════════════
-- 2. "Incomplete" — computed from the row, never stored
-- ════════════════════════════════════════════════════════════
-- Keys: name, type, photo, description, budget, item, return_crop,
--       return_quantity, return_unit. Product Sales programs return an empty list.
CREATE OR REPLACE FUNCTION public.program_missing_fields(p public.cooperative_programs)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE WHEN p.program_purpose <> 'distribution' THEN ARRAY[]::text[]
  ELSE array_remove(ARRAY[
    CASE WHEN p.program_name IS NULL OR btrim(p.program_name) = ''  THEN 'name' END,
    CASE WHEN p.program_type IS NULL OR btrim(p.program_type) = ''  THEN 'type' END,
    CASE WHEN p.image_url    IS NULL OR btrim(p.image_url)    = ''  THEN 'photo' END,
    CASE WHEN p.description  IS NULL OR btrim(p.description)  = ''  THEN 'description' END,
    CASE WHEN p.budget       IS NULL OR p.budget <= 0               THEN 'budget' END,
    CASE WHEN p.distribution_item_id IS NULL                        THEN 'item' END,
    CASE WHEN p.benefit_type = 'revenue_share' AND p.return_crop_id IS NULL
                                                                    THEN 'return_crop' END,
    CASE WHEN p.benefit_type = 'revenue_share'
          AND (p.return_quantity IS NULL OR p.return_quantity <= 0) THEN 'return_quantity' END,
    CASE WHEN p.benefit_type = 'revenue_share'
          AND (p.return_unit IS NULL OR btrim(p.return_unit) = '')  THEN 'return_unit' END
  ], NULL) END;
$$;

GRANT EXECUTE ON FUNCTION public.program_missing_fields(public.cooperative_programs) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 3. Required fields, enforced in the database
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.enforce_program_required_fields()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_new  text[];
  v_old  text[];
  v_gain text[];
BEGIN
  -- SQL editor / migrations have no signed-in user: not blocked.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  v_new := public.program_missing_fields(NEW);

  IF TG_OP = 'INSERT' THEN
    IF COALESCE(array_length(v_new, 1), 0) > 0 THEN
      RAISE EXCEPTION 'A distribution program needs every required field. Missing: %',
        array_to_string(v_new, ', ');
    END IF;
    RETURN NEW;
  END IF;

  -- UPDATE: nothing may BECOME missing. A legacy program that is already
  -- incomplete stays editable.
  v_old  := public.program_missing_fields(OLD);
  v_gain := ARRAY(SELECT unnest(v_new) EXCEPT SELECT unnest(v_old));
  IF COALESCE(array_length(v_gain, 1), 0) > 0 THEN
    RAISE EXCEPTION 'Required program fields cannot be left empty. Missing: %',
      array_to_string(v_gain, ', ');
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_program_required_fields ON public.cooperative_programs;
CREATE TRIGGER trg_enforce_program_required_fields
  BEFORE INSERT OR UPDATE ON public.cooperative_programs
  FOR EACH ROW EXECUTE FUNCTION public.enforce_program_required_fields();

-- ════════════════════════════════════════════════════════════
-- 4. distribute_program_benefit(): authorization, one distribution, locked item
-- ════════════════════════════════════════════════════════════
-- Same signature as the live function, so the app call is unchanged.
-- p_recorded_by is accepted for compatibility but the signed-in user is
-- always used, so a client cannot attribute a stock movement to someone else.
CREATE OR REPLACE FUNCTION public.distribute_program_benefit(
  p_program_member_id uuid,
  p_inventory_item_id uuid,
  p_quantity numeric,
  p_recorded_by uuid DEFAULT NULL::uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_member    program_members%ROWTYPE;
  v_program   cooperative_programs%ROWTYPE;
  v_available NUMERIC;
  v_item_name TEXT;
  v_active    BOOLEAN;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can distribute a program benefit';
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'The quantity must be greater than zero';
  END IF;

  SELECT * INTO v_member FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Program enrollment not found';
  END IF;
  IF v_member.status <> 'active' THEN
    RAISE EXCEPTION 'Only an active member can receive a distribution';
  END IF;
  IF v_member.distributed_at IS NOT NULL THEN
    RAISE EXCEPTION 'This member has already received a distribution';
  END IF;

  SELECT * INTO v_program FROM cooperative_programs WHERE id = v_member.program_id;
  IF v_program.program_purpose <> 'distribution' THEN
    RAISE EXCEPTION 'This is not a distribution program';
  END IF;
  IF v_program.distribution_item_id IS NULL THEN
    RAISE EXCEPTION 'This program is Incomplete: its distribution item is not set. Edit the program and choose the item first.';
  END IF;
  IF p_inventory_item_id IS DISTINCT FROM v_program.distribution_item_id THEN
    RAISE EXCEPTION 'This program distributes a different item. Distribute the item configured on the program.';
  END IF;

  SELECT quantity_on_hand, item_name, is_active
    INTO v_available, v_item_name, v_active
    FROM cooperative_inventory
   WHERE id = p_inventory_item_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Inventory item % no longer exists', p_inventory_item_id;
  END IF;
  IF NOT v_active THEN
    RAISE EXCEPTION '% is archived and cannot be distributed', v_item_name;
  END IF;
  IF v_available < p_quantity THEN
    RAISE EXCEPTION 'Insufficient stock for %: % on hand, % requested',
      v_item_name, v_available, p_quantity;
  END IF;

  UPDATE cooperative_inventory
     SET quantity_on_hand = quantity_on_hand - p_quantity
   WHERE id = p_inventory_item_id;

  INSERT INTO inventory_transactions (
    inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by
  ) VALUES (
    p_inventory_item_id, 'program_distribution', -p_quantity, p_program_member_id, 'program', auth.uid()
  );

  UPDATE program_members
     SET inventory_item_id = p_inventory_item_id,
         quantity_given = p_quantity,
         distributed_at = NOW(),
         distributed_item_name = v_item_name
   WHERE id = p_program_member_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_member.farmer_id, 'program', 'Benefit Distributed',
    'You received ' || p_quantity || ' ' || COALESCE(v_item_name, 'item(s)') || ' from your program.',
    FALSE, NOW()
  );
END;
$function$;

-- ════════════════════════════════════════════════════════════
-- 5. get_program_history(): the per-program accountability view
-- ════════════════════════════════════════════════════════════
-- Source of truth, so nothing is duplicated:
--   * admin_activity_log source='db'   who edited / enrolled / distributed / ...
--     (the existing trail written by trg_audit_staff_change on the program tables).
--   * cooperative_programs             who created the program and when (authoritative;
--                                      the trail's own 'created' row is skipped).
--   * program_enrollment_requests      the FARMER's request, and a staff decline
--                                      (farmer actions are not in the staff trail).
--   * program_members                  only as a fallback for members enrolled before the
--                                      trail existed (actor unknown, shown as such).
-- Approval of an enrollment is shown once, as the member being enrolled.
-- Returns structured rows; the app words them (English / Tagalog).
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
  )

  -- Created (from the program row itself)
  SELECT p.created_at, 'program_created'::text,
         ui.full_name, ur.role, NULL::text,
         jsonb_build_object('name', p.program_name)
  FROM prog p
  LEFT JOIN user_information ui ON ui.user_id = p.created_by
  LEFT JOIN user_roles ur ON ur.user_id = p.created_by

  UNION ALL
  -- Edited (field-level old / new values)
  SELECT t.created_at, 'program_updated', t.actor_name, t.actor_role, NULL,
         jsonb_build_object('old', t.old_values, 'new', t.new_values)
  FROM trail t
  WHERE t.table_name = 'cooperative_programs' AND t.operation = 'updated'

  UNION ALL
  -- Farmer asked to enroll
  SELECT r.submitted_at, 'enrollment_requested', ui.full_name, 'farmer', ui.full_name,
         '{}'::jsonb
  FROM program_enrollment_requests r
  LEFT JOIN user_information ui ON ui.user_id = r.farmer_id
  WHERE r.program_id = p_program_id

  UNION ALL
  -- Staff declined the request
  SELECT r.reviewed_at, 'enrollment_declined', sui.full_name, sur.role, fui.full_name,
         jsonb_build_object('note', r.admin_notes)
  FROM program_enrollment_requests r
  LEFT JOIN user_information fui ON fui.user_id = r.farmer_id
  LEFT JOIN user_information sui ON sui.user_id = r.reviewed_by
  LEFT JOIN user_roles sur ON sur.user_id = r.reviewed_by
  WHERE r.program_id = p_program_id AND r.status = 'rejected' AND r.reviewed_at IS NOT NULL

  UNION ALL
  -- Member enrolled (first time)
  SELECT t.created_at, 'member_enrolled', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('re_enrolled', false)
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'created'

  UNION ALL
  -- Member enrolled before the trail existed: actor unknown, nothing guessed
  SELECT m.enrolled_at, 'member_enrolled', NULL, NULL, m.full_name,
         jsonb_build_object('re_enrolled', false, 'actor_unrecorded', true)
  FROM mem m
  WHERE NOT EXISTS (
    SELECT 1 FROM trail t
    WHERE t.table_name = 'program_members' AND t.operation = 'created' AND t.record_id = m.id::text)

  UNION ALL
  -- Member enrolled again after a removal
  SELECT t.created_at, 'member_enrolled', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('re_enrolled', true)
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated'
    AND t.new_values ->> 'status' = 'active'

  UNION ALL
  SELECT t.created_at, 'member_removed', t.actor_name, t.actor_role, t.reference_label, '{}'::jsonb
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated'
    AND t.new_values ->> 'status' = 'withdrawn'

  UNION ALL
  SELECT t.created_at, 'benefit_distributed', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('quantity', t.new_values -> 'quantity_given',
                            'item', t.new_values ->> 'distributed_item_name')
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated'
    AND t.new_values ? 'distributed_at' AND t.new_values ->> 'distributed_at' IS NOT NULL

  UNION ALL
  SELECT t.created_at, 'outcome_recorded', t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('outcome', t.new_values ->> 'distribution_outcome')
  FROM trail t
  WHERE t.table_name = 'program_members' AND t.operation = 'updated'
    AND t.new_values ? 'distribution_outcome'

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
  -- Activities
  SELECT t.created_at,
         CASE t.operation WHEN 'created' THEN 'activity_created'
                          WHEN 'updated' THEN 'activity_updated' ELSE 'activity_deleted' END,
         t.actor_name, t.actor_role, t.reference_label,
         jsonb_build_object('old', t.old_values, 'new', t.new_values)
  FROM trail t
  WHERE t.table_name = 'program_activities'

  ORDER BY 1 DESC;
END;
$function$;

REVOKE ALL ON FUNCTION public.get_program_history(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_program_history(uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 6. Activities a Farmer may see (no staff identity)
-- ════════════════════════════════════════════════════════════
-- Live policy "program_activities: members read all" lets ANY signed-in account
-- (Buyers included) read every activity, including created_by. Dropped: staff keep
-- full access through "program_activities: admin manages all" (is_staff()).
DROP POLICY IF EXISTS "program_activities: members read all" ON public.program_activities;

CREATE OR REPLACE FUNCTION public.get_my_program_activities()
RETURNS TABLE (
  out_id            uuid,
  out_program_id    uuid,
  out_title         text,
  out_description   text,
  out_activity_date date,
  out_location      text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT a.id, a.program_id, a.title, a.description, a.activity_date, a.location
  FROM program_activities a
  JOIN program_members pm
    ON pm.program_id = a.program_id
   AND pm.farmer_id = auth.uid()
   AND pm.status IN ('active', 'completed')
  ORDER BY a.activity_date ASC, a.created_at ASC;
$$;

REVOKE ALL ON FUNCTION public.get_my_program_activities() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_program_activities() TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only; run each by itself AFTER applying)
-- ============================================================
-- 1. New columns exist (expect 4 rows):
--    SELECT column_name FROM information_schema.columns
--    WHERE table_schema='public' AND table_name='cooperative_programs'
--      AND column_name IN ('distribution_item_id','return_crop_id','return_quantity','return_unit');
-- 2. Which existing programs are Incomplete, and why (expect the legacy ones):
--    SELECT cp.program_name, cp.program_purpose, public.program_missing_fields(cp) AS missing
--    FROM cooperative_programs cp ORDER BY cp.created_at;
-- 3. Trigger and functions are in place (expect 1 row each):
--    SELECT tgname FROM pg_trigger WHERE tgname = 'trg_enforce_program_required_fields';
--    SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--      AND proname IN ('get_program_history','get_my_program_activities','program_missing_fields');
-- 4. distribute_program_benefit now checks staff and one-distribution (expect true, true, true):
--    SELECT pg_get_functiondef('public.distribute_program_benefit(uuid,uuid,numeric,uuid)'::regprocedure) ILIKE '%is_staff()%' AS has_staff_check,
--           pg_get_functiondef('public.distribute_program_benefit(uuid,uuid,numeric,uuid)'::regprocedure) ILIKE '%already received%' AS blocks_second,
--           pg_get_functiondef('public.distribute_program_benefit(uuid,uuid,numeric,uuid)'::regprocedure) ILIKE '%distribution_item_id%' AS uses_program_item;
-- 4b. No existing distribution was changed (expect the same count as before you ran this):
--    SELECT count(*) FROM program_members WHERE distributed_at IS NOT NULL;
-- 5. The broad activity policy is gone (expect 0 rows):
--    SELECT policyname FROM pg_policies WHERE tablename='program_activities'
--      AND policyname = 'program_activities: members read all';
-- 6. Accountability rows appear for program edits. After you edit any program in the
--    app, expect new rows here (if none appear, tell me — the audit trigger would need a look):
--    SELECT created_at, actor_name, actor_role, table_name, operation, reference_label
--    FROM admin_activity_log WHERE source='db' AND module='programs' ORDER BY created_at DESC LIMIT 10;
-- ============================================================
