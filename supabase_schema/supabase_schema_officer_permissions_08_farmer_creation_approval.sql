-- ============================================================
-- SAGANA — Officer permissions, script 8: FARMER CREATION AND APPROVAL
--
-- Requires scripts 01–06 (account_creation_requests, is_manager()).
-- Scripts 07 and 08 are independent of each other; run them in either order.
-- Run this BEFORE installing the app update that goes with it.
--
-- THE RULES THIS SCRIPT ENFORCES (all in the database, not only in the app)
--   * Only the Manager creates Officer accounts. An Officer's attempt is refused.
--   * A Farmer account created by the Manager is active at once.
--   * A Farmer account created by an Officer is a PENDING applicant: it appears
--     in Members / Pending Applicants, the Manager is notified, and only the
--     Manager can approve or disapprove it. The Officer who created it, and any
--     other Officer, cannot. (Self-registered applicants are unchanged: Officers
--     can still decide those.)
--   * Officer-created Farmers are NOT banned. They sign in like any applicant and
--     land on the existing Pending screen, so the existing pending, approved
--     (Continue) and disapproved (reason, resubmit) messages are reused.
--   * The temporary password is still forced to change at first sign-in
--     (user_roles.must_change_password, unchanged).
--   * Decision details (who decided, when, why) stay Manager-only: the base table
--     account_creation_requests is now readable by the Manager only. Staff read a
--     narrow view that shows only WHO CREATED the account and WHEN.
--
-- WHAT CHANGES
--   1. account_creation_requests: Manager-only read; new view
--      account_creation_sources (creator and date, for staff).
--   2. hold_officer_created_account(): no ban any more. An Officer-created Farmer
--      becomes 'pending' with a request row and a status-history row; an Officer
--      creating an Officer account is refused.
--   3. approve_member() / reject_member(): same behaviour as today, plus the
--      Manager-only rule for Officer-created accounts, the request row is closed,
--      and the creating Officer is notified of the outcome.
--   4. fn_notify_account_created(): the "created by the cooperative Manager"
--      notice is sent only when a Manager created the account (it was wrong for
--      Officer-created ones).
--   5. create_farmer_account(): new signature with the address (street, building,
--      house number), same fixed area as registration. Every old parameter is
--      kept (with its default), so the membership year, share value, opening
--      contribution and crops logic is NOT removed — the app form simply stops
--      sending them. An Officer-created account is pending and unverified, and
--      the Managers are notified.
--   6. approve_account_creation() / disapprove_account_creation() are dropped:
--      the Account Approvals screen that used them is removed, and Farmers are
--      decided through Members.
--
-- BASED ON THE LIVE DEFINITIONS read from the database on 2026-11
--   (approve_member, reject_member, create_farmer_account, hold_officer_created_account,
--    fn_notify_account_created all matched the repository copies).
--   The address rows copy register_account() from registration_12; that function's
--   live text was not read, so the pre-flight below checks the columns it needs.
--
-- COMPATIBILITY ORDER: run this script first. The old app can still create Farmers
-- only if it sends an address, which it does not — so install the app update right
-- after (Create Farmer needs the new form). Manager-created accounts keep working
-- for every other screen.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Re-runnable.
--
-- ROLLBACK NOTES: the previous definitions are in
--   supabase_schema_officer_permissions_04_account_approval.sql (hold trigger,
--   approve/disapprove_account_creation), supabase_schema_registration_02 (approve_member,
--   reject_member) and supabase_schema_registration_12 (create_farmer_account).
-- ============================================================

-- ─── PRE-FLIGHT (read-only; the script stops with a message if one fails) ─────
DO $$
DECLARE
  v_missing text;
