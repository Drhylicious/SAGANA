-- ============================================================
-- supabase_schema_registration_21_login_verified_email_only.sql
--
-- A person may sign in with their USERNAME at any time. They may sign in with an
-- EMAIL only if that email has been verified (script 18). An unverified email is
-- never a way in, for any role, and this is enforced here in the database, not
-- only on the Login screen.
--
-- HOW IT IS ENFORCED
--   Supabase Auth logs a person in by looking their address up in auth.users.
--   So the rule is simply: auth.users.email is EITHER the generated
--   username@sagana.local address OR the address that was proven with a code.
--   An unverified address is never in auth.users, so Auth cannot match it.
--
--   1. promote_contact_email (Farmer/Buyer "save email"): saves the contact email
--      but no longer copies it into the sign-in address. The sign-in address is
--      switched to it by verify_contact_email (script 20) once the code is right.
--      Changing or removing the email puts the sign-in back to the username.
--   2. A guard on auth.users: the email column can only be set to a
--      username@sagana.local address or to the person's verified address. This
--      also stops a signed-in user from pointing their own account at any other
--      address by calling Supabase Auth directly.
--   3. A one-time clean-up: any Farmer/Buyer/Officer who currently signs in with
--      an address that is not verified goes back to their username sign-in. Their
--      email stays on their profile as an (Unverified) contact email.
--   4. A trigger on user_information: whenever a Farmer's, Buyer's or Officer's
--      contact email changes or is removed, a sign-in address that is no longer
--      their email goes back to the username sign-in (the verified-change path
--      then switches it to the new address).
--
-- Run AFTER scripts 18 and 20. Script 19 (email recovery) is independent.
-- Safe to re-run.
--
-- WHAT YOU WILL NOTICE
--   * A Farmer/Buyer who was signing in with an unverified email can no longer do
--     so; they sign in with their username, then verify the email in Edit Profile
--     (after which both work).
--   * Officers sign in with their OFF-XXXX username at any time. Their email signs
--     them in too, but only once it is verified.
--   * The Manager has no username, so their existing sign-in email is left alone.
--     It must be verified (it is, if you did Edit Profile -> Verify Email). From
--     now on it can only ever be changed to another VERIFIED address.
-- ============================================================

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                 WHERE table_schema = 'public' AND table_name = 'user_information'
                   AND column_name = 'pending_contact_email') THEN
    RAISE EXCEPTION 'Run script 20 (change email) before this one.';
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1. promote_contact_email: save the email, switch the sign-in only if verified
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.promote_contact_email(p_email text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user_id  uuid := auth.uid();
  v_new      text;
  v_username text;
  v_verified text;
  v_role     text;
  v_current  text;
  v_target   text;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT username, lower(btrim(verified_contact_email))
    INTO v_username, v_verified
  FROM public.user_information
  WHERE user_id = v_user_id;

  IF v_username IS NULL THEN
    RAISE EXCEPTION 'No username on file for this account';
  END IF;

  SELECT role INTO v_role FROM public.user_roles WHERE user_id = v_user_id LIMIT 1;
  IF v_role IS NULL OR v_role NOT IN ('farmer', 'buyer') THEN
    RAISE EXCEPTION 'Change your email from Edit Profile > Verify Email.';
  END IF;

  IF p_email IS NULL OR btrim(p_email) = '' THEN
    v_new := NULL;
  ELSE
    v_new := lower(btrim(p_email));

    IF NOT public.is_valid_email(v_new) THEN
      RAISE EXCEPTION 'Please enter a valid email address.';
    END IF;

    IF v_new LIKE '%@sagana.local' THEN
      RAISE EXCEPTION 'This email domain is reserved for internal use.';
    END IF;

    IF EXISTS (
         SELECT 1 FROM auth.users WHERE lower(email) = v_new AND id <> v_user_id
       )
       OR EXISTS (
         SELECT 1 FROM public.user_information
         WHERE lower(btrim(contact_email)) = v_new AND user_id <> v_user_id
       ) THEN
      RAISE EXCEPTION 'This email address is already used by another account.';
    END IF;
  END IF;

  UPDATE public.user_information
  SET contact_email = v_new
  WHERE user_id = v_user_id;

  -- The sign-in address follows the contact email ONLY while that email is the
  -- verified one. Otherwise the person signs in with their username.
  v_target := CASE WHEN v_new IS NOT NULL AND v_new = v_verified
                   THEN v_new
                   ELSE lower(btrim(v_username)) || '@sagana.local' END;
  SELECT lower(email) INTO v_current FROM auth.users WHERE id = v_user_id;

  IF v_current IS DISTINCT FROM v_target THEN
    UPDATE auth.users
    SET email = v_target, updated_at = now()
    WHERE id = v_user_id;

    -- identities.email is a generated column derived from identity_data.
    UPDATE auth.identities
    SET identity_data = identity_data || jsonb_build_object('email', v_target),
        updated_at = now()
    WHERE user_id = v_user_id AND provider = 'email';
  END IF;
END;
$function$;

REVOKE ALL ON FUNCTION public.promote_contact_email(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.promote_contact_email(text) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 2. The guard: auth.users.email is a username address or a verified address
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.auth_email_verified_only()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF NEW.email IS NULL OR lower(NEW.email) LIKE '%@sagana.local' THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.user_information ui
    WHERE ui.user_id = NEW.id
      AND ui.verified_contact_email IS NOT NULL
      AND lower(btrim(ui.verified_contact_email)) = lower(btrim(NEW.email))
  ) THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION 'An email can only be used to sign in after it has been verified (Edit Profile > Verify Email).';
END;
$$;

REVOKE ALL ON FUNCTION public.auth_email_verified_only() FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 3. One-time clean-up of Farmers/Buyers/Officers who sign in with an unverified address
-- ════════════════════════════════════════════════════════════

-- Keep the address on their profile first (as the Unverified contact email).
UPDATE public.user_information ui
SET contact_email = lower(btrim(u.email))
FROM auth.users u
WHERE u.id = ui.user_id
  AND nullif(btrim(ui.contact_email), '') IS NULL
  AND lower(u.email) NOT LIKE '%@sagana.local'
  AND EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = ui.user_id AND r.role IN ('farmer', 'buyer', 'officer'))
  AND ui.username IS NOT NULL
  AND lower(btrim(coalesce(ui.verified_contact_email, ''))) <> lower(btrim(u.email));

