-- ============================================================
-- SAGANA — Program Management rework, PHASE 1: PROGRAM RULES AND CLEANUP
--
-- Written from the LIVE definitions returned by the pre-flight checks
-- (Database_checks.md, Q1-Q10) and from the Phase 5A script you already ran.
-- NOT APPLIED — run it yourself in the Supabase SQL editor, once, then run the
-- verification block at the bottom. It is one transaction: if anything fails,
-- nothing is applied.
--
-- WHAT THIS DOES
--   1. Program status is only 'active' or 'completed'. Q1 showed no program is
--      'suspended' (all 6 are active), and the script refuses to run if that has
--      changed, rather than guess where such a program should go.
--   2. A program cannot be deleted if it has ANY member row (withdrawn included),
--      any recorded distribution, or any purchase. The delete cascades to members,
--      products, purchases, enrollment requests and activities (Q2), so this is
--      the only thing standing between a click and losing those records.
--      Direct deletes of a member or a purchase row by a signed-in user are
--      refused too; a delete that comes from removing a user account (a cascade)
--      and statements with no signed-in user (the SQL editor, the dev-reset
--      script) are left alone.
--   3. A Completed program accepts no new enrollments (approving a request),
--      distributions or purchases. Its existing members are untouched and can
--      still be processed. Three live functions are re-issued with ONE added
--      check each; everything else in them is copied unchanged from the live
--      definitions:
--        distribute_program_benefit   (the Phase 5A version)
--        request_program_purchase     (live, Q3)
--        respond_to_program_enrollment_request (live, preflight)
--   4. The old outcome workflow is retired so it cannot create incorrect records.
--      The three functions keep their names and signatures (so nothing that still
--      references them breaks) but now only refuse, with an explanation:
--        record_program_thriving_outcome        (an outcome with no evidence)
--        convert_program_distribution_to_loan   (automatic loan conversion)
--        confirm_program_return                 (a return recorded in pesos)
--      Existing recorded outcomes, loans and settlements are NOT touched. The
--      replacement (Successful / Failed with evidence, review and Officer field
--      verification) arrives in the outcome phase.
--   5. get_my_program_activities() is dropped (Activities removal). The
--      program_activities TABLE, its rows, its audit trigger, the Manager
--      dashboard calendar read and the History events are all kept.
--
-- NOT CHANGED: product pricing, enrollment rules for Product Sales, Balik-Tangkilik,
-- Member Patronage, My Contribution (Phase 4, subject to your review).
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. Status: Active / Completed only
-- ════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.cooperative_programs WHERE status NOT IN ('active', 'completed')) THEN
    RAISE EXCEPTION 'A program has a status other than active/completed (for example suspended). Decide what it should become first.';
  END IF;
END;
$$;

ALTER TABLE public.cooperative_programs
  DROP CONSTRAINT IF EXISTS cooperative_programs_status_check;
ALTER TABLE public.cooperative_programs
  ADD CONSTRAINT cooperative_programs_status_check
  CHECK (status IN ('active', 'completed'));

-- ════════════════════════════════════════════════════════════
-- 2. Deletion protection
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.protect_program_from_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
DECLARE
  v_members   integer;
  v_distrib   integer;
  v_purchases integer;
BEGIN
  SELECT count(*), count(*) FILTER (WHERE distributed_at IS NOT NULL)
    INTO v_members, v_distrib
    FROM program_members WHERE program_id = OLD.id;
  SELECT count(*) INTO v_purchases
    FROM program_product_purchases WHERE program_id = OLD.id;

  IF v_members > 0 OR v_distrib > 0 OR v_purchases > 0 THEN
    RAISE EXCEPTION
      'This program cannot be deleted: it has % member record(s), % distribution(s) and % purchase(s). Mark it as Completed instead.',
      v_members, v_distrib, v_purchases;
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_program_from_delete ON public.cooperative_programs;
CREATE TRIGGER trg_protect_program_from_delete
  BEFORE DELETE ON public.cooperative_programs
  FOR EACH ROW EXECUTE FUNCTION public.protect_program_from_delete();

-- Enrollment and transaction rows: no direct delete by a signed-in user.
-- pg_trigger_depth() > 1 means the delete is itself a cascade (for example a
-- user account being removed), which is left to proceed; no signed-in user
-- (SQL editor, migrations, the dev-reset script) is not blocked either.
CREATE OR REPLACE FUNCTION public.protect_program_records_from_delete()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public'
AS $$
BEGIN
  IF auth.uid() IS NULL OR pg_trigger_depth() > 1 THEN
    RETURN OLD;
  END IF;
  RAISE EXCEPTION '% records cannot be deleted. Withdraw the member or cancel the purchase instead.',
    replace(TG_TABLE_NAME, '_', ' ');
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_program_members_delete ON public.program_members;
CREATE TRIGGER trg_protect_program_members_delete
  BEFORE DELETE ON public.program_members
  FOR EACH ROW EXECUTE FUNCTION public.protect_program_records_from_delete();

