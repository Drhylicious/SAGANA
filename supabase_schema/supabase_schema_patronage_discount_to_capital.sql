-- ============================================================
-- SAGANA — Member Patronage: purchase discount -> Capital Share
--
-- FOR YOUR REVIEW — NOT APPLIED. One transaction, safe to re-run.
--
-- THE RULE (from the Member Patronage Report brief)
--   When a Farmer who is a member of the program completes a Cooperative Product
--   purchase at the MEMBER price, the discount they received is added to their
--   Capital Share.
--
-- WHAT THIS DOES
--   1. capital_contribution_events accepts a new source, 'purchase_discount'.
--   2. It gets a reference_id (the order), and a partial unique index, so one
--      order can credit its discount ONCE (a retry or a re-run adds nothing).
--   3. A trigger on program_product_purchases: when an order BECOMES 'completed',
--      and it was bought at the member price (is_member_price) with a discount,
--      the discount is added to the ledger for that Farmer. The existing ledger
--      trigger then recomputes member_capital_shares (total_contribution and
--      total_shares) exactly as it does for any other ledger entry.
--      No notification is sent (the notice trigger only covers member payments).
--   4. OPTIONAL, commented out: credit the discount of orders that were
--      completed BEFORE this script. Review the preview first: it changes
--      members' Capital Share and therefore loan eligibility.
--
-- WHAT IT DOES NOT CHANGE
--   The purchase totals, Benefits Tracking's purchase figures and every figure
--   that reads program_product_purchases. The discount is part of the purchase
--   (regular price - discount = net paid); it is NOT extra money, so the
--   Member Patronage Report's Total Contributions does not add it again.
--
-- The Member Patronage Report already reads this: "Discount earned" comes from
-- the purchases, "Credited to Capital Share" from the ledger, and it says so when
-- the two differ. Before this script runs, credited is 0.
--
-- RUN ORDER: any time after the order engine (m04) and member pricing (p4).
-- Not applied automatically. Run the PRE-FLIGHT first.
-- ============================================================

-- ─── PRE-FLIGHT (read-only — run each by itself) ────────────────────────────
-- A. The ledger sources in use today (expect only the four known ones):
--    SELECT source, count(*) FROM public.capital_contribution_events GROUP BY 1 ORDER BY 1;
--
-- B. The current rule on the source column:
--    SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
--     WHERE conrelid = 'public.capital_contribution_events'::regclass AND contype = 'c';
--
-- C. The orders this rule applies to (completed, member price, with a discount):
--    SELECT count(*) AS orders, coalesce(sum(discount_amount), 0) AS discount_total
--      FROM public.program_product_purchases
--     WHERE status = 'completed' AND is_member_price AND coalesce(discount_amount, 0) > 0;
-- ────────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$ BEGIN
  IF to_regclass('public.capital_contribution_events') IS NULL THEN
    RAISE EXCEPTION 'capital_contribution_events is missing.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'program_product_purchases'
                    AND column_name = 'discount_amount') THEN
    RAISE EXCEPTION 'program_product_purchases.discount_amount is missing: run member pricing (p4) first.';
  END IF;
  -- Stop (instead of rejecting existing rows) if the ledger holds a source this script does not know.
  IF EXISTS (SELECT 1 FROM public.capital_contribution_events
              WHERE source NOT IN ('member_payment', 'patronage_capital', 'manual_adjustment',
                                   'opening_balance', 'purchase_discount')) THEN
    RAISE EXCEPTION 'The ledger has a source this script does not list. Run PRE-FLIGHT A and B, then adjust the list below.';
  END IF;
END $$;

-- 1. The new source ─────────────────────────────────────────────────────────
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
    'member_payment',     -- paid toward the annual share (monthly dues)
    'patronage_capital',  -- an older payout left in the cooperative (kept; no longer offered)
    'manual_adjustment',  -- a correction (may be negative)
    'opening_balance',    -- the balance at account creation
    'purchase_discount'   -- the member-price discount on a completed Cooperative Product order
  ));

-- 2. One credit per order ────────────────────────────────────────────────────
ALTER TABLE public.capital_contribution_events
  ADD COLUMN IF NOT EXISTS reference_id uuid;