BEGIN
  IF to_regclass('public.account_creation_requests') IS NULL THEN
    RAISE EXCEPTION 'account_creation_requests is missing. Run officer_permissions_04 first.';
  END IF;
  IF to_regprocedure('public.is_manager(uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_manager() is missing. Run officer_permissions_01 first.';
  END IF;
  IF to_regclass('public.buyer_addresses') IS NULL THEN
    RAISE EXCEPTION 'buyer_addresses is missing.';
  END IF;

  SELECT string_agg(c, ', ') INTO v_missing
  FROM unnest(ARRAY['user_id','label','recipient_name','contact_number','address_line','is_default',
                    'region_code','region_name','province_code','province_name',
                    'city_municipality_code','city_municipality_name',
                    'barangay_code','barangay_name','postal_code','street','building','house_no']) AS c
  WHERE NOT EXISTS (SELECT 1 FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = 'buyer_addresses' AND column_name = c);
  IF v_missing IS NOT NULL THEN
    RAISE EXCEPTION 'buyer_addresses is missing columns: %', v_missing;
  END IF;

  IF EXISTS (SELECT 1 FROM public.account_creation_requests WHERE status = 'pending') THEN
    RAISE EXCEPTION 'Some Officer-created accounts are still waiting under the old rule (they are banned until approved). Decide them first, then run this script.';
  END IF;
END $$;

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. Who can read what
-- ════════════════════════════════════════════════════════════
-- Decision details (who decided, when, why) are for the Manager only.
DROP POLICY IF EXISTS "acr: manager reads" ON public.account_creation_requests;
CREATE POLICY "acr: manager reads"
  ON public.account_creation_requests FOR SELECT
  USING (public.is_manager());

-- Staff see only the creator and the date, so Members can show where an
-- applicant came from. Runs with the owner's rights; the is_staff() filter is
-- what limits it.
CREATE OR REPLACE VIEW public.account_creation_sources AS
SELECT r.user_id, r.requested_by, r.requested_by_name, r.requested_by_role, r.requested_at
FROM public.account_creation_requests r
WHERE r.account_role = 'farmer' AND public.is_staff();

REVOKE ALL ON public.account_creation_sources FROM PUBLIC, anon;
GRANT SELECT ON public.account_creation_sources TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 2. The trigger: an Officer-created Farmer is a pending applicant
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.hold_officer_created_account()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_actor      uuid := auth.uid();
  v_actor_role text;
  v_actor_name text;
BEGIN
  -- Only accounts that a signed-in person creates FOR SOMEONE ELSE. Self
  -- registration, SQL-editor and service-key inserts have no such caller.
  IF v_actor IS NULL OR v_actor = NEW.user_id THEN
    RETURN NEW;
  END IF;
  IF NEW.role NOT IN ('farmer', 'officer') THEN
    RETURN NEW;
  END IF;

  SELECT role INTO v_actor_role FROM user_roles WHERE user_id = v_actor;
  IF v_actor_role IS DISTINCT FROM 'officer' THEN
    RETURN NEW;                                  -- the Manager: active at once
  END IF;

  -- An Officer never creates an Officer account.
  IF NEW.role = 'officer' THEN
    RAISE EXCEPTION 'Only the Manager can create an Officer account.';
  END IF;

  -- An Officer-created Farmer: a pending applicant that only the Manager decides.
  SELECT full_name INTO v_actor_name FROM user_information WHERE user_id = v_actor;

  INSERT INTO account_creation_requests
    (user_id, account_role, status, requested_by, requested_by_name, requested_by_role)
  VALUES
    (NEW.user_id, NEW.role, 'pending', v_actor, v_actor_name, v_actor_role)
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE user_roles
  SET status = 'pending', application_attempts = 1
  WHERE user_id = NEW.user_id;

  INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id)
  VALUES (NEW.user_id, NULL, 'pending', 'Created by an Officer - awaiting Manager approval', v_actor);

  RETURN NEW;
END;
$$;

-- (the trigger trg_hold_officer_created_account already exists; it now calls this function)

