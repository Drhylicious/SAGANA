-- ============================================================
-- SAGANA — Capital Share rates (percentage credits) and their history
--
-- FOR YOUR REVIEW. One transaction, safe to re-run (a rate you already saved is kept).
--
-- THE RULES
--   Total Capital Share = Monthly Contribution + Cooperative Purchase + Offer to Cooperative.
--   * Monthly Contribution: unchanged (payments the member makes). No percentage.
--   * Cooperative Purchase: when a COMPLETED order of a member who was enrolled in the
--     Product Sales program (is_member_price) is saved, purchase_percent % of the net amount
--     paid is added to the member's Capital Share.
--   * Offer to Cooperative: when an offer is settled (the sale is recorded in
--     member_sales_transactions, which only happens once the offer is successful and
--     completed), offer_percent % of its sale value is added.
--   * Non-members, pending, rejected, cancelled and unsuccessful transactions add nothing.
--
-- WHAT THIS DOES
--   1. capital_share_rates: ONE row with the two percentages (default 10 % each, 0-100, two
--      decimals; 0 turns a source off). Staff read it; the Manager, and an Officer with Manage
--      on Reports (the existing gate), change it, and every change is logged.
--   2. capital_share_rate_versions: ONE ROW PER SETTINGS CHANGE (version 1 = the first rates,
--      then one more each time a percentage is changed): date, the two rates, who changed it.
--      Signed-in users may read it; nobody writes it by hand (the settings trigger does).
--   3. Every credit in the ledger (capital_contribution_events) remembers: rate_percent and
--      base_amount (what it was worked out from), rate_version (the settings version in force),
--      credited_at (the moment it was credited) and, for a purchase, discount_amount (the
--      Product Sales discount of that order, for the history). Ledger rows cannot be edited,
--      so changing a rate NEVER changes an earlier credit.
--   4. Two ledger sources, 'purchase_share' and 'offer_share', one credit per transaction
--      (unique on the transaction id: a retry or a re-run adds nothing twice).
--   5. The earlier "purchase discount -> Capital Share" credit is RETIRED (its trigger is
--      dropped), otherwise a purchase would be credited twice. The member price discount
--      itself is unchanged. Credits it already made stay (source 'purchase_discount').
--   6. Two triggers credit a transaction when it completes; apply_capital_share_rates()
--      credits any eligible completed transaction that still has no credit, and runs when the
--      rates are saved and at the end of this script.
--   7. A change of a percentage first writes a NEW VERSION, then credits anything uncredited
--      under that new version. Credits made under an earlier version keep their version.
--      "Newly credited" in the app = the latest version; "previous" = every earlier one.
--
-- WHAT IT DOES NOT CHANGE
--   member_capital_shares and its recompute trigger (the balance is the sum of the ledger, so
--   every screen and the loan eligibility rule keep reading the same total), monthly dues,
--   Starting Capital, the member discount, RLS on the ledger. No notice is sent.
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ─────────────────────────────────────────────────
-- A. Sources in use today:
--    SELECT source, count(*) FROM public.capital_contribution_events GROUP BY 1 ORDER BY 1;
-- B. The current rule on the source column:
--    SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--     WHERE conrelid = 'public.capital_contribution_events'::regclass AND contype = 'c';
-- ────────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.capital_contribution_events') IS NULL
     OR to_regclass('public.program_product_purchases') IS NULL
     OR to_regclass('public.member_sales_transactions') IS NULL THEN
    RAISE EXCEPTION 'A table this script needs is missing.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.capital_contribution_events
              WHERE source NOT IN ('member_payment', 'patronage_capital', 'manual_adjustment',
                                   'opening_balance', 'purchase_discount',
                                   'purchase_share', 'offer_share')) THEN
    RAISE EXCEPTION 'The ledger has a source this script does not list. Run PRE-FLIGHT A and B, then adjust the list below.';
  END IF;
END $$;

-- 1. The rates ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.capital_share_rates (
  id               integer      PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  purchase_percent numeric(5,2) NOT NULL DEFAULT 10
                     CHECK (purchase_percent >= 0 AND purchase_percent <= 100),
  offer_percent    numeric(5,2) NOT NULL DEFAULT 10
                     CHECK (offer_percent >= 0 AND offer_percent <= 100),
  updated_at       timestamptz  NOT NULL DEFAULT now(),
  updated_by       uuid
);

COMMENT ON TABLE public.capital_share_rates IS
  'The percentage of a Cooperative Purchase / Offer to Cooperative that is added to the member''s Capital Share. One row. The rate used is copied onto each credit (capital_contribution_events.rate_percent).';

