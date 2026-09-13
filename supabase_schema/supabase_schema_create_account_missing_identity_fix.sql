-- Root cause: create_staff_account() and create_farmer_account() insert
-- directly into auth.users, but never insert a matching row into
-- auth.identities. GoTrue requires an identities row to authenticate
-- against — without it, login fails with a generic 500 ("Database error
-- querying schema"). Confirmed via auth.identities being empty for an
-- affected account, compared against a working account's row.
--
-- Built on top of the search_path fix already applied
-- (supabase_schema_create_account_search_path fix — 'public','auth','extensions').
-- CREATE OR REPLACE with identical argument lists to what's already live,
-- so no DROP is needed.

CREATE OR REPLACE FUNCTION public.create_staff_account(p_username text, p_password text, p_full_name text, p_phone_number text, p_sitio text DEFAULT NULL::text, p_position text DEFAULT NULL::text, p_employee_id text DEFAULT NULL::text, p_permissions jsonb DEFAULT NULL::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_user_id  UUID;
  v_email    TEXT;
  v_perms    JSONB;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can create staff accounts';
  END IF;

  v_email := lower(trim(p_username)) || '@sagana.local';
  v_perms := COALESCE(p_permissions, '{
    "can_record_payments": true,
    "can_approve_listings": true,
    "can_add_harvest": true,
    "can_issue_loans": false,
    "can_delete_members": false,
    "can_manage_accounts": false,
    "can_view_reports": false
  }'::jsonb);

  IF EXISTS (SELECT 1 FROM user_information WHERE username = lower(trim(p_username))) THEN
    RAISE EXCEPTION 'Username % is already taken', p_username;
  END IF;

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(), 'authenticated', 'authenticated',
    v_email, crypt(p_password, gen_salt('bf')), NOW(),
    '{"provider":"email","providers":["email"]}',
    json_build_object('full_name', p_full_name)::jsonb,
    NOW(), NOW(), '', ''
  )
  RETURNING id INTO v_user_id;

  -- Without this, GoTrue has no identity row to authenticate against and
  -- login fails with a generic 500 ("Database error querying schema") —
  -- confirmed via auth.identities being empty for this user, compared
  -- against a working account's row.
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

  INSERT INTO user_roles (user_id, role, status)
  VALUES (v_user_id, 'staff', 'active');

  INSERT INTO user_information (user_id, full_name, phone_number, sitio, username)
  VALUES (v_user_id, trim(p_full_name), trim(p_phone_number), p_sitio, lower(trim(p_username)));

  INSERT INTO staff_profiles (user_id, employee_id, position, permissions)
  VALUES (v_user_id,
    COALESCE(p_employee_id, 'EMP-' || lpad(
      (SELECT COUNT(*) + 1 FROM staff_profiles)::TEXT, 3, '0')),
    p_position, v_perms);

  RETURN v_user_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Username or employee ID already exists';
  WHEN OTHERS THEN RAISE;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_farmer_account(p_username text, p_password text, p_full_name text, p_phone_number text, p_sitio text, p_member_id text DEFAULT NULL::text, p_capital_shares integer DEFAULT 0, p_share_value_per_unit numeric DEFAULT 1000, p_initial_crops text[] DEFAULT ARRAY[]::text[], p_registry_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_user_id UUID;
  v_email   TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  v_email := lower(trim(p_username)) || '@sagana.local';
  IF EXISTS (SELECT 1 FROM user_information WHERE username = lower(trim(p_username))) THEN
    RAISE EXCEPTION 'Username % is already taken', p_username;
  END IF;
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
    created_at, updated_at, confirmation_token, recovery_token
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(), 'authenticated', 'authenticated',
    v_email, crypt(p_password, gen_salt('bf')), NOW(),
    '{"provider":"email","providers":["email"]}',
    json_build_object('full_name', p_full_name)::jsonb,
    NOW(), NOW(), '', ''
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

  INSERT INTO user_roles (user_id, role, status)
  VALUES (v_user_id, 'farmer', 'active');
  INSERT INTO user_information (user_id, full_name, phone_number, sitio, username)
  VALUES (v_user_id, trim(p_full_name), trim(p_phone_number), p_sitio, lower(trim(p_username)));
  INSERT INTO farmer_profiles (user_id, member_id, is_verified)
  VALUES (v_user_id,
    CASE WHEN p_member_id IS NOT NULL AND trim(p_member_id) <> ''
         THEN trim(p_member_id) ELSE NULL END,
    TRUE);
  IF p_capital_shares > 0 THEN
    INSERT INTO member_capital_shares (farmer_id, total_shares, share_value_per_unit)
    VALUES (v_user_id, p_capital_shares, p_share_value_per_unit);
  END IF;
  IF array_length(p_initial_crops, 1) > 0 THEN
    INSERT INTO farmer_crops (farmer_id, crop_name, category)
    SELECT v_user_id, unnest(p_initial_crops), 'Other';
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

NOTIFY pgrst, 'reload schema';
