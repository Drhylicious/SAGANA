-- ============================================================
-- SAGANA — Registration refactor, step 2 of 3: accounts and approval
--
-- Requires step 1 (supabase_schema_registration_01_foundation.sql).
--
-- What this does:
--   1. register_account()   NEW. The only way a Farmer or Buyer finishes
--      self-registration. Validates everything on the server, writes the
--      role / status / profile / fixed Farmer address / identifier in one
--      transaction. Farmers start 'pending'; Buyers start 'active'.
--   2. create_farmer_account()   Manager-created Farmer: registry parameter
--      and the full-name-uniqueness rule removed; membership year added.
--   3. create_officer_account()  Manager-created Officer: Officer Registry
--      requirement removed; membership year added.
--   4. approve_member()   no longer writes a row into sp3_member_registry.
--      reject_member()    notification wording is now "disapproved".
--      (The stored status value stays 'rejected' — only the wording changes.)
--   5. Registry lock-down: the name-lookup functions are no longer callable
--      by clients. The tables and every historical row are untouched.
--   6. Drops the user_roles self-insert policy, so a signed-in user can no
--      longer write their own role or status directly.
--   7. Account-created notification only for Manager-created accounts.
--   8. Phone availability check compares normalized numbers.
--
-- DEPLOY ORDER MATTERS. The app build that goes with this file calls
-- register_account(); the previous app build inserted into user_roles
-- directly, which section 6 forbids. Apply this file and release the matching
-- app build together.
--
-- Not applied automatically. Run the PRE-FLIGHT block first, then this file in
-- the Supabase SQL editor, then the verification block at the end.
-- ============================================================

-- ─── PRE-FLIGHT (read-only — run these first, each by itself) ─────────────
-- A. Step 1 is applied (expect 4 rows):
--    SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--      AND proname IN ('issue_member_identifier', 'check_username_available',
--                      'normalize_ph_mobile', 'is_valid_email');
--
-- B. The functions this file replaces: compare against the repo before
--    running (a hotfix applied only in the live database would be overwritten):
--    SELECT proname, pg_get_function_identity_arguments(oid) AS args
--    FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--      AND proname IN ('create_farmer_account', 'create_officer_account',
--                      'approve_member', 'reject_member', 'fn_notify_account_created');
--    -- full text of one, e.g.:
--    --   SELECT pg_get_functiondef('public.approve_member(uuid)'::regprocedure);
--
-- C. Current policies on user_roles (section 6 drops the self-insert one):
--    SELECT policyname, cmd, qual, with_check FROM pg_policies
--    WHERE schemaname = 'public' AND tablename = 'user_roles';
--
-- D. Farmer status counts (informational):
--    SELECT status, count(*) FROM public.user_roles
--    WHERE role = 'farmer' GROUP BY status ORDER BY status;
--
-- E. Realtime publication contains user_roles (informational — section 9
--    adds it if missing):
--    SELECT tablename FROM pg_publication_tables
--    WHERE pubname = 'supabase_realtime' AND tablename = 'user_roles';
-- ────────────────────────────────────────────────────────────────────────

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. register_account — Farmer and Buyer self-registration
-- ════════════════════════════════════════════════════════════
-- Called right after auth.signUp (the caller is the new, signed-in user).
-- The client supplies only what the person typed. Role/status are decided
-- here, and the Farmer address region/province/city/barangay/postal code are
-- fixed here — whatever the client sends for them is not read at all.

