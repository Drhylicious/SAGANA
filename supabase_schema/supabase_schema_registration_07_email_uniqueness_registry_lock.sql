-- ============================================================
-- SAGANA — Registration refactor, step 7: email checks in the database, and
-- the SP3 / Officer registries closed to everyone but a Manager
--
-- Requires steps 1 and 2 (is_valid_email). Run AFTER step 4.
--
-- 1. EMAIL RULES, IN THE DATABASE. Whichever screen or function saves a
--    contact email (registration, Manager-created accounts, Edit Profile, the
--    Pending Applicant screen, any API call), the database now:
--      * trims it, lower-cases it, and treats a blank as "no email";
--      * rejects a badly formed address ("Please enter a valid email address.");
--      * rejects the internal @sagana.local domain;
--      * rejects an address already used by another account, comparing both
--        the contact email and the sign-in email (a unique index is the final
--        guard against two simultaneous saves).
--    WHAT THE DATABASE CANNOT DO: check that the domain can receive mail. That
--    needs a DNS lookup, which a database function cannot make. The app does
--    it (validate-contact Edge Function) before saving, on registration,
--    Edit Profile and the Pending Applicant screen. A person calling the API
--    directly can skip that one check; format and uniqueness cannot be skipped.
--
-- 2. promote_contact_email() (the Edit Profile path that makes a typed email
--    the sign-in email) now uses the same format and uniqueness rules instead
--    of its own looser pattern, and also compares other accounts' contact
--    emails, not only sign-in emails.
--
-- 3. check_email_available() / check_phone_available() ignore the caller's own
--    record, so saving an unchanged email or phone on Edit Profile is not
--    reported as "already used".
--
-- 4. THE REGISTRIES ARE NOT READABLE BY APPS. sp3_member_registry and
--    officer_registry hold names, phone numbers and emails of cooperative
--    members and officers. The oldest policies on them let ANYONE (even signed
--    out, "sp3_registry: public checks name" USING true) or any signed-in user
--    read every row directly through the API, even after the lookup functions
--    were locked in step 2. All existing policies on the two tables are
--    removed and replaced by one: Manager only. No row is touched.
--
-- Not applied automatically. Run the PRE-FLIGHT block, this file, then verify.
-- ============================================================

-- ─── PRE-FLIGHT (read-only — run each by itself) ──────────────────────────
-- A. Step 4 is applied (expect 1 row) — otherwise run step 4 first:
--    SELECT indexname FROM pg_indexes WHERE indexname = 'uq_user_information_phone_normalized';
--
-- B. Emails shared by more than one account (expect ZERO rows). The unique
--    index cannot be built while any exist, and this file stops with an error:
--    SELECT lower(btrim(contact_email)) AS email, count(*) AS accounts,
--           array_agg(user_id) AS user_ids, array_agg(full_name) AS names
--    FROM public.user_information
--    WHERE contact_email IS NOT NULL AND btrim(contact_email) <> ''
--    GROUP BY 1 HAVING count(*) > 1;
--
-- C. Stored emails that would fail the new format check (informational — they
--    are left alone until their owner edits the email):
--    SELECT user_id, full_name, contact_email FROM public.user_information
--    WHERE contact_email IS NOT NULL AND btrim(contact_email) <> ''
--      AND NOT public.is_valid_email(lower(btrim(contact_email)));
--
-- D. Current policies on the two registries (these are all replaced):
--    SELECT tablename, policyname, cmd, roles, qual FROM pg_policies
--    WHERE schemaname='public' AND tablename IN ('sp3_member_registry','officer_registry');
-- ────────────────────────────────────────────────────────────────────────

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. One email, one account
-- ════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.user_information
    WHERE contact_email IS NOT NULL AND btrim(contact_email) <> ''
    GROUP BY lower(btrim(contact_email)) HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION
      'Some email addresses are shared by more than one account. Resolve them first - see PRE-FLIGHT query B at the top of this file.';
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_information_contact_email_ci
  ON public.user_information (lower(btrim(contact_email)))
  WHERE contact_email IS NOT NULL AND btrim(contact_email) <> '';

-- Runs on every insert, and on an update that changes the email. An update
-- that leaves the email alone (last_active_at, name, photo ...) is never
-- blocked by an old, oddly formatted address.
CREATE OR REPLACE FUNCTION public.user_information_email_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v text;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.contact_email IS NOT DISTINCT FROM OLD.contact_email THEN
    RETURN NEW;
  END IF;

  IF NEW.contact_email IS NULL OR btrim(NEW.contact_email) = '' THEN
    NEW.contact_email := NULL;
    RETURN NEW;
  END IF;

  v := lower(btrim(NEW.contact_email));

  IF NOT public.is_valid_email(v) THEN
    RAISE EXCEPTION 'Please enter a valid email address.';
  END IF;
  IF v LIKE '%@sagana.local' THEN
    RAISE EXCEPTION 'This email domain is reserved for internal use.';
  END IF;

  IF EXISTS (
       SELECT 1 FROM public.user_information u
       WHERE u.user_id <> NEW.user_id AND lower(btrim(u.contact_email)) = v
     )
     OR EXISTS (
       SELECT 1 FROM auth.users a
       WHERE a.id <> NEW.user_id AND lower(a.email) = v
     ) THEN
    RAISE EXCEPTION 'This email address is already used by another account.';
  END IF;

  NEW.contact_email := v;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_information_email_guard ON public.user_information;
