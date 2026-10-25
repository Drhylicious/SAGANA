-- ============================================================
-- supabase_schema_registration_12_name_components.sql
--
-- Splits the single "Full Name" into Surname, First Name, Middle Initial and
-- Suffix for Farmer and Buyer registration, Manager-created Farmers and
-- Manager-created Officers.
--
-- HOW THE DATA IS KEPT
--   * user_information.full_name stays. It is still NOT NULL and is still the one
--     column every list, profile, notification and report reads. From now on it
--     is BUILT from the parts, by one function, in one format:
--         First M. Surname Suffix      e.g.  Marc Louie M. Yañez Jr.
--     so the complete name is generated in exactly one place.
--   * New nullable columns: surname, first_name, middle_initial, suffix.
--     (middle_initial holds the letter only, "M"; the period is added when the
--     full name is built. suffix holds Jr., Sr., II, III, IV or V.)
--
-- EXISTING ACCOUNTS ARE NOT SPLIT
--   Nothing here guesses at how an existing full name divides. "Maria Luisa
--   Santos" could be first "Maria Luisa" or first "Maria" with middle name
--   "Luisa", and a wrong guess would be written into real records. Existing
--   rows keep their full_name exactly as it is, with NULL parts, and everything
--   keeps working. Section 7 (comments) lists them for review and gives a
--   guarded way to fill the parts in, one person at a time, only when the parts
--   rebuild exactly the name that is already stored.
--
-- WHAT CHANGES
--   1. user_information: 4 new columns + a consistency CHECK.
--   2. Helper functions: normalize_name_part, normalize_middle_initial,
--      normalize_name_suffix, compose_full_name.
--   3. Trigger on user_information: validates the parts, rebuilds full_name from
--      them, and drops the parts if full_name is edited on its own (so the two
--      can never disagree).
--   4-6. register_account, create_farmer_account, create_officer_account are
--      re-created with the name parameters replaced; the rest of each function is
--      the existing text, unchanged. The old signatures are dropped so exactly one
--      version of each remains.
--
-- NOT CHANGED: sign-in (username@sagana.local), roles, statuses, approval,
-- member identifiers, the fixed Farmer address, passwords, contributions.
--
-- Run order: after script 11. Not applied automatically. Run the PRE-FLIGHT
-- first, then this whole file in the Supabase SQL editor, then the verification
-- block at the end. Safe to re-run.
--
-- IMPORTANT: the Flutter app in this change calls the NEW signatures. Run this
-- script before using the new registration / Create Farmer / Create Officer
-- screens, or those calls will fail with "function not found".
-- ============================================================

-- ─── PRE-FLIGHT (read-only; run each on its own) ─────────────────────────
-- P1. Exactly one version of each function exists (expect 3 rows, overloads = 1):
--   SELECT proname, count(*) AS overloads FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace
--     AND proname IN ('register_account', 'create_farmer_account', 'create_officer_account')
--   GROUP BY proname ORDER BY proname;
--
-- P2. The live functions are the ones this script was built from (expect 3 rows, all true):
--   SELECT proname,
--          CASE proname
--            WHEN 'register_account'       THEN prosrc LIKE '%Please enter your full name.%'
--            WHEN 'create_farmer_account'  THEN prosrc LIKE '%Please enter the full name.%' AND prosrc LIKE '%must_change_password%'
--            WHEN 'create_officer_account' THEN prosrc LIKE '%Please enter the full name.%' AND prosrc LIKE '%must_change_password%'
--          END AS is_expected_version
--   FROM pg_proc
--   WHERE pronamespace = 'public'::regnamespace
--     AND proname IN ('register_account', 'create_farmer_account', 'create_officer_account')
--   ORDER BY proname;
--
-- P3. Nothing else already uses the new column names (expect 0 rows):
--   SELECT column_name FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'user_information'
--     AND column_name IN ('surname', 'first_name', 'middle_initial', 'suffix');
--
-- P4. Any other trigger on user_information that might touch full_name (review the list):
--   SELECT tgname, pg_get_triggerdef(oid) FROM pg_trigger
--   WHERE tgrelid = 'public.user_information'::regclass AND NOT tgisinternal;
-- ────────────────────────────────────────────────────────────────────────

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. New columns (all nullable: existing rows are left alone)
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.user_information
  ADD COLUMN IF NOT EXISTS surname        text,
  ADD COLUMN IF NOT EXISTS first_name     text,
  ADD COLUMN IF NOT EXISTS middle_initial text,
  ADD COLUMN IF NOT EXISTS suffix         text;