CREATE OR REPLACE FUNCTION public.register_account(
  p_role          text,
  p_full_name     text,
  p_username      text,
  p_phone_number  text DEFAULT NULL,
  p_contact_email text DEFAULT NULL,
  p_date_of_birth date DEFAULT NULL,
  p_gender        text DEFAULT NULL,
  p_street        text DEFAULT NULL,
  p_building      text DEFAULT NULL,
  p_house_no      text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid        uuid := auth.uid();
  v_name       text := regexp_replace(trim(coalesce(p_full_name, '')), '\s+', ' ', 'g');
  v_username   text := lower(trim(coalesce(p_username, '')));
  v_auth_email text;
  v_phone      text;
  v_email      text;
  v_street     text := NULLIF(trim(coalesce(p_street, '')), '');
  v_building   text := NULLIF(trim(coalesce(p_building, '')), '');
  v_house_no   text := NULLIF(trim(coalesce(p_house_no, '')), '');
  v_status     text;
  v_code       text;
  v_line       text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_role IS NULL OR p_role NOT IN ('farmer', 'buyer') THEN
    RAISE EXCEPTION 'Invalid account type';
  END IF;
  IF EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = v_uid) THEN
    RAISE EXCEPTION 'This account is already set up';
  END IF;

  -- Full name: a normal text field. Required, not unique.
  IF length(v_name) < 2 OR length(v_name) > 120 THEN
    RAISE EXCEPTION 'Please enter your full name.';
  END IF;

  -- Username: format, then uniqueness, then it must be the username this
  -- sign-in identity was created with.
  IF v_username !~ '^[a-z0-9._-]{3,30}$' THEN
    RAISE EXCEPTION 'Username must be 3 to 30 characters: letters, numbers, dots, underscores or hyphens.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.user_information WHERE lower(trim(username)) = v_username) THEN
    RAISE EXCEPTION 'This username is already taken.';
  END IF;
  SELECT lower(email) INTO v_auth_email FROM auth.users WHERE id = v_uid;
  IF v_auth_email IS DISTINCT FROM v_username || '@sagana.local' THEN
    RAISE EXCEPTION 'The username does not match the account that was just created.';
  END IF;

  -- Phone (optional): Philippine mobile, stored normalized (09XXXXXXXXX).
  IF NULLIF(trim(coalesce(p_phone_number, '')), '') IS NOT NULL THEN
    v_phone := public.normalize_ph_mobile(p_phone_number);
    IF v_phone IS NULL THEN
      RAISE EXCEPTION 'Please enter a valid Philippine mobile number.';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.user_information ui
      WHERE public.normalize_ph_mobile(ui.phone_number) = v_phone
    ) THEN
      RAISE EXCEPTION 'This phone number is already used by another account.';
    END IF;
  END IF;

  -- Email (optional): format only. It is stored as a contact address and is
  -- NOT verified — sign-in uses the username, not this address.
  v_email := NULLIF(lower(trim(coalesce(p_contact_email, ''))), '');
  IF v_email IS NOT NULL THEN
    IF NOT public.is_valid_email(v_email) THEN
      RAISE EXCEPTION 'Please enter a valid email address.';
    END IF;
    IF EXISTS (
      SELECT 1 FROM public.user_information ui
      WHERE lower(trim(ui.contact_email)) = v_email
    ) THEN
      RAISE EXCEPTION 'This email address is already used by another account.';
    END IF;
  END IF;

  IF p_role = 'farmer' THEN
    IF p_date_of_birth IS NULL THEN
      RAISE EXCEPTION 'Date of birth is required.';
    END IF;
    IF p_date_of_birth > (CURRENT_DATE - INTERVAL '18 years') THEN
      RAISE EXCEPTION 'You must be at least 18 years old to register as a cooperative member.';
    END IF;
    IF p_gender IS NULL OR p_gender NOT IN ('male', 'female', 'prefer_not_to_say') THEN
      RAISE EXCEPTION 'Please select a gender.';
    END IF;
    IF v_street IS NULL THEN
      RAISE EXCEPTION 'Street is required.';
    END IF;
    IF v_house_no IS NULL THEN
      RAISE EXCEPTION 'House number is required.';
    END IF;
  END IF;

  -- Role and status are decided here, never by the client.
  v_status := CASE p_role WHEN 'farmer' THEN 'pending' ELSE 'active' END;

  INSERT INTO public.user_roles (user_id, role, status, application_attempts)
  VALUES (v_uid, p_role, v_status, CASE WHEN p_role = 'farmer' THEN 1 ELSE 0 END);

  INSERT INTO public.user_information (user_id, full_name, phone_number, contact_email, username)
  VALUES (v_uid, v_name, v_phone, v_email, v_username);

  IF p_role = 'farmer' THEN
    INSERT INTO public.farmer_profiles (user_id, is_verified, date_of_birth, gender)
    VALUES (v_uid, FALSE, p_date_of_birth, p_gender);

    -- Fixed Farmer address: MIMAROPA Region / Marinduque / Torrijos /
    -- Payanas / 4903. Only street, building and house number come from the
    -- caller.
    v_line := concat_ws(', ', v_house_no, v_building, v_street,
                        'Payanas', 'Torrijos', 'Marinduque', 'MIMAROPA Region', '4903');
    INSERT INTO public.buyer_addresses (
      user_id, label, recipient_name, contact_number, address_line, is_default,
      region_code, region_name, province_code, province_name,
      city_municipality_code, city_municipality_name,
      barangay_code, barangay_name, postal_code, street, building, house_no
    ) VALUES (
      v_uid, 'Home', v_name, v_phone, v_line, TRUE,
      '1700000000', 'MIMAROPA Region', '1704000000', 'Marinduque',
      '1704006000', 'Torrijos',
      '1704006019', 'Payanas', '4903', v_street, v_building, v_house_no
    );

    INSERT INTO public.member_status_events (member_id, from_status, to_status, reason, actor_id)
    VALUES (v_uid, NULL, 'pending', 'Registered - awaiting Manager review', v_uid);

    INSERT INTO public.notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    SELECT ur.user_id, 'member_pending', 'New Membership Application',
           v_name || ' registered and needs review.', FALSE, NOW(), '/admin/farmers'
    FROM public.user_roles ur WHERE ur.role = 'admin';
  ELSE
    INSERT INTO public.buyer_profiles (user_id) VALUES (v_uid);
  END IF;

  v_code := public.issue_member_identifier(v_uid, p_role, NULL);

  RETURN jsonb_build_object('user_id', v_uid, 'member_code', v_code, 'status', v_status);
