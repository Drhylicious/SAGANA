-- ============================================================
-- SAGANA — Loans: database-level guards against duplicate deductions and
--          negative stock
--
-- OPTIONAL. Run supabase_schema_loan_request_integrity_audit.sql first; this file
-- adds two guards, and each one is created ONLY if the data already satisfies it
-- (otherwise it is skipped with a NOTICE that says why, and nothing is changed).
--
--   1. One stock deduction per item per loan. issue_loan() already deducts each
--      item once and a replay returns the first loan, so this changes nothing for
--      normal use. It makes the database REFUSE a second deduction for the same
--      item on the same loan, whatever code path tries it.
--   2. Stock on hand can never go below zero. issue_loan() already refuses an
--      issuance without enough stock; this refuses it at the table too.
--
-- Nothing is deleted or changed. Safe to re-run.
-- ============================================================

BEGIN;

DO $$
BEGIN
  -- 1. One 'loan_issued' deduction per (loan, inventory item) ----------------
  IF to_regclass('public.uq_inventory_loan_issue_once') IS NOT NULL THEN
    RAISE NOTICE 'Guard 1 already exists.';
  ELSIF EXISTS (
    SELECT 1 FROM public.inventory_transactions
     WHERE transaction_type = 'loan_issued' AND reference_type = 'loan'
     GROUP BY reference_id, inventory_id HAVING count(*) > 1
  ) THEN
    RAISE NOTICE 'Guard 1 SKIPPED: some loans already have the same item deducted more than once (see the audit). Fix those first.';
  ELSE
    CREATE UNIQUE INDEX uq_inventory_loan_issue_once
      ON public.inventory_transactions (reference_id, inventory_id)
      WHERE transaction_type = 'loan_issued' AND reference_type = 'loan';
    RAISE NOTICE 'Guard 1 created.';
  END IF;

  -- 2. No negative stock ----------------------------------------------------
  IF EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.cooperative_inventory'::regclass
       AND contype = 'c'
       AND pg_get_constraintdef(oid) ILIKE '%quantity_on_hand%>=%0%'
  ) THEN
    RAISE NOTICE 'Guard 2 already exists.';
  ELSIF EXISTS (SELECT 1 FROM public.cooperative_inventory WHERE quantity_on_hand < 0) THEN
    RAISE NOTICE 'Guard 2 SKIPPED: some items already have negative stock (see the audit). Correct them first.';
  ELSE
    ALTER TABLE public.cooperative_inventory
      ADD CONSTRAINT cooperative_inventory_quantity_non_negative CHECK (quantity_on_hand >= 0);
    RAISE NOTICE 'Guard 2 created.';
  END IF;
END;
$$;

COMMIT;

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- Which guards exist (expect 2 rows once both were created):
--   SELECT 'unique deduction per loan item' AS guard WHERE to_regclass('public.uq_inventory_loan_issue_once') IS NOT NULL
--   UNION ALL
--   SELECT 'stock never negative' WHERE EXISTS (SELECT 1 FROM pg_constraint
--     WHERE conrelid = 'public.cooperative_inventory'::regclass AND contype = 'c'
--       AND pg_get_constraintdef(oid) ILIKE '%quantity_on_hand%>=%0%');
-- ─────────────────────────────────────────────────────────────────────────
