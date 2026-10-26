-- ============================================================
-- supabase_schema_registration_20_change_email_pending.sql
--
-- Lets a Manager or Officer CHANGE their email in Edit Profile, safely.
--
-- THE RULE: a new address is only ever a CANDIDATE ("pending") until its owner
-- types back the 6-digit code that was e-mailed to it. Until then the current
-- email stays exactly as it is (and so does the verified one on record). Only a
-- correct code makes the new address the account's email.
--
--   Officer  the contact email changes. The sign-in address (OFF-XXXX@sagana.local)
--            is never touched.
--   Manager  the email IS the sign-in address (and where recovery codes go), so a
--            verified change switches the sign-in email too, in one step. They log
--            in with the new address from then on. The change also needs the
--            Manager's current password (checked by the Edge Function), so a
--            borrowed session alone cannot redirect the account.
--
-- Run after scripts 18 (and 19 if you have run it). Safe to re-run.
-- Farmers and Buyers are not affected: their Edit Profile keeps working as it did.
-- ============================================================

BEGIN;

ALTER TABLE public.user_information
  ADD COLUMN IF NOT EXISTS pending_contact_email text;
COMMENT ON COLUMN public.user_information.pending_contact_email IS
  'A new email the person has asked to switch to. It becomes their email only after the code sent to it is entered. Written only by set_pending_contact_email().';

-- The lock from script 18 now also covers the pending column: it is written only
-- by set_pending_contact_email() and verify_contact_email().
CREATE OR REPLACE FUNCTION public.user_information_verified_email_guard()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF coalesce(current_setting('sagana.contact_email_verify', true), '') = 'on' THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' THEN
    IF NEW.verified_contact_email IS NOT NULL
       OR NEW.contact_email_verified_at IS NOT NULL
       OR NEW.pending_contact_email IS NOT NULL THEN
      RAISE EXCEPTION 'Email verification can only be recorded by the verification process.';
    END IF;
  ELSIF NEW.verified_contact_email IS DISTINCT FROM OLD.verified_contact_email
     OR NEW.contact_email_verified_at IS DISTINCT FROM OLD.contact_email_verified_at
     OR NEW.pending_contact_email IS DISTINCT FROM OLD.pending_contact_email THEN
    RAISE EXCEPTION 'Email verification can only be recorded by the verification process.';
  END IF;
  RETURN NEW;
END;
$$;

