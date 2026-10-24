-- Delete a rejected applicant from the system.
--
-- Admin only (is_platform_admin). The target must be a farmer account whose
-- user_roles row is status 'rejected' and is the account's only role. The
-- function also refuses the caller's own account and any account that has
-- financial or operational records, as a safety net. The auth user is
-- removed, and the ON DELETE CASCADE rules remove the public rows
-- (user_roles, user_information, farmer_profiles, notifications and so on).
--
-- Run manually in the Supabase SQL editor (or supabase db query --linked -f).

BEGIN;

CREATE OR REPLACE FUNCTION public.admin_delete_rejected_applicant(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_role_count integer;
  v_role text;
  v_status text;
BEGIN
  IF NOT public.is_platform_admin(auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'You cannot delete your own account';
  END IF;

  SELECT count(*) INTO v_role_count FROM user_roles WHERE user_id = p_user_id;
  SELECT role, status INTO v_role, v_status FROM user_roles WHERE user_id = p_user_id;

  IF v_role_count <> 1 OR v_role <> 'farmer' OR v_status <> 'rejected' THEN
    RAISE EXCEPTION 'Only rejected farmer applicants can be deleted';
  END IF;

  IF EXISTS (SELECT 1 FROM harvest_records WHERE farmer_id = p_user_id)
     OR EXISTS (SELECT 1 FROM orders WHERE farmer_id = p_user_id OR buyer_id = p_user_id)
     OR EXISTS (SELECT 1 FROM farmer_loans WHERE farmer_id = p_user_id)
     OR EXISTS (SELECT 1 FROM member_capital_shares WHERE farmer_id = p_user_id)
     OR EXISTS (SELECT 1 FROM member_contributions WHERE farmer_id = p_user_id)
     OR EXISTS (SELECT 1 FROM capital_contribution_events WHERE farmer_id = p_user_id)
  THEN
    RAISE EXCEPTION 'This applicant has financial or operational records and cannot be deleted';
  END IF;

  INSERT INTO admin_activity_log (admin_id, module, action_type, description, reference_id)
  VALUES (
    auth.uid(),
    'members',
    'delete_rejected_applicant',
    'Deleted a rejected applicant account.',
    p_user_id
  );

  DELETE FROM auth.users WHERE id = p_user_id;
END;
$function$;

REVOKE ALL ON FUNCTION public.admin_delete_rejected_applicant(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_delete_rejected_applicant(uuid) TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
