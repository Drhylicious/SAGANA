-- Batch 7: Admin account creation and Purok removal (Admin side)
--
-- 1. create_farmer_account:
--    - removes p_purok (Purok is removed from SAGANA);
--    - adds p_contact_email (the Admin-entered email; the registry-matched
--      email is locked in the app and sent here);
--    - sets user_roles.must_change_password = true, so the new Farmer is
--      sent through the forced-password-change screen at first login;
--    - rejects an email already on another account (case-insensitive).
--    The signature changes, so the old overload is dropped first and the
--    new one created. Exactly one overload must remain (checked below).
--
-- 2. create_officer_account: removes the purok column from the INSERT.
--    Signature unchanged, so CREATE OR REPLACE. The purok column itself is
--    dropped in Batch 8.
--
-- Not applied automatically. Deploy this together with the Batch 7 app
-- build: the Add Member screen calls the new signature. Run in the Supabase
-- SQL editor (or `supabase db query --linked -f`), then run the verification
-- block at the end.

BEGIN;

-- ─── 1. create_farmer_account (signature change) ──────────────────────────────

-- Drops the previous signature (with p_purok) and this signature, so the file
-- can be run again without error ("already exists with same argument types").
DROP FUNCTION IF EXISTS public.create_farmer_account(
  text, text, text, text, text, date, text, numeric, numeric, text[], uuid
);
DROP FUNCTION IF EXISTS public.create_farmer_account(
  text, text, text, text, date, text, numeric, numeric, text[], uuid, text
);

CREATE FUNCTION public.create_farmer_account(
  p_username              text,
  p_password              text,
  p_full_name             text,
  p_phone_number          text      DEFAULT NULL::text,
  p_date_of_birth         date      DEFAULT NULL::date,
  p_gender                text      DEFAULT NULL::text,
  p_share_value_per_unit  numeric   DEFAULT 2000,
  p_initial_contribution  numeric   DEFAULT 0,
  p_initial_crops         text[]    DEFAULT ARRAY[]::text[],
  p_registry_id           uuid      DEFAULT NULL::uuid,
  p_contact_email         text      DEFAULT NULL::text
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_user_id   UUID;
  v_email     TEXT;
  v_contact   TEXT := NULLIF(lower(trim(COALESCE(p_contact_email, ''))), '');
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  IF p_date_of_birth IS NOT NULL
     AND p_date_of_birth > (CURRENT_DATE - INTERVAL '18 years') THEN
    RAISE EXCEPTION 'Member must be at least 18 years old';
  END IF;

  IF p_gender IS NOT NULL
     AND p_gender NOT IN ('male', 'female', 'prefer_not_to_say') THEN
    RAISE EXCEPTION 'Invalid gender value';
  END IF;

  v_email := lower(trim(p_username)) || '@sagana.local';

  IF EXISTS (SELECT 1 FROM user_information WHERE username = lower(trim(p_username))) THEN
    RAISE EXCEPTION 'Username % is already taken', p_username;
  END IF;

  IF EXISTS (
    SELECT 1 FROM user_information ui
    WHERE lower(trim(ui.full_name)) = lower(trim(p_full_name))
  ) THEN
    RAISE EXCEPTION 'A member named "%" already exists', p_full_name;
  END IF;

  IF v_contact IS NOT NULL AND EXISTS (
    SELECT 1 FROM user_information ui
    WHERE lower(trim(ui.contact_email)) = v_contact
  ) THEN
    RAISE EXCEPTION 'This email address is already used by another account.';
  END IF;

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
    json_build_object('full_name', p_full_name)::jsonb,
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
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', v_email,
      'email_verified', false,
      'phone_verified', false
    ),
    'email', NOW(), NOW(), NOW()
  );

  -- Forced password change at first login (Admin-issued temporary password).
  INSERT INTO user_roles (user_id, role, status, must_change_password)
  VALUES (v_user_id, 'farmer', 'active', true);

  INSERT INTO user_information (user_id, full_name, phone_number, username, contact_email)
  VALUES (
    v_user_id,
    trim(p_full_name),
    NULLIF(trim(COALESCE(p_phone_number, '')), ''),
    lower(trim(p_username)),
    v_contact
  );

  INSERT INTO farmer_profiles (user_id, is_verified, date_of_birth, gender)
  VALUES (v_user_id, TRUE, p_date_of_birth, p_gender);

  INSERT INTO member_capital_shares (farmer_id, share_value_per_unit, total_contribution)
  VALUES (v_user_id, COALESCE(p_share_value_per_unit, 2000), 0)
  ON CONFLICT (farmer_id) DO NOTHING;

  IF COALESCE(p_initial_contribution, 0) > 0 THEN
    INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by)
    VALUES (v_user_id, p_initial_contribution, 'opening_balance',
            'Recorded at account creation', auth.uid());
  END IF;

  IF array_length(p_initial_crops, 1) > 0 THEN
    INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id)
    SELECT v_user_id, cm.crop_name, cm.category, cm.id
    FROM crop_master cm
    WHERE cm.is_active = TRUE
      AND cm.crop_name = ANY(p_initial_crops)
    ON CONFLICT (farmer_id, crop_name) DO NOTHING;
  END IF;

  IF p_registry_id IS NOT NULL THEN
    UPDATE sp3_member_registry
    SET is_registered = TRUE, registered_user_id = v_user_id
    WHERE id = p_registry_id;
  END IF;

  RETURN v_user_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Username already taken';
  WHEN OTHERS THEN RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.create_farmer_account(
  text, text, text, text, date, text, numeric, numeric, text[], uuid, text
) TO authenticated;