-- Then back to the username sign-in.
UPDATE auth.users u
SET email = lower(btrim(ui.username)) || '@sagana.local', updated_at = now()
FROM public.user_information ui
WHERE u.id = ui.user_id
  AND ui.username IS NOT NULL
  AND lower(u.email) NOT LIKE '%@sagana.local'
  AND EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = ui.user_id AND r.role IN ('farmer', 'buyer', 'officer'))
  AND lower(btrim(coalesce(ui.verified_contact_email, ''))) <> lower(btrim(u.email));

UPDATE auth.identities i
SET identity_data = i.identity_data || jsonb_build_object('email', u.email),
    updated_at = now()
FROM auth.users u
WHERE i.user_id = u.id
  AND i.provider = 'email'
  AND lower(u.email) LIKE '%@sagana.local'
  AND lower(coalesce(i.identity_data->>'email', '')) NOT LIKE '%@sagana.local';

-- ════════════════════════════════════════════════════════════
-- 4. The sign-in follows the contact email: when a Farmer's, Buyer's or Officer's
--    contact email changes or is removed, a sign-in address that is no longer
--    their email goes back to the username sign-in. (A Manager has no username
--    and their email IS the sign-in, so they are not covered: they can only
--    change it through a verified change, which the guard below enforces.)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.signin_follows_contact_email()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_current text;
  v_synth   text;
