-- Officer access, final rule:
--   Officers manage Dashboard, Marketplace, Loan, Reports, Inventory, Crop Management,
--   Program Management, Loan Catalog, Supply Chain, Price Management, Market Linking,
--   Officer Profile and Edit Profile.
--   Officers are blocked only from the Members tab and its Member Management features.
--   Officers may suspend and reactivate BUYERS. Farmer suspension stays Admin-only.
--
-- Changes in this file:
--   1. Programme and contribution tables and programme functions return to their
--      original rules, since those screens belong to Officers' modules.
--   2. Password-reset requests and account e-mail changes stay Admin-only (Manage Accounts).
--   3. suspend_member and reactivate_member allow an Officer only when the target is a buyer.
--
-- Not applied automatically. Run in the Supabase SQL editor.

BEGIN;

-- 1a. Restore original policies (undo the split from the previous step).
DROP POLICY IF EXISTS "member_contributions: admin manages all (read)" ON public.member_contributions;
DROP POLICY IF EXISTS "member_contributions: admin manages all (insert)" ON public.member_contributions;
DROP POLICY IF EXISTS "member_contributions: admin manages all (update)" ON public.member_contributions;
DROP POLICY IF EXISTS "member_contributions: admin manages all (delete)" ON public.member_contributions;
DROP POLICY IF EXISTS "member_contributions: admin manages all" ON public.member_contributions;
CREATE POLICY "member_contributions: admin manages all" ON public.member_contributions
  FOR ALL TO public
  USING ((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid()))));

DROP POLICY IF EXISTS "program_members: admin manages all (read)" ON public.program_members;
DROP POLICY IF EXISTS "program_members: admin manages all (insert)" ON public.program_members;
DROP POLICY IF EXISTS "program_members: admin manages all (update)" ON public.program_members;
DROP POLICY IF EXISTS "program_members: admin manages all (delete)" ON public.program_members;
DROP POLICY IF EXISTS "program_members: admin manages all" ON public.program_members;
CREATE POLICY "program_members: admin manages all" ON public.program_members
  FOR ALL TO public
  USING ((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid()))));

DROP POLICY IF EXISTS "program_enrollment_requests: admin manages all (read)" ON public.program_enrollment_requests;
DROP POLICY IF EXISTS "program_enrollment_requests: admin manages all (insert)" ON public.program_enrollment_requests;
DROP POLICY IF EXISTS "program_enrollment_requests: admin manages all (update)" ON public.program_enrollment_requests;
DROP POLICY IF EXISTS "program_enrollment_requests: admin manages all (delete)" ON public.program_enrollment_requests;
DROP POLICY IF EXISTS "program_enrollment_requests: admin manages all" ON public.program_enrollment_requests;
CREATE POLICY "program_enrollment_requests: admin manages all" ON public.program_enrollment_requests
  FOR ALL TO public
  USING ((EXISTS ( SELECT 1
   FROM admin_profiles
  WHERE (admin_profiles.user_id = auth.uid()))));

