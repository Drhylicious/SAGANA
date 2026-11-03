-- ============================================================
-- SAGANA — Offer to Cooperative: a reference number on every completed sale
--
-- Farmer Transaction History, the Manager / Officer Sales Report and the offer
-- screens all show a "Reference No." for a completed Offer to Cooperative sale. The
-- sale row (member_sales_transactions) is created by
-- confirm_cooperative_offer_receipt(), which has never set one, so the reference
-- has been empty for every offer sale. This script makes the database issue it:
--
--     OTC-20261030-A001
--         |        |
--         |        +-- sequence for the YEAR: A001 ... A999, B001 ... (the same
--         |            layout function Orders and Loans use)
--         +----------- the Philippine date the sale was recorded
--
--   * A BEFORE INSERT trigger on member_sales_transactions issues it when the row
--     has none, so it does not matter which function or screen writes the sale.
--     confirm_cooperative_offer_receipt() is NOT touched.
--   * A reference that is already there (any older style) is kept as it is, and a
--     reference can never be changed once set.
--   * Existing sales with no reference are numbered once, oldest first, so history
--     and reports show one for every sale. Nothing else about them changes (not the
--     amount, date, quantity, farmer or the staff member who recorded it).
--
-- Not applied automatically. Run in the Supabase SQL editor, then the verification
-- block at the end. Safe to re-run.
-- Requires supabase_schema_order_number.sql (format_order_sequence).
-- ============================================================

-- ─── PRE-FLIGHT (read-only) ──────────────────────────────────────────────
-- A. Sales that will be numbered (the ones with no reference today):
--    SELECT count(*) FROM public.member_sales_transactions WHERE reference_no IS NULL OR btrim(reference_no) = '';
-- B. Sales that already have a reference (kept as they are):
--    SELECT reference_no FROM public.member_sales_transactions WHERE reference_no IS NOT NULL AND btrim(reference_no) <> '' LIMIT 10;
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

DO $$
BEGIN
  IF to_regclass('public.member_sales_transactions') IS NULL THEN
    RAISE EXCEPTION 'public.member_sales_transactions is missing.';
  END IF;
  IF to_regprocedure('public.format_order_sequence(integer)') IS NULL THEN
    RAISE EXCEPTION 'format_order_sequence() is missing. Run supabase_schema_order_number.sql first.';
  END IF;
END;
$$;

-- ═══ 1. The yearly counter ══════════════════════════════════════════════
CREATE TABLE IF NOT EXISTS public.coop_sale_reference_counters (
  year      INTEGER PRIMARY KEY CHECK (year BETWEEN 2000 AND 9999),
  last_seq  INTEGER NOT NULL CHECK (last_seq >= 0)
);
ALTER TABLE public.coop_sale_reference_counters ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.coop_sale_reference_counters FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.next_coop_sale_reference(p_at TIMESTAMPTZ DEFAULT NOW())
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_local TIMESTAMP;
  v_year  INTEGER;
  v_seq   INTEGER;
BEGIN
  v_local := p_at AT TIME ZONE 'Asia/Manila';
  v_year  := EXTRACT(YEAR FROM v_local)::INTEGER;
  INSERT INTO coop_sale_reference_counters (year, last_seq)
  VALUES (v_year, 1)
  ON CONFLICT (year) DO UPDATE SET last_seq = coop_sale_reference_counters.last_seq + 1
  RETURNING last_seq INTO v_seq;
  RETURN 'OTC-' || to_char(v_local, 'YYYYMMDD') || '-' || public.format_order_sequence(v_seq);
END;
$$;
REVOKE ALL ON FUNCTION public.next_coop_sale_reference(TIMESTAMPTZ) FROM PUBLIC, anon, authenticated;

-- ═══ 2. Triggers on member_sales_transactions ═══════════════════════════
CREATE OR REPLACE FUNCTION public.assign_coop_sale_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.reference_no IS NULL OR btrim(NEW.reference_no) = '' THEN
    NEW.reference_no := public.next_coop_sale_reference(COALESCE(NEW.created_at, NOW()));
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_member_sales_assign_reference ON public.member_sales_transactions;
CREATE TRIGGER trg_member_sales_assign_reference
  BEFORE INSERT ON public.member_sales_transactions
  FOR EACH ROW EXECUTE FUNCTION public.assign_coop_sale_reference();

CREATE OR REPLACE FUNCTION public.protect_coop_sale_reference()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.reference_no IS NOT NULL AND btrim(OLD.reference_no) <> ''
     AND NEW.reference_no IS DISTINCT FROM OLD.reference_no THEN
    RAISE EXCEPTION 'A sale reference number cannot be changed.';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_member_sales_protect_reference ON public.member_sales_transactions;
CREATE TRIGGER trg_member_sales_protect_reference
  BEFORE UPDATE OF reference_no ON public.member_sales_transactions
  FOR EACH ROW EXECUTE FUNCTION public.protect_coop_sale_reference();

-- ═══ 3. Number the sales that have none, oldest first ═══════════════════
-- Only reference_no is written. The protect trigger allows it: these rows have none.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT id, created_at
      FROM public.member_sales_transactions
     WHERE reference_no IS NULL OR btrim(reference_no) = ''
     ORDER BY created_at, id
  LOOP
    UPDATE public.member_sales_transactions
       SET reference_no = public.next_coop_sale_reference(COALESCE(r.created_at, NOW()))
     WHERE id = r.id;
  END LOOP;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- 1. Every sale has a reference (expect 0):
--    SELECT count(*) FROM public.member_sales_transactions WHERE reference_no IS NULL OR btrim(reference_no) = '';
-- 2. No duplicates among the new OTC references (expect 0 rows):
--    SELECT reference_no, count(*) FROM public.member_sales_transactions
--    WHERE reference_no LIKE 'OTC-%' GROUP BY 1 HAVING count(*) > 1;
-- 3. The shape of every new reference (expect 0 rows):
--    SELECT id, reference_no FROM public.member_sales_transactions
--    WHERE reference_no LIKE 'OTC-%' AND reference_no !~ '^OTC-[0-9]{8}-[A-Z]+[0-9]{3}$';
-- 4. Amounts, dates and quantities were not touched (compare with the pre-change
--    totals you noted):
--    SELECT count(*), sum(amount), sum(quantity_kg) FROM public.member_sales_transactions;
-- 5. After the next completed offer, the new sale carries its reference:
--    SELECT t.reference_no, o.status, o.received_at FROM public.member_sales_transactions t
--    JOIN public.cooperative_purchase_offers o ON o.member_sales_transaction_id = t.id
--    ORDER BY o.received_at DESC NULLS LAST LIMIT 5;
-- ─────────────────────────────────────────────────────────────────────────
