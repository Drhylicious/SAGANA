-- ============================================================
-- SAGANA — Registration refactor, step 4: identifiers (database-only),
-- phone-number uniqueness, and the fixed Farmer address
--
-- Requires steps 1 and 2.
--
-- 1. IDENTIFIERS ARE DATABASE-ONLY. The Member / Officer / Buyer identifiers
--    (SP3-/OFF-/BUY-YYYY-NNN) are not shown or editable anywhere in the app.
--    admin_set_membership_year() (callable by a signed-in Manager in step 1)
--    is dropped. Changing a membership year is now something a database
--    administrator does in the SQL editor, with dba_set_membership_year()
--    below, or by updating member_identifiers directly. Either way, a trigger
--    keeps the identifier consistent and unique:
--      * member_code is always rebuilt from role + membership_year +
--        sequence_no, so the three can never disagree;
--      * the (role, year, sequence) combination and the code are unique;
--      * the yearly counter is moved forward if a sequence number above it is
--        written, and can never be moved backward, so a number is never
--        issued twice;
--      * every change of code is recorded in member_identifier_history.
--
-- 2. PHONE NUMBERS ARE UNIQUE, IN THE DATABASE. One normalized Philippine
--    mobile number can belong to one account only, whichever way it is saved
--    (registration, Manager-created account, profile edit, any other write).
--    A trigger normalizes and validates the number; a unique index is the
--    final guard against two simultaneous saves.
--
-- 3. THE FARMER ADDRESS IS FIXED, IN THE DATABASE. For an account whose role
--    is 'farmer', every address row written or changed in buyer_addresses has
--    its Region / Province / City / Barangay / Postal Code forced to
--    MIMAROPA Region / Marinduque / Torrijos / Payanas / 4903, and address_line
--    is rebuilt from the typed Street / Building / House No. plus those fixed
--    values. Label, map coordinates, notes, recipient, contact number and the
--    default flag are left exactly as the user saved them. A legacy address is
--    only rewritten when its location fields are changed.
--
-- Not applied automatically. Run the PRE-FLIGHT block, then this file, then
-- the verification block.
-- ============================================================

-- ─── PRE-FLIGHT (read-only — run each by itself) ──────────────────────────
-- A. Steps 1 and 2 are applied (expect 3 rows):
--    SELECT proname FROM pg_proc WHERE pronamespace='public'::regnamespace
--      AND proname IN ('issue_member_identifier','normalize_ph_mobile','register_account');
--
-- B. Phone numbers shared by more than one account (expect ZERO rows). The
--    unique index cannot be built while any exist, and this file stops with an
--    error. Decide which account keeps the number and clear or correct the
--    others BEFORE running this file:
--    SELECT public.normalize_ph_mobile(phone_number) AS phone, count(*) AS accounts,
--           array_agg(user_id) AS user_ids, array_agg(full_name) AS names
--    FROM public.user_information
--    WHERE public.normalize_ph_mobile(phone_number) IS NOT NULL
--    GROUP BY 1 HAVING count(*) > 1;
--
-- C. Stored phone numbers that are not valid Philippine mobile numbers
--    (informational — they are left alone until their owner edits the number):
--    SELECT user_id, full_name, phone_number FROM public.user_information
--    WHERE phone_number IS NOT NULL AND btrim(phone_number) <> ''
--      AND public.normalize_ph_mobile(phone_number) IS NULL;
--
-- D. Farmer addresses outside Payanas (informational — not changed by this
--    file; they are corrected the next time the farmer edits the address):
--    SELECT ba.id, ba.user_id, ba.label, ba.address_line, ba.barangay_name, ba.postal_code
--    FROM public.buyer_addresses ba JOIN public.user_roles ur ON ur.user_id = ba.user_id
--    WHERE ur.role = 'farmer'
--      AND (ba.barangay_code IS DISTINCT FROM '1704006019' OR ba.postal_code IS DISTINCT FROM '4903');
-- ────────────────────────────────────────────────────────────────────────

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. Identifiers: database administrators only
-- ════════════════════════════════════════════════════════════