-- 1b. Restore original programme functions.
-- confirm_program_return
CREATE OR REPLACE FUNCTION public.confirm_program_return(p_program_member_id uuid, p_amount_returned numeric, p_admin_notes text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member RECORD;
  v_program RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can confirm a program return';
  END IF;

  SELECT * INTO v_member FROM program_members WHERE id = p_program_member_id FOR UPDATE;
  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Program enrollment not found';
  END IF;
  IF v_member.settled_at IS NOT NULL THEN
    RAISE EXCEPTION 'This enrollment has already been settled';
  END IF;

  SELECT * INTO v_program FROM cooperative_programs WHERE id = v_member.program_id;
  IF v_program.benefit_type != 'revenue_share' THEN
    RAISE EXCEPTION 'This program does not require a return settlement';
  END IF;

  UPDATE program_members
  SET amount_returned = p_amount_returned,
      settled_at = NOW(),
      status = 'completed',
      notes = COALESCE(p_admin_notes, notes)
  WHERE id = p_program_member_id;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  VALUES (
    v_member.farmer_id,
    'program',
    'Program Return Settled',
    'Your return of ₱' || p_amount_returned || ' for ' || v_program.program_name || ' has been recorded. Thank you!',
    FALSE,
    NOW(),
    '/farmer/profile/programs'
  );
END;
$function$;

-- convert_program_distribution_to_loan
CREATE OR REPLACE FUNCTION public.convert_program_distribution_to_loan(p_program_member_id uuid, p_monthly_payment numeric, p_next_payment_date date, p_notes text DEFAULT NULL::text)
 RETURNS TABLE(loan_id uuid, reference_no text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_member       RECORD;
  v_item         RECORD;
  v_line_total   NUMERIC;
  v_items        JSONB;
  v_result       RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can convert a distribution to a loan';
  END IF;

  SELECT pm.*, cp.program_name INTO v_member
  FROM program_members pm
  JOIN cooperative_programs cp ON cp.id = pm.program_id
  WHERE pm.id = p_program_member_id
  FOR UPDATE OF pm;

  IF v_member IS NULL THEN
    RAISE EXCEPTION 'Program member not found';
  END IF;

  IF v_member.distributed_at IS NULL THEN
    RAISE EXCEPTION 'This member has not been distributed a benefit yet';
  END IF;

  IF v_member.converted_loan_id IS NOT NULL THEN
    RAISE EXCEPTION 'This distribution has already been converted to a loan';
  END IF;

  IF v_member.inventory_item_id IS NULL OR v_member.quantity_given IS NULL THEN
    RAISE EXCEPTION 'This distribution has no recorded item/quantity to convert';
  END IF;

  SELECT item_name, unit, COALESCE(unit_cost, 0) AS unit_cost
  INTO v_item
  FROM cooperative_inventory
  WHERE id = v_member.inventory_item_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'The distributed inventory item no longer exists';
  END IF;

  v_line_total := v_member.quantity_given * v_item.unit_cost;

  v_items := jsonb_build_array(jsonb_build_object(
    'itemName',  v_item.item_name,
    'quantity',  v_member.quantity_given,
    'unit',      v_item.unit,
    'unitPrice', v_item.unit_cost,
    'lineTotal', v_line_total
  ));

  SELECT * INTO v_result FROM issue_loan(
    v_member.farmer_id,
    v_items,
    CURRENT_DATE,
    p_monthly_payment,
    p_next_payment_date,
    COALESCE(p_notes, 'From Program Distribution: ' || v_member.program_name),
    auth.uid(),
    NULL
  );

  UPDATE farmer_loans
  SET source_program_id = v_member.program_id
  WHERE id = v_result.loan_id;

  UPDATE program_members
  SET distribution_outcome = 'failed',
      outcome_recorded_at = NOW(),
      converted_loan_id = v_result.loan_id
  WHERE id = p_program_member_id;

  RETURN QUERY SELECT v_result.loan_id, v_result.reference_no;
END;
$function$;

-- respond_to_program_enrollment_request
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
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can review enrollment requests';
  END IF;

  SELECT farmer_id, program_id, status INTO v_farmer_id, v_program_id, v_status
  FROM program_enrollment_requests WHERE id = p_request_id FOR UPDATE;

  IF v_farmer_id IS NULL THEN
    RAISE EXCEPTION 'Request not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Request already reviewed (status: %)', v_status;
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
    -- Reactivate-or-insert, identical shape to ProgramRepository.
    -- enrollFarmer() (program_members has UNIQUE(program_id, farmer_id),
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

-- 2. Buyer suspension and reactivation: Admin, or an Officer acting on a buyer.
-- suspend_member
CREATE OR REPLACE FUNCTION public.suspend_member(p_user_id uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT (is_platform_admin() OR (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()) AND EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = p_user_id AND r.role = 'buyer'))) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A suspension reason is required';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  UPDATE user_roles
  SET status = 'suspended', suspension_reason = trim(p_reason)
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, v_status, 'suspended', trim(p_reason), auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
  VALUES (p_user_id, 'member_updated', 'Account Suspended',
          'Your SP3 account has been suspended. Reason: ' || trim(p_reason)
          || ' Please contact the SP3 Cooperative.',
          false, '/farmer/profile');
END;
$function$;

-- reactivate_member
CREATE OR REPLACE FUNCTION public.reactivate_member(p_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT (is_platform_admin() OR (EXISTS (SELECT 1 FROM public.officer_profiles o WHERE o.user_id = auth.uid()) AND EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = p_user_id AND r.role = 'buyer'))) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  -- Only a suspended member can be reactivated. Any other status must go
  -- through its own flow (approve_member for pending applicants).
  IF v_status <> 'suspended' THEN
    RAISE EXCEPTION 'Only a suspended member can be reactivated (current: %)', v_status;
  END IF;

  UPDATE user_roles
  SET status = 'active', suspension_reason = NULL
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, v_status, 'active', 'Reactivated by admin', auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
  VALUES (p_user_id, 'member_updated', 'Account Reactivated',
          'Your SP3 account has been reactivated. Welcome back!',
          false, '/farmer/profile');
END;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── CHECKS ───────────────────────────────────────────────────────────────
-- 1. Officer can suspend a buyer and reactivate a suspended buyer.
-- 2. Officer cannot suspend or reactivate a farmer (Unauthorized).
-- 3. Admin can still suspend and reactivate farmers.
-- 4. Officer can run Program Management actions again.
