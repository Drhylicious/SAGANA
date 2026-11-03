-- ============================================================
-- SAGANA — Officer permissions, script 4 of 6: ACCOUNT APPROVAL
--
-- Requires script 01. Run before the app release (the app calls these RPCs).
--
-- RULE: a Farmer or Officer account created by an OFFICER cannot sign in until
-- the MANAGER approves it. An account created by the Manager is active at once,
-- exactly as today. Public self-registration is unchanged (its own approval
-- flow, approve_member / reject_member).
--
-- HOW IT IS ENFORCED (independent of the app and of the permission gate)
--   * A trigger on user_roles. Whenever a row is inserted by a signed-in OFFICER
--     for ANOTHER user, the account is (a) recorded in account_creation_requests
--     as 'pending' and (b) banned in Supabase Auth (auth.users.banned_until, 100
--     years). A banned login is refused by Supabase Auth itself, so confirming the
--     creation never activates the account, whichever screen or RPC made it.
--   * Only approve_account_creation() lifts the ban, and it checks is_manager():
--     the "Members = Manage" permission (which makes an Officer pass
--     is_platform_admin() inside Members requests) does NOT satisfy it. No
--     permission can approve an account.
--   * Disapproving keeps the ban and the record. Nothing is deleted; removing a
--     disapproved account is a separate Manager decision.
--   * The status stays 'active' in user_roles on purpose. Using 'pending' would
--     put the account in the Members applications list, where an Officer with
--     Members = Manage could approve it with approve_member().
--
-- ALSO IN THIS SCRIPT
--   * create_officer_account(): Position removed, permission matrix added. The
--     matrix is written at creation (Manage for any module not mentioned) and is
--     reviewed by the Manager when approving; the Manager can edit it then.
--   * create_farmer_account() is NOT redefined: the trigger covers it.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor.
-- ============================================================

-- ─── PRE-FLIGHT (read-only; run by itself) ───────────────────────────────
--   SELECT pg_get_function_identity_arguments(oid) FROM pg_proc
--   WHERE proname = 'create_officer_account';
--   -- expect the registration_12 signature (12 args, p_position text).
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. The request record
-- ════════════════════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.account_creation_requests (
  id                 UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            UUID        NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  account_role       TEXT        NOT NULL,
  status             TEXT        NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'approved', 'disapproved')),
  requested_by       UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  requested_by_name  TEXT,
  requested_by_role  TEXT,
  requested_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  decided_by         UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  decided_by_name    TEXT,
  decided_at         TIMESTAMPTZ,
  decision_reason    TEXT
);

CREATE INDEX IF NOT EXISTS idx_acr_status_requested
  ON public.account_creation_requests (status, requested_at DESC);

ALTER TABLE public.account_creation_requests ENABLE ROW LEVEL SECURITY;

-- The Manager reads everything; an Officer reads only the requests they made
-- (to see "awaiting approval"). Nobody writes directly: only the functions below.
DROP POLICY IF EXISTS "acr: manager reads" ON public.account_creation_requests;
CREATE POLICY "acr: manager reads"
  ON public.account_creation_requests FOR SELECT
  USING (public.is_manager() OR requested_by = auth.uid());

REVOKE ALL ON public.account_creation_requests FROM PUBLIC, anon;
GRANT SELECT ON public.account_creation_requests TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 2. The trigger: Officer-created accounts are held for the Manager
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
  -- registration (the new user is the caller), SQL-editor and service-key
  -- inserts have no such caller and are untouched.
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

  SELECT full_name INTO v_actor_name FROM user_information WHERE user_id = v_actor;

  INSERT INTO account_creation_requests
    (user_id, account_role, status, requested_by, requested_by_name, requested_by_role)
  VALUES
    (NEW.user_id, NEW.role, 'pending', v_actor, v_actor_name, v_actor_role)
  ON CONFLICT (user_id) DO NOTHING;

  -- The login is refused by Supabase Auth until the Manager approves.
  UPDATE auth.users
  SET banned_until = NOW() + INTERVAL '100 years'
  WHERE id = NEW.user_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_hold_officer_created_account ON public.user_roles;
CREATE TRIGGER trg_hold_officer_created_account
  AFTER INSERT ON public.user_roles
  FOR EACH ROW EXECUTE FUNCTION public.hold_officer_created_account();

-- ════════════════════════════════════════════════════════════
-- 3. The Manager's decision (strictly the Manager)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.approve_account_creation(p_request_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_req  account_creation_requests%ROWTYPE;
  v_name text;
