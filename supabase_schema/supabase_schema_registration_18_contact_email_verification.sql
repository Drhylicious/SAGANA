-- ============================================================
-- supabase_schema_registration_18_contact_email_verification.sql
--
-- Email VERIFICATION for the contact email of every role (Manager, Officer,
-- Farmer, Buyer): a person proves they own the address by typing back a 6-digit
-- code that was e-mailed to it.
--
-- Run after script 12. Safe to re-run. Nothing here changes who can sign in.
--
-- WHY A SEPARATE VERIFICATION, NOT SUPABASE'S BUILT-IN "CHANGE EMAIL"
--   Supabase Auth's own verification works by changing the account's SIGN-IN
--   email. That does not fit SAGANA:
--     * Officers must keep a generated OFF-XXXX@sagana.local sign-in address (the
--       app signs an Officer out if the sign-in email is a real address).
--     * The Manager's sign-in email is a real address and is locked in Edit
--       Profile; changing it is not what "verify my email" means.
--     * A Farmer's/Buyer's saved email is ALREADY copied into the sign-in email
--       (promote_contact_email), so there is no "change" left for Supabase to
--       confirm, and its secure-email-change step would need an answer from the
--       generated address, which cannot receive mail.
--   So the proof of ownership is kept next to the contact email, and this does
--   not touch sign-in, password recovery or auth.users in any way.
--
-- HOW IT WORKS
--   * user_information gets verified_contact_email + contact_email_verified_at.
--     An address counts as VERIFIED only while it equals verified_contact_email.
--     Change the address and it is Unverified again, automatically; the earlier
--     verified address stays on record until a new one is confirmed.
--   * Nobody can write those two columns from the app (a trigger refuses it).
--     They are written only by verify_contact_email(), after the right code.
--   * The code is made and hashed in the database; the plain code is handed only
--     to the send-email-verification Edge Function (service role), which e-mails
--     it. The app never receives the code. 10 minutes to use it, 5 tries, one
--     send per minute, 5 per hour, 10 per day, per account.
--
-- WHO COUNTS AS "THE EMAIL" FOR AN ACCOUNT (effective_contact_email)
--     the contact email, else the sign-in email when it is a real address.
--   (The Manager has no separate contact email: the sign-in email is it.)
--
-- EXISTING ACCOUNTS: every address starts Unverified. Nothing is marked verified
-- automatically (auth.users.email_confirmed_at is NOT proof: SAGANA creates
-- accounts already confirmed). See the diagnostic in BLOCK 3.
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. Columns, and a lock on them
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.user_information
  ADD COLUMN IF NOT EXISTS verified_contact_email    text,
  ADD COLUMN IF NOT EXISTS contact_email_verified_at timestamptz;

COMMENT ON COLUMN public.user_information.verified_contact_email    IS 'The last email address whose ownership was proven with a code. The address is Verified only while it equals the current contact email.';
COMMENT ON COLUMN public.user_information.contact_email_verified_at IS 'When verified_contact_email was proven.';

ALTER TABLE public.user_information DROP CONSTRAINT IF EXISTS user_information_email_verified_chk;
ALTER TABLE public.user_information
  ADD CONSTRAINT user_information_email_verified_chk
  CHECK ((verified_contact_email IS NULL) = (contact_email_verified_at IS NULL));

-- Only verify_contact_email() (and an explicit, deliberate admin fix, see BLOCK 3)
-- may write the two columns. Any other write, including a person editing their
-- own row through the API, is refused, so verification cannot be forged.
CREATE OR REPLACE FUNCTION public.user_information_verified_email_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF coalesce(current_setting('sagana.contact_email_verify', true), '') = 'on' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.verified_contact_email IS NOT NULL OR NEW.contact_email_verified_at IS NOT NULL THEN
      RAISE EXCEPTION 'Email verification can only be recorded by the verification process.';
    END IF;
  ELSIF NEW.verified_contact_email IS DISTINCT FROM OLD.verified_contact_email
     OR NEW.contact_email_verified_at IS DISTINCT FROM OLD.contact_email_verified_at THEN
    RAISE EXCEPTION 'Email verification can only be recorded by the verification process.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_information_verified_email_guard ON public.user_information;
