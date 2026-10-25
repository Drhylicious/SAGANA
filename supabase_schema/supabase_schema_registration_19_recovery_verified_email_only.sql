-- ============================================================
-- supabase_schema_registration_19_recovery_verified_email_only.sql
--
-- Email-based password recovery (the emailed OTP) is allowed ONLY for an email
-- address that has been verified (script 18). The other recovery method,
-- "Request Password Assistance" (the Manager sets a temporary password for a
-- username), is not touched and stays open to everyone.
--
-- Run after script 18. Safe to re-run.
--
-- !! BEFORE YOU RUN THIS: every existing address is Unverified, so the moment
-- this is applied NO account can recover by email until its owner verifies it
-- in Edit Profile. That includes the Manager: nobody can use Password
-- Assistance for the Manager's own account. Verify the Manager's email in the
-- app FIRST (Edit Profile -> Verify Email), then run this.
--
-- WHAT "VERIFIED" MEANS HERE (recovery_email_is_verified)
--   The recovery email goes to the account's SIGN-IN email (auth.users.email).
--   So the account is eligible only when that sign-in email is a real address AND
--   equals the address that was proven with a code. This is stricter than "the
--   contact email is verified": a contact email that was changed after
--   verification, or an Officer's generated sign-in address, never qualifies.
--
-- TWO PLACES THIS IS ENFORCED
--   1. can_use_otp_reset(): what the Login screen asks before it offers the
--      emailed code. (UI routing: the database answers, the app does not decide.)
--   2. may_receive_recovery_email(): asked by the Send Email hook
--      (supabase/functions/auth-send-email). Supabase Auth sends the recovery
--      email itself, so a check in the app or in a database function cannot stop
--      a direct call to Auth. The hook is the one place that can refuse the send.
--      TURN THE HOOK ON (see that function's README), or only (1) applies.
-- ============================================================

BEGIN;

-- The one rule. Internal: not callable from the app.
CREATE OR REPLACE FUNCTION public.recovery_email_is_verified(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT coalesce((
    SELECT u.email IS NOT NULL
       AND lower(u.email) NOT LIKE '%@sagana.local'
       AND ui.verified_contact_email IS NOT NULL
       AND lower(btrim(u.email)) = lower(btrim(ui.verified_contact_email))
    FROM auth.users u
    JOIN public.user_information ui ON ui.user_id = u.id
    WHERE u.id = p_user_id
  ), false);
$$;

REVOKE ALL ON FUNCTION public.recovery_email_is_verified(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.recovery_email_is_verified(uuid) TO service_role;

-- 1. The Login screen's question: may this identifier use the emailed code?
--    Same shape as before (anon can call it, one boolean back, the same "false"
--    for unknown / no email / unverified so it reveals nothing about accounts).
CREATE OR REPLACE FUNCTION public.can_use_otp_reset(p_identifier TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user_id UUID;
BEGIN
  SELECT ui.user_id INTO v_user_id
  FROM public.user_information ui
  WHERE ui.username = lower(trim(p_identifier));

  IF v_user_id IS NULL THEN
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE lower(email) = lower(trim(p_identifier));
  END IF;

  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  RETURN public.recovery_email_is_verified(v_user_id);
END;
$function$;

GRANT EXECUTE ON FUNCTION public.can_use_otp_reset(TEXT) TO anon;
GRANT EXECUTE ON FUNCTION public.can_use_otp_reset(TEXT) TO authenticated;

-- 2. The Send Email hook's question: may a recovery email go to this address?
CREATE OR REPLACE FUNCTION public.may_receive_recovery_email(p_email text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT coalesce((
    SELECT public.recovery_email_is_verified(u.id)
    FROM auth.users u
    WHERE lower(u.email) = lower(btrim(p_email))
    LIMIT 1
  ), false);
$$;

REVOKE ALL ON FUNCTION public.may_receive_recovery_email(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.may_receive_recovery_email(text) TO service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- BLOCK 1 — WHO CAN RECOVER BY EMAIL RIGHT NOW (read-only). Run on its own.
-- "Email recovery" = yes only for a verified address. Everyone can always use
-- Password Assistance (the username route) whatever this says.
-- ============================================================

SELECT ui.full_name,
       (SELECT string_agg(r.role, ', ') FROM public.user_roles r WHERE r.user_id = ui.user_id) AS roles,
       u.email                                                           AS sign_in_email,
       CASE WHEN lower(u.email) LIKE '%@sagana.local' THEN 'username only'
            WHEN public.recovery_email_is_verified(ui.user_id) THEN 'YES'
            WHEN ui.verified_contact_email IS NULL THEN 'no (not verified)'
            ELSE 'no (sign-in email differs from the verified one)' END  AS email_recovery,
       'yes'                                                             AS password_assistance
FROM public.user_information ui
JOIN auth.users u ON u.id = ui.user_id
ORDER BY email_recovery, ui.full_name;


-- ============================================================
-- BLOCK 2 — CHECK the install (read-only). Run on its own. Every row PASS.
-- ============================================================

SELECT 'the rule exists and only the server can call it' AS check_name,
       CASE WHEN has_function_privilege('service_role', 'public.recovery_email_is_verified(uuid)', 'EXECUTE')
             AND NOT has_function_privilege('authenticated', 'public.recovery_email_is_verified(uuid)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.recovery_email_is_verified(uuid)', 'EXECUTE')
            THEN 'PASS' ELSE 'FAIL' END AS result
UNION ALL
SELECT 'the hook check is service-role only',
       CASE WHEN has_function_privilege('service_role', 'public.may_receive_recovery_email(text)', 'EXECUTE')
             AND NOT has_function_privilege('authenticated', 'public.may_receive_recovery_email(text)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.may_receive_recovery_email(text)', 'EXECUTE')
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'the Login screen can still ask whether email recovery is available',
       CASE WHEN has_function_privilege('anon', 'public.can_use_otp_reset(text)', 'EXECUTE')
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'Password Assistance is untouched',
       CASE WHEN has_function_privilege('anon', 'public.request_password_assistance(text)', 'EXECUTE')
            THEN 'PASS' ELSE 'FAIL' END;