CREATE TRIGGER trg_user_information_email_guard
  BEFORE INSERT OR UPDATE OF contact_email ON public.user_information
  FOR EACH ROW EXECUTE FUNCTION public.user_information_email_guard();

-- ════════════════════════════════════════════════════════════
-- 2. promote_contact_email — same rules as everywhere else
--    (behavior otherwise unchanged: a real email becomes the sign-in email,
--    a blank reverts to username@sagana.local)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.promote_contact_email(p_email TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_user_id UUID := auth.uid();
  v_new_email TEXT;
  v_username TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT username INTO v_username
  FROM public.user_information
  WHERE user_id = v_user_id;

  IF v_username IS NULL THEN
    RAISE EXCEPTION 'No username on file for this account';
  END IF;

  IF p_email IS NULL OR trim(p_email) = '' THEN
    -- Revert: no real email provided, go back to the synthetic address.
    v_new_email := lower(trim(v_username)) || '@sagana.local';
  ELSE
    v_new_email := lower(trim(p_email));

    IF NOT public.is_valid_email(v_new_email) THEN
      RAISE EXCEPTION 'Please enter a valid email address.';
    END IF;

    IF v_new_email LIKE '%@sagana.local' THEN
      RAISE EXCEPTION 'This email domain is reserved for internal use.';
    END IF;

    IF EXISTS (
         SELECT 1 FROM auth.users WHERE lower(email) = v_new_email AND id <> v_user_id
       )
       OR EXISTS (
         SELECT 1 FROM public.user_information
         WHERE lower(btrim(contact_email)) = v_new_email AND user_id <> v_user_id
       ) THEN
      RAISE EXCEPTION 'This email address is already used by another account.';
    END IF;
  END IF;

  UPDATE auth.users
  SET email = v_new_email, updated_at = NOW()
  WHERE id = v_user_id;

  -- identities.email is a generated column derived from identity_data —
  -- identity_data is what must be written, not the email column directly.
  UPDATE auth.identities
  SET identity_data = identity_data || jsonb_build_object('email', v_new_email),
      updated_at = NOW()
  WHERE user_id = v_user_id AND provider = 'email';

  UPDATE public.user_information
  SET contact_email = CASE WHEN p_email IS NULL OR trim(p_email) = '' THEN NULL ELSE v_new_email END
  WHERE user_id = v_user_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.promote_contact_email(TEXT) TO authenticated;

-- ════════════════════════════════════════════════════════════
-- 3. Availability checks ignore the caller's own record
--    (signed-out callers — registration — have no own record: auth.uid() is
--    NULL, so nothing is excluded for them)
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.check_email_available(p_email text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v text := lower(btrim(coalesce(p_email, '')));
BEGIN
  IF v = '' THEN
    RETURN true;
  END IF;

  RETURN NOT EXISTS (
           SELECT 1 FROM public.user_information ui
           WHERE lower(btrim(ui.contact_email)) = v
             AND ui.user_id IS DISTINCT FROM auth.uid()
         )
     AND NOT EXISTS (
           SELECT 1 FROM auth.users a
           WHERE lower(a.email) = v
             AND a.id IS DISTINCT FROM auth.uid()
         );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.check_email_available(text) TO anon, authenticated;

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
    WHERE user_id IS DISTINCT FROM auth.uid()
      AND (trim(phone_number) = v_raw
           OR (v_norm IS NOT NULL AND public.normalize_ph_mobile(phone_number) = v_norm))
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION public.check_phone_available(text) TO anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 4. Registries: Manager only
-- ════════════════════════════════════════════════════════════

DO $$
DECLARE
  t   text;
  pol record;
BEGIN
  FOREACH t IN ARRAY ARRAY['sp3_member_registry', 'officer_registry']
  LOOP
    IF to_regclass('public.' || t) IS NULL THEN
      CONTINUE;
    END IF;

    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);

    FOR pol IN
      SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = t
    LOOP
      EXECUTE format('DROP POLICY %I ON public.%I', pol.policyname, t);
    END LOOP;

    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR ALL TO authenticated '
      'USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin())',
      t || ': Manager only', t);

    EXECUTE format('REVOKE ALL ON public.%I FROM anon', t);
  END LOOP;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION ────────────────────────────────────────────
-- 1. Index and trigger exist (expect 1 row each):
--    SELECT indexname FROM pg_indexes WHERE indexname = 'uq_user_information_contact_email_ci';
--    SELECT tgname FROM pg_trigger WHERE tgname = 'trg_user_information_email_guard';
--
-- 2. Email rules (rolled back). Use two real accounts. Expect the format
--    error, then the "already used" error:
--    BEGIN;
--      UPDATE public.user_information SET contact_email = 'not-an-email' WHERE user_id = '<account A>';  -- ERROR
--      UPDATE public.user_information SET contact_email = '<account B''s email>' WHERE user_id = '<account A>';  -- ERROR
--    ROLLBACK;
--
-- 3. Registries are closed (expect exactly one policy each, "Manager only"; and
--    anon has no privilege):
--    SELECT tablename, policyname, cmd FROM pg_policies
--    WHERE tablename IN ('sp3_member_registry','officer_registry');
--    SELECT has_table_privilege('anon','public.sp3_member_registry','SELECT');   -- false
--
-- 4. Registry rows untouched (compare with your earlier counts):
--    SELECT (SELECT count(*) FROM public.sp3_member_registry), (SELECT count(*) FROM public.officer_registry);
-- ============================================================
