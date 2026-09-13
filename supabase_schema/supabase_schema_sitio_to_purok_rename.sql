-- ============================================================
-- SAGANA — Rename "Sitio" terminology to "Purok" system-wide
-- Renames the underlying columns and updates the three
-- SECURITY DEFINER functions that reference them, based on the
-- CURRENT live function definitions (confirmed via
-- pg_get_functiondef, not the older migration files, which do
-- not match what's actually deployed).
-- ============================================================

BEGIN;

-- ─── 1. Rename columns ───────────────────────────────────────────────────────

ALTER TABLE public.user_information RENAME COLUMN sitio TO purok;
ALTER TABLE public.sp3_member_registry RENAME COLUMN sitio TO purok;

COMMENT ON COLUMN public.user_information.purok IS
  'One of: ''Purok 1 — Centro 1'', ''Purok 2 — Centro 2'', ''Purok 3 — Centro 3'', '
  '''Purok 4 — Kailugan'', ''Purok 5 — Binubungan'', ''Purok 6 — Tigas'', ''Purok 7 — Manggahan''';

-- ─── 2. check_sp3_registry — rename returned column ──────────────────────────

DROP FUNCTION IF EXISTS public.check_sp3_registry(text);

CREATE FUNCTION public.check_sp3_registry(p_full_name text)
 RETURNS TABLE(registry_id uuid, is_available boolean, suggested_purok text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    r.id,
    NOT r.is_registered AS is_available,
    r.purok
  FROM sp3_member_registry r
  WHERE r.normalized_name = lower(trim(p_full_name))
  LIMIT 1;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.check_sp3_registry TO anon, authenticated;

-- ─── 3. create_farmer_account — rename parameter + column reference ─────────

DROP FUNCTION IF EXISTS public.create_farmer_account(text,text,text,text,text,text,integer,numeric,text[],uuid);

CREATE FUNCTION public.create_farmer_account(p_username text, p_password text, p_full_name text, p_phone_number text, p_purok text, p_member_id text DEFAULT NULL::text, p_capital_shares integer DEFAULT 0, p_share_value_per_unit numeric DEFAULT 1000, p_initial_crops text[] DEFAULT ARRAY[]::text[], p_registry_id uuid DEFAULT NULL::uuid)
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
  VALUES (v_user_id, 'farmer', 'active');

  INSERT INTO user_information (user_id, full_name, phone_number, purok, username)
  VALUES (v_user_id, trim(p_full_name), trim(p_phone_number), p_purok, lower(trim(p_username)));

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

GRANT EXECUTE ON FUNCTION public.create_farmer_account TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_farmer_account FROM anon;

-- ─── 4. create_staff_account — rename parameter + column reference ──────────

DROP FUNCTION IF EXISTS public.create_staff_account(text,text,text,text,text,text,text,jsonb);

CREATE FUNCTION public.create_staff_account(p_username text, p_password text, p_full_name text, p_phone_number text, p_purok text DEFAULT NULL::text, p_position text DEFAULT NULL::text, p_employee_id text DEFAULT NULL::text, p_permissions jsonb DEFAULT NULL::jsonb)
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

  INSERT INTO user_information (user_id, full_name, phone_number, purok, username)
  VALUES (v_user_id, trim(p_full_name), trim(p_phone_number), p_purok, lower(trim(p_username)));

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

GRANT EXECUTE ON FUNCTION public.create_staff_account TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_staff_account FROM anon;

COMMIT;