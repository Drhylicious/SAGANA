-- ============================================================
-- SAGANA — Phase B: Member ID generator, Capital Shares model,
--                   Capital-share loan eligibility, DOB / Gender
-- (Admin Members tab enhancement — Issue 4 + age/gender)
--
-- Sections
--   1. farmer_profiles.date_of_birth + gender (nullable, farmer-only
--      personal information — NOT stored in sp3_member_registry)
--   2. member_capital_shares: + total_contribution (authoritative
--      running ₱ total); share_value_per_unit default -> 2000.00;
--      total_shares becomes trigger-maintained =
--      floor(total_contribution / share_value_per_unit)  (Decision D1f)
--   3. capital_contribution_events ledger + recompute trigger
--      (Admin records each ₱100/monthly-dues or opening payment;
--       Decision D1a/D1c)
--   4. loan_policy_settings: + minimum_capital_contribution (₱2,000),
--      monthly_dues_amount (₱100), annual_capital_share_target (₱2,000)
--   5. generate_member_id(p_year) — the ONE shared SP3-<year>-<seq>
--      generator, yearly reset, advisory-locked, dup-proof (Decision D4)
--   6. create_farmer_account — rewritten: server-generated Member ID,
--      DOB / gender, crop_master-linked crops, ₱2,000 default share
--      value, optional opening contribution (Decision D16)
--   7. issue_loan — adds a HARD capital-contribution eligibility block
--      after the admin check (Issue 4d; UI warning is separate)
--
-- Existing data (Decision D1e — no full migration, DB reset planned
-- later): every member_capital_shares row is normalised to
-- share_value_per_unit = 2000 with total_contribution = total_shares
-- * 2000; every ACTIVE farmer with no row gets one at 0 (loan-
-- ineligible until the Admin records a payment — Decision #3).
--
-- Live function bodies reproduced from the CURRENT definitions:
--   create_farmer_account -> supabase_schema_sitio_to_purok_rename.sql
--   issue_loan            -> supabase_schema_loan_rpc_authorization_hardening.sql
-- ============================================================

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. farmer_profiles — Date of Birth + Gender
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.farmer_profiles
  ADD COLUMN IF NOT EXISTS date_of_birth DATE,
  ADD COLUMN IF NOT EXISTS gender        TEXT;

ALTER TABLE public.farmer_profiles
  DROP CONSTRAINT IF EXISTS farmer_profiles_gender_check;
ALTER TABLE public.farmer_profiles
  ADD CONSTRAINT farmer_profiles_gender_check
  CHECK (gender IS NULL OR gender IN ('male', 'female', 'prefer_not_to_say'));

COMMENT ON COLUMN public.farmer_profiles.date_of_birth IS
  'Farmer personal information. Nullable — existing members backfill via '
  'Farmer Edit Profile. New registrations enforce age >= 18.';
COMMENT ON COLUMN public.farmer_profiles.gender IS
  'Farmer personal information: male | female | prefer_not_to_say. Nullable.';

-- ════════════════════════════════════════════════════════════
-- 2. member_capital_shares — total_contribution + ₱2,000 share value
-- ════════════════════════════════════════════════════════════

-- Snapshot each existing member's share COUNT before any trigger runs.
-- The pre-existing 100-share row is worth ₱200,000 once shares are
-- ₱2,000 each (Decision D3), NOT its old 100 × ₱1,000. Section 3a turns
-- this snapshot into ledger opening_balance rows.
DROP TABLE IF EXISTS _phase_b_mcs_snapshot;
CREATE TEMP TABLE _phase_b_mcs_snapshot ON COMMIT DROP AS
SELECT farmer_id, total_shares
FROM public.member_capital_shares;

ALTER TABLE public.member_capital_shares
  ADD COLUMN IF NOT EXISTS total_contribution NUMERIC(12,2) NOT NULL DEFAULT 0
    CHECK (total_contribution >= 0);

ALTER TABLE public.member_capital_shares
  ALTER COLUMN share_value_per_unit SET DEFAULT 2000.00;

COMMENT ON COLUMN public.member_capital_shares.total_contribution IS
  'Authoritative running ₱ total of all recorded capital contributions. '
  'Loan eligibility checks this value. Maintained by trigger from '
  'capital_contribution_events.';
COMMENT ON COLUMN public.member_capital_shares.total_shares IS
  'Derived (trigger-maintained) = floor(total_contribution / '
  'share_value_per_unit). Only fully-completed ₱2,000 shares count '
  '(Decision D1f). Do not write directly.';

-- Keep total_shares in lock-step with total_contribution (Decision D1f:
-- only whole completed share increments count).
CREATE OR REPLACE FUNCTION public.sync_member_capital_shares_derived()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF COALESCE(NEW.share_value_per_unit, 0) > 0 THEN
    NEW.total_shares := floor(NEW.total_contribution / NEW.share_value_per_unit);
  ELSE
    NEW.total_shares := 0;
  END IF;
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_member_capital_shares_derived ON public.member_capital_shares;
CREATE TRIGGER trg_member_capital_shares_derived
  BEFORE INSERT OR UPDATE ON public.member_capital_shares
  FOR EACH ROW EXECUTE FUNCTION public.sync_member_capital_shares_derived();

-- Normalise the share value on existing rows to the finalised ₱2,000
-- (Decision D1e / D3). total_contribution is left alone here — it is
-- rebuilt from the ledger further down (section 3a) so the running
-- total and the ledger can never disagree once events start flowing.
UPDATE public.member_capital_shares
SET share_value_per_unit = 2000.00
WHERE share_value_per_unit <> 2000.00;

-- Every ACTIVE farmer must have a capital row (Decision #3 — created at
-- 0, loan-ineligible until the Admin records a payment).
INSERT INTO public.member_capital_shares (farmer_id, share_value_per_unit, total_contribution)
SELECT fp.user_id, 2000.00, 0
FROM public.farmer_profiles fp
JOIN public.user_roles ur ON ur.user_id = fp.user_id AND ur.status = 'active'
LEFT JOIN public.member_capital_shares mcs ON mcs.farmer_id = fp.user_id
WHERE mcs.id IS NULL;

-- ════════════════════════════════════════════════════════════
-- 3. capital_contribution_events — the contribution ledger
-- ════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.capital_contribution_events (
  id           UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id    UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount       NUMERIC(12,2) NOT NULL CHECK (amount <> 0),
  source       TEXT          NOT NULL CHECK (source IN (
                 'member_payment',      -- ₱100+ paid toward the ₱2,000 annual share
                 'patronage_capital',   -- member left their Balik-Tangkilik refund in the coop
                 'manual_adjustment',   -- Admin correction (may be negative)
                 'opening_balance'      -- starting balance recorded at account creation
               )),
  note         TEXT,
  recorded_by  UUID          REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cce_farmer_created
  ON public.capital_contribution_events (farmer_id, created_at DESC);

ALTER TABLE public.capital_contribution_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "cce: farmer reads own" ON public.capital_contribution_events;
CREATE POLICY "cce: farmer reads own"
  ON public.capital_contribution_events FOR SELECT
  USING (auth.uid() = farmer_id);

DROP POLICY IF EXISTS "cce: admin manages all" ON public.capital_contribution_events;
CREATE POLICY "cce: admin manages all"
  ON public.capital_contribution_events FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

-- Recompute member_capital_shares.total_contribution from the ledger
-- whenever an event is inserted / updated / deleted. Creates the
-- member_capital_shares row if it is somehow missing.
CREATE OR REPLACE FUNCTION public.recompute_member_capital()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_farmer UUID := COALESCE(NEW.farmer_id, OLD.farmer_id);
  v_total  NUMERIC(12,2);
BEGIN
  SELECT COALESCE(SUM(amount), 0) INTO v_total
  FROM capital_contribution_events
  WHERE farmer_id = v_farmer;

  IF v_total < 0 THEN
    v_total := 0;  -- never let corrections drive the running total negative
  END IF;

  INSERT INTO member_capital_shares (farmer_id, share_value_per_unit, total_contribution)
  VALUES (v_farmer, 2000.00, v_total)
  ON CONFLICT (farmer_id)
  DO UPDATE SET total_contribution = EXCLUDED.total_contribution;

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_cce_recompute ON public.capital_contribution_events;
CREATE TRIGGER trg_cce_recompute
  AFTER INSERT OR UPDATE OR DELETE ON public.capital_contribution_events
  FOR EACH ROW EXECUTE FUNCTION public.recompute_member_capital();

-- ─── 3a. Back the existing capital totals with ledger events ────────────────
-- Rebuild total_contribution entirely from the ledger so the recompute
-- trigger stays consistent forever (otherwise the first real event a
-- member gets would reset their running total to just that event's
-- amount). One opening_balance row per member who held shares before
-- this migration = (snapshot share count) × ₱2,000  (Decision D1e / D3).
-- The recompute + derived triggers then set total_contribution and
-- total_shares from it. Members with 0 shares get no event (SUM = 0).
INSERT INTO public.capital_contribution_events (farmer_id, amount, source, note, recorded_by)
SELECT s.farmer_id,
       s.total_shares * 2000.00,
       'opening_balance',
       'Phase B migration — normalised to ₱2,000/share',
       NULL
FROM _phase_b_mcs_snapshot s
WHERE s.total_shares > 0
  AND NOT EXISTS (
    SELECT 1 FROM public.capital_contribution_events cce
    WHERE cce.farmer_id = s.farmer_id
  );

-- Belt-and-braces: force every row's total_contribution to match its
-- ledger sum (covers rows that got no event — they settle at 0).
UPDATE public.member_capital_shares mcs
SET total_contribution = COALESCE((
      SELECT SUM(amount) FROM public.capital_contribution_events cce
      WHERE cce.farmer_id = mcs.farmer_id
    ), 0)
WHERE mcs.total_contribution IS DISTINCT FROM COALESCE((
      SELECT SUM(amount) FROM public.capital_contribution_events cce
      WHERE cce.farmer_id = mcs.farmer_id
    ), 0);

-- ════════════════════════════════════════════════════════════
-- 4. loan_policy_settings — capital-contribution policy
-- ════════════════════════════════════════════════════════════

ALTER TABLE public.loan_policy_settings
  ADD COLUMN IF NOT EXISTS minimum_capital_contribution NUMERIC(12,2) NOT NULL DEFAULT 2000.00,
  ADD COLUMN IF NOT EXISTS monthly_dues_amount          NUMERIC(12,2) NOT NULL DEFAULT 100.00,
  ADD COLUMN IF NOT EXISTS annual_capital_share_target   NUMERIC(12,2) NOT NULL DEFAULT 2000.00;

COMMENT ON COLUMN public.loan_policy_settings.minimum_capital_contribution IS
  'Minimum member_capital_shares.total_contribution required before a '
  'farmer may be issued a loan. Enforced hard in issue_loan().';

-- The Issue-Loan screen needs to read this value to show its warning
-- banner; the existing policy only grants SELECT to admins. Officers
-- (Phase D) will be added to this policy there.
DROP POLICY IF EXISTS "loan_policy_settings: admin reads" ON public.loan_policy_settings;
CREATE POLICY "loan_policy_settings: admin reads"
  ON public.loan_policy_settings FOR SELECT
  USING (EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()));

-- ════════════════════════════════════════════════════════════
-- 5. generate_member_id — the single shared SP3-<year>-<seq> generator
-- ════════════════════════════════════════════════════════════
-- Yearly-reset 3-digit sequence. Advisory-locked on the year so
-- concurrent creation across ALL three paths (self-registration,
-- Admin Add Member, any future path) cannot collide. Intended to be
-- called INSIDE a transaction that then inserts the farmer_profiles
-- row — the xact lock is held to COMMIT. A standalone call is a
-- non-authoritative preview only.

CREATE OR REPLACE FUNCTION public.generate_member_id(p_year INT DEFAULT NULL)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_year INT := COALESCE(p_year, EXTRACT(YEAR FROM now())::INT);
  v_seq  INT;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('member_id_' || v_year::TEXT));

  SELECT COALESCE(MAX(
    NULLIF(regexp_replace(fp.member_id, '^SP3-\d{4}-', ''), '')::INT
  ), 0) + 1
  INTO v_seq
  FROM farmer_profiles fp
  WHERE fp.member_id LIKE 'SP3-' || v_year || '-%';

  RETURN 'SP3-' || v_year || '-' || LPAD(v_seq::TEXT, 3, '0');