CREATE TRIGGER trg_user_information_verified_email_guard
  BEFORE INSERT OR UPDATE ON public.user_information
  FOR EACH ROW EXECUTE FUNCTION public.user_information_verified_email_guard();

-- ════════════════════════════════════════════════════════════
-- 2. The pending codes (no one can read or write this table directly)
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.contact_email_codes (
  user_id           uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email             text        NOT NULL,
  code_hash         text        NOT NULL,
  expires_at        timestamptz NOT NULL,
  attempts          integer     NOT NULL DEFAULT 0,
  last_sent_at      timestamptz NOT NULL DEFAULT now(),
  hour_started_at   timestamptz NOT NULL DEFAULT now(),
  sends_in_hour     integer     NOT NULL DEFAULT 1,
  day_started_at    timestamptz NOT NULL DEFAULT now(),
  sends_in_day      integer     NOT NULL DEFAULT 1
);

ALTER TABLE public.contact_email_codes ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: with row level security on and no policy, the API
-- roles can neither read nor write a row. Only the functions below can.
REVOKE ALL ON public.contact_email_codes FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 3. effective_contact_email: the address a person's verification is about
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.effective_contact_email(p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT coalesce(
           nullif(lower(btrim(ui.contact_email)), ''),
           CASE WHEN u.email IS NOT NULL AND lower(u.email) NOT LIKE '%@sagana.local'
                THEN lower(btrim(u.email)) END
         )
  FROM public.user_information ui
  JOIN auth.users u ON u.id = ui.user_id
  WHERE ui.user_id = p_user_id;
$$;

REVOKE ALL ON FUNCTION public.effective_contact_email(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.effective_contact_email(uuid) TO service_role;

-- ════════════════════════════════════════════════════════════
-- 4. issue_contact_email_code — called ONLY by the Edge Function (service role)
--    Returns jsonb. The plain code is in the result only when status = 'sent',
--    and only the Edge Function ever sees it.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.issue_contact_email_code(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_email text;
  v_now   timestamptz := now();
  r       public.contact_email_codes%ROWTYPE;
  v_code  text;
  v_hash  text;
  v_wait  integer;
BEGIN
  v_email := public.effective_contact_email(p_user_id);
  IF v_email IS NULL THEN
    RETURN jsonb_build_object('status', 'no_email');
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_information
    WHERE user_id = p_user_id AND lower(btrim(verified_contact_email)) = v_email
  ) THEN
    RETURN jsonb_build_object('status', 'already_verified');
  END IF;

  SELECT * INTO r FROM public.contact_email_codes WHERE user_id = p_user_id FOR UPDATE;
  IF FOUND THEN
    -- One code per minute.
    IF r.last_sent_at > v_now - interval '60 seconds' THEN
      v_wait := ceil(extract(epoch FROM (r.last_sent_at + interval '60 seconds' - v_now)))::int;
      RETURN jsonb_build_object('status', 'cooldown', 'retry_after', v_wait);
    END IF;
    -- At most 5 an hour, 10 a day.
    IF r.hour_started_at > v_now - interval '1 hour' AND r.sends_in_hour >= 5 THEN
      v_wait := ceil(extract(epoch FROM (r.hour_started_at + interval '1 hour' - v_now)))::int;
      RETURN jsonb_build_object('status', 'limit', 'retry_after', v_wait);
    END IF;
    IF r.day_started_at > v_now - interval '1 day' AND r.sends_in_day >= 10 THEN
      v_wait := ceil(extract(epoch FROM (r.day_started_at + interval '1 day' - v_now)))::int;
      RETURN jsonb_build_object('status', 'limit', 'retry_after', v_wait);
    END IF;
  END IF;

  -- Six digits from the database's secure random source.
  v_code := lpad(
    ((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint) % 1000000)::text,
    6, '0');
  -- Stored hashed, tied to this account and this address.
  v_hash := encode(sha256(convert_to(v_code || ':' || p_user_id::text || ':' || v_email, 'UTF8')), 'hex');

  INSERT INTO public.contact_email_codes AS c
    (user_id, email, code_hash, expires_at, attempts, last_sent_at,
     hour_started_at, sends_in_hour, day_started_at, sends_in_day)
  VALUES
    (p_user_id, v_email, v_hash, v_now + interval '10 minutes', 0, v_now,
     v_now, 1, v_now, 1)
  ON CONFLICT (user_id) DO UPDATE SET
    email         = EXCLUDED.email,
    code_hash     = EXCLUDED.code_hash,
    expires_at    = EXCLUDED.expires_at,
    attempts      = 0,
    last_sent_at  = EXCLUDED.last_sent_at,
    hour_started_at = CASE WHEN c.hour_started_at > v_now - interval '1 hour'
                           THEN c.hour_started_at ELSE EXCLUDED.hour_started_at END,
    sends_in_hour = CASE WHEN c.hour_started_at > v_now - interval '1 hour'
                         THEN c.sends_in_hour + 1 ELSE 1 END,
    day_started_at = CASE WHEN c.day_started_at > v_now - interval '1 day'
                          THEN c.day_started_at ELSE EXCLUDED.day_started_at END,
    sends_in_day  = CASE WHEN c.day_started_at > v_now - interval '1 day'
                         THEN c.sends_in_day + 1 ELSE 1 END;

  RETURN jsonb_build_object(
    'status', 'sent', 'email', v_email, 'code', v_code,
    'expires_in', 600, 'resend_after', 60);
END;
$$;

REVOKE ALL ON FUNCTION public.issue_contact_email_code(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.issue_contact_email_code(uuid) TO service_role;

-- If the e-mail could not be sent, the code is useless and must not count
-- against the person: void it and give the send back.
CREATE OR REPLACE FUNCTION public.release_contact_email_code(p_user_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.contact_email_codes
  SET expires_at    = now(),
      last_sent_at  = now() - interval '1 day',
      sends_in_hour = greatest(sends_in_hour - 1, 0),
      sends_in_day  = greatest(sends_in_day - 1, 0)
  WHERE user_id = p_user_id;
$$;

REVOKE ALL ON FUNCTION public.release_contact_email_code(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.release_contact_email_code(uuid) TO service_role;

-- ════════════════════════════════════════════════════════════
-- 5. verify_contact_email — called by the signed-in person
--    Returns jsonb {status, attempts_left?}. Wrong guesses are COUNTED (the
--    function returns normally, so the count is kept).
--      verified | invalid_code | expired | too_many_attempts | no_code |
--      email_changed | invalid_format | not_signed_in
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.verify_contact_email(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v_code    text := btrim(coalesce(p_code, ''));
  r         public.contact_email_codes%ROWTYPE;
  v_current text;
  v_hash    text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('status', 'not_signed_in');
  END IF;
  IF v_code !~ '^[0-9]{6}$' THEN
    RETURN jsonb_build_object('status', 'invalid_format');
  END IF;

  SELECT * INTO r FROM public.contact_email_codes WHERE user_id = v_uid FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'no_code');
  END IF;

  IF r.expires_at <= now() THEN
    DELETE FROM public.contact_email_codes WHERE user_id = v_uid;
    RETURN jsonb_build_object('status', 'expired');
  END IF;
  IF r.attempts >= 5 THEN
    DELETE FROM public.contact_email_codes WHERE user_id = v_uid;
    RETURN jsonb_build_object('status', 'too_many_attempts');
  END IF;

  -- The address was changed after the code was sent: the code is for another
  -- address and proves nothing about this one.
  v_current := public.effective_contact_email(v_uid);
  IF v_current IS DISTINCT FROM r.email THEN
    DELETE FROM public.contact_email_codes WHERE user_id = v_uid;
    RETURN jsonb_build_object('status', 'email_changed');
  END IF;

  v_hash := encode(sha256(convert_to(v_code || ':' || v_uid::text || ':' || r.email, 'UTF8')), 'hex');
  IF v_hash <> r.code_hash THEN
    IF r.attempts + 1 >= 5 THEN
      DELETE FROM public.contact_email_codes WHERE user_id = v_uid;
      RETURN jsonb_build_object('status', 'too_many_attempts');
    END IF;
    UPDATE public.contact_email_codes SET attempts = attempts + 1 WHERE user_id = v_uid;
    RETURN jsonb_build_object('status', 'invalid_code', 'attempts_left', 5 - (r.attempts + 1));
  END IF;

  -- Right code: record the proof (the one place that may write these columns).
  PERFORM set_config('sagana.contact_email_verify', 'on', true);
  UPDATE public.user_information
  SET verified_contact_email    = r.email,
      contact_email_verified_at = now()
  WHERE user_id = v_uid;
  PERFORM set_config('sagana.contact_email_verify', 'off', true);

  DELETE FROM public.contact_email_codes WHERE user_id = v_uid;
  RETURN jsonb_build_object('status', 'verified');
END;
$$;

REVOKE ALL ON FUNCTION public.verify_contact_email(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_contact_email(text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- BLOCK 1 — CHECK the install (read-only). Select it and run it on its own.
-- Expect every row PASS.
-- ============================================================

SELECT 'columns exist' AS check_name,
       CASE WHEN (SELECT count(*) FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'user_information'
                    AND column_name IN ('verified_contact_email', 'contact_email_verified_at')) = 2
            THEN 'PASS' ELSE 'FAIL' END AS result
UNION ALL
SELECT 'write lock trigger exists',
       CASE WHEN EXISTS (SELECT 1 FROM pg_trigger
                         WHERE tgname = 'trg_user_information_verified_email_guard' AND NOT tgisinternal)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'code table is closed to app users (row level security on)',
       CASE WHEN (SELECT relrowsecurity FROM pg_class WHERE oid = 'public.contact_email_codes'::regclass)
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'code table has no policies (nobody can read or write it directly)',
       CASE WHEN NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname = 'public' AND tablename = 'contact_email_codes')
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'app users cannot touch the code table',
       CASE WHEN NOT has_table_privilege('authenticated', 'public.contact_email_codes', 'SELECT,INSERT,UPDATE,DELETE')
             AND NOT has_table_privilege('anon', 'public.contact_email_codes', 'SELECT,INSERT,UPDATE,DELETE')
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'only the Edge Function (service role) can issue a code',
       CASE WHEN has_function_privilege('service_role', 'public.issue_contact_email_code(uuid)', 'EXECUTE')
             AND NOT has_function_privilege('authenticated', 'public.issue_contact_email_code(uuid)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.issue_contact_email_code(uuid)', 'EXECUTE')
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'signed-in users can check a code; signed-out users cannot',
       CASE WHEN has_function_privilege('authenticated', 'public.verify_contact_email(text)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.verify_contact_email(text)', 'EXECUTE')
            THEN 'PASS' ELSE 'FAIL' END;


-- ============================================================
-- BLOCK 2 — EXISTING ACCOUNTS (read-only). Run on its own.
-- Shows each account's address and its status. Everyone is "Unverified" until
-- they verify in Edit Profile; nothing is marked automatically.
-- ============================================================

SELECT ui.full_name,
       (SELECT string_agg(r.role, ', ') FROM public.user_roles r WHERE r.user_id = ui.user_id) AS roles,
       public.effective_contact_email(ui.user_id)                    AS email,
       CASE WHEN public.effective_contact_email(ui.user_id) IS NULL THEN 'no email'
            WHEN lower(btrim(ui.verified_contact_email)) = public.effective_contact_email(ui.user_id) THEN 'Verified'
            ELSE 'Unverified' END                                    AS status,
       ui.contact_email_verified_at,
       u.email_confirmed_at IS NOT NULL                              AS auth_email_confirmed_by_system
FROM public.user_information ui
JOIN auth.users u ON u.id = ui.user_id
ORDER BY status, ui.full_name;


-- ============================================================
-- BLOCK 3 — MARK ONE ACCOUNT VERIFIED BY HAND (optional; edit before running).
-- Only for an address you know the owner already proved by another means (for
-- example the Manager, who has reset their password through that mailbox).
-- Replace the user id, and only run it for that person. Returns 1 row.
--
--   BEGIN;
--   SELECT set_config('sagana.contact_email_verify', 'on', true);
--   UPDATE public.user_information
--   SET verified_contact_email    = public.effective_contact_email(user_id),
--       contact_email_verified_at = now()
--   WHERE user_id = '<USER ID>'
--     AND public.effective_contact_email(user_id) IS NOT NULL
--   RETURNING full_name, verified_contact_email;
--   COMMIT;
-- ============================================================
