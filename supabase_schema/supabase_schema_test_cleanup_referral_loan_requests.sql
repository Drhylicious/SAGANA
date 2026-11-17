-- ============================================================
-- SAGANA — TEST DATA CLEANUP: the two loan requests sent from the old "Referred -> Request a Loan" flow
--
-- FOR YOUR REVIEW — NOT APPLIED. Run STEP 1 first (read-only) and check what it lists. Run STEP 2 only if it is what
-- you expect. STEP 2 is one transaction: any problem undoes all of it.
--
-- What is removed (Jhon Drhy M. Salangsang's two test requests on Nov 14, 2026):
--   * LQR-20261114-A001   Disapproved loan request
--   * LQR-20261114-A002   Approved loan request, and the real loan it issued: LRN-20261114-A002 (₱120.00, nothing paid)
--   * their items, and the notices they sent (to the Farmer and to staff)
--
-- What is NOT removed, on purpose (these are protected records, not displayed data):
--   * The stock ledger: approving A002 took 1 kg of Peanut Seeds out of stock and wrote an inventory log row.
--     The ledger cannot be edited or deleted. Put the 1 kg back in the app (Inventory Management -> add stock, with a
--     note such as "Restore test loan LRN-20261114-A002"), so the ledger shows both movements.
--   * The staff activity log and workflow history for those requests (kept for accountability).
--   * The assistance and loan number counters: the next loan request number is simply A003.
-- ============================================================

-- ═══ STEP 1 — PREVIEW (read-only) ═══════════════════════════════════════════
-- 1a. The requests and the loan (expect 2 requests, 1 loan, all Jhon's):
SELECT lr.request_no, lr.status, ui.full_name AS farmer, fl.reference_no AS loan_reference,
       fl.status AS loan_status, fl.total_value, fl.amount_paid
  FROM loan_requests lr
  LEFT JOIN user_information ui ON ui.user_id = lr.farmer_id
  LEFT JOIN farmer_loans fl ON fl.id = lr.loan_id
 WHERE lr.request_no IN ('LQR-20261114-A001', 'LQR-20261114-A002');

-- 1b. Payments on that loan (expect 0 rows; if there are any, STOP and tell me):
SELECT p.* FROM farmer_loan_payments p
  JOIN farmer_loans fl ON fl.id = p.loan_id WHERE fl.reference_no = 'LRN-20261114-A002';

-- 1c. The notices that mention them (these are deleted):
SELECT n.id, n.type, n.title, left(n.body, 90) AS body
  FROM notifications n
 WHERE n.body LIKE '%LQR-20261114-A001%' OR n.body LIKE '%LQR-20261114-A002%' OR n.body LIKE '%LRN-20261114-A002%';

-- ═══ STEP 2 — CLEANUP (run only after checking STEP 1) ══════════════════════
BEGIN;

DO $$
DECLARE
  v_loan UUID;
  v_pay  INTEGER;
BEGIN
  SELECT id INTO v_loan FROM farmer_loans WHERE reference_no = 'LRN-20261114-A002';
  IF v_loan IS NOT NULL THEN
    SELECT count(*) INTO v_pay FROM farmer_loan_payments WHERE loan_id = v_loan;
    IF v_pay > 0 THEN
      RAISE EXCEPTION 'This loan already has % payment(s). Nothing was deleted.', v_pay;
    END IF;
    IF EXISTS (SELECT 1 FROM farmer_loans WHERE id = v_loan AND (amount_paid > 0 OR total_value <> 120.00)) THEN
      RAISE EXCEPTION 'This loan is not the ₱120.00 unpaid test loan. Nothing was deleted.';
    END IF;
  END IF;
END $$;

-- Notices first (they only mention the numbers).
DELETE FROM notifications
 WHERE body LIKE '%LQR-20261114-A001%' OR body LIKE '%LQR-20261114-A002%' OR body LIKE '%LRN-20261114-A002%';

-- The requests (their items go with them), then the loan (its items go with it).
DELETE FROM loan_requests WHERE request_no IN ('LQR-20261114-A001', 'LQR-20261114-A002');
DELETE FROM farmer_loans  WHERE reference_no = 'LRN-20261114-A002';

COMMIT;

-- CHECK (expect 0, 0):
--   SELECT (SELECT count(*) FROM loan_requests WHERE request_no IN ('LQR-20261114-A001', 'LQR-20261114-A002')) AS requests,
--          (SELECT count(*) FROM farmer_loans WHERE reference_no = 'LRN-20261114-A002') AS loans;