COMMENT ON COLUMN public.user_information.surname        IS 'Surname (required once the name is structured). NULL on accounts created before the split.';
COMMENT ON COLUMN public.user_information.first_name     IS 'Given name(s) (required once the name is structured).';
COMMENT ON COLUMN public.user_information.middle_initial IS 'One letter, no period. Optional.';
COMMENT ON COLUMN public.user_information.suffix         IS 'Jr., Sr., II, III, IV or V. Optional.';

-- Parts are all-or-nothing: a surname needs a first name and the other way
-- round, and a middle initial or suffix needs both. Existing rows (all NULL) pass.
ALTER TABLE public.user_information DROP CONSTRAINT IF EXISTS user_information_name_parts_chk;
ALTER TABLE public.user_information
  ADD CONSTRAINT user_information_name_parts_chk CHECK (
    (surname IS NULL) = (first_name IS NULL)
    AND (middle_initial IS NULL OR surname IS NOT NULL)
    AND (suffix IS NULL OR surname IS NOT NULL)
  );

-- ════════════════════════════════════════════════════════════
-- 2. Helper functions
--    The Flutter app applies the same rules before it sends anything, so a
--    person sees the problem on the field. These are the authoritative copy.
-- ════════════════════════════════════════════════════════════

-- Surname / first name: trimmed, inner spaces collapsed, 2 to 60 characters,
-- letters (including accented ones such as ñ), spaces, hyphens, apostrophes and
-- periods only. Capital letters are kept as typed ("de la Cruz", "O'Brien").
-- Blank becomes NULL; the caller decides whether that is allowed.
CREATE OR REPLACE FUNCTION public.normalize_name_part(p_value text, p_label text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v text := regexp_replace(btrim(coalesce(p_value, '')), '\s+', ' ', 'g');
BEGIN
  IF v = '' THEN
    RETURN NULL;
  END IF;
  IF length(v) < 2 OR length(v) > 60 THEN
    RAISE EXCEPTION '% must be 2 to 60 characters.', p_label;
  END IF;
  IF v !~ '^[A-Za-zÀ-ɏ][A-Za-zÀ-ɏ .''’-]*$' THEN
    RAISE EXCEPTION '% may contain letters, spaces, hyphens, apostrophes and periods only.', p_label;
  END IF;
  RETURN v;
END;
$$;

-- Middle initial: one letter, with or without a period. Stored as the capital
-- letter alone ("m." -> "M"). Blank becomes NULL.
CREATE OR REPLACE FUNCTION public.normalize_middle_initial(p_value text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v text := btrim(coalesce(p_value, ''));
BEGIN
  IF v = '' THEN
    RETURN NULL;
  END IF;
  IF v !~ '^[A-Za-zÀ-ɏ]\.?$' THEN
    RAISE EXCEPTION 'Middle initial must be a single letter.';
  END IF;
  RETURN upper(left(v, 1));
END;
$$;

-- Suffix: Jr., Sr., II, III, IV or V, typed any way ("jr", "JR.", "iii").
-- Stored in the canonical form. Blank becomes NULL.
CREATE OR REPLACE FUNCTION public.normalize_name_suffix(p_value text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public
AS $$
DECLARE
  v text := lower(regexp_replace(btrim(coalesce(p_value, '')), '[\s.]+', '', 'g'));
BEGIN
  IF v = '' THEN
    RETURN NULL;
  END IF;
  IF v NOT IN ('jr', 'sr', 'ii', 'iii', 'iv', 'v') THEN
    RAISE EXCEPTION 'Please choose a valid suffix (Jr., Sr., II, III, IV or V).';
  END IF;
  RETURN CASE v
    WHEN 'jr'  THEN 'Jr.'
    WHEN 'sr'  THEN 'Sr.'
    WHEN 'ii'  THEN 'II'
    WHEN 'iii' THEN 'III'
    WHEN 'iv'  THEN 'IV'
    WHEN 'v'   THEN 'V'
    ELSE NULL
  END;
END;
$$;

-- Complete name: First M. Surname Suffix. The middle initial gets its period
-- here; a missing middle initial or suffix leaves no gap or stray punctuation.
CREATE OR REPLACE FUNCTION public.compose_full_name(
  p_first_name     text,
  p_middle_initial text,
  p_surname        text,
  p_suffix         text
)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT concat_ws(' ',
    NULLIF(btrim(p_first_name), ''),
    CASE WHEN NULLIF(btrim(p_middle_initial), '') IS NOT NULL
         THEN btrim(p_middle_initial) || '.' END,
    NULLIF(btrim(p_surname), ''),
    NULLIF(btrim(p_suffix), '')
  );
$$;

-- ════════════════════════════════════════════════════════════
-- 3. Trigger: the parts and full_name can never disagree
-- ════════════════════════════════════════════════════════════
--   * parts given or changed -> validated, and full_name is rebuilt from them
--   * only full_name changed (the old single-field Edit Profile screens) ->
--     if it no longer matches the parts, the parts are cleared, because they
--     would now describe a different name
--   * no parts at all (accounts from before the split) -> full_name is untouched

CREATE OR REPLACE FUNCTION public.user_information_name_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.suffix         := public.normalize_name_suffix(NEW.suffix);
  NEW.surname        := public.normalize_name_part(NEW.surname, 'Surname');
  NEW.first_name     := public.normalize_name_part(NEW.first_name, 'First name');
  NEW.middle_initial := public.normalize_middle_initial(NEW.middle_initial);

  -- Parts untouched by this statement.
  IF TG_OP = 'UPDATE'
     AND NEW.surname        IS NOT DISTINCT FROM OLD.surname
     AND NEW.first_name     IS NOT DISTINCT FROM OLD.first_name
     AND NEW.middle_initial IS NOT DISTINCT FROM OLD.middle_initial
     AND NEW.suffix         IS NOT DISTINCT FROM OLD.suffix THEN
    IF NEW.surname IS NOT NULL
       AND NEW.full_name IS DISTINCT FROM OLD.full_name
       AND NEW.full_name IS DISTINCT FROM
           public.compose_full_name(NEW.first_name, NEW.middle_initial, NEW.surname, NEW.suffix) THEN
      NEW.surname        := NULL;
      NEW.first_name     := NULL;
      NEW.middle_initial := NULL;
      NEW.suffix         := NULL;
    END IF;
    RETURN NEW;
  END IF;

  -- Parts given or changed.
  IF NEW.surname IS NULL AND NEW.first_name IS NULL THEN
    IF NEW.middle_initial IS NOT NULL OR NEW.suffix IS NOT NULL THEN
      RAISE EXCEPTION 'Surname and first name are required when a middle initial or suffix is given.';
    END IF;
    RETURN NEW; -- no parts: an older account, full_name stays as it is
  END IF;
  IF NEW.surname IS NULL THEN
    RAISE EXCEPTION 'Please enter the surname.';
  END IF;
  IF NEW.first_name IS NULL THEN
    RAISE EXCEPTION 'Please enter the first name.';
  END IF;

  NEW.full_name := public.compose_full_name(
    NEW.first_name, NEW.middle_initial, NEW.surname, NEW.suffix
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_information_name_guard ON public.user_information;
CREATE TRIGGER trg_user_information_name_guard
  BEFORE INSERT OR UPDATE ON public.user_information
  FOR EACH ROW EXECUTE FUNCTION public.user_information_name_guard();

-- ════════════════════════════════════════════════════════════
-- 4. register_account — Farmer and Buyer self-registration
--    Same function as before, with the name handling replaced. The old
--    signature is dropped so exactly one version remains.
-- ════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.register_account(
  text, text, text, text, text, date, text, text, text, text
);
-- (re-run safety: also drop the new signature if a previous run created it)
DROP FUNCTION IF EXISTS public.register_account(
  text, text, text, text, text, text, text, text, date, text, text, text, text
);

CREATE FUNCTION public.register_account(
  p_role          text,
  p_surname       text,
  p_first_name    text,
  p_username      text,
  p_middle_initial text DEFAULT NULL,
  p_suffix        text DEFAULT NULL,
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
  v_surname    text;
  v_first      text;
  v_mi         text;
  v_suffix     text;
  v_name       text;
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

  -- Name: surname and first name are required; middle initial and suffix are
  -- optional. Each part is trimmed and checked, and the full name is built from
  -- them here (First M. Surname Suffix). Names are not unique.
  v_surname := public.normalize_name_part(p_surname, 'Surname');
  v_first   := public.normalize_name_part(p_first_name, 'First name');
  v_mi      := public.normalize_middle_initial(p_middle_initial);
  v_suffix  := public.normalize_name_suffix(p_suffix);
  IF v_surname IS NULL THEN
    RAISE EXCEPTION 'Please enter your surname.';
  END IF;
  IF v_first IS NULL THEN
    RAISE EXCEPTION 'Please enter your first name.';
  END IF;
  v_name := public.compose_full_name(v_first, v_mi, v_surname, v_suffix);

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

  INSERT INTO public.user_information (
    user_id, full_name, surname, first_name, middle_initial, suffix,
    phone_number, contact_email, username
  ) VALUES (
    v_uid, v_name, v_surname, v_first, v_mi, v_suffix,
    v_phone, v_email, v_username
  );

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

REVOKE ALL ON FUNCTION public.register_account(
  text, text, text, text, text, text, text, text, date, text, text, text, text
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.register_account(
  text, text, text, text, text, text, text, text, date, text, text, text, text
) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 5. create_farmer_account — Manager-created Farmer
-- ════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.create_farmer_account(
  text, text, text, text, date, text, numeric, numeric, text[], text, integer
);
-- (re-run safety: also drop the new signature if a previous run created it)
DROP FUNCTION IF EXISTS public.create_farmer_account(
  text, text, text, text, text, text, text, date, text, numeric, numeric, text[], text, integer
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
  v_surname  TEXT;
  v_first    TEXT;
  v_mi       TEXT;
  v_suffix   TEXT;
  v_name     TEXT;
  v_email    TEXT;
  v_phone    TEXT;
  v_contact  TEXT := NULLIF(lower(trim(COALESCE(p_contact_email, ''))), '');
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;

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

  INSERT INTO user_information (
    user_id, full_name, surname, first_name, middle_initial, suffix,
    phone_number, username, contact_email
  ) VALUES (
    v_user_id, v_name, v_surname, v_first, v_mi, v_suffix,
    v_phone, v_username, v_contact
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
  text, text, text, text, text, text, text, date, text, numeric, numeric, text[], text, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_farmer_account(
  text, text, text, text, text, text, text, date, text, numeric, numeric, text[], text, integer
) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 6. create_officer_account — Manager-created Officer
-- ════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.create_officer_account(
  text, text, text, date, text, text, text, text, integer
);
-- (re-run safety: also drop the new signature if a previous run created it)
DROP FUNCTION IF EXISTS public.create_officer_account(
  text, text, text, text, text, text, date, text, text, text, text, integer
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
    RAISE EXCEPTION 'Unauthorized: only Managers can create Officer accounts';
  END IF;

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

  -- Manager-created: active at once, forced password change at first login
  -- (same rule as create_farmer_account).
  INSERT INTO user_roles (user_id, role, status, must_change_password)
  VALUES (v_user_id, 'officer', 'active', true);

  INSERT INTO user_information (
    user_id, full_name, surname, first_name, middle_initial, suffix,
    phone_number, username, contact_email
  ) VALUES (
    v_user_id, v_name, v_surname, v_first, v_mi, v_suffix,
    v_phone, v_username, v_contact
  );

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
  text, text, text, text, text, text, date, text, text, text, text, integer
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_officer_account(
  text, text, text, text, text, text, date, text, text, text, text, integer
) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION (run each on its own) ──────────────────────
-- V1. One version of each function, with the new parameters (expect 3 rows, overloads = 1,
--     and every args text contains p_surname and p_first_name):
--   SELECT p.proname, count(*) OVER (PARTITION BY p.proname) AS overloads,
--          pg_get_function_arguments(p.oid) LIKE '%p_surname%'
--            AND pg_get_function_arguments(p.oid) LIKE '%p_first_name%' AS has_name_parts
--   FROM pg_proc p
--   WHERE p.pronamespace = 'public'::regnamespace
--     AND p.proname IN ('register_account', 'create_farmer_account', 'create_officer_account')
--   ORDER BY p.proname;
--
-- V2. Rights are unchanged (expect: register_account  true | false | true, and the same
--     for the other two. A signed-in user can call register_account; anon cannot):
--   SELECT p.proname, p.prosecdef,
--          has_function_privilege('anon', p.oid, 'EXECUTE')          AS anon_can,
--          has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can
--   FROM pg_proc p
--   WHERE p.pronamespace = 'public'::regnamespace
--     AND p.proname IN ('register_account', 'create_farmer_account', 'create_officer_account')
--   ORDER BY p.proname;
--
-- V3. The columns, the CHECK and the trigger exist (expect 4 rows, 1 row, 1 row):
--   SELECT column_name FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'user_information'
--     AND column_name IN ('surname', 'first_name', 'middle_initial', 'suffix') ORDER BY 1;
--   SELECT conname FROM pg_constraint WHERE conname = 'user_information_name_parts_chk';
--   SELECT tgname FROM pg_trigger WHERE tgname = 'trg_user_information_name_guard' AND NOT tgisinternal;
--
-- V4. Existing names were not touched. Every account still has its full_name, and the
--     accounts from before the split have no parts (expect: total = with_full_name;
--     with_parts is 0 until someone registers or you fill parts in below):
--   SELECT count(*) AS total,
--          count(*) FILTER (WHERE full_name IS NOT NULL AND btrim(full_name) <> '') AS with_full_name,
--          count(*) FILTER (WHERE surname IS NOT NULL) AS with_parts
--   FROM public.user_information;
--
-- V5. The full-name format. Expect the rightmost column to read 'ok' on every row:
--   SELECT t.first_name, t.mi, t.surname, t.suffix,
--          public.compose_full_name(t.first_name, public.normalize_middle_initial(t.mi), t.surname, public.normalize_name_suffix(t.suffix)) AS full_name,
--          CASE WHEN public.compose_full_name(t.first_name, public.normalize_middle_initial(t.mi), t.surname, public.normalize_name_suffix(t.suffix)) = t.expected THEN 'ok' ELSE 'WRONG' END AS check
--   FROM (VALUES
--     ('Juan',        NULL,  'Cruz',  NULL,   'Juan Cruz'),
--     ('Juan',        'd',   'Cruz',  NULL,   'Juan D. Cruz'),
--     ('Juan',        'D.',  'Cruz',  'jr',   'Juan D. Cruz Jr.'),
--     ('Marc Louie',  'M',   'Yañez', 'iii',  'Marc Louie M. Yañez III'),
--     ('Maria',       NULL,  'de la Cruz', 'II', 'Maria de la Cruz II')
--   ) AS t(first_name, mi, surname, suffix, expected);
--
-- V6. The rules reject bad input (each statement below must FAIL with the message shown;
--     run them one at a time):
--   SELECT public.normalize_name_part('J0hn', 'First name');   -- First name may contain letters, spaces, hyphens, apostrophes and periods only.
--   SELECT public.normalize_name_part('A', 'Surname');          -- Surname must be 2 to 60 characters.
--   SELECT public.normalize_middle_initial('MA');               -- Middle initial must be a single letter.
--   SELECT public.normalize_middle_initial('1');                -- Middle initial must be a single letter.
--   SELECT public.normalize_name_suffix('Esq');                 -- Please choose a valid suffix (Jr., Sr., II, III, IV or V).
--
-- V7. The trigger, in a transaction that is rolled back (nothing is saved). Replace the uuid
--     with any real user_id from user_information. Expect the three notices below:
--   BEGIN;
--   DO $t$
--   DECLARE v_id uuid := '00000000-0000-0000-0000-000000000000';  -- <-- put a real user_id here
--           r record;
--   BEGIN
--     UPDATE public.user_information SET surname = 'Cruz', first_name = 'Juan', middle_initial = 'd', suffix = 'jr' WHERE user_id = v_id;
--     SELECT full_name, surname, middle_initial, suffix INTO r FROM public.user_information WHERE user_id = v_id;
--     RAISE NOTICE '1) parts -> full_name = %, MI = %, suffix = %  (expect: Juan D. Cruz Jr., D, Jr.)', r.full_name, r.middle_initial, r.suffix;
--     UPDATE public.user_information SET full_name = 'Someone Else' WHERE user_id = v_id;
--     SELECT full_name, surname INTO r FROM public.user_information WHERE user_id = v_id;
--     RAISE NOTICE '2) full_name edited alone -> full_name = %, surname = %  (expect: Someone Else, NULL)', r.full_name, r.surname;
--     BEGIN
--       UPDATE public.user_information SET surname = 'Cruz' WHERE user_id = v_id;
--       RAISE NOTICE '3) surname without first name was ACCEPTED (wrong)';
--     EXCEPTION WHEN others THEN
--       RAISE NOTICE '3) surname without first name rejected: %  (expected)', SQLERRM;
--     END;
--   END $t$;
--   ROLLBACK;
--
-- V8. Every account that has parts has a full_name that matches them (expect 0 rows):
--   SELECT user_id, username, full_name FROM public.user_information
--   WHERE surname IS NOT NULL
--     AND full_name IS DISTINCT FROM public.compose_full_name(first_name, middle_initial, surname, suffix);
--
-- ─── EXISTING ACCOUNTS: REVIEW, AND FILL IN THE PARTS ONLY WHERE SURE ────
-- Optional. Skipping this is fine: accounts without parts work everywhere.
--
-- R1. List accounts that still have only a full name. Read each one and decide the split
--     yourself; "words" is only a hint (a name of 2 words is not automatically
--     first + surname):
--   SELECT ur.role, ui.username, ui.full_name,
--          array_length(string_to_array(btrim(ui.full_name), ' '), 1) AS words
--   FROM public.user_information ui JOIN public.user_roles ur ON ur.user_id = ui.user_id
--   WHERE ui.surname IS NULL
--   ORDER BY ur.role, ui.full_name;
--
-- R2. Fill in the parts for the people you are sure about. The UPDATE only applies when the
--     parts rebuild EXACTLY the name already stored, so a wrong or mistyped row changes
--     nothing instead of changing someone's displayed name. Edit the VALUES list
--     (username, surname, first name, middle initial or NULL, suffix or NULL):
--   UPDATE public.user_information ui
--   SET surname = v.surname, first_name = v.first_name,
--       middle_initial = v.mi, suffix = v.suffix
--   FROM (VALUES
--     ('some.username', 'Cruz', 'Juan', 'D', NULL)
--   ) AS v(username, surname, first_name, mi, suffix)
--   WHERE lower(ui.username) = lower(v.username)
--     AND ui.surname IS NULL
--     AND public.compose_full_name(
--           public.normalize_name_part(v.first_name, 'First name'),
--           public.normalize_middle_initial(v.mi),
--           public.normalize_name_part(v.surname, 'Surname'),
--           public.normalize_name_suffix(v.suffix)) = ui.full_name;
--   -- Then re-run R1: the people you filled in drop out of the list. Anyone whose row
--   -- stayed in the list did not match the stored name; check the spelling or spacing.