-- ════════════════════════════════════════════════════════════
-- 3. approve_member / reject_member: the Manager-only rule
--    Everything else below is the live behaviour, unchanged.
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.approve_member(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_status TEXT;
  v_req    account_creation_requests%ROWTYPE;
  v_name   TEXT;
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

  -- An account an Officer created is decided by the Manager only. The request
  -- row stays for good, so this also holds after a disapproved applicant
  -- resubmits.
  SELECT * INTO v_req FROM account_creation_requests
  WHERE user_id = p_user_id AND account_role = 'farmer' FOR UPDATE;
  IF FOUND AND NOT public.is_manager() THEN
    RAISE EXCEPTION 'Only the Manager can approve an account created by an Officer.';
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

  IF v_req.id IS NOT NULL THEN
    SELECT full_name INTO v_name FROM user_information WHERE user_id = auth.uid();
    UPDATE account_creation_requests
    SET status = 'approved', decided_by = auth.uid(), decided_by_name = v_name,
        decided_at = NOW(), decision_reason = NULL
    WHERE id = v_req.id;

    IF v_req.requested_by IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
      VALUES (v_req.requested_by, 'member_updated', 'Account approved',
              'The Farmer account you created was approved.',
              false, '/admin/farmers');
    END IF;
  END IF;
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
  v_req    account_creation_requests%ROWTYPE;
  v_name   TEXT;
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

  SELECT * INTO v_req FROM account_creation_requests
  WHERE user_id = p_user_id AND account_role = 'farmer' FOR UPDATE;
  IF FOUND AND NOT public.is_manager() THEN
    RAISE EXCEPTION 'Only the Manager can disapprove an account created by an Officer.';
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

  IF v_req.id IS NOT NULL THEN
    SELECT full_name INTO v_name FROM user_information WHERE user_id = auth.uid();
    UPDATE account_creation_requests
    SET status = 'disapproved', decided_by = auth.uid(), decided_by_name = v_name,
        decided_at = NOW(), decision_reason = trim(p_reason)
    WHERE id = v_req.id;

    IF v_req.requested_by IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, is_read, route_on_tap)
      VALUES (v_req.requested_by, 'member_updated', 'Account not approved',
              'The Farmer account you created was not approved. Reason: '
              || trim(p_reason),
              false, '/admin/farmers');
    END IF;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.reject_member(uuid, text) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 4. The "Account Created ... by the cooperative Manager" notice
--    Only when a Manager created the account.
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.fn_notify_account_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF NEW.role IN ('farmer', 'officer')
     AND NEW.user_id IS DISTINCT FROM auth.uid()
     AND EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = auth.uid() AND role = 'admin') THEN
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
-- 5. create_farmer_account: address added, Officer-created = pending
-- ════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.create_farmer_account(
  text, text, text, text, text, text, text, date, text, numeric, numeric, text[], text, integer
);
-- (re-run safety: also drop the new signature if a previous run created it)
DROP FUNCTION IF EXISTS public.create_farmer_account(
  text, text, text, text, text, text, text, date, text, numeric, numeric, text[], text, integer,
  text, text, text
);

