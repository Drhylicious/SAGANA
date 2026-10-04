-- Registration follow-ups (Batch 4 corrections)
--
-- 1. check_phone_available(text): phone counterpart of check_email_available.
--    Used before a registry match is completed, so a registry phone already
--    on another account is reported clearly instead of being overwritten.
--
-- 2. cancel_failed_registration(): rolls back the account created by a
--    self-registration attempt that failed after signup. Scoped to the
--    signed-in user and to accounts created within the last hour, so it
--    only removes the attempt that just failed. Frees the username, email,
--    and any registry link the attempt created.
--
-- Not applied automatically. Run in the Supabase SQL editor, then run the
-- verification block at the end. BEFORE running step 2, check the
-- "foreign keys referencing auth.users" query at the bottom: the function
-- deletes from the tables listed in it, and any other table with a
-- user-referencing foreign key must be added first.

BEGIN;

-- ─── 1. check_phone_available ────────────────────────────────────────────────
-- TRUE when no user_information.phone_number matches (trimmed, exact).
-- An empty / null input is considered available (phone is optional).

CREATE OR REPLACE FUNCTION public.check_phone_available(p_phone text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_norm text := trim(coalesce(p_phone, ''));
BEGIN
  IF v_norm = '' THEN
    RETURN true;
  END IF;

  RETURN NOT EXISTS (
    SELECT 1
    FROM public.user_information
    WHERE trim(phone_number) = v_norm
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.check_phone_available(text) TO anon, authenticated;

-- ─── 2. cancel_failed_registration ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cancel_failed_registration()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_uid     uuid := auth.uid();
  v_created timestamptz;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not signed in';
  END IF;

  SELECT created_at INTO v_created FROM auth.users WHERE id = v_uid;
  IF v_created IS NULL OR v_created < now() - interval '1 hour' THEN
    RAISE EXCEPTION 'Registration can only be cancelled within one hour of signup';
  END IF;

  -- Registry link, in case a failed attempt had already linked one.
  UPDATE public.sp3_member_registry
     SET is_registered = FALSE,
         registered_user_id = NULL
   WHERE registered_user_id = v_uid;

  DELETE FROM public.member_capital_shares       WHERE farmer_id = v_uid;
  DELETE FROM public.capital_contribution_events WHERE farmer_id = v_uid;
  DELETE FROM public.buyer_addresses             WHERE user_id = v_uid;
  DELETE FROM public.farmer_profiles             WHERE user_id = v_uid;
  DELETE FROM public.buyer_profiles              WHERE user_id = v_uid;
  DELETE FROM public.user_information            WHERE user_id = v_uid;
  DELETE FROM public.user_roles                  WHERE user_id = v_uid;

  DELETE FROM auth.users WHERE id = v_uid;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.cancel_failed_registration() TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── PRE-DEPLOY CHECK (read-only): foreign keys referencing auth.users ──────
-- Every table listed here must be handled by cancel_failed_registration()
-- or be guaranteed empty for a brand-new account. Rows from the other
-- tables would block the final DELETE FROM auth.users.
--
-- SELECT conrelid::regclass AS referencing_table, conname
-- FROM pg_constraint
-- WHERE contype = 'f' AND confrelid = 'auth.users'::regclass;

-- ─── POST-DEPLOY VERIFICATION (read-only) ────────────────────────────────
-- 1. Both functions exist (expect 2 rows):
--    SELECT proname FROM pg_proc
--    WHERE pronamespace = 'public'::regnamespace
--      AND proname IN ('check_phone_available', 'cancel_failed_registration');
--
-- 2. check_phone_available behaves (expect true, then false):
--    SELECT public.check_phone_available('');
--    SELECT public.check_phone_available('<an existing user_information phone>');
--
-- 3. Rollback test (use a throwaway test account created today, signed in
--    as that account, then run from the SQL editor as that user):
--    SELECT count(*) FROM auth.users WHERE id = auth.uid();  -- expect 1
--    SELECT public.cancel_failed_registration();
--    SELECT count(*) FROM auth.users WHERE id = auth.uid();  -- expect 0