EXCEPTION
  WHEN unique_violation THEN
    IF SQLERRM ILIKE '%username%' THEN
      RAISE EXCEPTION 'This username is already taken.';
    END IF;
    RAISE;
END;
$$;

REVOKE ALL ON FUNCTION public.register_account(text, text, text, text, text, date, text, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_account(text, text, text, text, text, date, text, text, text, text)
  TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 2. create_farmer_account — Manager-created Farmer
--    Signature changes: p_registry_id removed, p_membership_year added.
--    The old overloads are dropped first so exactly one remains.
-- ════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.create_farmer_account(
  text, text, text, text, text, date, text, numeric, numeric, text[], uuid
);
DROP FUNCTION IF EXISTS public.create_farmer_account(
  text, text, text, text, date, text, numeric, numeric, text[], uuid, text
);

CREATE FUNCTION public.create_farmer_account(
  p_username             text,
  p_password             text,
  p_full_name            text,
  p_phone_number         text      DEFAULT NULL,
  p_date_of_birth        date      DEFAULT NULL,
  p_gender               text      DEFAULT NULL,
  p_share_value_per_unit numeric   DEFAULT 2000,
  p_initial_contribution numeric   DEFAULT 0,
  p_initial_crops        text[]    DEFAULT ARRAY[]::text[],
  p_contact_email        text      DEFAULT NULL,
  p_membership_year      integer   DEFAULT NULL
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
  v_contact  TEXT := NULLIF(lower(trim(COALESCE(p_contact_email, ''))), '');
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
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
    RAISE EXCEPTION 'Member must be at least 18 years old';
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
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', v_email,
      'email_verified', false,
      'phone_verified', false
    ),
    'email', NOW(), NOW(), NOW()
  );

  -- Manager-created: active at once, forced password change at first login.
  INSERT INTO user_roles (user_id, role, status, must_change_password)
  VALUES (v_user_id, 'farmer', 'active', true);

  INSERT INTO user_information (user_id, full_name, phone_number, username, contact_email)
  VALUES (v_user_id, v_name, v_phone, v_username, v_contact);

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

  -- SP3-YYYY-NNN. Defaults to the current year; a Manager can enter an
  -- earlier year for a historical member.
  PERFORM public.issue_member_identifier(v_user_id, 'farmer', p_membership_year);

  RETURN v_user_id;