END;
$$;

GRANT EXECUTE ON FUNCTION public.generate_member_id(INT) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.generate_member_id(INT) FROM anon;

-- ════════════════════════════════════════════════════════════
-- 6. create_farmer_account — rewritten for Phase B
-- ════════════════════════════════════════════════════════════
-- Changes vs the live version:
--   * p_member_id / p_capital_shares REMOVED — member ID is now
--     server-generated; capital starts at 0 unless p_initial_contribution
--   * p_date_of_birth / p_gender ADDED (18+ enforced)
--   * p_share_value_per_unit default 1000 -> 2000
--   * p_initial_contribution ADDED (optional opening_balance event)
--   * crops now link to crop_master (name + real category + crop_master_id)

-- Drop EVERY existing create_farmer_account overload (the pre-Phase-B
-- 10-arg version, and — on a re-run — the Phase B 11-arg version this
-- file creates). A bare DROP with one fixed signature is not enough
-- because the signature changes in Phase B, so a re-run would collide
-- (ERROR 42723). This loop makes the whole file safely re-runnable.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT oid::regprocedure AS sig
    FROM pg_proc
    WHERE proname = 'create_farmer_account'
      AND pronamespace = 'public'::regnamespace
  LOOP
    EXECUTE 'DROP FUNCTION ' || r.sig::text || ' CASCADE';
  END LOOP;