-- No client may change a membership year any more.
DROP FUNCTION IF EXISTS public.admin_set_membership_year(uuid, integer, text);

-- Counters only move forward, so an issued number is never issued again.
CREATE OR REPLACE FUNCTION public.member_id_counters_forward_only()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.last_seq < OLD.last_seq THEN
    RAISE EXCEPTION 'Identifier counters can only move forward (% % : % -> %)',
      OLD.role, OLD.year, OLD.last_seq, NEW.last_seq;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_member_id_counters_forward_only ON public.member_id_counters;
CREATE TRIGGER trg_member_id_counters_forward_only
  BEFORE UPDATE ON public.member_id_counters
  FOR EACH ROW EXECUTE FUNCTION public.member_id_counters_forward_only();

-- Keeps every identifier row consistent, however it was written.
CREATE OR REPLACE FUNCTION public.member_identifiers_integrity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_prefix       text;
  v_current_year integer := EXTRACT(YEAR FROM (now() AT TIME ZONE 'Asia/Manila'))::integer;
  v_reason       text := NULLIF(current_setting('app.member_id_reason', true), '');
BEGIN
  IF TG_OP = 'UPDATE' AND (NEW.user_id <> OLD.user_id OR NEW.role <> OLD.role) THEN
    RAISE EXCEPTION 'The account and role of an identifier cannot be changed';
  END IF;

  v_prefix := CASE NEW.role WHEN 'farmer' THEN 'SP3' WHEN 'officer' THEN 'OFF' WHEN 'buyer' THEN 'BUY' END;
  IF NEW.membership_year > v_current_year THEN
    RAISE EXCEPTION 'Membership year cannot be in the future (%)', NEW.membership_year;
  END IF;

  -- The code is derived, never typed: role + year + sequence decide it.
  NEW.member_code := v_prefix || '-' || NEW.membership_year || '-' ||
    CASE WHEN NEW.sequence_no < 1000 THEN lpad(NEW.sequence_no::text, 3, '0')
         ELSE NEW.sequence_no::text END;

  -- The yearly counter must never be behind an issued number.
  INSERT INTO public.member_id_counters (role, year, last_seq)
  VALUES (NEW.role, NEW.membership_year, NEW.sequence_no)
  ON CONFLICT (role, year)
  DO UPDATE SET last_seq = GREATEST(public.member_id_counters.last_seq, EXCLUDED.last_seq);

  IF TG_OP = 'UPDATE' AND NEW.member_code <> OLD.member_code THEN
    NEW.updated_at := NOW();
    INSERT INTO public.member_identifier_history (user_id, old_code, new_code, changed_by, reason)
    VALUES (NEW.user_id, OLD.member_code, NEW.member_code, auth.uid(),
            COALESCE(v_reason, 'Changed directly in the database'));
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_member_identifiers_integrity ON public.member_identifiers;
CREATE TRIGGER trg_member_identifiers_integrity
  BEFORE INSERT OR UPDATE ON public.member_identifiers
  FOR EACH ROW EXECUTE FUNCTION public.member_identifiers_integrity();

