-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_admin_create_member.sql
-- Creates a SECURITY DEFINER PostgreSQL function that allows the admin app
-- to create a new farmer account without terminating the admin's own session.
--
-- This is necessary because Supabase's client-side auth.signUp() signs in
-- as the new user, which would log out the admin. By using an RPC function
-- with SECURITY DEFINER, the server creates the auth user on behalf of the
-- admin without affecting the client session.
--
-- Run in Supabase SQL Editor (requires service role or superuser).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION create_farmer_account(
  p_email               TEXT,
  p_password            TEXT,
  p_full_name           TEXT,
  p_phone_number        TEXT,
  p_sitio               TEXT,
  p_member_id           TEXT      DEFAULT NULL,
  p_capital_shares      INT       DEFAULT 0,
  p_share_value_per_unit NUMERIC  DEFAULT 1000,
  p_initial_crops       TEXT[]    DEFAULT ARRAY[]::TEXT[]
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  -- Only admins may call this function
  IF NOT EXISTS (
    SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can create farmer accounts';
  END IF;

  -- 1. Create the auth user via Supabase's internal function
  --    (uses the auth schema which SECURITY DEFINER gives us access to)
  v_user_id := (
    SELECT id FROM auth.users
    WHERE email = lower(trim(p_email))
    LIMIT 1
  );

  IF v_user_id IS NOT NULL THEN
    RAISE EXCEPTION 'Email % is already registered', p_email;
  END IF;

  -- Insert into auth.users using Supabase's encrypted password format
  INSERT INTO auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    recovery_token
  )
  VALUES (
    '00000000-0000-0000-0000-000000000000',
    gen_random_uuid(),
    'authenticated',
    'authenticated',
    lower(trim(p_email)),
    crypt(p_password, gen_salt('bf')),
    NOW(), -- pre-confirmed since admin is creating
    '{"provider":"email","providers":["email"]}',
    json_build_object('full_name', p_full_name)::jsonb,
    NOW(),
    NOW(),
    '',
    ''
  )
  RETURNING id INTO v_user_id;

  -- 2. user_roles
  INSERT INTO user_roles (user_id, role, status, created_at)
  VALUES (v_user_id, 'farmer', 'active', NOW());

  -- 3. user_information
  INSERT INTO user_information (
    user_id, full_name, phone_number, sitio
  )
  VALUES (
    v_user_id,
    trim(p_full_name),
    trim(p_phone_number),
    p_sitio
  );

  -- 4. farmer_profiles
  INSERT INTO farmer_profiles (
    user_id, member_id, is_verified, created_at
  )
  VALUES (
    v_user_id,
    CASE WHEN p_member_id IS NOT NULL AND trim(p_member_id) <> ''
         THEN trim(p_member_id) ELSE NULL END,
    TRUE, -- admin-created members are pre-verified
    NOW()
  );

  -- 5. Capital shares (if any)
  IF p_capital_shares > 0 THEN
    INSERT INTO member_capital_shares (
      farmer_id, total_shares, share_value_per_unit
    )
    VALUES (
      v_user_id, p_capital_shares, p_share_value_per_unit
    );
  END IF;

  -- 6. Initial crops (if any)
  IF array_length(p_initial_crops, 1) > 0 THEN
    INSERT INTO farmer_crops (farmer_id, crop_name, category)
    SELECT
      v_user_id,
      unnest(p_initial_crops),
      'Other';
  END IF;

  RETURN v_user_id;

EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Email % is already registered', p_email;
  WHEN OTHERS THEN
    RAISE;
END;
$$;

-- Grant execute to authenticated role (admin guard is inside the function)
GRANT EXECUTE ON FUNCTION create_farmer_account TO authenticated;

-- Revoke from anon (safety)
REVOKE EXECUTE ON FUNCTION create_farmer_account FROM anon;
