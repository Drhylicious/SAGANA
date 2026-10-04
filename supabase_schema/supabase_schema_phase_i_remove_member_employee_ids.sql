-- ============================================================
-- SAGANA — Phase I: Remove Member ID / Employee ID entirely
--
-- Product decision, not a bug fix: SP3 Agriculture Cooperative currently
-- runs on a manual logbook with no digital system and no confirmed
-- official member/employee numbering scheme. The SP3-<year>-<seq> /
-- EMP-### formats introduced in Phase B / Phase D were invented for this
-- app, not verified to be how the cooperative actually identifies its
-- people — presenting a fabricated-looking official ID risked a fair
-- challenge ("is this a real identifier the cooperative uses?").
--
-- Share Value and Initial/Capital Contribution are NOT affected — those
-- are confirmed real, existing cooperative practices (₱100/month,
-- ₱2,000/year capital share, per the case-study interview material) and
-- stay exactly as they are. member_capital_shares and
-- capital_contribution_events are untouched by this migration.
--
-- IMPORTANT — apply this only together with the matching Dart changes
-- (removal of every farmer_profiles.member_id / officer_profiles.
-- employee_id reference across the app). Applying this migration before
-- the Dart side is updated will break any screen still selecting the
-- now-dropped columns.
--
-- Order: redefine every function that touches these columns first (so
-- nothing is ever left referencing a column that no longer exists),
-- then drop the now-unused generator functions, then drop the columns.
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. approve_member — return type changes (text -> void), so this one
--    needs DROP + CREATE, not CREATE OR REPLACE (Postgres rejects an
--    OR REPLACE that changes the return type — 42P13).
-- ════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.approve_member(uuid);