-- For a database administrator, in the SQL editor: moves a Farmer or Officer
-- to the next free number of [p_year] (for example a member who joined the
-- cooperative in 2015). The old number is retired, never reused, and logged.
-- NOT callable from the app: no client role has EXECUTE.
CREATE OR REPLACE FUNCTION public.dba_set_membership_year(
  p_user_id uuid,
  p_year    integer,
  p_reason  text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.member_identifiers%ROWTYPE;
  v_seq integer;
BEGIN
  SELECT * INTO v_row FROM public.member_identifiers WHERE user_id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'This account has no identifier';
  END IF;
  IF v_row.membership_year = p_year THEN
    RETURN v_row.member_code;
  END IF;

  INSERT INTO public.member_id_counters (role, year, last_seq)
  VALUES (v_row.role, p_year, 1)
  ON CONFLICT (role, year)
  DO UPDATE SET last_seq = public.member_id_counters.last_seq + 1
  RETURNING last_seq INTO v_seq;

  PERFORM set_config('app.member_id_reason', COALESCE(p_reason, 'Membership year changed by a database administrator'), true);

  -- The integrity trigger rebuilds member_code and writes the history row.
  UPDATE public.member_identifiers
  SET membership_year = p_year, sequence_no = v_seq
  WHERE user_id = p_user_id;

  RETURN (SELECT member_code FROM public.member_identifiers WHERE user_id = p_user_id);
END;
$$;

REVOKE ALL ON FUNCTION public.dba_set_membership_year(uuid, integer, text)
  FROM PUBLIC, anon, authenticated, service_role;

-- The tables themselves stay read-only for app users (see step 1): the app
-- can neither read another person's counter nor write any identifier.

-- ════════════════════════════════════════════════════════════
-- 2. Phone numbers: one normalized number, one account
-- ════════════════════════════════════════════════════════════

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.user_information
    WHERE public.normalize_ph_mobile(phone_number) IS NOT NULL
    GROUP BY public.normalize_ph_mobile(phone_number) HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION
      'Some phone numbers are shared by more than one account. Resolve them first - see PRE-FLIGHT query B at the top of this file.';
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_user_information_phone_normalized
  ON public.user_information (public.normalize_ph_mobile(phone_number))
  WHERE public.normalize_ph_mobile(phone_number) IS NOT NULL;

-- Runs on every insert, and on an update that changes the phone number. An
-- update that leaves the number alone (last_active_at, name, photo, ...) is
-- never blocked by an old, oddly formatted number.
CREATE OR REPLACE FUNCTION public.user_information_phone_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v text;
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.phone_number IS NOT DISTINCT FROM OLD.phone_number THEN
    RETURN NEW;
  END IF;

  IF NEW.phone_number IS NULL OR btrim(NEW.phone_number) = '' THEN
    NEW.phone_number := NULL;
    RETURN NEW;
  END IF;

  v := public.normalize_ph_mobile(NEW.phone_number);
  IF v IS NULL THEN
    RAISE EXCEPTION 'Please enter a valid Philippine mobile number.';
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_information u
    WHERE u.user_id <> NEW.user_id
      AND public.normalize_ph_mobile(u.phone_number) = v
  ) THEN
    RAISE EXCEPTION 'This phone number is already used by another account.';
  END IF;

  NEW.phone_number := v;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_information_phone_guard ON public.user_information;
CREATE TRIGGER trg_user_information_phone_guard
  BEFORE INSERT OR UPDATE OF phone_number ON public.user_information
  FOR EACH ROW EXECUTE FUNCTION public.user_information_phone_guard();

-- ════════════════════════════════════════════════════════════
-- 3. Fixed Farmer address
-- ════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.buyer_addresses_farmer_fixed_area()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text;
BEGIN
  SELECT role INTO v_role FROM public.user_roles WHERE user_id = NEW.user_id;
  IF v_role IS DISTINCT FROM 'farmer' THEN
    RETURN NEW; -- Buyers (and everyone else) keep free-form addresses
  END IF;

  -- On an update that does not touch the location fields (label, map pin,
  -- notes, default flag ...) leave the row exactly as it is.
  IF TG_OP = 'UPDATE'
     AND NEW.region_code            IS NOT DISTINCT FROM OLD.region_code
     AND NEW.region_name            IS NOT DISTINCT FROM OLD.region_name
     AND NEW.province_code          IS NOT DISTINCT FROM OLD.province_code
     AND NEW.province_name          IS NOT DISTINCT FROM OLD.province_name
     AND NEW.city_municipality_code IS NOT DISTINCT FROM OLD.city_municipality_code
     AND NEW.city_municipality_name IS NOT DISTINCT FROM OLD.city_municipality_name
     AND NEW.barangay_code          IS NOT DISTINCT FROM OLD.barangay_code
     AND NEW.barangay_name          IS NOT DISTINCT FROM OLD.barangay_name
     AND NEW.postal_code            IS NOT DISTINCT FROM OLD.postal_code
     AND NEW.street                 IS NOT DISTINCT FROM OLD.street
     AND NEW.building               IS NOT DISTINCT FROM OLD.building
     AND NEW.house_no               IS NOT DISTINCT FROM OLD.house_no
     AND NEW.address_line           IS NOT DISTINCT FROM OLD.address_line THEN
    RETURN NEW;
  END IF;

  -- The five fixed fields are not negotiable, whatever the caller sent.
  NEW.region_code            := '1700000000';
  NEW.region_name            := 'MIMAROPA Region';
  NEW.province_code          := '1704000000';
  NEW.province_name          := 'Marinduque';
  NEW.city_municipality_code := '1704006000';
  NEW.city_municipality_name := 'Torrijos';
  NEW.barangay_code          := '1704006019';
  NEW.barangay_name          := 'Payanas';
  NEW.postal_code            := '4903';

  -- The three typed fields stay the user's.
  NEW.street   := NULLIF(btrim(NEW.street), '');
  NEW.building := NULLIF(btrim(NEW.building), '');
  NEW.house_no := NULLIF(btrim(NEW.house_no), '');

  NEW.address_line := concat_ws(', ',
    NEW.house_no, NEW.building, NEW.street,
    'Payanas', 'Torrijos', 'Marinduque', 'MIMAROPA Region', '4903');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_buyer_addresses_farmer_fixed_area ON public.buyer_addresses;
