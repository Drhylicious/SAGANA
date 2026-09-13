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
