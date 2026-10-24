-- ============================================================
-- SAGANA — Registration refactor, step 10: an Officer created by the Manager
-- must change the temporary password at first sign-in
--
-- WHY. create_farmer_account already marks a Manager-created Farmer
-- must_change_password = true, so the app sends them to the "choose a new
-- password" screen before anything else. create_officer_account did not, so a
-- Manager-created Officer could keep the temporary password the Manager had
-- typed (and may have shared). This makes both accounts behave the same.
--
-- WHAT CHANGES. Only one statement of create_officer_account: the user_roles
-- insert now also sets must_change_password = true. Everything else in the
-- function is copied unchanged from script 02 (same name, same arguments, same
-- return type, same checks, same rights).
--
-- WHAT DOES NOT CHANGE.
--   * Officer accounts that already exist are NOT touched (a one-line option
--     is at the bottom if you want to force them as well).
--   * The app needs no change: the sign-in code, the router and the
--     change-password screen already handle this flag for every role.
--
-- Not applied automatically. Run it in the Supabase SQL editor, then run the
-- verification block at the end.
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ──────────────────────────────────────────────
-- Exactly one version of the function must exist (expect 1 row, overloads = 1):
--   SELECT proname, count(*) AS overloads FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace AND proname = 'create_officer_account'
--   GROUP BY proname;
-- ────────────────────────────────────────────────────────────────────────

BEGIN;

CREATE OR REPLACE FUNCTION public.create_officer_account(
  p_username        text,
  p_password        text,
  p_full_name       text,
  p_date_of_birth   date    DEFAULT NULL,
  p_gender          text    DEFAULT NULL,
  p_email           text    DEFAULT NULL,
  p_phone_number    text    DEFAULT NULL,
  p_position        text    DEFAULT NULL,
  p_membership_year integer DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_user_id  UUID;
  v_username TEXT := lower(trim(coalesce(p_username, '')));
  v_name     TEXT := regexp_replace(trim(coalesce(p_full_name, '')), '\s+', ' ', 'g');
  v_email    TEXT;
  v_phone    TEXT;
  v_contact  TEXT := NULLIF(lower(trim(COALESCE(p_email, ''))), '');
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized: only Managers can create Officer accounts';
  END IF;

  IF length(v_name) < 2 THEN
    RAISE EXCEPTION 'Please enter the full name.';
  END IF;

  IF v_username !~ '^[a-z0-9._-]{3,30}$' THEN
    RAISE EXCEPTION 'Username must be 3 to 30 characters: letters, numbers, dots, underscores or hyphens.';
  END IF;
  IF EXISTS (SELECT 1 FROM user_information WHERE lower(trim(username)) = v_username) THEN
    RAISE EXCEPTION 'This username is already taken.';
  END IF;

  IF p_date_of_birth IS NOT NULL
     AND p_date_of_birth > (CURRENT_DATE - INTERVAL '18 years') THEN
    RAISE EXCEPTION 'Officer must be at least 18 years old';
  END IF;

  IF p_gender IS NOT NULL
     AND p_gender NOT IN ('male', 'female', 'prefer_not_to_say') THEN
    RAISE EXCEPTION 'Invalid gender value';
  END IF;

  IF NULLIF(trim(coalesce(p_phone_number, '')), '') IS NOT NULL THEN
    v_phone := public.normalize_ph_mobile(p_phone_number);
    IF v_phone IS NULL THEN
      RAISE EXCEPTION 'Please enter a valid Philippine mobile number.';
    END IF;
    IF EXISTS (
      SELECT 1 FROM user_information ui
      WHERE public.normalize_ph_mobile(ui.phone_number) = v_phone
    ) THEN
      RAISE EXCEPTION 'This phone number is already used by another account.';
    END IF;
  END IF;

  IF v_contact IS NOT NULL THEN
    IF NOT public.is_valid_email(v_contact) THEN
      RAISE EXCEPTION 'Please enter a valid email address.';
    END IF;
    IF EXISTS (
      SELECT 1 FROM user_information ui
      WHERE lower(trim(ui.contact_email)) = v_contact
    ) THEN
      RAISE EXCEPTION 'This email address is already used by another account.';
    END IF;
  END IF;

  v_email := v_username || '@sagana.local';

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at,
    confirmation_token, recovery_token, email_change, email_change_token_new,
    email_change_token_current, phone_change, phone_change_token,
    reauthentication_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(), 'authenticated', 'authenticated',
    v_email, crypt(p_password, gen_salt('bf', 10)), NOW(),
    '{"provider":"email","providers":["email"]}',
    json_build_object('full_name', v_name)::jsonb,
    NOW(), NOW(),
    '', '', '', '',
    '', '', '',
    ''
  )
  RETURNING id INTO v_user_id;

  INSERT INTO auth.identities (
    provider_id, user_id, identity_data, provider,
    last_sign_in_at, created_at, updated_at
  ) VALUES (
    v_user_id::text, v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email,
                       'email_verified', false, 'phone_verified', false),
    'email', NOW(), NOW(), NOW()
  );

  -- Manager-created: active at once, forced password change at first login
  -- (same rule as create_farmer_account).
  INSERT INTO user_roles (user_id, role, status, must_change_password)
  VALUES (v_user_id, 'officer', 'active', true);

  INSERT INTO user_information (user_id, full_name, phone_number, username, contact_email)
  VALUES (v_user_id, v_name, v_phone, v_username, v_contact);

  INSERT INTO officer_profiles (user_id, position, date_of_birth, gender)
  VALUES (v_user_id, p_position, p_date_of_birth, p_gender);

  -- OFF-YYYY-NNN
  PERFORM public.issue_member_identifier(v_user_id, 'officer', p_membership_year);

  RETURN v_user_id;