CREATE TRIGGER trg_buyer_addresses_farmer_fixed_area
  BEFORE INSERT OR UPDATE ON public.buyer_addresses
  FOR EACH ROW EXECUTE FUNCTION public.buyer_addresses_farmer_fixed_area();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── POST-DEPLOY VERIFICATION ────────────────────────────────────────────
-- 1. The Manager-callable year function is gone and the DBA one is locked
--    (expect 0 rows, then false, false, false):
--    SELECT proname FROM pg_proc WHERE proname = 'admin_set_membership_year';
--    SELECT has_function_privilege('anon','public.dba_set_membership_year(uuid,integer,text)','EXECUTE'),
--           has_function_privilege('authenticated','public.dba_set_membership_year(uuid,integer,text)','EXECUTE'),
--           has_function_privilege('service_role','public.dba_set_membership_year(uuid,integer,text)','EXECUTE');
--
-- 2. A database administrator changes a year (use a TEST account). Expect a
--    new code for that year, the old one in history, and the counter ahead:
--    SELECT public.dba_set_membership_year('<test user uuid>', 2015, 'test');
--    SELECT member_code, membership_year, sequence_no FROM public.member_identifiers WHERE user_id='<test user uuid>';
--    SELECT old_code, new_code, reason FROM public.member_identifier_history WHERE user_id='<test user uuid>';
--
-- 3. A typed code cannot disagree with year/sequence, and a counter cannot go
--    back (both inside a rolled-back transaction):
--    BEGIN;
--      UPDATE public.member_identifiers SET member_code='SP3-1999-999' WHERE user_id='<test user uuid>';
--      SELECT member_code FROM public.member_identifiers WHERE user_id='<test user uuid>';  -- rebuilt, not 1999
--      UPDATE public.member_id_counters SET last_seq = 0 WHERE role='farmer' AND year = extract(year from now())::int;  -- expect ERROR
--    ROLLBACK;
--
-- 4. Phone uniqueness (expect the second statement to fail with
--    "This phone number is already used by another account."), rolled back:
--    BEGIN;
--      UPDATE public.user_information SET phone_number='+63 917 000 0001' WHERE user_id='<account A>';
--      UPDATE public.user_information SET phone_number='09170000001'      WHERE user_id='<account B>';  -- expect ERROR
--    ROLLBACK;
--
-- 5. Fixed farmer address (rolled back). Expect Payanas / 4903 and the typed
--    street kept, whatever is sent:
--    BEGIN;
--      INSERT INTO public.buyer_addresses (user_id, label, address_line, region_name, barangay_name, postal_code, street, house_no)
--      VALUES ('<a FARMER uuid>', 'Test', 'x', 'NCR', 'Elsewhere', '1000', 'Rizal St', '12') RETURNING address_line, barangay_name, postal_code;
--    ROLLBACK;
--    -- The same insert for a BUYER uuid keeps 'Elsewhere' / '1000'.
-- ============================================================
