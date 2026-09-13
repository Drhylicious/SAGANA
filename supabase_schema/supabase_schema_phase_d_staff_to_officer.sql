-- ============================================================
-- SAGANA — Phase D-1: Staff → Officer rename + Officer Registry
-- (Admin Members tab enhancement — Issue 6, Decisions D18–D23)
--
-- Scope of THIS migration (D-1):
--   1. user_roles.role CHECK  : 'staff' -> 'officer' (data + constraint)
--   2. staff_profiles          -> officer_profiles (table rename);
--      DROP the per-flag `permissions` column (Decision D12 — Officer is
--      now a fixed role: every Admin module EXCEPT the Members tab, with
--      the same data Admin sees; there is no per-officer variation).
--   3. Migrate the existing officer identity fully:
--        user_information.username         stf-0001  -> off-0001
--        auth.users.email / auth.identities  stf-0001@sagana.local -> off-0001@sagana.local
--      employee_id (EMP-###) is unchanged.
--   4. officer_registry  — mirror of sp3_member_registry (Decision D22):
--      every Officer must have a registry row; the create form auto-fills
--      from it. Seeded with the existing officer.
--   5. generate_employee_id()  — the single EMP-### generator, globally
--      sequential, zero-padded 3, advisory-locked (Decision D23).
--   6. check_officer_registry(text)  — name lookup for the create form.
--   7. create_officer_account(...)   — replaces create_staff_account;
--      email + phone optional, EMP-### auto, requires an officer_registry
--      match. Old create_staff_account is dropped.
--   8. Rename the Staff read-only RLS policies to Officer.
--
-- NOT in this migration (Phase D-2): widening the ~15 operational RPCs
-- and the operational "admin manages all" RLS policies so an Officer can
-- actually perform loan/listing/order/offer/inventory/price writes. Until
-- D-2, an Officer has the same SELECT-only operational access Staff had.
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. user_roles.role — staff -> officer
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.user_roles DROP CONSTRAINT IF EXISTS user_roles_role_check;

UPDATE public.user_roles SET role = 'officer' WHERE role = 'staff';

ALTER TABLE public.user_roles ADD CONSTRAINT user_roles_role_check
  CHECK (role IN ('admin', 'farmer', 'buyer', 'officer'));

-- ════════════════════════════════════════════════════════════
-- 2. staff_profiles -> officer_profiles  (+ drop permissions)
-- ════════════════════════════════════════════════════════════

ALTER TABLE IF EXISTS public.staff_profiles RENAME TO officer_profiles;

-- Rename the PK / unique constraint names too, so nothing downstream
-- trips over a stale "staff_profiles_*" identifier.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT conname FROM pg_constraint
    WHERE conrelid = 'public.officer_profiles'::regclass
      AND conname LIKE 'staff_profiles%'
  LOOP
    EXECUTE format('ALTER TABLE public.officer_profiles RENAME CONSTRAINT %I TO %I',
                   r.conname, replace(r.conname, 'staff_profiles', 'officer_profiles'));
  END LOOP;
END $$;

ALTER INDEX IF EXISTS public.staff_profiles_pkey RENAME TO officer_profiles_pkey;

-- Decision D12 — per-flag permissions removed.
ALTER TABLE public.officer_profiles DROP COLUMN IF EXISTS permissions;

COMMENT ON TABLE public.officer_profiles IS
  'Cooperative Officer accounts. An Officer has every Admin module EXCEPT '
  'the Members tab (Issue 6). employee_id = EMP-### (generate_employee_id).';

-- ════════════════════════════════════════════════════════════
-- 3. Migrate the existing officer identity  (stf-0001 -> off-0001)
-- ════════════════════════════════════════════════════════════

-- auth.users.email + auth.identities (synthetic @sagana.local address)
UPDATE auth.users
SET email = replace(email, 'stf-', 'off-')
WHERE email LIKE 'stf-%@sagana.local';

UPDATE auth.identities
SET identity_data = jsonb_set(
      identity_data, '{email}',
      to_jsonb(replace(identity_data->>'email', 'stf-', 'off-')))
WHERE identity_data->>'email' LIKE 'stf-%@sagana.local';

-- user_information.username
UPDATE public.user_information
SET username = replace(username, 'stf-', 'off-')
WHERE username LIKE 'stf-%';

-- ════════════════════════════════════════════════════════════
-- 4. officer_registry  (mirror of sp3_member_registry — Decision D22)
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.officer_registry (
  id                 UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  full_name          TEXT        NOT NULL,
  normalized_name    TEXT        GENERATED ALWAYS AS (lower(trim(full_name))) STORED,
  email              TEXT,
  phone_number       TEXT,
  is_registered      BOOLEAN     NOT NULL DEFAULT FALSE,
  registered_user_id UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  notes              TEXT,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_officer_registry_normalized
  ON public.officer_registry (normalized_name);

DROP TRIGGER IF EXISTS trg_officer_registry_updated_at ON public.officer_registry;
CREATE TRIGGER trg_officer_registry_updated_at
  BEFORE UPDATE ON public.officer_registry
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.officer_registry ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "officer_registry: admin manages all" ON public.officer_registry;
CREATE POLICY "officer_registry: admin manages all"
  ON public.officer_registry FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

DROP POLICY IF EXISTS "officer_registry: auth reads" ON public.officer_registry;
CREATE POLICY "officer_registry: auth reads"
  ON public.officer_registry FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- Seed the existing officer(s) so every Officer has a registry row.
INSERT INTO public.officer_registry (full_name, phone_number, is_registered, registered_user_id)
SELECT COALESCE(ui.full_name, 'SP3 Officer'), ui.phone_number, TRUE, op.user_id
FROM public.officer_profiles op
JOIN public.user_information ui ON ui.user_id = op.user_id
LEFT JOIN public.officer_registry orr ON orr.registered_user_id = op.user_id
WHERE orr.id IS NULL;

-- ════════════════════════════════════════════════════════════
-- 5. generate_employee_id — the single EMP-### generator (Decision D23)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.generate_employee_id()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_seq INT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('employee_id_seq'));

  SELECT COALESCE(MAX(
    NULLIF(regexp_replace(employee_id, '^EMP-', ''), '')::INT
  ), 0) + 1
  INTO v_seq
  FROM officer_profiles
  WHERE employee_id LIKE 'EMP-%';

  RETURN 'EMP-' || LPAD(v_seq::TEXT, 3, '0');
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_employee_id() TO authenticated;
REVOKE EXECUTE ON FUNCTION public.generate_employee_id() FROM anon;

-- ════════════════════════════════════════════════════════════
-- 6. check_officer_registry — name lookup for the create form
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.check_officer_registry(p_full_name text)
RETURNS TABLE(
  registry_id   uuid,
  is_available  boolean,
  phone_number  text,
  email         text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT r.id, NOT r.is_registered, r.phone_number, r.email
  FROM officer_registry r
  WHERE r.normalized_name = lower(trim(p_full_name))
  LIMIT 1;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_officer_registry(text) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 7. create_officer_account — replaces create_staff_account
-- ════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.create_staff_account(text,text,text,text,text,text,text,jsonb);

CREATE OR REPLACE FUNCTION public.create_officer_account(
  p_username      text,
  p_password      text,
  p_full_name     text,
  p_email         text DEFAULT NULL,
  p_phone_number  text DEFAULT NULL,
  p_position      text DEFAULT NULL,
  p_registry_id   uuid DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_user_id     UUID;
  v_email       TEXT;
  v_employee_id TEXT;
  v_reg         RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can create Officer accounts';
  END IF;

  -- Every Officer must come from officer_registry (Decision D22).
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

  INSERT INTO user_information (user_id, full_name, phone_number, purok, username, contact_email)
  VALUES (
    v_user_id,
    trim(p_full_name),
    NULLIF(trim(COALESCE(p_phone_number, v_reg.phone_number, '')), ''),
    NULL,
    lower(trim(p_username)),
    NULLIF(lower(trim(COALESCE(p_email, v_reg.email, ''))), '')
  );

  v_employee_id := generate_employee_id();
  INSERT INTO officer_profiles (user_id, employee_id, position)
  VALUES (v_user_id, v_employee_id, p_position);

  UPDATE officer_registry
  SET is_registered = TRUE, registered_user_id = v_user_id
  WHERE id = p_registry_id;

  RETURN v_user_id;
EXCEPTION
  WHEN unique_violation THEN
    RAISE EXCEPTION 'Username or employee ID already exists';
  WHEN OTHERS THEN RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.create_officer_account(text,text,text,text,text,text,uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_officer_account(text,text,text,text,text,text,uuid) FROM anon;

-- ════════════════════════════════════════════════════════════
-- 8. Rename Staff read-only RLS policies -> Officer
-- ════════════════════════════════════════════════════════════
-- These are the SELECT-only grants from
-- supabase_schema_staff_dashboard_read_access.sql +
-- supabase_schema_loan_staff_child_table_access.sql. The USING clause is
-- re-pointed from staff_profiles to officer_profiles (same rows, renamed
-- table) and the policy name updated. Write access is Phase D-2.

DO $$
DECLARE
  t text;
  tables text[] := ARRAY[
    'cooperative_inventory','harvest_records','marketplace_listings',
    'farmer_loans','farmer_loan_items','farmer_loan_payments',
    'crop_requests','broadcast_logs','user_roles','user_information',
    'farmer_profiles','orders'
  ];
BEGIN
  FOREACH t IN ARRAY tables LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': staff reads all', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t || ': officer reads all', t);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR SELECT USING (EXISTS (SELECT 1 FROM public.officer_profiles WHERE user_id = auth.uid()))',
      t || ': officer reads all', t);
  END LOOP;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) Role migrated:
--    SELECT role, count(*) FROM user_roles GROUP BY role;  -- no 'staff'
--    SELECT pg_get_constraintdef(oid) FROM pg_constraint
--    WHERE conname='user_roles_role_check';   -- IN (admin,farmer,buyer,officer)
--
-- 2) Table + column:
--    SELECT to_regclass('public.officer_profiles');            -- not null
--    SELECT to_regclass('public.staff_profiles');              -- NULL
--    SELECT 1 FROM information_schema.columns
--    WHERE table_name='officer_profiles' AND column_name='permissions';  -- 0 rows
--
-- 3) Existing officer identity:
--    SELECT ui.username, u.email, op.employee_id
--    FROM officer_profiles op
--    JOIN user_information ui ON ui.user_id = op.user_id
--    JOIN auth.users u ON u.id = op.user_id;
--    -- username off-0001, email off-0001@sagana.local, employee_id EMP-001
--    -- Log in with  off-0001 / <existing password>
--
-- 4) Registry + generators:
--    SELECT full_name, is_registered, registered_user_id FROM officer_registry;  -- 1+ seeded rows
--    SELECT generate_employee_id();                       -- 'EMP-00N'
--    SELECT proname FROM pg_proc WHERE proname IN
--      ('create_officer_account','check_officer_registry','generate_employee_id');  -- 3 rows
--    SELECT proname FROM pg_proc WHERE proname='create_staff_account';             -- 0 rows
--
-- 5) In app: existing officer logs in with off-0001, lands on the Admin
--    dashboard WITHOUT a Members tab. Admin > Members > (＋) > Add Officer
--    Account: typing a name that matches officer_registry auto-fills phone
--    / email and shows EMP-### (read-only); save creates an 'officer' role
--    account and flips that registry row to is_registered = true.
-- ============================================================
