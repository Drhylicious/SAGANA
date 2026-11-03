-- ============================================================
-- SAGANA — Officer permissions, script 19: SHOW THE MANAGER'S E-MAIL IN MANAGE ACCOUNTS
--
-- WHY THE E-MAIL WAS MISSING
--   Manage Accounts reads user_information.contact_email. The Manager has no
--   separate contact e-mail: the Manager SIGNS IN with a real e-mail address, and
--   that address lives only in auth.users.email (see script registration_18,
--   "WHO COUNTS AS THE EMAIL FOR AN ACCOUNT"). The app cannot read auth.users for
--   another account, so the Manager's row showed only the phone number.
--
-- WHAT THIS DOES
--   Adds one read-only function that returns the sign-in e-mail of MANAGER accounts
--   only, and only when it is a real address (never the internal @sagana.local
--   one). Callable by staff (Manager and Officers) so both see the same row.
--   It returns nothing for Farmers, Buyers or Officers, so no other account's
--   sign-in address is exposed. Nothing is written or changed.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Re-runnable.
-- To undo: DROP FUNCTION public.get_manager_sign_in_emails();
-- ============================================================

DO $$
BEGIN
  IF to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_staff() is missing.';
  END IF;
  IF to_regclass('public.user_roles') IS NULL THEN
    RAISE EXCEPTION 'user_roles is missing.';
  END IF;
END $$;

BEGIN;

CREATE OR REPLACE FUNCTION public.get_manager_sign_in_emails()
RETURNS TABLE (account_id uuid, sign_in_email text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT r.user_id, lower(btrim(u.email))
  FROM public.user_roles r
  JOIN auth.users u ON u.id = r.user_id
  WHERE r.role = 'admin'
    AND public.is_staff()
    AND u.email IS NOT NULL
    AND lower(u.email) NOT LIKE '%@sagana.local';
$$;

REVOKE ALL ON FUNCTION public.get_manager_sign_in_emails() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_manager_sign_in_emails() TO authenticated;

COMMIT;

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
--   SELECT oid::regprocedure FROM pg_proc WHERE proname = 'get_manager_sign_in_emails';
--   -- In the SQL editor there is no signed-in user, so the function returns no rows
--   -- there. In the app: Manage Accounts > Management shows the Manager's e-mail.
-- ─────────────────────────────────────────────────────────────────────────