COMMENT ON COLUMN public.capital_contribution_events.reference_id IS
  'The record this entry came from (for purchase_discount: the Cooperative Product order). Lets an order credit its discount only once.';

CREATE UNIQUE INDEX IF NOT EXISTS uq_cce_purchase_discount_once
  ON public.capital_contribution_events (reference_id)
  WHERE source = 'purchase_discount';

-- 3. Credit the discount when the order is completed ─────────────────────────
CREATE OR REPLACE FUNCTION public.credit_purchase_discount_to_capital()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only a Product Sales program's member-price order earns the credit.
  IF COALESCE(NEW.is_member_price, FALSE) AND COALESCE(NEW.discount_amount, 0) > 0
     AND EXISTS (SELECT 1 FROM public.cooperative_programs p
                  WHERE p.id = NEW.program_id AND p.program_purpose = 'sales') THEN
    INSERT INTO public.capital_contribution_events
      (farmer_id, amount, source, note, recorded_by, reference_id)
    VALUES
      (NEW.farmer_id, round(NEW.discount_amount, 2), 'purchase_discount',
       'Discount on order ' || COALESCE(NEW.order_number, NEW.id::text), NULL, NEW.id)
    ON CONFLICT (reference_id) WHERE source = 'purchase_discount' DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.credit_purchase_discount_to_capital() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_credit_purchase_discount ON public.program_product_purchases;
CREATE TRIGGER trg_credit_purchase_discount
  AFTER UPDATE OF status ON public.program_product_purchases
  FOR EACH ROW
  WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed')
  EXECUTE FUNCTION public.credit_purchase_discount_to_capital();

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── 4. OPTIONAL BACKFILL — orders completed before this script ─────────────
-- Preview first (read-only). Each row below would add its discount to the member's Capital Share:
--
--   SELECT p.id, p.order_number, p.farmer_id, p.completed_at, p.discount_amount
--     FROM public.program_product_purchases p
--    WHERE p.status = 'completed' AND p.is_member_price AND coalesce(p.discount_amount, 0) > 0
--      AND NOT EXISTS (SELECT 1 FROM public.capital_contribution_events e
--                       WHERE e.source = 'purchase_discount' AND e.reference_id = p.id)
--    ORDER BY p.completed_at;
--
-- To apply it, remove the comment marks and run it by itself, once you agree
-- with the preview. It is safe to run twice (an order is credited once):
--
--   INSERT INTO public.capital_contribution_events
--     (farmer_id, amount, source, note, recorded_by, reference_id, created_at)
--   SELECT p.farmer_id, round(p.discount_amount, 2), 'purchase_discount',
--          'Discount on order ' || coalesce(p.order_number, p.id::text), NULL, p.id,
--          coalesce(p.completed_at, p.confirmed_at, now())
--     FROM public.program_product_purchases p
--    WHERE p.status = 'completed' AND p.is_member_price AND coalesce(p.discount_amount, 0) > 0
--   ON CONFLICT (reference_id) WHERE source = 'purchase_discount' DO NOTHING;

-- ─── VERIFICATION (read-only; run each by itself) ───────────────────────────
-- 1. The rule and the trigger exist:
--    SELECT conname FROM pg_constraint WHERE conname = 'cce_source_check';
--    SELECT tgname FROM pg_trigger WHERE tgname = 'trg_credit_purchase_discount';
--
-- 2. Earned vs credited, per member (the two columns agree once everything is credited):
--    SELECT p.farmer_id,
--           sum(p.discount_amount)                                   AS discount_earned,
--           coalesce((SELECT sum(e.amount) FROM public.capital_contribution_events e
--                      WHERE e.farmer_id = p.farmer_id AND e.source = 'purchase_discount'), 0) AS credited
--      FROM public.program_product_purchases p
--     WHERE p.status = 'completed' AND p.is_member_price AND coalesce(p.discount_amount, 0) > 0
--     GROUP BY p.farmer_id;
--
-- 3. The Capital Share follows the ledger:
--    SELECT s.farmer_id, s.total_contribution,
--           (SELECT greatest(sum(amount), 0) FROM public.capital_contribution_events e WHERE e.farmer_id = s.farmer_id) AS ledger
--      FROM public.member_capital_shares s;
