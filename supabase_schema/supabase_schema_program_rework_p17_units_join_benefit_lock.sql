-- ============================================================
-- SAGANA — Program Management p17: one unit (the Inventory item's), Join requests
--          are approved (never declined), and Benefit Type is locked.
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run.
-- Run AFTER p15 (return the same item) and p16 (program types).
--
-- WHAT IT DOES
--   1. UNIT = THE INVENTORY ITEM'S UNIT
--      A program no longer has a unit of its own. program_missing_fields() stops asking
--      for return_unit (a Harvest Return program needs a quantity only; the unit is the
--      unit of the item given to each Farmer). The old cooperative_programs.return_unit
--      column and its values are KEPT but nothing reads them any more.
--      program_members gets distributed_unit: the item's unit at the moment of
--      distribution, so a past distribution keeps reading "2 head Pig" even if the item
--      is edited later. Existing distributions are filled from the item's CURRENT unit
--      (so Pig, already changed to Head, reads Head). distribute_program_benefit() now
--      records it and names the unit in the Farmer's notice.
--   2. BENEFIT TYPE IS LOCKED
--      Free Distribution <-> Harvest Return can no longer be changed once the program
--      exists (a trigger, so it holds for every caller, not only the Edit form).
--      Direct SQL (no signed-in user) is not blocked, as with the status lock.
--   3. JOIN REQUESTS ARE APPROVED, NEVER DECLINED
--      respond_to_program_enrollment_request() and respond_to_da_amad_enrollment()
--      refuse p_approve = false. A request ends in one of two ways: a Manager or Officer
--      approves it, or it is closed automatically when its program is completed
--      (complete_program(), reworded here). Requests already declined in the past stay in
--      History untouched. Wording says "join" instead of "enroll".
--
-- Nothing is deleted. No member, distribution, outcome, return, purchase or request row
-- is removed or rewritten, apart from filling the new distributed_unit column.
-- ============================================================

-- PREVIEW (read-only): what each distribution will be recorded in
SELECT cp.program_name, pm.distributed_item_name, pm.quantity_given,
       ci.unit AS item_unit_now, cp.return_unit AS old_program_unit
  FROM program_members pm
  JOIN cooperative_programs cp ON cp.id = pm.program_id
  LEFT JOIN cooperative_inventory ci ON ci.id = pm.inventory_item_id
 WHERE pm.distributed_at IS NOT NULL
 ORDER BY cp.program_name;

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.program_returns') IS NULL
     OR to_regclass('public.program_types') IS NULL THEN
    RAISE EXCEPTION 'Apply p15 and p16 first.';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1. Unit: the Inventory item's
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.program_missing_fields(p public.cooperative_programs)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT array_remove(ARRAY[
    CASE WHEN p.program_name IS NULL OR btrim(p.program_name) = ''  THEN 'name' END,
    CASE WHEN p.program_type IS NULL OR btrim(p.program_type) = ''  THEN 'type' END,
    CASE WHEN p.image_url    IS NULL OR btrim(p.image_url)    = ''  THEN 'photo' END,
    CASE WHEN p.description  IS NULL OR btrim(p.description)  = ''  THEN 'description' END,
    CASE WHEN p.budget       IS NULL OR p.budget <= 0               THEN 'budget' END,
    CASE WHEN COALESCE(array_length(p.source_categories, 1), 0) = 0
          AND (p.program_purpose = 'sales' OR p.distribution_item_id IS NULL)
                                                                    THEN 'sources' END,
    -- A Harvest Return program needs the quantity. Its unit is the unit of the item given.
    CASE WHEN p.program_purpose = 'distribution' AND p.benefit_type = 'revenue_share'
          AND (p.return_quantity IS NULL OR p.return_quantity <= 0) THEN 'return_quantity' END
  ], NULL);
$$;

ALTER TABLE public.program_members ADD COLUMN IF NOT EXISTS distributed_unit TEXT;

UPDATE public.program_members pm
   SET distributed_unit = btrim(ci.unit)
  FROM public.cooperative_inventory ci
 WHERE ci.id = pm.inventory_item_id
   AND pm.distributed_at IS NOT NULL
   AND pm.distributed_unit IS NULL;

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
  v_unit      TEXT;
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
  IF v_program.status <> 'active' THEN
    RAISE EXCEPTION 'This program is Completed and no longer distributes items.';
  END IF;
  IF v_program.distribution_item_id IS NULL
     AND COALESCE(array_length(v_program.source_categories, 1), 0) = 0 THEN
    RAISE EXCEPTION 'This program is Incomplete: where it distributes from is not set. Edit the program and choose the categories first.';
  END IF;
  IF p_inventory_item_id IS DISTINCT FROM v_program.distribution_item_id
     AND NOT EXISTS (
       SELECT 1
         FROM cooperative_inventory ci, unnest(COALESCE(v_program.source_categories, '{}')) c
        WHERE ci.id = p_inventory_item_id AND lower(btrim(ci.category)) = lower(btrim(c))) THEN
    RAISE EXCEPTION 'This item is not in a category this program distributes from.';
  END IF;

  SELECT quantity_on_hand, item_name, btrim(unit), is_active
    INTO v_available, v_item_name, v_unit, v_active
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

  -- The unit is the Inventory item's, kept with the distribution.
  UPDATE program_members
     SET inventory_item_id = p_inventory_item_id,
         quantity_given = p_quantity,
         distributed_at = NOW(),
         distributed_item_name = v_item_name,
         distributed_unit = v_unit
   WHERE id = p_program_member_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_member.farmer_id, 'program', 'Benefit Distributed',
    'You received ' || p_quantity || COALESCE(' ' || v_unit, '') || ' ' ||
      COALESCE(v_item_name, 'item(s)') || ' from your program.',
    FALSE, NOW()
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.distribute_program_benefit(uuid, uuid, numeric, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.distribute_program_benefit(uuid, uuid, numeric, uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 2. Benefit Type is fixed once the program exists
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.lock_program_benefit_type()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.benefit_type IS DISTINCT FROM OLD.benefit_type AND auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'BENEFIT_TYPE_LOCKED: The Benefit Type of a program cannot be changed after it is created. Members, outcomes and returns depend on it.';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_lock_program_benefit_type ON public.cooperative_programs;
CREATE TRIGGER trg_lock_program_benefit_type
  BEFORE UPDATE OF benefit_type ON public.cooperative_programs
  FOR EACH ROW EXECUTE FUNCTION public.lock_program_benefit_type();

-- ════════════════════════════════════════════════════════════
-- 3. Join requests: approved, never declined
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.respond_to_program_enrollment_request(p_request_id uuid, p_approve boolean, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer_id UUID;
  v_program_id UUID;
  v_status TEXT;
  v_program_name TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can review join requests';
  END IF;
  IF NOT COALESCE(p_approve, FALSE) THEN
    RAISE EXCEPTION 'DECLINE_NOT_ALLOWED: A join request is approved, never declined. It closes by itself when its program is completed.';
  END IF;

  SELECT farmer_id, program_id, status INTO v_farmer_id, v_program_id, v_status
  FROM program_enrollment_requests WHERE id = p_request_id FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_status;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM cooperative_programs WHERE id = v_program_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'PROGRAM_COMPLETED: This program is Completed and no longer accepts new members.';
  END IF;

  SELECT program_name INTO v_program_name
  FROM cooperative_programs WHERE id = v_program_id;

  UPDATE program_enrollment_requests
  SET status = 'approved',
      reviewed_by = auth.uid(),
      reviewed_at = NOW(),
      admin_notes = p_notes
  WHERE id = p_request_id;

  -- Reactivate-or-insert (program_members has UNIQUE(program_id, farmer_id)).
  IF EXISTS (
    SELECT 1 FROM program_members
    WHERE program_id = v_program_id AND farmer_id = v_farmer_id
  ) THEN
    UPDATE program_members
    SET status = 'active', enrolled_at = NOW()
    WHERE program_id = v_program_id AND farmer_id = v_farmer_id;
  ELSE
    INSERT INTO program_members (program_id, farmer_id)
    VALUES (v_program_id, v_farmer_id);
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id, 'program', 'Join Request Approved',
    'Your request to join ' || COALESCE(v_program_name, 'the program') || ' was approved. You are now a member.',
    FALSE, NOW()
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.respond_to_da_amad_enrollment(p_enrollment_id uuid, p_approve boolean, p_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer_id UUID;
  v_status TEXT;
BEGIN
  IF NOT public.is_staff() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or Officer can review join requests';
  END IF;
  IF NOT COALESCE(p_approve, FALSE) THEN
    RAISE EXCEPTION 'DECLINE_NOT_ALLOWED: A join request is approved, never declined.';
  END IF;

  SELECT farmer_id, status INTO v_farmer_id, v_status
  FROM da_amad_enrollments WHERE id = p_enrollment_id FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Join request not found';
  END IF;
  IF v_status != 'pending' THEN
    RAISE EXCEPTION 'Join request already reviewed (status: %)', v_status;
  END IF;

  UPDATE da_amad_enrollments
  SET status = 'approved',
      reviewed_by = auth.uid(),
      reviewed_at = NOW(),
      admin_notes = p_notes
  WHERE id = p_enrollment_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id, 'system', 'Market Linking Join Request Approved',
    'You can now submit your Ginger harvest for sale through Market Linking.',
    FALSE, NOW()
  );
END;
$function$;

-- Completing a program closes its still-pending join requests (the one way a request
-- ends without an approval), with a notice. Same rules as before; wording only.
CREATE OR REPLACE FUNCTION public.complete_program(p_program_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_p        cooperative_programs%ROWTYPE;
  v_b        jsonb;
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
REVOKE ALL ON FUNCTION public.complete_program(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_program(uuid) TO authenticated;

-- The staff notice for a new request.
CREATE OR REPLACE FUNCTION public.notify_admins_of_program_enrollment_request()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_program_name TEXT;
BEGIN
  SELECT program_name INTO v_program_name
  FROM cooperative_programs WHERE id = NEW.program_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'program',
    'New Join Request',
    'A farmer asked to join ' || COALESCE(v_program_name, 'a program') || '. Review the request.',
    FALSE,
    NOW()
  FROM public.user_roles ap WHERE ap.role IN ('admin', 'officer');

  RETURN NEW;
END;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only)
-- ============================================================
-- V1  Every distribution has its unit, and it matches the item today:
--     SELECT pm.distributed_item_name, pm.quantity_given, pm.distributed_unit, ci.unit AS item_unit_now
--       FROM program_members pm LEFT JOIN cooperative_inventory ci ON ci.id = pm.inventory_item_id
--      WHERE pm.distributed_at IS NOT NULL;
-- V2  A Harvest Return program no longer reports a missing unit:
--     SELECT program_name, program_missing_fields(cooperative_programs) FROM cooperative_programs;
-- V3  The Benefit Type lock exists:
--     SELECT tgname FROM pg_trigger WHERE tgname = 'trg_lock_program_benefit_type';
-- V4  Declining is refused (run as a signed-in staff user from the app, not here).
-- V5  Nothing was lost (same counts as before):
--     SELECT count(*) FROM program_members;  SELECT count(*) FROM program_enrollment_requests;
