-- ============================================================
-- SAGANA — Registration refactor, step 1 of 3: foundation
--
-- Adds (nothing is dropped, no row is deleted or changed except the
-- identifier backfill in section 6, which only INSERTs new rows):
--   1. normalize_ph_mobile()   Philippine mobile number normalizer
--   2. is_valid_email()        server-side email format check
--   3. A case-insensitive UNIQUE index on user_information.username
--   4. check_username_available()  callable before sign-in (anon)
--   5. member_identifiers / member_id_counters / member_identifier_history
--      and the backend-only identifier generator
--   6. A one-time, idempotent backfill of identifiers for existing accounts
--   (Changing a membership year is deliberately NOT available to the app: a
--   database administrator does it, see step 4: dba_set_membership_year().)
--
-- Identifier format (per role, per year, own sequence):
--   Farmer  SP3-YYYY-NNN     Officer  OFF-YYYY-NNN     Buyer  BUY-YYYY-NNN
-- NNN is zero-padded to 3 digits and grows past 999 (SP3-2026-1000).
--
-- PREREQUISITES (already part of the repo's final access migration):
--   public.is_staff() and public.is_platform_admin() exist.
--
-- Not applied automatically. Run the PRE-FLIGHT block below first, then run
-- this file in the Supabase SQL editor, then run the verification block at
-- the end. Apply steps 1, 2 and 3 in order.
-- ============================================================

-- ─── PRE-FLIGHT (read-only — run these first, each by itself) ─────────────
-- A. Helper functions this file depends on (expect 2 rows):
--    SELECT proname FROM pg_proc
--    WHERE pronamespace = 'public'::regnamespace
--      AND proname IN ('is_staff', 'is_platform_admin');
--
-- B. Case-insensitive duplicate usernames (expect ZERO rows). If any row
--    appears, resolve it before continuing — the unique index below cannot
--    be created while duplicates exist, and this file stops with an error:
--    SELECT lower(trim(username)) AS username, count(*) AS accounts,
--           array_agg(user_id) AS user_ids
--    FROM public.user_information
--    WHERE username IS NOT NULL AND trim(username) <> ''
--    GROUP BY 1 HAVING count(*) > 1;
--
-- C. How many accounts will receive a backfilled identifier:
--    SELECT role, count(*) FROM public.user_roles
--    WHERE role IN ('farmer', 'officer', 'buyer') GROUP BY role;
-- ────────────────────────────────────────────────────────────────────────

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. Philippine mobile number normalizer
--    Accepts 09XXXXXXXXX, +639XXXXXXXXX and 639XXXXXXXXX (spaces, dashes,
--    dots and brackets are ignored). Returns the canonical local form
--    09XXXXXXXXX — the form already stored by existing accounts — or NULL
--    when the input is not a valid Philippine mobile number.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.normalize_ph_mobile(p_phone text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v text := regexp_replace(coalesce(p_phone, ''), '[\s\-\(\)\.]', '', 'g');
BEGIN
  IF v = '' THEN
    RETURN NULL;
  ELSIF v ~ '^\+639\d{9}$' THEN
    RETURN '0' || substr(v, 4);
  ELSIF v ~ '^639\d{9}$' THEN
    RETURN '0' || substr(v, 3);
  ELSIF v ~ '^09\d{9}$' THEN
    RETURN v;
  END IF;
  RETURN NULL;
END;
$$;

-- ════════════════════════════════════════════════════════════
-- 2. Email format check (syntax + a well-formed domain with a letter TLD)
--    Format only. A well-formed address is NOT proof the person owns it.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.is_valid_email(p_email text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT p_email IS NOT NULL
     AND length(p_email) <= 254
     AND p_email !~ '\.\.'
     AND p_email ~* '^[a-z0-9.!#$%&''*+/=?^_`{|}~-]+@[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\.[a-z]{2,}$';
$$;

-- ════════════════════════════════════════════════════════════
-- 3. Username uniqueness — case-insensitive, enforced by the database
--    (the older UNIQUE constraint is case-sensitive). Usernames are stored
--    lower-cased and trimmed by every account-creation function.
--    The format rule (^[a-z0-9._-]{3,30}$) is enforced inside the creating
--    functions, not as a table CHECK, so legacy usernames stay untouched.
-- ════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.user_information
    WHERE username IS NOT NULL AND trim(username) <> ''
    GROUP BY lower(trim(username)) HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION
      'Duplicate usernames exist (case-insensitive). Resolve them first - see PRE-FLIGHT query B at the top of this file.';
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_information_username_ci
  ON public.user_information (lower(trim(username)))
  WHERE username IS NOT NULL AND trim(username) <> '';

-- ════════════════════════════════════════════════════════════
-- 4. Username availability — callable before sign-in
--    (the old client check read user_information directly; RLS hides every
--    row from an anonymous caller, so it always answered "available").
--    Returns 'available' | 'taken' | 'invalid'.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.check_username_available(p_username text)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v text := lower(trim(coalesce(p_username, '')));
BEGIN
  IF v !~ '^[a-z0-9._-]{3,30}$' THEN
    RETURN 'invalid';
  END IF;
  IF EXISTS (SELECT 1 FROM public.user_information WHERE lower(trim(username)) = v) THEN
    RETURN 'taken';
  END IF;
  -- A leftover sign-in identity with this username also blocks it.
  IF EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = v || '@sagana.local') THEN
    RETURN 'taken';
  END IF;
  RETURN 'available';
END;
$$;

REVOKE ALL ON FUNCTION public.check_username_available(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.check_username_available(text) TO anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 5. Human-readable identifiers
--    Separate from the UUID keys, which stay the primary keys everywhere.
--    Clients can READ their own row (staff read all) and can never write:
--    there is no INSERT/UPDATE/DELETE policy, only the functions below.
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.member_id_counters (
  role     TEXT    NOT NULL CHECK (role IN ('farmer', 'officer', 'buyer')),
  year     INTEGER NOT NULL CHECK (year BETWEEN 1900 AND 2200),
  last_seq INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (role, year)
);

CREATE TABLE IF NOT EXISTS public.member_identifiers (
  user_id         UUID        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  role            TEXT        NOT NULL CHECK (role IN ('farmer', 'officer', 'buyer')),
  member_code     TEXT        NOT NULL UNIQUE,
  membership_year INTEGER     NOT NULL CHECK (membership_year BETWEEN 1900 AND 2200),
  sequence_no     INTEGER     NOT NULL CHECK (sequence_no > 0),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (role, membership_year, sequence_no)
);

CREATE TABLE IF NOT EXISTS public.member_identifier_history (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  old_code   TEXT        NOT NULL,
  new_code   TEXT        NOT NULL,
  changed_by UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  reason     TEXT,
  changed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.member_id_counters        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_identifiers        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_identifier_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "member_identifiers: read own or staff" ON public.member_identifiers;
CREATE POLICY "member_identifiers: read own or staff"
  ON public.member_identifiers FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_staff());

DROP POLICY IF EXISTS "member_identifier_history: admin reads" ON public.member_identifier_history;
CREATE POLICY "member_identifier_history: admin reads"
  ON public.member_identifier_history FOR SELECT TO authenticated
  USING (public.is_platform_admin());

-- member_id_counters: RLS on, no policy — reachable only through the
-- SECURITY DEFINER functions below.

-- Issues the next identifier for (role, year). INTERNAL: other SECURITY
-- DEFINER functions call it; no client may. The counter row is locked by the
-- ON CONFLICT upsert, so simultaneous registrations are serialized per
-- (role, year) and can never receive the same number. The counter only ever
-- moves forward, so a number is never issued twice, even after an account is
-- deleted. Idempotent: an account that already has an identifier keeps it.
CREATE OR REPLACE FUNCTION public.issue_member_identifier(
  p_user_id uuid,
  p_role    text,
  p_year    integer DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_year integer := EXTRACT(YEAR FROM (now() AT TIME ZONE 'Asia/Manila'))::integer;
  v_year         integer := COALESCE(p_year, v_current_year);
  v_prefix       text;
  v_seq          integer;
  v_code         text;
  v_existing     text;
BEGIN
  v_prefix := CASE p_role
                WHEN 'farmer'  THEN 'SP3'
                WHEN 'officer' THEN 'OFF'
                WHEN 'buyer'   THEN 'BUY'
              END;
  IF v_prefix IS NULL THEN
    RAISE EXCEPTION 'No identifier is issued for role %', p_role;
  END IF;
  IF v_year < 1900 OR v_year > v_current_year THEN
    RAISE EXCEPTION 'Membership year must be between 1900 and %', v_current_year;
  END IF;

  SELECT member_code INTO v_existing
  FROM public.member_identifiers WHERE user_id = p_user_id;
  IF v_existing IS NOT NULL THEN
    RETURN v_existing;
  END IF;

  INSERT INTO public.member_id_counters (role, year, last_seq)
  VALUES (p_role, v_year, 1)
  ON CONFLICT (role, year)
  DO UPDATE SET last_seq = public.member_id_counters.last_seq + 1
  RETURNING last_seq INTO v_seq;

  v_code := v_prefix || '-' || v_year || '-' ||
            CASE WHEN v_seq < 1000 THEN lpad(v_seq::text, 3, '0') ELSE v_seq::text END;

  INSERT INTO public.member_identifiers (user_id, role, member_code, membership_year, sequence_no)
  VALUES (p_user_id, p_role, v_code, v_year, v_seq);

  RETURN v_code;
END;
$$;

REVOKE ALL ON FUNCTION public.issue_member_identifier(uuid, text, integer)
  FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 6. Backfill — existing accounts that have no identifier yet.
--    Year = the year the account was created (the real cooperative
--    membership year is not recorded anywhere); it can be corrected
--    afterwards with dba_set_membership_year() (step 4, database administrators only). Oldest accounts get the
--    lowest numbers. Idempotent: accounts that already have one are skipped.
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT ur.user_id, ur.role,
           EXTRACT(YEAR FROM (ur.created_at AT TIME ZONE 'Asia/Manila'))::integer AS yr
    FROM public.user_roles ur
    LEFT JOIN public.member_identifiers mi ON mi.user_id = ur.user_id
    WHERE ur.role IN ('farmer', 'officer', 'buyer')
      AND mi.user_id IS NULL
    ORDER BY ur.created_at, ur.user_id
  LOOP
    PERFORM public.issue_member_identifier(r.user_id, r.role, r.yr);
  END LOOP;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION (read-only) ────────────────────────────────
-- 1. Phone normalizer (expect 09171234567 three times, then NULL twice):
--    SELECT public.normalize_ph_mobile('09171234567'),
--           public.normalize_ph_mobile('+639171234567'),
--           public.normalize_ph_mobile('+63 917 123 4567'),
--           public.normalize_ph_mobile('0817123456'),
--           public.normalize_ph_mobile('12345');
--
-- 2. Email check (expect true, false, false, false):
--    SELECT public.is_valid_email('example@gmail.com'),
--           public.is_valid_email('examplegmail.com'),
--           public.is_valid_email('a@b'),
--           public.is_valid_email('a@b..com');
--
-- 3. Username check (expect invalid, then available for an unused name):
--    SELECT public.check_username_available('ab'),
--           public.check_username_available('some.unused.name');
--
-- 4. Unique index exists (expect 1 row):
--    SELECT indexname FROM pg_indexes
--    WHERE indexname = 'uq_user_information_username_ci';
--
-- 5. Every farmer / officer / buyer now has an identifier (expect 0 rows):
--    SELECT ur.user_id, ur.role FROM public.user_roles ur
--    LEFT JOIN public.member_identifiers mi ON mi.user_id = ur.user_id
--    WHERE ur.role IN ('farmer', 'officer', 'buyer') AND mi.user_id IS NULL;
--
-- 6. Identifiers per role and year, with the counter agreeing
--    (expect max_seq = counter_last_seq on every row):
--    SELECT mi.role, mi.membership_year, count(*) AS issued,
--           max(mi.sequence_no) AS max_seq, c.last_seq AS counter_last_seq
--    FROM public.member_identifiers mi
--    JOIN public.member_id_counters c
--      ON c.role = mi.role AND c.year = mi.membership_year
--    GROUP BY mi.role, mi.membership_year, c.last_seq
--    ORDER BY mi.role, mi.membership_year;
--
-- 7. Clients cannot write identifiers (expect no INSERT/UPDATE/DELETE policy):
--    SELECT policyname, cmd FROM pg_policies
--    WHERE tablename IN ('member_identifiers', 'member_id_counters');
--
-- 8. Sample of codes (format SP3-YYYY-NNN / OFF-YYYY-NNN / BUY-YYYY-NNN):
--    SELECT role, member_code, membership_year FROM public.member_identifiers
--    ORDER BY role, membership_year, sequence_no LIMIT 20;
-- ============================================================