BEGIN
  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'Only the Manager can approve a new account.';
  END IF;

  SELECT * INTO v_req FROM account_creation_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account request not found.';
  END IF;
  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'This account request was already %.', v_req.status;
  END IF;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = auth.uid();

  UPDATE account_creation_requests
  SET status = 'approved', decided_by = auth.uid(), decided_by_name = v_name,
      decided_at = NOW(), decision_reason = NULL
  WHERE id = p_request_id;

  UPDATE auth.users SET banned_until = NULL WHERE id = v_req.user_id;

  IF v_req.requested_by IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, is_read)
    VALUES (v_req.requested_by, 'member_updated', 'Account approved',
            'The account you created was approved by the Manager and can now sign in.',
            false);
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.disapprove_account_creation(p_request_id uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_req  account_creation_requests%ROWTYPE;
  v_name text;
BEGIN
  IF NOT public.is_manager() THEN
    RAISE EXCEPTION 'Only the Manager can disapprove a new account.';
  END IF;
  IF p_reason IS NULL OR trim(p_reason) = '' THEN
    RAISE EXCEPTION 'A reason is required.';
  END IF;

  SELECT * INTO v_req FROM account_creation_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Account request not found.';
  END IF;
  IF v_req.status <> 'pending' THEN
    RAISE EXCEPTION 'This account request was already %.', v_req.status;
  END IF;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = auth.uid();

  -- The account stays banned and stays on record. It is not deleted.
  UPDATE account_creation_requests
  SET status = 'disapproved', decided_by = auth.uid(), decided_by_name = v_name,
      decided_at = NOW(), decision_reason = trim(p_reason)
  WHERE id = p_request_id;

  IF v_req.requested_by IS NOT NULL THEN
    INSERT INTO notifications (user_id, type, title, body, is_read)
    VALUES (v_req.requested_by, 'member_updated', 'Account not approved',
            'The account you created was not approved by the Manager. Reason: ' || trim(p_reason),
            false);
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.approve_account_creation(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.disapprove_account_creation(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.approve_account_creation(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.disapprove_account_creation(uuid, text) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 4. create_officer_account — Position removed, permission matrix added
-- ════════════════════════════════════════════════════════════
DROP FUNCTION IF EXISTS public.create_officer_account(
  text, text, text, text, text, text, date, text, text, text, text, integer
);
-- (re-run safety)
DROP FUNCTION IF EXISTS public.create_officer_account(
  text, text, text, text, text, text, date, text, text, text, jsonb, integer
);

CREATE FUNCTION public.create_officer_account(
  p_username        text,
  p_password        text,
  p_surname         text,
  p_first_name      text,
  p_middle_initial  text    DEFAULT NULL,
  p_suffix          text    DEFAULT NULL,
  p_date_of_birth   date    DEFAULT NULL,
  p_gender          text    DEFAULT NULL,
  p_email           text    DEFAULT NULL,
  p_phone_number    text    DEFAULT NULL,
  p_permissions     jsonb   DEFAULT NULL,
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
  v_surname  TEXT;
  v_first    TEXT;
  v_mi       TEXT;
  v_suffix   TEXT;
  v_name     TEXT;
  v_email    TEXT;
  v_phone    TEXT;
  v_contact  TEXT := NULLIF(lower(trim(COALESCE(p_email, ''))), '');
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized: only a Manager or an Officer who manages Members can create Officer accounts';
  END IF;

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

  -- Reject a malformed permission matrix before any row is written.
  IF p_permissions IS NOT NULL AND jsonb_typeof(p_permissions) <> 'object' THEN
    RAISE EXCEPTION 'Permissions must be an object of module: level pairs.';
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

  INSERT INTO user_roles (user_id, role, status, must_change_password)
  VALUES (v_user_id, 'officer', 'active', true);

  INSERT INTO user_information (
    user_id, full_name, surname, first_name, middle_initial, suffix,
    phone_number, username, contact_email
  ) VALUES (
    v_user_id, v_name, v_surname, v_first, v_mi, v_suffix,
    v_phone, v_username, v_contact
  );

  -- position is no longer collected; the column is left NULL.
  INSERT INTO officer_profiles (user_id, position, date_of_birth, gender)
  VALUES (v_user_id, NULL, p_date_of_birth, p_gender);

  -- Manage for any module not named; the Manager reviews this when approving.
  PERFORM public._apply_officer_permissions(v_user_id, p_permissions, 'manage');

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
  text, text, text, text, text, text, date, text, text, text, jsonb, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_officer_account(
  text, text, text, text, text, text, date, text, text, text, jsonb, integer
) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION (run each by itself)
-- ============================================================
-- 1) Exactly one create_officer_account, with p_permissions jsonb and no p_position:
--    SELECT pg_get_function_identity_arguments(oid) FROM pg_proc WHERE proname = 'create_officer_account';
-- 2) The trigger and the Manager-only decision functions exist:
--    SELECT tgname FROM pg_trigger WHERE tgname = 'trg_hold_officer_created_account';
--    SELECT prosrc LIKE '%is_manager()%' FROM pg_proc WHERE proname = 'approve_account_creation';  -- true
-- 3) After an Officer creates an account in the app:
--    SELECT r.status, r.account_role, r.requested_by_name, u.banned_until
--    FROM account_creation_requests r JOIN auth.users u ON u.id = r.user_id
--    ORDER BY r.requested_at DESC LIMIT 5;     -- pending, banned_until ~100 years ahead
--    The new account must be REFUSED at sign-in. After the Manager approves,
--    banned_until is NULL and the sign-in works.
-- 4) An account created by the Manager has no row in account_creation_requests
--    and signs in at once.
-- ============================================================