INSERT INTO public.capital_share_rates (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.capital_share_rates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "capital_share_rates: staff read" ON public.capital_share_rates;
CREATE POLICY "capital_share_rates: staff read"
  ON public.capital_share_rates FOR SELECT USING (public.is_staff());

DROP POLICY IF EXISTS "capital_share_rates: staff update" ON public.capital_share_rates;
CREATE POLICY "capital_share_rates: staff update"
  ON public.capital_share_rates FOR UPDATE
  USING (public.is_platform_admin()) WITH CHECK (public.is_platform_admin());

CREATE OR REPLACE FUNCTION public.capital_share_rates_touch()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  NEW.id := 1;
  NEW.updated_at := now();
  NEW.updated_by := auth.uid();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_capital_share_rates_touch ON public.capital_share_rates;
CREATE TRIGGER trg_capital_share_rates_touch
  BEFORE UPDATE ON public.capital_share_rates
  FOR EACH ROW EXECUTE FUNCTION public.capital_share_rates_touch();

-- 2. One row per settings change ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.capital_share_rate_versions (
  version          integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  purchase_percent numeric(5,2) NOT NULL,
  offer_percent    numeric(5,2) NOT NULL,
  changed_at       timestamptz  NOT NULL DEFAULT now(),
  changed_by       uuid
);

COMMENT ON TABLE public.capital_share_rate_versions IS
  'One row per change of the Capital Share percentages (version 1 = the first rates). Written by the settings trigger only.';

-- Version 1 = the rates as they are now (only the first time).
INSERT INTO public.capital_share_rate_versions (purchase_percent, offer_percent, changed_at)
SELECT r.purchase_percent, r.offer_percent, r.updated_at
  FROM public.capital_share_rates r
 WHERE r.id = 1 AND NOT EXISTS (SELECT 1 FROM public.capital_share_rate_versions);

ALTER TABLE public.capital_share_rate_versions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "capital_share_rate_versions: signed-in read" ON public.capital_share_rate_versions;
CREATE POLICY "capital_share_rate_versions: signed-in read"
  ON public.capital_share_rate_versions FOR SELECT TO authenticated USING (true);

-- 3. What each credit remembers ──────────────────────────────────────────────
ALTER TABLE public.capital_contribution_events
  ADD COLUMN IF NOT EXISTS reference_id    uuid,
  ADD COLUMN IF NOT EXISTS rate_percent    numeric(5,2),
  ADD COLUMN IF NOT EXISTS base_amount     numeric(12,2),
  ADD COLUMN IF NOT EXISTS rate_version    integer,
  ADD COLUMN IF NOT EXISTS credited_at     timestamptz,
  ADD COLUMN IF NOT EXISTS discount_amount numeric(12,2);

COMMENT ON COLUMN public.capital_contribution_events.rate_percent IS
  'purchase_share / offer_share only: the percentage in force when the credit was made.';
COMMENT ON COLUMN public.capital_contribution_events.base_amount IS
  'purchase_share / offer_share only: the amount the credit was worked out from (net paid / sale value).';
COMMENT ON COLUMN public.capital_contribution_events.rate_version IS
  'purchase_share / offer_share only: the capital_share_rate_versions row in force when the credit was made.';
COMMENT ON COLUMN public.capital_contribution_events.credited_at IS
  'purchase_share / offer_share only: the moment the credit was made (not the day of the transaction).';
COMMENT ON COLUMN public.capital_contribution_events.discount_amount IS
  'purchase_share only: the Product Sales discount of the order, kept for the history.';

-- Credits made before versions existed belong to version 1. Their real credit moment is not
-- recorded, so the moment of this script is used. (The ledger is closed to signed-in users;
-- the SQL Editor is not a signed-in user, so this one-time fill is allowed.)
UPDATE public.capital_contribution_events e
   SET rate_version = COALESCE(e.rate_version, 1),
       credited_at  = COALESCE(e.credited_at, now())
 WHERE e.source IN ('purchase_share', 'offer_share')
   AND (e.rate_version IS NULL OR e.credited_at IS NULL);

UPDATE public.capital_contribution_events e
   SET discount_amount = p.discount_amount
  FROM public.program_product_purchases p
 WHERE e.source = 'purchase_share' AND e.reference_id = p.id AND e.discount_amount IS NULL;

-- 4. The two sources ─────────────────────────────────────────────────────────
DO $$
DECLARE c record;
BEGIN
  FOR c IN
    SELECT conname FROM pg_constraint
     WHERE conrelid = 'public.capital_contribution_events'::regclass AND contype = 'c'
       AND pg_get_constraintdef(oid) ILIKE '%source%' AND pg_get_constraintdef(oid) ILIKE '%member_payment%'
  LOOP
    EXECUTE format('ALTER TABLE public.capital_contribution_events DROP CONSTRAINT %I', c.conname);
  END LOOP;
END $$;

ALTER TABLE public.capital_contribution_events
  ADD CONSTRAINT cce_source_check CHECK (source IN (
    'member_payment',     -- Monthly Contribution
    'patronage_capital',  -- an older payout left in the cooperative (kept, no longer offered)
    'manual_adjustment',  -- a correction (may be negative)
    'opening_balance',    -- Starting Capital
    'purchase_discount',  -- the earlier discount credit (kept, no longer made)
    'purchase_share',     -- Cooperative Purchase: a percentage of the net amount paid
    'offer_share'         -- Offer to Cooperative: a percentage of the sale value
  ));

CREATE UNIQUE INDEX IF NOT EXISTS uq_cce_share_once
  ON public.capital_contribution_events (source, reference_id)
  WHERE source IN ('purchase_share', 'offer_share') AND reference_id IS NOT NULL;

-- 5. Retire the discount credit (it would double-credit a purchase) ──────────
DROP TRIGGER IF EXISTS trg_credit_purchase_discount ON public.program_product_purchases;
DROP FUNCTION IF EXISTS public.credit_purchase_discount_to_capital();

-- 6. Cooperative Purchase: when a member-price order is completed ────────────
CREATE OR REPLACE FUNCTION public.credit_purchase_share_to_capital()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate   numeric;
  v_credit numeric;
  v_ver    integer;
BEGIN
  IF NOT COALESCE(NEW.is_member_price, FALSE) OR COALESCE(NEW.total_amount, 0) <= 0 THEN
    RETURN NEW;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.cooperative_programs p
                  WHERE p.id = NEW.program_id AND p.program_purpose = 'sales') THEN
    RETURN NEW;
  END IF;

  SELECT purchase_percent INTO v_rate FROM public.capital_share_rates WHERE id = 1;
  IF COALESCE(v_rate, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  v_credit := round(NEW.total_amount * v_rate / 100, 2);
  IF v_credit <= 0 THEN
    RETURN NEW;
  END IF;
  SELECT max(version) INTO v_ver FROM public.capital_share_rate_versions;

  INSERT INTO public.capital_contribution_events
    (farmer_id, amount, source, note, recorded_by, reference_id, rate_percent, base_amount,
     rate_version, credited_at, discount_amount)
  VALUES
    (NEW.farmer_id, v_credit, 'purchase_share',
     'Cooperative Purchase ' || COALESCE(NEW.order_number, NEW.id::text),
     NULL, NEW.id, v_rate, NEW.total_amount, v_ver, now(), COALESCE(NEW.discount_amount, 0))
  ON CONFLICT (source, reference_id)
    WHERE source IN ('purchase_share', 'offer_share') AND reference_id IS NOT NULL
  DO NOTHING;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.credit_purchase_share_to_capital() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_credit_purchase_share ON public.program_product_purchases;
CREATE TRIGGER trg_credit_purchase_share
  AFTER UPDATE OF status ON public.program_product_purchases
  FOR EACH ROW
  WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed')
  EXECUTE FUNCTION public.credit_purchase_share_to_capital();

-- 7. Offer to Cooperative: when the successful, completed sale is recorded ───
CREATE OR REPLACE FUNCTION public.credit_offer_share_to_capital()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rate   numeric;
  v_credit numeric;
  v_ver    integer;
BEGIN
  IF COALESCE(NEW.amount, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  SELECT offer_percent INTO v_rate FROM public.capital_share_rates WHERE id = 1;
  IF COALESCE(v_rate, 0) <= 0 THEN
    RETURN NEW;
  END IF;

  v_credit := round(NEW.amount * v_rate / 100, 2);
  IF v_credit <= 0 THEN
    RETURN NEW;
  END IF;
  SELECT max(version) INTO v_ver FROM public.capital_share_rate_versions;

  INSERT INTO public.capital_contribution_events
    (farmer_id, amount, source, note, recorded_by, reference_id, rate_percent, base_amount,
     rate_version, credited_at)
  VALUES
    (NEW.farmer_id, v_credit, 'offer_share',
     'Offer to Cooperative: ' || COALESCE(NEW.crop_name, ''),
     NULL, NEW.id, v_rate, NEW.amount, v_ver, now())
  ON CONFLICT (source, reference_id)
    WHERE source IN ('purchase_share', 'offer_share') AND reference_id IS NOT NULL
  DO NOTHING;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.credit_offer_share_to_capital() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_credit_offer_share ON public.member_sales_transactions;
CREATE TRIGGER trg_credit_offer_share
  AFTER INSERT ON public.member_sales_transactions
  FOR EACH ROW EXECUTE FUNCTION public.credit_offer_share_to_capital();

-- 8. Credit every eligible transaction that has no credit yet ─────────────────
CREATE OR REPLACE FUNCTION public.apply_capital_share_rates()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_purchase numeric;
  v_offer    numeric;
  v_ver      integer;
  v_n        integer := 0;
  v_k        integer;
BEGIN
  SELECT purchase_percent, offer_percent INTO v_purchase, v_offer
    FROM public.capital_share_rates WHERE id = 1;
  SELECT max(version) INTO v_ver FROM public.capital_share_rate_versions;

  IF COALESCE(v_offer, 0) > 0 THEN
    INSERT INTO public.capital_contribution_events
      (farmer_id, amount, source, note, recorded_by, reference_id, rate_percent, base_amount,
       rate_version, credited_at)
    SELECT t.farmer_id, round(t.amount * v_offer / 100, 2), 'offer_share',
           'Offer to Cooperative: ' || COALESCE(t.crop_name, ''), NULL, t.id, v_offer, t.amount,
           v_ver, now()
      FROM public.member_sales_transactions t
     WHERE COALESCE(t.amount, 0) > 0
       AND round(t.amount * v_offer / 100, 2) > 0
    ON CONFLICT (source, reference_id)
      WHERE source IN ('purchase_share', 'offer_share') AND reference_id IS NOT NULL
    DO NOTHING;
    GET DIAGNOSTICS v_k = ROW_COUNT;
    v_n := v_n + v_k;
  END IF;

  IF COALESCE(v_purchase, 0) > 0 THEN
    INSERT INTO public.capital_contribution_events
      (farmer_id, amount, source, note, recorded_by, reference_id, rate_percent, base_amount,
       rate_version, credited_at, discount_amount)
    SELECT p.farmer_id, round(p.total_amount * v_purchase / 100, 2), 'purchase_share',
           'Cooperative Purchase ' || COALESCE(p.order_number, p.id::text), NULL, p.id,
           v_purchase, p.total_amount, v_ver, now(), COALESCE(p.discount_amount, 0)
      FROM public.program_product_purchases p
      JOIN public.cooperative_programs g ON g.id = p.program_id AND g.program_purpose = 'sales'
     WHERE p.status = 'completed' AND COALESCE(p.is_member_price, FALSE)
       AND COALESCE(p.total_amount, 0) > 0
       AND round(p.total_amount * v_purchase / 100, 2) > 0
    ON CONFLICT (source, reference_id)
      WHERE source IN ('purchase_share', 'offer_share') AND reference_id IS NOT NULL
    DO NOTHING;
    GET DIAGNOSTICS v_k = ROW_COUNT;
    v_n := v_n + v_k;
  END IF;

  RETURN v_n;
END;
$$;

REVOKE ALL ON FUNCTION public.apply_capital_share_rates() FROM PUBLIC, anon, authenticated;

-- Saving the rates: a CHANGE writes a new version first, then credits what has no credit yet.
DROP TRIGGER IF EXISTS trg_capital_share_rates_apply ON public.capital_share_rates;

CREATE OR REPLACE FUNCTION public.capital_share_rates_apply()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.purchase_percent IS DISTINCT FROM OLD.purchase_percent
     OR NEW.offer_percent IS DISTINCT FROM OLD.offer_percent THEN
    INSERT INTO public.capital_share_rate_versions (purchase_percent, offer_percent, changed_by)
    VALUES (NEW.purchase_percent, NEW.offer_percent, auth.uid());
  END IF;
  PERFORM public.apply_capital_share_rates();
  RETURN NULL;
END $$;

REVOKE ALL ON FUNCTION public.capital_share_rates_apply() FROM PUBLIC, anon, authenticated;

CREATE TRIGGER trg_capital_share_rates_apply
  AFTER UPDATE ON public.capital_share_rates
  FOR EACH ROW EXECUTE FUNCTION public.capital_share_rates_apply();

-- And once now, for everything that is already completed.
SELECT public.apply_capital_share_rates() AS credits_made;

-- 9. Who may change the rates: Manage on Reports (the Manager, or an Officer with Manage
--    on the Reports module). View Only cannot write. Every change is logged (who, when, old
--    and new values) in the Manager's Accountability screen under Reports.
DO $$
BEGIN
  IF to_regclass('public.staff_permission_targets') IS NOT NULL THEN
    DELETE FROM public.staff_permission_targets WHERE kind = 'table' AND name = 'capital_share_rates';
    INSERT INTO public.staff_permission_targets (kind, name, module)
    VALUES ('table', 'capital_share_rates', 'reports');
  END IF;
  IF to_regprocedure('public.audit_staff_change()') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.capital_share_rates;
    EXECUTE 'CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.capital_share_rates '
         || 'FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(''reports'', '''')';
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── CHECK (read-only) ─────────────────────────────────────────────────────────
--   SELECT * FROM public.capital_share_rate_versions ORDER BY version;
--   SELECT rate_version, source, count(*), sum(amount) FROM public.capital_contribution_events
--    WHERE source IN ('purchase_share', 'offer_share') GROUP BY 1, 2 ORDER BY 1, 2;