EXCEPTION
  WHEN unique_violation THEN
    IF SQLERRM ILIKE '%username%' THEN
      RAISE EXCEPTION 'This username is already taken.';
    END IF;
    RAISE;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_officer_account(
  text, text, text, date, text, text, text, text, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_officer_account(
  text, text, text, date, text, text, text, text, integer
) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION ────────────────────────────────────────────
-- 1. The new statement is live (expect true), and there is still one version:
--    SELECT prosrc LIKE '%must_change_password%' AS flag_set, count(*) OVER () AS versions
--    FROM pg_proc
--    WHERE pronamespace = 'public'::regnamespace AND proname = 'create_officer_account';
--
-- 2. The function keeps its rights (expect prosecdef = true; anon cannot run it):
--    SELECT prosecdef,
--           has_function_privilege('anon', p.oid, 'EXECUTE')          AS anon_can,
--           has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can
--    FROM pg_proc p
--    WHERE p.pronamespace = 'public'::regnamespace AND p.proname = 'create_officer_account';
--    -- expect:  true | false | true
--
-- 3. Behaviour: in the app, as the Manager, create an Officer (Add -> Add Officer).
--    Then:
--      SELECT ui.username, ur.role, ur.status, ur.must_change_password
--      FROM public.user_information ui JOIN public.user_roles ur USING (user_id)
--      WHERE ui.username = '<the new officer username>';
--    -- expect:  officer | active | true
--    Sign in as that Officer with the temporary password: the app must open the
--    "choose a new password" screen first. After a new password is saved the
--    flag becomes false (re-run the query: false).
--
-- OPTIONAL — also force the Officers who already exist to choose a new password
-- at their next sign-in (only if you want that; it affects real accounts, so
-- look at the list first):
--    SELECT ui.username, ui.full_name FROM public.user_roles ur
--    JOIN public.user_information ui USING (user_id) WHERE ur.role = 'officer';
--    UPDATE public.user_roles SET must_change_password = true WHERE role = 'officer';
-- ============================================================