EXCEPTION
  WHEN unique_violation THEN
    IF SQLERRM ILIKE '%username%' THEN
      RAISE EXCEPTION 'This username is already taken.';
    END IF;
    RAISE;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_farmer_account(
  text, text, text, text, date, text, numeric, numeric, text[], text, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_farmer_account(
  text, text, text, text, date, text, numeric, numeric, text[], text, integer
) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 3. create_officer_account — Manager-created Officer
--    Signature changes: p_registry_id removed, p_membership_year added.
--    Officers still receive no admin_profiles row (access comes from the
--    role, as in supabase_schema_role_based_staff_access.sql).
-- ════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.create_officer_account(
  text, text, text, date, text, text, text, text, uuid
);

CREATE FUNCTION public.create_officer_account(
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

  INSERT INTO user_roles (user_id, role, status)
  VALUES (v_user_id, 'officer', 'active');

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

-- ════════════════════════════════════════════════════════════
-- 4. approve_member / reject_member
--    Same behavior as before, minus the sp3_member_registry write in
--    approve_member and with "disapproved" wording in reject_member.
--    The stored status value remains 'rejected' (the app labels it
--    "Disapproved"), so no constraint, history row or function that reads
--    the status value changes.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.approve_member(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_status TEXT;
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

CREATE OR REPLACE FUNCTION public.reject_member(p_user_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A reason for disapproval is required';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending application can be disapproved (current: %)', v_status;
  END IF;

  UPDATE user_roles
  SET status = 'rejected',
      rejection_reason = trim(p_reason),
      pending_acknowledgement = false
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, 'pending', 'rejected', trim(p_reason), auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
  VALUES (p_user_id, 'member_rejected', 'Application Disapproved',
          'Your SP3 membership application was disapproved. Reason: ' || trim(p_reason)
          || ' You may review your details and resubmit.',
          false, '/farmer/profile');
END;
$$;

GRANT EXECUTE ON FUNCTION public.reject_member(uuid, text) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 5. Registry lock-down
--    Registry names are no longer used to allow, block or pre-fill any
--    account. The name-lookup functions stop being callable by clients (they
--    returned registry phone numbers and emails to anyone, even signed out).
--    sp3_member_registry and officer_registry, and every row in them, are
--    left exactly as they are.
-- ════════════════════════════════════════════════════════════

DO $$
BEGIN
  BEGIN REVOKE ALL ON FUNCTION public.check_sp3_registry(text) FROM PUBLIC, anon, authenticated;
  EXCEPTION WHEN undefined_function THEN NULL; END;
  BEGIN REVOKE ALL ON FUNCTION public.check_officer_registry(text) FROM PUBLIC, anon, authenticated;
  EXCEPTION WHEN undefined_function THEN NULL; END;
  BEGIN REVOKE ALL ON FUNCTION public.check_full_name_available(text, text) FROM PUBLIC, anon, authenticated;
  EXCEPTION WHEN undefined_function THEN NULL; END;
  BEGIN REVOKE ALL ON FUNCTION public.finalize_official_membership(uuid) FROM PUBLIC, anon, authenticated;
  EXCEPTION WHEN undefined_function THEN NULL; END;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 6. No more self-inserted roles
--    "user_roles: insert on registration" let any signed-in user insert
--    their own user_roles row with any role and status. register_account()
--    now does that insert, so the policy is removed.
-- ════════════════════════════════════════════════════════════

DROP POLICY IF EXISTS "user_roles: insert on registration" ON public.user_roles;

-- ════════════════════════════════════════════════════════════
-- 7. "Account Created" notice — Manager-created accounts only
--    batch9_01_decision_notices.sql already limits this notice to accounts a
--    Manager creates for someone else (a self-registration runs as the new
--    user, so auth.uid() = NEW.user_id and the notice is skipped). This
--    keeps that exact rule and only changes "admin" to "Manager" in the text,
--    so register_account() does not send a farmer a notice meant for
--    Manager-created accounts.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.fn_notify_account_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.role IN ('farmer', 'officer')
     AND NEW.user_id IS DISTINCT FROM auth.uid()
     AND public.is_platform_admin(auth.uid()) THEN
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    VALUES (
      NEW.user_id,
      'system',
      'Account Created',
      'Your SAGANA account was created by the cooperative Manager. Sign in with your temporary password and change it to continue.',
      FALSE,
      NOW(),
      NULL
    );
  END IF;
  RETURN NEW;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 8. Phone availability compares normalized numbers
--    (+639171234567 and 09171234567 are the same number)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.check_phone_available(p_phone text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_raw  text := trim(coalesce(p_phone, ''));
  v_norm text := public.normalize_ph_mobile(p_phone);
BEGIN
  IF v_raw = '' THEN
    RETURN true;
  END IF;

  RETURN NOT EXISTS (
    SELECT 1
    FROM public.user_information
    WHERE trim(phone_number) = v_raw
       OR (v_norm IS NOT NULL AND public.normalize_ph_mobile(phone_number) = v_norm)
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.check_phone_available(text) TO anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 9. Realtime: the Manager's Members list listens for new registrations
--    (a no-op when user_roles is already published)
-- ════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'user_roles'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_roles;
  END IF;
EXCEPTION WHEN undefined_object THEN
  NULL; -- no supabase_realtime publication in this database
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── OPTIONAL — NOT RUN BY THIS FILE ─────────────────────────────────────
-- Farmers who registered under the old flow and never tapped "Submit
-- Application" are still 'draft' and stay hidden from the Members list. The
-- app still lets them submit from their Pending Applicant screen, so leaving
-- them alone is safe. To list them as Pending right away instead, review the
-- count with PRE-FLIGHT query D, then run:
--
--   BEGIN;
--   INSERT INTO public.member_status_events (member_id, from_status, to_status, reason, actor_id)
--     SELECT user_id, 'draft', 'pending', 'Moved to Pending by migration', NULL
--     FROM public.user_roles WHERE role = 'farmer' AND status = 'draft';
--   UPDATE public.user_roles
--     SET status = 'pending', application_attempts = GREATEST(application_attempts, 1)
--     WHERE role = 'farmer' AND status = 'draft';
--   COMMIT;
-- ────────────────────────────────────────────────────────────────────────

-- ─── POST-DEPLOY VERIFICATION (read-only) ────────────────────────────────
-- 1. One overload each, no registry parameter (expect has_registry = false):
--    SELECT proname, count(*) AS overloads,
--           bool_or(pg_get_function_identity_arguments(oid) ILIKE '%registry%') AS has_registry
--    FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--      AND proname IN ('create_farmer_account', 'create_officer_account', 'register_account')
--    GROUP BY proname;
--
-- 2. No function body still reads the registry tables for account creation
--    (expect only check_sp3_registry, check_officer_registry,
--    finalize_official_membership, link_sp3_registry and similar historical
--    helpers — NOT register_account / create_* / approve_member):
--    SELECT proname FROM pg_proc WHERE pronamespace = 'public'::regnamespace
--      AND (prosrc ILIKE '%sp3_member_registry%' OR prosrc ILIKE '%officer_registry%')
--    ORDER BY proname;
--
-- 3. Registry lookups are no longer client-callable (expect false, false, false):
--    SELECT has_function_privilege('anon', 'public.check_sp3_registry(text)', 'EXECUTE'),
--           has_function_privilege('authenticated', 'public.check_sp3_registry(text)', 'EXECUTE'),
--           has_function_privilege('authenticated', 'public.check_officer_registry(text)', 'EXECUTE');
--
-- 4. The self-insert policy is gone (expect 0 rows):
--    SELECT policyname FROM pg_policies
--    WHERE tablename = 'user_roles' AND policyname = 'user_roles: insert on registration';
--
-- 5. Registry rows untouched (compare with a count taken before the migration):
--    SELECT (SELECT count(*) FROM public.sp3_member_registry) AS sp3_rows,
--           (SELECT count(*) FROM public.officer_registry)    AS officer_rows;
--
-- 6. End-to-end (use throwaway accounts, then delete them from the app):
--    - Register a Farmer in the app, then:
--      SELECT ur.status, ui.username, mi.member_code, ba.postal_code, ba.barangay_name
--      FROM public.user_roles ur
--      JOIN public.user_information ui USING (user_id)
--      JOIN public.member_identifiers mi USING (user_id)
--      LEFT JOIN public.buyer_addresses ba USING (user_id)
--      WHERE ui.username = '<the username you used>';
--      -- expect: pending | <username> | SP3-<this year>-NNN | 4903 | Payanas
--    - Register a Buyer; expect status 'active', code BUY-<this year>-NNN, and
--      the Buyer absent from Manager > Members.
--    - Register two Farmers with the SAME full name: both succeed.
-- ============================================================