CREATE FUNCTION public.create_farmer_account(
  p_username             text,
  p_password             text,
  p_surname              text,
  p_first_name           text,
  p_middle_initial       text      DEFAULT NULL,
  p_suffix               text      DEFAULT NULL,
  p_phone_number         text      DEFAULT NULL,
  p_date_of_birth        date      DEFAULT NULL,
  p_gender               text      DEFAULT NULL,
  p_share_value_per_unit numeric   DEFAULT 2000,
  p_initial_contribution numeric   DEFAULT 0,
  p_initial_crops        text[]    DEFAULT ARRAY[]::text[],
  p_contact_email        text      DEFAULT NULL,
  p_membership_year      integer   DEFAULT NULL,
  p_street               text      DEFAULT NULL,
  p_building             text      DEFAULT NULL,
  p_house_no             text      DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth', 'extensions'
AS $function$
DECLARE
  v_user_id    UUID;
  v_username   TEXT := lower(trim(coalesce(p_username, '')));
  v_surname    TEXT;
  v_first      TEXT;
  v_mi         TEXT;
  v_suffix     TEXT;
  v_name       TEXT;
  v_email      TEXT;
  v_phone      TEXT;
  v_contact    TEXT := NULLIF(lower(trim(COALESCE(p_contact_email, ''))), '');
  v_street     TEXT := NULLIF(trim(coalesce(p_street, '')), '');
  v_building   TEXT := NULLIF(trim(coalesce(p_building, '')), '');
  v_house_no   TEXT := NULLIF(trim(coalesce(p_house_no, '')), '');
  v_line       TEXT;
  v_by_officer BOOLEAN := FALSE;
  v_creator    TEXT;
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

  SELECT COALESCE(role = 'officer', FALSE) INTO v_by_officer
  FROM user_roles WHERE user_id = auth.uid();
  v_by_officer := COALESCE(v_by_officer, FALSE);

  -- Name: surname and first name are required; middle initial and suffix are
  -- optional. Each part is trimmed and checked, and the full name is built from
  -- them here (First M. Surname Suffix). Names are not unique.
  v_surname := public.normalize_name_part(p_surname, 'Surname');
  v_first   := public.normalize_name_part(p_first_name, 'First name');
  v_mi      := public.normalize_middle_initial(p_middle_initial);
  v_suffix  := public.normalize_name_suffix(p_suffix);
  IF v_surname IS NULL THEN
    RAISE EXCEPTION 'Please enter the surname.';
  END IF;
  IF v_first IS NULL THEN
    RAISE EXCEPTION 'Please enter the first name.';
  END IF;
  v_name := public.compose_full_name(v_first, v_mi, v_surname, v_suffix);

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

  -- Same address rules as registration: street and house number are required.
  IF v_street IS NULL THEN
    RAISE EXCEPTION 'Street is required.';
  END IF;
  IF v_house_no IS NULL THEN
    RAISE EXCEPTION 'House number is required.';
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

  -- Manager-created: active at once. Officer-created: a pending applicant (the
  -- trigger records the request and the status history). Either way the
  -- temporary password must be changed at first sign-in.
  INSERT INTO user_roles (user_id, role, status, must_change_password, application_attempts)
  VALUES (v_user_id, 'farmer',
          CASE WHEN v_by_officer THEN 'pending' ELSE 'active' END,
          true,
          CASE WHEN v_by_officer THEN 1 ELSE 0 END);

  INSERT INTO user_information (
    user_id, full_name, surname, first_name, middle_initial, suffix,
    phone_number, username, contact_email
  ) VALUES (
    v_user_id, v_name, v_surname, v_first, v_mi, v_suffix,
    v_phone, v_username, v_contact
  );

  -- Only the Manager verifies a member; an Officer-created account is verified
  -- when the Manager approves it (approve_member).
  INSERT INTO farmer_profiles (user_id, is_verified, date_of_birth, gender)
  VALUES (v_user_id, NOT v_by_officer, p_date_of_birth, p_gender);

  -- Fixed Farmer address: MIMAROPA Region / Marinduque / Torrijos / Payanas /
  -- 4903. Only street, building and house number come from the caller (same as
  -- register_account()).
  v_line := concat_ws(', ', v_house_no, v_building, v_street,
                      'Payanas', 'Torrijos', 'Marinduque', 'MIMAROPA Region', '4903');
  INSERT INTO public.buyer_addresses (
    user_id, label, recipient_name, contact_number, address_line, is_default,
    region_code, region_name, province_code, province_name,
    city_municipality_code, city_municipality_name,
    barangay_code, barangay_name, postal_code, street, building, house_no
  ) VALUES (
    v_user_id, 'Home', v_name, v_phone, v_line, TRUE,
    '1700000000', 'MIMAROPA Region', '1704000000', 'Marinduque',
    '1704006000', 'Torrijos',
    '1704006019', 'Payanas', '4903', v_street, v_building, v_house_no
  );

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

  -- An Officer-created Farmer is a new applicant: tell the Managers.
  IF v_by_officer THEN
    SELECT full_name INTO v_creator FROM user_information WHERE user_id = auth.uid();
    INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
    SELECT ur.user_id, 'member_pending', 'New Membership Application',
           v_name || ' was created by ' || COALESCE(v_creator, 'an Officer')
           || ' and needs your approval.',
           FALSE, NOW(), '/admin/farmers'
    FROM user_roles ur WHERE ur.role = 'admin';
  END IF;

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
  text, text, text, text, text, text, text, date, text, numeric, numeric, text[], text, integer,
  text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_farmer_account(
  text, text, text, text, text, text, text, date, text, numeric, numeric, text[], text, integer,
  text, text, text
) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 6. The old approval RPCs (their screen is removed)
-- ════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.approve_account_creation(uuid);
DROP FUNCTION IF EXISTS public.disapprove_account_creation(uuid, text);

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only; run each by itself) ────────────────────────
-- 1. One create_farmer_account, with the address parameters:
--    SELECT pg_get_function_identity_arguments(oid) FROM pg_proc
--    WHERE proname = 'create_farmer_account' AND pronamespace = 'public'::regnamespace;
--    -- expect ONE row ending in "... p_membership_year integer, p_street text, p_building text, p_house_no text"
-- 2. The old approval RPCs are gone:
--    SELECT proname FROM pg_proc WHERE proname IN ('approve_account_creation','disapprove_account_creation');
--    -- expect no rows
-- 3. The decision table is Manager-only; staff read the view:
--    SELECT policyname, cmd, qual FROM pg_policies WHERE tablename = 'account_creation_requests';
--    SELECT * FROM public.account_creation_sources;      -- as the Manager: all rows (none yet)
-- ─────────────────────────────────────────────────────────────────────────