BEGIN
  IF NEW.username IS NULL
     OR NOT EXISTS (SELECT 1 FROM public.user_roles r
                    WHERE r.user_id = NEW.user_id AND r.role IN ('farmer', 'buyer', 'officer')) THEN
    RETURN NEW;
  END IF;
  SELECT lower(email) INTO v_current FROM auth.users WHERE id = NEW.user_id;
  IF v_current IS NULL OR v_current LIKE '%@sagana.local' THEN
    RETURN NEW;
  END IF;
  IF lower(btrim(coalesce(NEW.contact_email, ''))) IS DISTINCT FROM v_current THEN
    v_synth := lower(btrim(NEW.username)) || '@sagana.local';
    UPDATE auth.users SET email = v_synth, updated_at = now() WHERE id = NEW.user_id;
    UPDATE auth.identities
    SET identity_data = identity_data || jsonb_build_object('email', v_synth),
        updated_at = now()
    WHERE user_id = NEW.user_id AND provider = 'email';
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.signin_follows_contact_email() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_signin_follows_contact_email ON public.user_information;
CREATE TRIGGER trg_signin_follows_contact_email
  AFTER UPDATE OF contact_email ON public.user_information
  FOR EACH ROW
  WHEN (NEW.contact_email IS DISTINCT FROM OLD.contact_email)
  EXECUTE FUNCTION public.signin_follows_contact_email();

-- Guard goes on last, so the clean-up above is not what it is checked against.
DROP TRIGGER IF EXISTS trg_auth_email_verified_only ON auth.users;
CREATE TRIGGER trg_auth_email_verified_only
  BEFORE UPDATE OF email ON auth.users
  FOR EACH ROW
  WHEN (NEW.email IS DISTINCT FROM OLD.email)
  EXECUTE FUNCTION public.auth_email_verified_only();

COMMIT;

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- BLOCK 1 — WHO CAN SIGN IN BY EMAIL RIGHT NOW (read-only). Run on its own.
-- "Email sign-in" is yes only for a verified address. Everyone can use their
-- username whatever this says (Officers: always their OFF-XXXX username).
-- ============================================================

SELECT ui.full_name,
       (SELECT string_agg(r.role, ', ') FROM public.user_roles r WHERE r.user_id = ui.user_id) AS roles,
       ui.username,
       CASE WHEN lower(u.email) LIKE '%@sagana.local' THEN 'no (username only)'
            WHEN lower(btrim(coalesce(ui.verified_contact_email, ''))) = lower(btrim(u.email)) THEN 'YES (verified)'
            ELSE 'PROBLEM: unverified email is a sign-in' END AS email_sign_in,
       CASE WHEN ui.contact_email IS NULL OR btrim(ui.contact_email) = '' THEN '-'
            WHEN lower(btrim(coalesce(ui.verified_contact_email, ''))) = lower(btrim(ui.contact_email)) THEN 'Verified'
            ELSE 'Unverified' END AS contact_email_status
FROM public.user_information ui
JOIN auth.users u ON u.id = ui.user_id
ORDER BY email_sign_in, ui.full_name;


-- ============================================================
-- BLOCK 2 — CHECK the install (read-only). Run on its own. Every row PASS.
-- ============================================================

SELECT 'no account signs in with an unverified email' AS check_name,
       CASE WHEN NOT EXISTS (
              SELECT 1 FROM auth.users u
              LEFT JOIN public.user_information ui ON ui.user_id = u.id
              WHERE lower(u.email) NOT LIKE '%@sagana.local'
                AND lower(btrim(coalesce(ui.verified_contact_email, ''))) <> lower(btrim(u.email)))
            THEN 'PASS' ELSE 'FAIL' END AS result
UNION ALL
SELECT 'the sign-in follows a changed or removed contact email',
       CASE WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_signin_follows_contact_email' AND NOT tgisinternal)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'the guard on auth.users is in place',
       CASE WHEN EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_auth_email_verified_only' AND NOT tgisinternal)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'saving an email no longer changes the sign-in address by itself',
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname = 'promote_contact_email' LIMIT 1) LIKE '%v_verified%'
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'signed-in users can still save an email; signed-out users cannot',
       CASE WHEN has_function_privilege('authenticated', 'public.promote_contact_email(text)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.promote_contact_email(text)', 'EXECUTE')
            THEN 'PASS' ELSE 'FAIL' END;