CREATE FUNCTION public.approve_member(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_status    TEXT;
  v_full_name TEXT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending application can be approved (current: %)', v_status;
  END IF;

  SELECT full_name INTO v_full_name FROM user_information WHERE user_id = p_user_id;

  UPDATE user_roles
  SET status = 'active',
      pending_acknowledgement = true,
      rejection_reason = NULL,
      suspension_reason = NULL
  WHERE user_id = p_user_id;

  UPDATE farmer_profiles
  SET is_verified = true
  WHERE user_id = p_user_id;

  -- Every approved member gets a capital-shares row immediately (parity
  -- with create_farmer_account) — starts at 0, loan-ineligible until a
  -- payment is recorded, but the row always exists.
  INSERT INTO member_capital_shares (farmer_id, share_value_per_unit, total_contribution)
  VALUES (p_user_id, 2000.00, 0)
  ON CONFLICT (farmer_id) DO NOTHING;

  IF EXISTS (SELECT 1 FROM sp3_member_registry WHERE registered_user_id = p_user_id) THEN
    UPDATE sp3_member_registry SET is_registered = true WHERE registered_user_id = p_user_id;
  ELSE
    INSERT INTO sp3_member_registry (full_name, is_registered, registered_user_id)
    VALUES (COALESCE(v_full_name, 'SP3 Member'), true, p_user_id)
    ON CONFLICT (registered_user_id) DO UPDATE SET is_registered = true;
  END IF;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, 'pending', 'active', 'Application approved', auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
  VALUES (p_user_id, 'member_approved', 'Membership Approved',
          'Your SP3 cooperative membership has been approved. Open SAGANA and tap '
          || 'Continue to activate your farmer access.',
          false, '/farmer/profile');
END;
$$;

GRANT EXECUTE ON FUNCTION public.approve_member(uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 2. create_farmer_account — same signature/return type, CREATE OR
--    REPLACE is fine. Member ID generation/assignment removed; every
--    other behavior (capital shares, initial contribution, crops,
--    registry link) unchanged.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_farmer_account(
  p_username             text,
  p_password             text,
  p_full_name            text,
  p_phone_number         text        DEFAULT NULL,
  p_purok                text        DEFAULT NULL,
  p_date_of_birth        date        DEFAULT NULL,
  p_gender               text        DEFAULT NULL,
  p_share_value_per_unit numeric     DEFAULT 2000,
  p_initial_contribution numeric     DEFAULT 0,
  p_initial_crops        text[]      DEFAULT ARRAY[]::text[],
  p_registry_id          uuid        DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_user_id   UUID;
  v_email     TEXT;
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
  VALUES (
    v_user_id,
    trim(p_full_name),
    NULLIF(trim(COALESCE(p_phone_number, '')), ''),
    p_purok,
    lower(trim(p_username))
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
  text,text,text,text,text,date,text,numeric,numeric,text[],uuid
) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_farmer_account(
  text,text,text,text,text,date,text,numeric,numeric,text[],uuid
) FROM anon;

-- ════════════════════════════════════════════════════════════
-- 3. finalize_official_membership — return type changes (text -> void).
--    Keeps the capital-shares creation and registry link exactly as
--    Phase H built them; only the Member ID generation/assignment is
--    removed.
-- ════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.finalize_official_membership(uuid);

CREATE FUNCTION public.finalize_official_membership(p_registry_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller      UUID := auth.uid();
  v_caller_name TEXT;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT full_name INTO v_caller_name FROM user_information WHERE user_id = v_caller;
  IF v_caller_name IS NULL THEN
    RAISE EXCEPTION 'Account has no name on record';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM farmer_profiles WHERE user_id = v_caller) THEN
    RAISE EXCEPTION 'Farmer profile not found for caller';
  END IF;

  INSERT INTO member_capital_shares (farmer_id, share_value_per_unit, total_contribution)
  VALUES (v_caller, 2000.00, 0)
  ON CONFLICT (farmer_id) DO NOTHING;

  UPDATE sp3_member_registry
  SET is_registered = true,
      registered_user_id = v_caller
  WHERE id = p_registry_id
    AND (registered_user_id IS NULL OR registered_user_id = v_caller)
    AND normalized_name = lower(trim(v_caller_name));
END;
$$;

GRANT EXECUTE ON FUNCTION public.finalize_official_membership(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.finalize_official_membership(uuid) FROM anon;

-- ════════════════════════════════════════════════════════════
-- 4. create_officer_account — same signature/return type, CREATE OR
--    REPLACE is fine. Employee ID generation/assignment removed.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.create_officer_account(
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

GRANT EXECUTE ON FUNCTION public.create_officer_account(text,text,text,date,text,text,text,text,uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_officer_account(text,text,text,date,text,text,text,text,uuid) FROM anon;

-- ════════════════════════════════════════════════════════════
-- 5. Drop the now-unused generator/management functions
-- ════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.admin_assign_member_id(uuid);
DROP FUNCTION IF EXISTS public.generate_member_id(int);
DROP FUNCTION IF EXISTS public.generate_employee_id();

-- ════════════════════════════════════════════════════════════
-- 6. Drop the columns themselves — safe now that no function body
--    references them.
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.farmer_profiles DROP COLUMN IF EXISTS member_id;
ALTER TABLE public.officer_profiles DROP COLUMN IF EXISTS employee_id;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION (run manually)
-- ============================================================
-- 1) Columns are gone:
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name IN ('farmer_profiles','officer_profiles')
--      AND column_name IN ('member_id','employee_id');
--    -- expect: zero rows
--
-- 2) Generator/management functions are gone:
--    SELECT proname FROM pg_proc
--    WHERE proname IN ('generate_member_id','generate_employee_id','admin_assign_member_id');
--    -- expect: zero rows
--
-- 3) Share Value / Capital Contribution completely untouched — spot
--    check a known farmer (swap in a real user_id):
--    SELECT farmer_id, share_value_per_unit, total_contribution, total_shares
--    FROM member_capital_shares WHERE farmer_id = '<a known farmer id>';
--    -- expect: identical to before this migration
--
-- 4) create_farmer_account / approve_member / create_officer_account /
--    finalize_official_membership all still run end-to-end (exercise
--    each from the app after deploying the matching Dart changes):
--    Add Member, Approve a pending applicant, Create Officer Account,
--    and a fresh official-member self-registration should all succeed
--    with no error and no reference to a Member ID/Employee ID anywhere.
-- ============================================================