DROP TRIGGER IF EXISTS trg_protect_program_purchases_delete ON public.program_product_purchases;
CREATE TRIGGER trg_protect_program_purchases_delete
  BEFORE DELETE ON public.program_product_purchases
  FOR EACH ROW EXECUTE FUNCTION public.protect_program_records_from_delete();

-- ════════════════════════════════════════════════════════════
-- 3. Completed programs: no new enrollments, distributions or purchases
-- ════════════════════════════════════════════════════════════

-- 3a. distribute_program_benefit — the Phase 5A version plus one check.
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
  -- NEW in Phase 1
  IF v_program.status <> 'active' THEN
    RAISE EXCEPTION 'This program is Completed and no longer distributes items.';
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

-- 3b. request_program_purchase — the live definition plus one check.
CREATE OR REPLACE FUNCTION public.request_program_purchase(p_program_id uuid, p_product_id uuid, p_quantity numeric)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_farmer_id   UUID := auth.uid();
  v_product     RECORD;
  v_on_hand     DECIMAL;
  v_reserved    DECIMAL;
  v_item_name   TEXT;
  v_farmer_name TEXT;
  v_purchase_id UUID;
BEGIN
  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantity must be greater than zero.';
  END IF;

  -- NEW in Phase 1
  IF NOT EXISTS (
    SELECT 1 FROM public.cooperative_programs
    WHERE id = p_program_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'This program is Completed and no longer accepts purchases.';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.program_members
    WHERE program_id = p_program_id
      AND farmer_id = v_farmer_id
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'You are not an active member of this program.';
  END IF;

  SELECT pp.id, pp.unit_price, pp.is_available, pp.inventory_item_id
    INTO v_product
    FROM public.program_products pp
    WHERE pp.id = p_product_id
      AND pp.program_id = p_program_id
    FOR SHARE;

  IF v_product IS NULL THEN
    RAISE EXCEPTION 'Product not found for this program.';
  END IF;
  IF NOT v_product.is_available THEN
    RAISE EXCEPTION 'This product is not currently available for purchase.';
  END IF;

  SELECT quantity_on_hand, quantity_reserved, item_name
    INTO v_on_hand, v_reserved, v_item_name
    FROM public.cooperative_inventory
    WHERE id = v_product.inventory_item_id
    FOR SHARE;

  IF v_on_hand IS NULL THEN
    RAISE EXCEPTION 'Linked inventory item no longer exists.';
  END IF;
  IF (v_on_hand - v_reserved) < p_quantity THEN
    RAISE EXCEPTION 'Not enough stock available for this quantity.';
  END IF;

  INSERT INTO public.program_product_purchases (
    program_id, product_id, farmer_id, quantity, unit_price, total_amount, status
  ) VALUES (
    p_program_id, p_product_id, v_farmer_id, p_quantity, v_product.unit_price,
    (v_product.unit_price * p_quantity), 'pending'
  )
  RETURNING id INTO v_purchase_id;

  SELECT full_name INTO v_farmer_name FROM public.user_information WHERE user_id = v_farmer_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  SELECT
    ap.user_id,
    'program',
    'New Program Purchase Request',
    COALESCE(v_farmer_name, 'A farmer') || ' requested to purchase ' || p_quantity || ' ' ||
      COALESCE(v_item_name, 'item(s)') || '.',
    FALSE,
    NOW()
  FROM public.admin_profiles ap;

  RETURN v_purchase_id;
END;
$function$;

-- 3c. respond_to_program_enrollment_request — the live definition plus one check
-- (approving is refused for a Completed program; declining is still allowed).
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
    RAISE EXCEPTION 'Unauthorized: only Managers can review enrollment requests';
  END IF;

  SELECT farmer_id, program_id, status INTO v_farmer_id, v_program_id, v_status
  FROM program_enrollment_requests WHERE id = p_request_id FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_status;
  END IF;

  -- NEW in Phase 1
  IF p_approve AND NOT EXISTS (
    SELECT 1 FROM cooperative_programs WHERE id = v_program_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'This program is Completed and no longer accepts new members. Decline the request instead.';
  END IF;

  SELECT program_name INTO v_program_name
  FROM cooperative_programs WHERE id = v_program_id;

  UPDATE program_enrollment_requests
  SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
      reviewed_by = auth.uid(),
      reviewed_at = NOW(),
      admin_notes = p_notes
  WHERE id = p_request_id;

  IF p_approve THEN
    -- Reactivate-or-insert (program_members has UNIQUE(program_id, farmer_id),
    -- and a farmer who was previously withdrawn already has a row here).
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
  END IF;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at)
  VALUES (
    v_farmer_id,
    'program',
    CASE WHEN p_approve THEN 'Program Enrollment Approved' ELSE 'Program Enrollment Declined' END,
    CASE WHEN p_approve
      THEN 'Your enrollment request for ' || COALESCE(v_program_name, 'the program') || ' was approved.'
      ELSE COALESCE(
        'Your enrollment request for ' || COALESCE(v_program_name, 'the program') || ' was declined: ' || p_notes,
        'Your enrollment request for ' || COALESCE(v_program_name, 'the program') || ' was declined. You may submit a new request.'
      )
    END,
    FALSE,
    NOW()
  );
END;
$function$;

-- ════════════════════════════════════════════════════════════
-- 4. Retire the old outcome workflow (names and signatures kept)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.record_program_thriving_outcome(p_program_member_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RAISE EXCEPTION 'Recording an outcome this way has been retired. Successful and Failed outcomes now need Farmer evidence, review and Officer field verification.';
END;
$function$;

CREATE OR REPLACE FUNCTION public.convert_program_distribution_to_loan(p_program_member_id uuid, p_monthly_payment numeric, p_next_payment_date date, p_notes text DEFAULT NULL::text)
 RETURNS TABLE(loan_id uuid, reference_no text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RAISE EXCEPTION 'A failed program no longer converts into a loan automatically. The Farmer requests assistance separately through Loan Management.';
END;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_program_return(p_program_member_id uuid, p_amount_returned numeric, p_admin_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RAISE EXCEPTION 'A program return is harvested produce, not money. Recording it will be part of the outcome workflow.';
END;
$function$;

-- ════════════════════════════════════════════════════════════
-- 5. Activities removal: the Farmer function goes; the table and data stay
-- ════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.get_my_program_activities();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- VERIFICATION (read-only; run each by itself AFTER applying)
-- ============================================================
-- V1. Only two statuses are allowed (expect: CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text])))):
--     SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'cooperative_programs_status_check';
-- V2. Delete protection triggers exist (expect 3 rows):
--     SELECT tgname, tgrelid::regclass FROM pg_trigger
--     WHERE tgname IN ('trg_protect_program_from_delete','trg_protect_program_members_delete','trg_protect_program_purchases_delete');
-- V3. A program that has members or purchases cannot be deleted. Inside a transaction you roll back, expect an error
--     naming the member / purchase counts, and the program still present afterwards:
--     BEGIN;
--       DELETE FROM cooperative_programs WHERE program_name = 'Peanut Seed Distribution';
--     ROLLBACK;
--     SELECT count(*) FROM cooperative_programs WHERE program_name = 'Peanut Seed Distribution';  -- expect 1
-- V4. The three retired functions now refuse (expect all three to raise; none change data):
--     SELECT pg_get_functiondef('public.convert_program_distribution_to_loan(uuid,numeric,date,text)'::regprocedure) ILIKE '%no longer converts%' AS convert_retired,
--            pg_get_functiondef('public.record_program_thriving_outcome(uuid)'::regprocedure) ILIKE '%retired%' AS thriving_retired,
--            pg_get_functiondef('public.confirm_program_return(uuid,numeric,text)'::regprocedure) ILIKE '%not money%' AS return_retired;
--     -- expect true, true, true
-- V5. The three guarded functions now check for a Completed program (expect true, true, true):
--     SELECT pg_get_functiondef('public.distribute_program_benefit(uuid,uuid,numeric,uuid)'::regprocedure) ILIKE '%Completed%' AS distribute_checks,
--            pg_get_functiondef('public.request_program_purchase(uuid,uuid,numeric)'::regprocedure) ILIKE '%Completed%' AS purchase_checks,
--            pg_get_functiondef('public.respond_to_program_enrollment_request(uuid,boolean,text)'::regprocedure) ILIKE '%Completed%' AS enroll_checks;
-- V6. The Farmer activities function is gone and the table + rows are intact (expect 0, then the same count as before = 0):
--     SELECT count(*) FROM pg_proc WHERE pronamespace = 'public'::regnamespace AND proname = 'get_my_program_activities';
--     SELECT count(*) FROM program_activities;
-- V7. No existing record changed (expect 5 distributed members, 1 paid purchase of 500.00, 6 programs):
--     SELECT count(*) FROM program_members WHERE distributed_at IS NOT NULL;
--     SELECT count(*), sum(total_amount) FROM program_product_purchases WHERE status = 'paid';
--     SELECT count(*) FROM cooperative_programs;
-- ============================================================
