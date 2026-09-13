-- ============================================================
-- SAGANA — Phase D-2: Officer operational authorization
-- (Admin Members tab enhancement — Issue 6, Decision D21)
--
-- Goal: an Officer can perform every operational write an Admin can
-- (issue loans, approve/reject listings, complete/cancel orders, confirm/
-- decline cooperative offers, complete market linking, approve/reject crop
-- requests, distribute program benefits, confirm program returns, adjust
-- inventory, manage prices, broadcasts, Balik-Tangkilik) — but NOT the
-- Members tab (Decision D19).
--
-- Mechanism (chosen for minimal, low-risk surface):
--   * Every `officer` gets a row in admin_profiles. The ~15 operational
--     RPCs and the operational "admin manages all" RLS policies already
--     test `EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid())`
--     — so they start accepting Officers with ZERO body changes.
--   * A strict `is_platform_admin()` (user_roles.role = 'admin') is
--     introduced and swapped into ONLY the Members-management surface —
--     the RPCs written in Phase B/C/D-1 and the Members-table RLS
--     policies — so Officers stay locked out of member management.
--   * Officers get the read-only policies they need for operational
--     screens that display member-adjacent data (capital contribution for
--     the loan-eligibility banner; loan policy settings).
--
-- create_officer_account (Phase D-1) is re-created here to (a) insert the
-- admin_profiles row for new Officers and (b) use is_platform_admin().
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. Strict platform-admin check (excludes Officers)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_platform_admin(p_uid uuid DEFAULT auth.uid())
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM user_roles
    WHERE user_id = p_uid AND role = 'admin'
  );
$$;
GRANT EXECUTE ON FUNCTION public.is_platform_admin(uuid) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 2. Every Officer gets an admin_profiles row
-- ════════════════════════════════════════════════════════════
-- This is what grants the operational RPC + RLS access. employee_id is
-- left NULL here (the Officer's real EMP-### lives on officer_profiles;
-- admin_profiles.employee_id is UNIQUE and we don't want a collision or
-- to imply "admin staff number").

INSERT INTO public.admin_profiles (user_id, position)
SELECT op.user_id, op.position
FROM public.officer_profiles op
LEFT JOIN public.admin_profiles ap ON ap.user_id = op.user_id
WHERE ap.user_id IS NULL;

-- ════════════════════════════════════════════════════════════
-- 3. Lock the Members-management surface to strict admin
-- ════════════════════════════════════════════════════════════

-- ─── 3a. Members-table RLS "admin manages all" policies ───────────────────
-- Re-point from admin_profiles to is_platform_admin() so an Officer's
-- admin_profiles row does NOT grant member management.

-- user_roles: admin updates status  (writes — status changes)
DROP POLICY IF EXISTS "user_roles: admin updates status" ON public.user_roles;
CREATE POLICY "user_roles: admin updates status"
  ON public.user_roles FOR UPDATE
  USING (is_platform_admin());

-- sp3_member_registry
DROP POLICY IF EXISTS "sp3_registry: admin manages all" ON public.sp3_member_registry;
CREATE POLICY "sp3_registry: admin manages all"
  ON public.sp3_member_registry FOR ALL
  USING (is_platform_admin());

-- member_capital_shares  (writes admin-only; Officer read policy added in 4)
DROP POLICY IF EXISTS "member_capital_shares: admin manages all" ON public.member_capital_shares;
CREATE POLICY "member_capital_shares: admin manages all"
  ON public.member_capital_shares FOR ALL
  USING (is_platform_admin());

-- capital_contribution_events
DROP POLICY IF EXISTS "cce: admin manages all" ON public.capital_contribution_events;
CREATE POLICY "cce: admin manages all"
  ON public.capital_contribution_events FOR ALL
  USING (is_platform_admin());

-- member_status_events
DROP POLICY IF EXISTS "mse: admin manages all" ON public.member_status_events;
CREATE POLICY "mse: admin manages all"
  ON public.member_status_events FOR ALL
  USING (is_platform_admin());

-- officer_registry  (only real admins create Officers)
DROP POLICY IF EXISTS "officer_registry: admin manages all" ON public.officer_registry;
CREATE POLICY "officer_registry: admin manages all"
  ON public.officer_registry FOR ALL
  USING (is_platform_admin());

-- officer_profiles  (the old staff_profiles "admin manages all" policy —
-- it may still carry a staff_profiles-era name; drop both spellings)
DROP POLICY IF EXISTS "staff_profiles: admin manages all" ON public.officer_profiles;
DROP POLICY IF EXISTS "officer_profiles: admin manages all" ON public.officer_profiles;
CREATE POLICY "officer_profiles: admin manages all"
  ON public.officer_profiles FOR ALL
  USING (is_platform_admin());

-- ─── 3b. Members-management RPCs (Phase B / C / D-1) ──────────────────────
-- Swap the admin_profiles EXISTS check for is_platform_admin(). Only the
-- guard line changes; every other statement is reproduced verbatim from
-- the phase that introduced the function.

