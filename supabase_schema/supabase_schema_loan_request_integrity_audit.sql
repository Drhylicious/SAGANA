-- ============================================================
-- SAGANA — Loans, loan requests and inventory: integrity AUDIT (read-only)
--
-- One query. It changes nothing. Every row should show 0 violations. It answers:
--   * Is cooperative inventory taken ONLY when a loan is issued? (A request, a
--     pending request, a disapproved or cancelled one never has a loan or a stock
--     movement; an approved request is exactly one loan.)
--   * Was any item deducted twice, or by a different quantity than the loan says?
--   * Is any stock negative, or any loan balance inconsistent?
--
-- Run it in the Supabase SQL editor. Any row that is not 0 lists WHAT to look at in
-- the HINT column. Then, if you want the database to refuse the duplicate /
-- negative-stock cases outright, run supabase_schema_loan_request_integrity_hardening.sql.
-- ============================================================

WITH checks(area, item, violations, hint) AS (
  VALUES
  -- Requests <-> loans
  ('requests', 'approved request with no loan',
     (SELECT count(*) FROM public.loan_requests WHERE status = 'approved' AND loan_id IS NULL),
     'An approved request must be exactly one issued loan.'),
  ('requests', 'request that is NOT approved but has a loan',
     (SELECT count(*) FROM public.loan_requests WHERE status <> 'approved' AND loan_id IS NOT NULL),
     'Pending, disapproved and cancelled requests must never have a loan.'),
  ('requests', 'one loan linked to two requests',
     (SELECT count(*) FROM (SELECT loan_id FROM public.loan_requests WHERE loan_id IS NOT NULL
                            GROUP BY loan_id HAVING count(*) > 1) d),
     'A loan can come from one request only.'),
  ('requests', 'decided request with no deciding staff member',
     (SELECT count(*) FROM public.loan_requests WHERE status IN ('approved', 'disapproved')
                AND (reviewed_by IS NULL OR reviewed_at IS NULL)),
     'Every decision records who decided and when (older rows from before staff names were kept are not expected here).'),

  -- Inventory movements
  ('inventory', 'loan deduction that belongs to no loan',
     (SELECT count(*) FROM public.inventory_transactions t
       WHERE t.transaction_type = 'loan_issued' AND t.reference_type = 'loan'
         AND NOT EXISTS (SELECT 1 FROM public.farmer_loans l WHERE l.id = t.reference_id)),
     'Stock left the shelf for a loan that does not exist.'),
  ('inventory', 'same item deducted twice for one loan',
     (SELECT count(*) FROM (SELECT reference_id, inventory_id FROM public.inventory_transactions
                            WHERE transaction_type = 'loan_issued' AND reference_type = 'loan'
                            GROUP BY reference_id, inventory_id HAVING count(*) > 1) d),
     'Duplicate deduction. (A loan listing the same item on two lines also shows here.)'),
  ('inventory', 'deducted quantity differs from the approved request',
     (SELECT count(*) FROM public.loan_requests lr
        JOIN public.loan_request_items i ON i.request_id = lr.id
        LEFT JOIN LATERAL (
          SELECT COALESCE(-sum(t.quantity), 0) AS taken
            FROM public.inventory_transactions t
           WHERE t.reference_id = lr.loan_id AND t.reference_type = 'loan'
             AND t.transaction_type = 'loan_issued' AND t.inventory_id = i.inventory_item_id
        ) d ON TRUE
       WHERE lr.status = 'approved' AND abs(d.taken - i.quantity) > 0.005),
     'The stock taken for an approved request must equal what the request asked for, once.'),
  ('inventory', 'negative stock on hand',
     (SELECT count(*) FROM public.cooperative_inventory WHERE quantity_on_hand < 0),
     'Stock went below zero: an issuance was allowed without enough stock.'),

  -- Loan balances
  ('loans', 'loan total differs from the sum of its items',
     (SELECT count(*) FROM public.farmer_loans l
       WHERE abs(l.total_value - COALESCE((SELECT sum(i.line_total) FROM public.farmer_loan_items i WHERE i.loan_id = l.id), 0)) > 0.005),
     'total_value must equal the item lines.'),
  ('loans', 'amount paid differs from the sum of its payments',
     (SELECT count(*) FROM public.farmer_loans l
       WHERE abs(COALESCE(l.amount_paid, 0) - COALESCE((SELECT sum(p.amount_paid) FROM public.farmer_loan_payments p WHERE p.loan_id = l.id), 0)) > 0.005),
     'amount_paid must equal the payments recorded (a loan settled with "Mark as Paid" and no payment shows here by design).'),
  ('loans', 'last payment shows the wrong balance',
     (SELECT count(*) FROM (
         SELECT DISTINCT ON (p.loan_id) p.loan_id, p.running_balance
           FROM public.farmer_loan_payments p
          ORDER BY p.loan_id, p.payment_date DESC, p.created_at DESC) lp
        JOIN public.farmer_loans l ON l.id = lp.loan_id
       WHERE abs(lp.running_balance - GREATEST(l.total_value - COALESCE(l.amount_paid, 0), 0)) > 0.005),
     'The newest payment''s balance must equal total minus amount paid.'),
  ('loans', 'fully paid but not marked paid',
     (SELECT count(*) FROM public.farmer_loans
       WHERE status <> 'paid' AND COALESCE(amount_paid, 0) >= total_value - 0.005),
     'A loan with nothing left to pay must be Paid.'),
  ('loans', 'paid more than the loan is worth',
     (SELECT count(*) FROM public.farmer_loans WHERE COALESCE(amount_paid, 0) > total_value + 0.005),
     'Overpayment.')
)
SELECT area,
       item,
       violations,
       CASE WHEN violations = 0 THEN 'OK' ELSE 'CHECK' END AS status,
       CASE WHEN violations = 0 THEN '' ELSE hint END AS hint
FROM checks
ORDER BY (violations = 0), area, item;