END $$;

CREATE FUNCTION public.create_farmer_account(
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
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
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

  -- Server-generated Member ID (advisory-locked to COMMIT).
  v_member_id := generate_member_id(EXTRACT(YEAR FROM now())::INT);

  INSERT INTO farmer_profiles (user_id, member_id, is_verified, date_of_birth, gender)
  VALUES (v_user_id, v_member_id, TRUE, p_date_of_birth, p_gender);

  -- Every Admin-created member gets a capital row (Decision #3).
  INSERT INTO member_capital_shares (farmer_id, share_value_per_unit, total_contribution)
  VALUES (v_user_id, COALESCE(p_share_value_per_unit, 2000), 0)
  ON CONFLICT (farmer_id) DO NOTHING;

  IF COALESCE(p_initial_contribution, 0) > 0 THEN
    INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by)
    VALUES (v_user_id, p_initial_contribution, 'opening_balance',
            'Recorded at account creation', auth.uid());
  END IF;

  -- Crops linked to crop_master (Decision D16). Names not in the active
  -- catalog are silently skipped — the UI only offers catalog names.
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

GRANT EXECUTE ON FUNCTION public.create_farmer_account(
  text,text,text,text,text,date,text,numeric,numeric,text[],uuid
) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.create_farmer_account(
  text,text,text,text,text,date,text,numeric,numeric,text[],uuid
) FROM anon;

-- ════════════════════════════════════════════════════════════
-- 7. issue_loan — hard capital-contribution eligibility block
-- ════════════════════════════════════════════════════════════
-- Full body reproduced from
-- supabase_schema_loan_rpc_authorization_hardening.sql; the ONLY
-- addition is the capital-contribution check immediately after the
-- admin check. Signature unchanged -> CREATE OR REPLACE (no DROP).

CREATE OR REPLACE FUNCTION issue_loan(
  p_farmer_id UUID,
  p_items JSONB,
  p_issued_date DATE,
  p_monthly_payment NUMERIC,
  p_next_payment_date DATE,
  p_notes TEXT DEFAULT NULL,
  p_recorded_by UUID DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
)
RETURNS TABLE (loan_id UUID, reference_no TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_loan_id       UUID;
  v_total_value   NUMERIC := 0;
  v_item          JSONB;
  v_inventory_id  UUID;
  v_quantity      NUMERIC;
  v_unit_price    NUMERIC;
  v_line_total    NUMERIC;
  v_available     NUMERIC;
  v_item_name     TEXT;
  v_year          INT := EXTRACT(YEAR FROM p_issued_date)::INT;
  v_next_seq      INT;
  v_reference_no  TEXT;
  v_existing_id   UUID;
  v_existing_ref  TEXT;
  v_contribution  NUMERIC;
  v_minimum       NUMERIC;
BEGIN
  -- Admin check — first statement in the body.
  IF NOT EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only admins may issue loans';
  END IF;

  -- Capital-share loan eligibility — HARD block (Issue 4d). Runs before
  -- the replay check so a replayed call re-verifies too. The Issue-Loan
  -- screen shows its own warning banner; this is the backend authority.
  SELECT COALESCE(mcs.total_contribution, 0) INTO v_contribution
  FROM member_capital_shares mcs
  WHERE mcs.farmer_id = p_farmer_id;
  v_contribution := COALESCE(v_contribution, 0);

  SELECT COALESCE(lps.minimum_capital_contribution, 2000) INTO v_minimum
  FROM loan_policy_settings lps
  WHERE lps.id = 1;
  v_minimum := COALESCE(v_minimum, 2000);

  IF v_contribution < v_minimum THEN
    RAISE EXCEPTION
      'Farmer has not met the minimum capital contribution of % required for a loan (current contribution: %)',
      v_minimum, v_contribution;
  END IF;

  -- Input validation.
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'At least one loan item is required';
  END IF;

  IF p_monthly_payment <= 0 THEN
    RAISE EXCEPTION 'Monthly payment must be greater than zero';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_quantity   := (v_item->>'quantity')::NUMERIC;
    v_unit_price := (v_item->>'unitPrice')::NUMERIC;
    v_line_total := (v_item->>'lineTotal')::NUMERIC;

    IF v_quantity IS NULL OR v_quantity <= 0 THEN
      RAISE EXCEPTION 'Item quantity must be greater than zero: %', v_item->>'itemName';
    END IF;

    IF v_unit_price IS NULL OR v_unit_price < 0 THEN
      RAISE EXCEPTION 'Item unit price must not be negative: %', v_item->>'itemName';
    END IF;

    IF v_line_total IS NULL OR v_line_total < 0 THEN
      RAISE EXCEPTION 'Item line total must not be negative: %', v_item->>'itemName';
    END IF;
  END LOOP;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT fl.id, fl.reference_no INTO v_existing_id, v_existing_ref
      FROM farmer_loans fl
      WHERE fl.idempotency_key = p_idempotency_key;

    IF FOUND THEN
      RETURN QUERY SELECT v_existing_id, v_existing_ref;
      RETURN;
    END IF;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext('loan_reference_' || v_year::TEXT));

  SELECT COALESCE(MAX(
    NULLIF(regexp_replace(fl.reference_no, '^LN-\d{4}-', ''), '')::INT
  ), 0) + 1
  INTO v_next_seq
  FROM farmer_loans fl
  WHERE fl.reference_no LIKE 'LN-' || v_year || '-%';

  v_reference_no := 'LN-' || v_year || '-' || LPAD(v_next_seq::TEXT, 3, '0');

  SELECT COALESCE(SUM((elem->>'lineTotal')::NUMERIC), 0)
    INTO v_total_value
    FROM jsonb_array_elements(p_items) AS elem;

  INSERT INTO farmer_loans (
    farmer_id, reference_no, issued_date, total_value, amount_paid,
    status, notes, monthly_payment, next_payment_date, idempotency_key
  ) VALUES (
    p_farmer_id, v_reference_no, p_issued_date, v_total_value, 0,
    'active', p_notes, p_monthly_payment, p_next_payment_date, p_idempotency_key
  )
  RETURNING id INTO v_loan_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    INSERT INTO farmer_loan_items (loan_id, item_name, quantity, unit, unit_price, line_total)
    VALUES (
      v_loan_id,
      v_item->>'itemName',
      (v_item->>'quantity')::NUMERIC,
      v_item->>'unit',
      (v_item->>'unitPrice')::NUMERIC,
      (v_item->>'lineTotal')::NUMERIC
    );

    v_inventory_id := NULLIF(v_item->>'inventoryItemId', '')::UUID;
    IF v_inventory_id IS NOT NULL THEN
      v_quantity := (v_item->>'quantity')::NUMERIC;

      SELECT quantity_on_hand, item_name INTO v_available, v_item_name
        FROM cooperative_inventory
        WHERE id = v_inventory_id
        FOR UPDATE;

      IF NOT FOUND THEN
        RAISE EXCEPTION 'Inventory item % no longer exists', v_inventory_id;
      END IF;

      IF v_available < v_quantity THEN
        RAISE EXCEPTION 'Insufficient stock for %: % on hand, % requested',
          v_item_name, v_available, v_quantity;
      END IF;

      UPDATE cooperative_inventory
      SET quantity_on_hand = quantity_on_hand - v_quantity
      WHERE id = v_inventory_id;

      INSERT INTO inventory_transactions (
        inventory_id, transaction_type, quantity, reference_id, reference_type, recorded_by
      ) VALUES (
        v_inventory_id, 'loan_issued', -v_quantity, v_loan_id, 'loan', p_recorded_by
      );
    END IF;
  END LOOP;

  RETURN QUERY SELECT v_loan_id, v_reference_no;
END;
$$;

GRANT EXECUTE ON FUNCTION issue_loan(UUID, JSONB, DATE, NUMERIC, DATE, TEXT, UUID, TEXT) TO authenticated;

COMMIT;

-- ============================================================
-- POST-DEPLOY VERIFICATION
-- ============================================================
-- 1) DOB / gender columns:
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name='farmer_profiles' AND column_name IN ('date_of_birth','gender');
--    -- expect 2 rows
--
-- 2) Capital shares normalised:
--    SELECT farmer_id, total_shares, share_value_per_unit, total_contribution
--    FROM member_capital_shares ORDER BY total_contribution DESC;
--    -- every share_value_per_unit = 2000.00
--    -- the pre-existing 100-share row: total_shares=100, total_contribution=200000.00
--    -- newly-seeded active farmers: total_shares=0, total_contribution=0
--
-- 3) Ledger recompute trigger:
--    INSERT INTO capital_contribution_events (farmer_id, amount, source, recorded_by)
--    VALUES ('<a farmer_id>', 500, 'member_payment', auth.uid());
--    SELECT total_contribution, total_shares FROM member_capital_shares WHERE farmer_id='<that id>';
--    -- total_contribution rose by 500; total_shares = floor(total_contribution/2000)
--    -- (then DELETE that test event to undo)
--
-- 4) Member ID generator (preview):
--    SELECT generate_member_id();               -- 'SP3-<thisyear>-00N'
--    SELECT generate_member_id(2027);           -- 'SP3-2027-001'
--
-- 5) Loan eligibility block:
--    -- Pick a farmer with total_contribution < 2000 and try Issue Loan in-app
--    -- -> RPC raises "has not met the minimum capital contribution".
--    SELECT id, minimum_capital_contribution, monthly_dues_amount
--    FROM loan_policy_settings;  -- one row, id=1, 2000.00 / 100.00
-- ============================================================