-- The address a code is for: the pending one if there is one, else the email in use.
CREATE OR REPLACE FUNCTION public.verification_target_email(p_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT coalesce(
           nullif(lower(btrim(ui.pending_contact_email)), ''),
           public.effective_contact_email(p_user_id))
  FROM public.user_information ui
  WHERE ui.user_id = p_user_id;
$$;

REVOKE ALL ON FUNCTION public.verification_target_email(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.verification_target_email(uuid) TO service_role;

-- Must a password be shown before a code is sent? Yes when a Manager is about to
-- change the address they SIGN IN with. (The Edge Function checks the password.)
CREATE OR REPLACE FUNCTION public.email_change_needs_password(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT coalesce((
    SELECT EXISTS (SELECT 1 FROM public.user_roles r WHERE r.user_id = p_user_id AND r.role = 'admin')
       AND nullif(btrim(ui.pending_contact_email), '') IS NOT NULL
       AND lower(btrim(ui.pending_contact_email)) IS DISTINCT FROM lower(u.email)
    FROM public.user_information ui
    JOIN auth.users u ON u.id = ui.user_id
    WHERE ui.user_id = p_user_id
  ), false);
$$;

REVOKE ALL ON FUNCTION public.email_change_needs_password(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.email_change_needs_password(uuid) TO service_role;

-- ════════════════════════════════════════════════════════════
-- set_pending_contact_email — the signed-in person names the address they want.
-- Nothing about their current email changes here.
--   pending | cleared | invalid_format | reserved | in_use | not_signed_in
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.set_pending_contact_email(p_email text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid     uuid := auth.uid();
  v         text := lower(btrim(coalesce(p_email, '')));
  v_current text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('status', 'not_signed_in');
  END IF;

  v_current := public.effective_contact_email(v_uid);

  -- Blank, or the address already in use: nothing is pending any more.
  IF v = '' OR v = v_current THEN
    PERFORM set_config('sagana.contact_email_verify', 'on', true);
    UPDATE public.user_information SET pending_contact_email = NULL WHERE user_id = v_uid;
    PERFORM set_config('sagana.contact_email_verify', 'off', true);
    DELETE FROM public.contact_email_codes
    WHERE user_id = v_uid AND email IS DISTINCT FROM v_current;
    RETURN jsonb_build_object('status', 'cleared');
  END IF;

  IF NOT public.is_valid_email(v) THEN
    RETURN jsonb_build_object('status', 'invalid_format');
  END IF;
  IF v LIKE '%@sagana.local' THEN
    RETURN jsonb_build_object('status', 'reserved');
  END IF;

  -- One email, one account.
  IF EXISTS (SELECT 1 FROM auth.users a WHERE a.id <> v_uid AND lower(a.email) = v)
     OR EXISTS (SELECT 1 FROM public.user_information u
                WHERE u.user_id <> v_uid AND lower(btrim(u.contact_email)) = v) THEN
    RETURN jsonb_build_object('status', 'in_use');
  END IF;

  PERFORM set_config('sagana.contact_email_verify', 'on', true);
  UPDATE public.user_information SET pending_contact_email = v WHERE user_id = v_uid;
  PERFORM set_config('sagana.contact_email_verify', 'off', true);

  -- A code sent for some other address no longer applies.
  DELETE FROM public.contact_email_codes WHERE user_id = v_uid AND email IS DISTINCT FROM v;
  RETURN jsonb_build_object('status', 'pending', 'email', v);
END;
$$;

REVOKE ALL ON FUNCTION public.set_pending_contact_email(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.set_pending_contact_email(text) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- issue_contact_email_code — as in script 18, but the code goes to the PENDING
-- address when there is one.
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.issue_contact_email_code(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_pending text;
  v_email   text;
  v_now     timestamptz := now();
  r         public.contact_email_codes%ROWTYPE;
  v_code    text;
  v_hash    text;
  v_wait    integer;
BEGIN
  SELECT nullif(lower(btrim(pending_contact_email)), '') INTO v_pending
  FROM public.user_information WHERE user_id = p_user_id;
  v_email := coalesce(v_pending, public.effective_contact_email(p_user_id));
  IF v_email IS NULL THEN
    RETURN jsonb_build_object('status', 'no_email');
  END IF;

  -- (A pending address is a change in progress: it is never "already verified".)
  IF v_pending IS NULL AND EXISTS (
    SELECT 1 FROM public.user_information
    WHERE user_id = p_user_id AND lower(btrim(verified_contact_email)) = v_email
  ) THEN
    RETURN jsonb_build_object('status', 'already_verified');
  END IF;

  SELECT * INTO r FROM public.contact_email_codes WHERE user_id = p_user_id FOR UPDATE;
  IF FOUND THEN
    IF r.last_sent_at > v_now - interval '60 seconds' THEN
      v_wait := ceil(extract(epoch FROM (r.last_sent_at + interval '60 seconds' - v_now)))::int;
      RETURN jsonb_build_object('status', 'cooldown', 'retry_after', v_wait);
    END IF;
    IF r.hour_started_at > v_now - interval '1 hour' AND r.sends_in_hour >= 5 THEN
      v_wait := ceil(extract(epoch FROM (r.hour_started_at + interval '1 hour' - v_now)))::int;
      RETURN jsonb_build_object('status', 'limit', 'retry_after', v_wait);
    END IF;
    IF r.day_started_at > v_now - interval '1 day' AND r.sends_in_day >= 10 THEN
      v_wait := ceil(extract(epoch FROM (r.day_started_at + interval '1 day' - v_now)))::int;
      RETURN jsonb_build_object('status', 'limit', 'retry_after', v_wait);
    END IF;
  END IF;

  v_code := lpad(
    ((('x' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))::bit(32)::bigint) % 1000000)::text,
    6, '0');
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

-- ════════════════════════════════════════════════════════════
-- verify_contact_email — as in script 18, plus: a correct code for a PENDING
-- address makes it the account's email.
--   verified | invalid_code | expired | too_many_attempts | no_code |
--   email_changed | email_in_use | invalid_format | not_signed_in
--   'verified' also says whether the SIGN-IN email changed (signin_changed).
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
  v_target  text;
  v_pending text;
  v_hash    text;
  v_admin   boolean;
  v_old     text;
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

  -- The address the person is working on changed after the code was sent.
  v_target := public.verification_target_email(v_uid);
  IF v_target IS DISTINCT FROM r.email THEN
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

  -- Right code.
  SELECT nullif(lower(btrim(pending_contact_email)), '') INTO v_pending
  FROM public.user_information WHERE user_id = v_uid;

  PERFORM set_config('sagana.contact_email_verify', 'on', true);

  IF v_pending IS NOT NULL AND v_pending = r.email THEN
    -- A change of address, now proven: someone else may have taken it meanwhile.
    IF EXISTS (SELECT 1 FROM auth.users a WHERE a.id <> v_uid AND lower(a.email) = r.email)
       OR EXISTS (SELECT 1 FROM public.user_information u
                  WHERE u.user_id <> v_uid AND lower(btrim(u.contact_email)) = r.email) THEN
      PERFORM set_config('sagana.contact_email_verify', 'off', true);
      DELETE FROM public.contact_email_codes WHERE user_id = v_uid;
      RETURN jsonb_build_object('status', 'email_in_use');
    END IF;

    v_admin := EXISTS (SELECT 1 FROM public.user_roles WHERE user_id = v_uid AND role = 'admin');
    SELECT lower(email) INTO v_old FROM auth.users WHERE id = v_uid;

    IF v_admin THEN
      -- The Manager signs in with this address: switch it, and its identity row,
      -- in the same step as the proof.
      UPDATE auth.users SET email = r.email, updated_at = now() WHERE id = v_uid;
      UPDATE auth.identities
      SET identity_data = identity_data || jsonb_build_object('email', r.email),
          updated_at = now()
      WHERE user_id = v_uid AND provider = 'email';
    END IF;

    UPDATE public.user_information
    SET contact_email             = r.email,
        pending_contact_email     = NULL,
        verified_contact_email    = r.email,
        contact_email_verified_at = now()
    WHERE user_id = v_uid;

    PERFORM set_config('sagana.contact_email_verify', 'off', true);
    DELETE FROM public.contact_email_codes WHERE user_id = v_uid;
    RETURN jsonb_build_object(
      'status', 'verified',
      'signin_changed', v_admin AND v_old IS DISTINCT FROM r.email);
  END IF;

  -- The address already in use: record the proof (as in script 18).
  UPDATE public.user_information
  SET verified_contact_email    = r.email,
      contact_email_verified_at = now()
  WHERE user_id = v_uid;
  PERFORM set_config('sagana.contact_email_verify', 'off', true);

  DELETE FROM public.contact_email_codes WHERE user_id = v_uid;
  RETURN jsonb_build_object('status', 'verified', 'signin_changed', false);
END;
$$;

REVOKE ALL ON FUNCTION public.verify_contact_email(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.verify_contact_email(text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';


-- ============================================================
-- BLOCK 1 — CHECK the install (read-only). Run on its own. Every row PASS.
-- ============================================================

SELECT 'pending column exists' AS check_name,
       CASE WHEN EXISTS (SELECT 1 FROM information_schema.columns
                         WHERE table_schema = 'public' AND table_name = 'user_information'
                           AND column_name = 'pending_contact_email')
            THEN 'PASS' ELSE 'FAIL' END AS result
UNION ALL
SELECT 'pending column is locked (only the two functions write it)',
       CASE WHEN (SELECT prosrc FROM pg_proc WHERE proname = 'user_information_verified_email_guard' LIMIT 1)
                 LIKE '%pending_contact_email%'
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'signed-in users can name a new address; signed-out users cannot',
       CASE WHEN has_function_privilege('authenticated', 'public.set_pending_contact_email(text)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.set_pending_contact_email(text)', 'EXECUTE')
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'only the Edge Function (service role) can issue a code',
       CASE WHEN has_function_privilege('service_role', 'public.issue_contact_email_code(uuid)', 'EXECUTE')
             AND NOT has_function_privilege('authenticated', 'public.issue_contact_email_code(uuid)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.issue_contact_email_code(uuid)', 'EXECUTE')
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'the password rule is server-only',
       CASE WHEN has_function_privilege('service_role', 'public.email_change_needs_password(uuid)', 'EXECUTE')
             AND NOT has_function_privilege('authenticated', 'public.email_change_needs_password(uuid)', 'EXECUTE')
            THEN 'PASS' ELSE 'FAIL' END
UNION ALL
SELECT 'signed-in users can check a code; signed-out users cannot',
       CASE WHEN has_function_privilege('authenticated', 'public.verify_contact_email(text)', 'EXECUTE')
             AND NOT has_function_privilege('anon', 'public.verify_contact_email(text)', 'EXECUTE')
            THEN 'PASS' ELSE 'FAIL' END;