-- approve_member (Phase C)
CREATE OR REPLACE FUNCTION public.approve_member(p_user_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status    TEXT;
  v_full_name TEXT;
  v_member_id TEXT;
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

  SELECT member_id INTO v_member_id FROM farmer_profiles WHERE user_id = p_user_id;
  IF v_member_id IS NULL OR trim(v_member_id) = '' THEN
    v_member_id := generate_member_id(EXTRACT(YEAR FROM now())::INT);
  END IF;

  UPDATE farmer_profiles
  SET member_id = v_member_id, is_verified = true
  WHERE user_id = p_user_id;

  IF EXISTS (SELECT 1 FROM sp3_member_registry WHERE registered_user_id = p_user_id) THEN
    UPDATE sp3_member_registry SET is_registered = true WHERE registered_user_id = p_user_id;
  ELSE
    INSERT INTO sp3_member_registry (full_name, is_registered, registered_user_id)
    VALUES (COALESCE(v_full_name, 'SP3 Member'), true, p_user_id)
    ON CONFLICT (registered_user_id) DO UPDATE SET is_registered = true;
  END IF;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, 'pending', 'active', 'Application approved', auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (p_user_id, 'member_approved', 'Membership Approved',
          'Your SP3 cooperative membership has been approved. Open SAGANA and tap '
          || 'Continue to activate your farmer access. Your Member ID is ' || v_member_id || '.',
          false);

  RETURN v_member_id;
END;
$$;

-- reject_member (Phase C)
CREATE OR REPLACE FUNCTION public.reject_member(p_user_id UUID, p_reason TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A rejection reason is required';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;
  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'Only a pending application can be rejected (current: %)', v_status;
  END IF;

  UPDATE user_roles
  SET status = 'rejected',
      rejection_reason = trim(p_reason),
      pending_acknowledgement = false
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, 'pending', 'rejected', trim(p_reason), auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (p_user_id, 'member_rejected', 'Application Not Approved',
          'Your SP3 membership application was not approved. Reason: ' || trim(p_reason)
          || ' You may review your details and resubmit.',
          false);
END;
$$;

-- suspend_member (Phase C)
CREATE OR REPLACE FUNCTION public.suspend_member(p_user_id UUID, p_reason TEXT)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A suspension reason is required';
  END IF;

  SELECT status INTO v_status FROM user_roles WHERE user_id = p_user_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Member not found';
  END IF;

  UPDATE user_roles
  SET status = 'suspended', suspension_reason = trim(p_reason)
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, v_status, 'suspended', trim(p_reason), auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (p_user_id, 'member_updated', 'Account Suspended',
          'Your SP3 account has been suspended. Reason: ' || trim(p_reason)
          || ' Please contact the SP3 Cooperative.',
          false);
END;
$$;

-- reactivate_member (Phase C)
CREATE OR REPLACE FUNCTION public.reactivate_member(p_user_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  UPDATE user_roles
  SET status = 'active', suspension_reason = NULL
  WHERE user_id = p_user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (p_user_id, v_status, 'active', 'Reactivated by admin', auth.uid());

  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (p_user_id, 'member_updated', 'Account Reactivated',
          'Your SP3 account has been reactivated. Welcome back!',
          false);
END;
$$;

-- create_farmer_account (Phase B) — swap ONLY the guard line.
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
  v_member_id TEXT;
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

  v_member_id := generate_member_id(EXTRACT(YEAR FROM now())::INT);

  INSERT INTO farmer_profiles (user_id, member_id, is_verified, date_of_birth, gender)
  VALUES (v_user_id, v_member_id, TRUE, p_date_of_birth, p_gender);

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

-- create_officer_account (Phase D-1) — strict-admin guard + insert the
-- new Officer's admin_profiles row so they get operational access.
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

  -- Operational authorization (Decision D21): an Officer performs the same
  -- operational writes an Admin does. The admin_profiles row is the grant;
  -- role stays 'officer' so the Members surface (is_platform_admin) stays
  -- locked.
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

-- ════════════════════════════════════════════════════════════
-- 4. Officer read-only policies for operational screens
-- ════════════════════════════════════════════════════════════

-- Issue New Loan shows a capital-contribution eligibility banner — the
-- Officer needs to read member_capital_shares (write stays admin-only).
DROP POLICY IF EXISTS "member_capital_shares: officer reads all" ON public.member_capital_shares;
CREATE POLICY "member_capital_shares: officer reads all"
  ON public.member_capital_shares FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.officer_profiles WHERE user_id = auth.uid()));

-- loan_policy_settings — the eligibility minimum + loan maintenance
-- staleness read on the Loan dashboard.
DROP POLICY IF EXISTS "loan_policy_settings: officer reads" ON public.loan_policy_settings;
CREATE POLICY "loan_policy_settings: officer reads"
  ON public.loan_policy_settings FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.officer_profiles WHERE user_id = auth.uid()));

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) Helper + officer grants:
--    SELECT is_platform_admin('<a real admin user_id>');    -- true
--    SELECT is_platform_admin('<the off-0001 user_id>');     -- false
--    SELECT count(*) FROM admin_profiles ap
--    JOIN user_roles ur ON ur.user_id = ap.user_id AND ur.role = 'officer';
--    -- = number of officer accounts (each now has an admin_profiles row)
--
-- 2) Members surface locked (run AS the officer — or check the policy defs):
--    SELECT pg_get_functiondef('approve_member(uuid)'::regprocedure)
--           LIKE '%is_platform_admin%';                      -- true
--    SELECT pg_get_expr(polqual, polrelid) FROM pg_policy
--    WHERE polname = 'sp3_registry: admin manages all';      -- is_platform_admin()
--
-- 3) In app, logged in as off-0001:
--    * Loans → Issue New Loan for an eligible farmer → succeeds
--      (previously "Only admins may issue loans").
--    * Marketplace → approve / request-changes / reject a pending listing → succeeds.
--    * Orders → complete / cancel an order → succeeds.
--    * Cooperative offer → confirm / decline → succeeds.
--    * Inventory → adjust stock → succeeds.
--    * Prices → record a price → succeeds.
--    * Broadcast → send → succeeds.
--    * Balik-Tangkilik management → refresh / record distribution → succeeds.
--    * Members tab is still absent; hitting /admin/members bounces to the
--      dashboard; there is no way to approve/reject/suspend a member or
--      record a capital contribution.
--
-- 4) Logged in as a real Admin — everything above STILL works, and the
--    Members tab + all member actions still work.
-- ============================================================
