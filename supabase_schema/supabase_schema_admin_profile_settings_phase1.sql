-- ============================================================
-- SAGANA — Admin Profile & Settings, Phase 1: Database & Backend
-- Foundation
--
-- Part of the Admin-Profile & Settings implementation plan. Lands every
-- schema/RPC change up front so later UI phases (Officer Account
-- Creation DOB/Gender fields, Edit Profile Gender/DOB fields, Activity
-- Summary expansion) have something real to build against.
--
-- NOTE: an earlier version of this file also added an admin_registry
-- table and a create_admin_account()/check_admin_registry() RPC pair,
-- built on a misreading of the requirements. Admin account creation is
-- explicitly NOT a SAGANA in-app feature — Admin accounts are created
-- directly via Supabase Authentication, outside the app. Those objects
-- were reverted; see supabase_schema_admin_account_creation_revert.sql
-- for the corresponding rollback against a database that already ran
-- the original version of this file.
--
-- Covers:
--   1. date_of_birth/gender on admin_profiles + officer_profiles
--      (mirrors farmer_profiles' existing pattern — Phase B — and
--      buyer_profiles' existing pattern). admin_profiles gets these
--      for the Admin's own Edit Profile self-edit; officer_profiles
--      gets these for both Officer account creation and the Officer's
--      own Edit Profile self-edit (same shared screen Admin uses).
--   2. create_officer_account(...) recreated with p_date_of_birth /
--      p_gender params added (Officer creation currently collects
--      neither) — same 18+ guard used by create_farmer_account.
--   3. Confirmed bug fix: marketplace_listings never populates
--      reviewed_by despite the column existing for exactly that
--      purpose (crop_requests already does this correctly — this
--      brings listings in line with that working pattern). Adds the
--      missing reviewed_at column to match.
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. date_of_birth / gender on admin_profiles + officer_profiles
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.admin_profiles
  ADD COLUMN IF NOT EXISTS date_of_birth DATE,
  ADD COLUMN IF NOT EXISTS gender        TEXT;

ALTER TABLE public.admin_profiles
  DROP CONSTRAINT IF EXISTS admin_profiles_gender_check;
ALTER TABLE public.admin_profiles
  ADD CONSTRAINT admin_profiles_gender_check
  CHECK (gender IS NULL OR gender IN ('male', 'female', 'prefer_not_to_say'));

ALTER TABLE public.officer_profiles
  ADD COLUMN IF NOT EXISTS date_of_birth DATE,
  ADD COLUMN IF NOT EXISTS gender        TEXT;

ALTER TABLE public.officer_profiles
  DROP CONSTRAINT IF EXISTS officer_profiles_gender_check;
ALTER TABLE public.officer_profiles
  ADD CONSTRAINT officer_profiles_gender_check
  CHECK (gender IS NULL OR gender IN ('male', 'female', 'prefer_not_to_say'));

-- ════════════════════════════════════════════════════════════
-- 2. create_officer_account — recreated with p_date_of_birth/p_gender
--    added (Decision 3.2 covers both Admin and Officer creation).
--    DROP first: adding parameters changes the signature, and Postgres
--    rejects a signature-changing CREATE OR REPLACE (same constraint
--    already documented in the Sitio->Purok migration).
-- ════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.create_officer_account(text,text,text,text,text,text,uuid);

CREATE FUNCTION public.create_officer_account(
  p_username      text,
  p_password      text,
  p_full_name     text,
  p_date_of_birth date DEFAULT NULL,
  p_gender        text DEFAULT NULL,
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
  INSERT INTO officer_profiles (user_id, employee_id, position, date_of_birth, gender)
  VALUES (v_user_id, v_employee_id, p_position, p_date_of_birth, p_gender);

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
    RAISE EXCEPTION 'Username or employee ID already exists';
  WHEN OTHERS THEN RAISE;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.create_officer_account(text,text,text,date,text,text,text,text,uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_officer_account(text,text,text,date,text,text,text,text,uuid) FROM anon;

-- ════════════════════════════════════════════════════════════
-- 3. Confirmed bug fix: marketplace_listings.reviewed_by never
--    populated. crop_requests already does this correctly
--    (SET reviewed_by = auth.uid(), reviewed_at = NOW()) — bring
--    listings in line with that working pattern. reviewed_at doesn't
--    exist yet on this table (crop_requests has it; listings doesn't).
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.marketplace_listings
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.approve_listing(p_listing_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can approve listings';
  END IF;

  SELECT status INTO v_status FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_status != 'pending_review' THEN
    RAISE EXCEPTION 'Only pending_review listings can be approved (current: %)', v_status;
  END IF;

  UPDATE marketplace_listings
  SET status = 'approved', admin_notes = NULL, reviewed_by = auth.uid(), reviewed_at = NOW(), updated_at = NOW()
  WHERE id = p_listing_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reject_listing(
  p_listing_id UUID,
  p_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_listing RECORD;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can reject listings';
  END IF;

  SELECT * INTO v_listing FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_listing IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;

  IF v_listing.inventory_batch_id IS NOT NULL THEN
    PERFORM _release_batch_reservation(v_listing.inventory_batch_id, v_listing.volume_kg);
  END IF;

  UPDATE marketplace_listings
  SET status = 'rejected', admin_notes = p_reason, reviewed_by = auth.uid(), reviewed_at = NOW(), updated_at = NOW()
  WHERE id = p_listing_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.request_listing_changes(p_listing_id UUID, p_notes TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Unauthorized: only admins can request changes on listings';
  END IF;

  SELECT status INTO v_status FROM marketplace_listings WHERE id = p_listing_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Listing not found';
  END IF;
  IF v_status != 'pending_review' THEN
    RAISE EXCEPTION 'Only pending_review listings can have changes requested (current: %)', v_status;
  END IF;

  UPDATE marketplace_listings
  SET status = 'changes_required', admin_notes = p_notes, reviewed_by = auth.uid(), reviewed_at = NOW(), updated_at = NOW()
  WHERE id = p_listing_id;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) New columns exist:
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name IN ('admin_profiles','officer_profiles') AND column_name IN ('date_of_birth','gender');  -- 4 rows
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name = 'marketplace_listings' AND column_name = 'reviewed_at';  -- 1 row
--
-- 2) Approve a pending listing in-app, then:
--    SELECT id, status, reviewed_by, reviewed_at FROM marketplace_listings
--    WHERE status = 'approved' ORDER BY reviewed_at DESC LIMIT 1;  -- reviewed_by/reviewed_at populated
--
-- 3) Officer creation still works (now with optional DOB/gender):
--    SELECT proname FROM pg_proc WHERE proname = 'create_officer_account';  -- 1 row
-- ============================================================
