-- ============================================================
-- SAGANA — Username Authentication & Staff Schema
-- Adds username-based auth support on top of existing email auth.
-- Usernames are stored in user_information.username.
-- Supabase auth.users.email stores {username}@sagana.local internally.
-- Admin continues using real email. Staff/Farmer/Buyer use username.
-- ============================================================

-- ─── 1. Add username column to user_information ───────────────────────────────
ALTER TABLE public.user_information
  ADD COLUMN IF NOT EXISTS username TEXT UNIQUE;

CREATE INDEX IF NOT EXISTS idx_user_information_username
  ON public.user_information (username);

-- ─── 2. Extend user_roles.role to include 'staff' ────────────────────────────
ALTER TABLE public.user_roles
  DROP CONSTRAINT IF EXISTS user_roles_role_check;

ALTER TABLE public.user_roles
  ADD CONSTRAINT user_roles_role_check
  CHECK (role IN ('admin', 'farmer', 'buyer', 'staff'));

-- ─── 3. staff_profiles table ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.staff_profiles (
  id           UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  employee_id  TEXT        UNIQUE,
  position     TEXT,
  permissions  JSONB       NOT NULL DEFAULT '{
    "can_record_payments": true,
    "can_approve_listings": true,
    "can_add_harvest": true,
    "can_issue_loans": false,
    "can_delete_members": false,
    "can_manage_accounts": false,
    "can_view_reports": false
  }'::jsonb,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (user_id)
);

CREATE TRIGGER trg_staff_profiles_updated_at
  BEFORE UPDATE ON public.staff_profiles
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.staff_profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "staff_profiles: staff reads own"
  ON public.staff_profiles FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "staff_profiles: admin manages all"
  ON public.staff_profiles FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

-- ─── 4. sp3_member_registry ──────────────────────────────────────────────────
-- Official SP3 member list. Admin-managed.
-- Used during self-registration to detect if a person is an official member.
-- If their name matches (case-insensitive), system assigns SP3-XXXX username.
CREATE TABLE IF NOT EXISTS public.sp3_member_registry (
  id            UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  full_name     TEXT        NOT NULL,
  normalized_name TEXT      GENERATED ALWAYS AS (lower(trim(full_name))) STORED,
  sitio         TEXT,
  phone_number  TEXT,
  is_registered BOOLEAN     NOT NULL DEFAULT FALSE, -- true once they create an account
  registered_user_id UUID   REFERENCES auth.users(id) ON DELETE SET NULL,
  notes         TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_sp3_member_registry_updated_at
  BEFORE UPDATE ON public.sp3_member_registry
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE INDEX IF NOT EXISTS idx_sp3_registry_normalized
  ON public.sp3_member_registry (normalized_name);

ALTER TABLE public.sp3_member_registry ENABLE ROW LEVEL SECURITY;

-- Admin manages the registry
CREATE POLICY "sp3_registry: admin manages all"
  ON public.sp3_member_registry FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

-- Public read for registration check (unauthenticated check needed)
CREATE POLICY "sp3_registry: public checks name"
  ON public.sp3_member_registry FOR SELECT
  USING (true);

-- ─── 5. RPC: check_sp3_registry ──────────────────────────────────────────────
-- Called during self-registration to check if a name is in the registry.
-- Returns null if not found, returns the registry row if found.
CREATE OR REPLACE FUNCTION check_sp3_registry(p_full_name TEXT)
RETURNS TABLE (
  registry_id   UUID,
  is_available  BOOLEAN,
  suggested_sitio TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    r.id,
    NOT r.is_registered AS is_available,
    r.sitio
  FROM sp3_member_registry r
  WHERE r.normalized_name = lower(trim(p_full_name))
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION check_sp3_registry TO anon, authenticated;

-- ─── 6. RPC: suggest_next_username ───────────────────────────────────────────
-- Returns the next available SP3-XXXX or STF-XXXX username.
CREATE OR REPLACE FUNCTION suggest_next_username(p_prefix TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
  v_candidate TEXT;
  v_exists BOOLEAN;
BEGIN
  -- Count existing usernames with this prefix
  SELECT COUNT(*) INTO v_count
  FROM user_information
  WHERE username ILIKE p_prefix || '-%';

  LOOP
    v_count := v_count + 1;
    v_candidate := p_prefix || '-' || lpad(v_count::TEXT, 4, '0');
    SELECT EXISTS (
      SELECT 1 FROM user_information WHERE username = v_candidate
    ) INTO v_exists;
    EXIT WHEN NOT v_exists;
  END LOOP;

  RETURN v_candidate;
END;
$$;

GRANT EXECUTE ON FUNCTION suggest_next_username TO anon, authenticated;

-- ─── 7. RPC: create_staff_account ────────────────────────────────────────────
-- Parallel to create_farmer_account but for staff.
-- Admin-only. Creates auth user with username@sagana.local email.
CREATE OR REPLACE FUNCTION create_staff_account(
  p_username    TEXT,
  p_password    TEXT,
  p_full_name   TEXT,
  p_phone_number TEXT,
  p_sitio       TEXT DEFAULT NULL,
  p_position    TEXT DEFAULT NULL,
  p_employee_id TEXT DEFAULT NULL,
  p_permissions JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
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

  -- Check username not taken
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
$$;

GRANT EXECUTE ON FUNCTION create_staff_account TO authenticated;
REVOKE EXECUTE ON FUNCTION create_staff_account FROM anon;

-- ─── 8. Update create_farmer_account to store username ───────────────────────
-- Replace the existing RPC with an updated version that:
-- a) accepts p_username instead of p_email
-- b) stores username in user_information.username
-- c) uses username@sagana.local as the auth email
DO $$
BEGIN
  DROP FUNCTION IF EXISTS public.create_farmer_account(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, NUMERIC, TEXT[]
  );
  DROP FUNCTION IF EXISTS public.create_farmer_account(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, INT, NUMERIC, TEXT[], UUID
  );
END
$$;

CREATE FUNCTION create_farmer_account(
  p_username             TEXT,
  p_password             TEXT,
  p_full_name            TEXT,
  p_phone_number         TEXT,
  p_sitio                TEXT,
  p_member_id            TEXT      DEFAULT NULL,
  p_capital_shares       INT       DEFAULT 0,
  p_share_value_per_unit NUMERIC   DEFAULT 1000,
  p_initial_crops        TEXT[]    DEFAULT ARRAY[]::TEXT[],
  p_registry_id          UUID      DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
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

  -- Mark registry entry as registered
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
$$;

GRANT EXECUTE ON FUNCTION create_farmer_account TO authenticated;
REVOKE EXECUTE ON FUNCTION create_farmer_account FROM anon;