-- ─── 2. create_officer_account (purok column removed from INSERT) ────────────

CREATE OR REPLACE FUNCTION public.create_officer_account(
  p_username      text,
  p_password      text,
  p_full_name     text,
  p_date_of_birth date    DEFAULT NULL::date,
  p_gender        text    DEFAULT NULL::text,
  p_email         text    DEFAULT NULL::text,
  p_phone_number  text    DEFAULT NULL::text,
  p_position      text    DEFAULT NULL::text,
  p_registry_id   uuid    DEFAULT NULL::uuid
)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_user_id     UUID;
  v_email       TEXT;
  v_reg         RECORD;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized: only admins can create Officer accounts';
  END IF;

  IF p_registry_id IS NULL THEN
    RAISE EXCEPTION 'An Officer Registry record is required';
  END IF;
  SELECT * INTO v_reg FROM officer_registry WHERE id = p_registry_id FOR UPDATE;
  IF v_reg IS NULL THEN
    RAISE EXCEPTION 'Officer Registry record not found';
  END IF;
  IF v_reg.is_registered THEN
    RAISE EXCEPTION 'This Officer Registry record already has an account';
  END IF;

  IF p_date_of_birth IS NOT NULL
     AND p_date_of_birth > (CURRENT_DATE - INTERVAL '18 years') THEN
    RAISE EXCEPTION 'Officer must be at least 18 years old';
  END IF;

  IF p_gender IS NOT NULL
     AND p_gender NOT IN ('male', 'female', 'prefer_not_to_say') THEN
    RAISE EXCEPTION 'Invalid gender value';
  END IF;

  v_email := lower(trim(p_username)) || '@sagana.local';
  IF EXISTS (SELECT 1 FROM user_information WHERE username = lower(trim(p_username))) THEN
    RAISE EXCEPTION 'Username % is already taken', p_username;
  END IF;

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
    json_build_object('full_name', p_full_name)::jsonb,
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

  INSERT INTO user_roles (user_id, role, status)
  VALUES (v_user_id, 'officer', 'active');

  INSERT INTO user_information (user_id, full_name, phone_number, username, contact_email)
  VALUES (
    v_user_id,
    trim(p_full_name),
    NULLIF(trim(COALESCE(p_phone_number, v_reg.phone_number, '')), ''),
    lower(trim(p_username)),
    NULLIF(lower(trim(COALESCE(p_email, v_reg.email, ''))), '')
  );

  INSERT INTO officer_profiles (user_id, position, date_of_birth, gender)
  VALUES (v_user_id, p_position, p_date_of_birth, p_gender);

  -- Operational authorization (Decision D21, unchanged from Phase D-2):
  -- an Officer performs the same operational writes an Admin does.
  INSERT INTO admin_profiles (user_id, position)
  VALUES (v_user_id, p_position)
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE officer_registry
  SET is_registered = TRUE, registered_user_id = v_user_id
  WHERE id = p_registry_id;

  RETURN v_user_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Username already taken';
  WHEN OTHERS THEN RAISE;
END;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION (read-only) ────────────────────────────────
-- 1. Exactly one create_farmer_account overload, with no p_purok (expect 1 row,
--    args contain p_contact_email and no p_purok):
--    SELECT count(*) AS overloads,
--           bool_or(pg_get_function_identity_arguments(oid) LIKE '%p_purok%') AS has_purok,
--           bool_or(pg_get_function_identity_arguments(oid) LIKE '%p_contact_email%') AS has_contact_email
--    FROM pg_proc
--    WHERE pronamespace = 'public'::regnamespace AND proname = 'create_farmer_account';
--
-- 2. No purok in either creator's body (expect 0 for both):
--    SELECT proname, (prosrc ILIKE '%purok%') AS mentions_purok
--    FROM pg_proc
--    WHERE pronamespace = 'public'::regnamespace
--      AND proname IN ('create_farmer_account', 'create_officer_account');
--
-- 3. After creating one test farmer from the app, the new role row is flagged
--    (expect must_change_password = true for that user only):
--    SELECT ur.user_id, ur.must_change_password, ui.username
--    FROM user_roles ur JOIN user_information ui USING (user_id)
--    WHERE ur.role = 'farmer' ORDER BY ur.must_change_password DESC LIMIT 5;
