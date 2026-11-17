-- ============================================================
-- SAGANA — Capital Share loan eligibility: scenario test
--
-- Uses one active farmer. It sets that farmer's Capital Share to 500 through the
-- ledger, then tries loan items worth 300, 500 and 600 on a loan and on a request,
-- and Capital Share 0. It changes nothing: it ends by raising an error on purpose,
-- which rolls everything back, and the error text IS the report.
--
-- Run supabase_schema_loan_capital_eligibility.sql first. Then run this whole file.
-- ============================================================

DO $test$
DECLARE
  v_report  TEXT := E'\n';
  v_fail    INT;
  v_farmer  UUID;
  v_now     NUMERIC;
  v_loan    UUID;
  v_req     UUID;
  v_msg     TEXT;
BEGIN
  SELECT ur.user_id INTO v_farmer
    FROM user_roles ur WHERE ur.role = 'farmer' AND ur.status = 'active' LIMIT 1;
  IF v_farmer IS NULL THEN
    RAISE EXCEPTION E'NO ACTIVE FARMER to test with. Nothing was saved.';
  END IF;

  -- 1. The rule is installed ----------------------------------------------------
  v_report := v_report || CASE WHEN (SELECT count(*) FROM pg_trigger WHERE NOT tgisinternal
      AND tgname IN ('trg_farmer_loan_items_capital', 'trg_loan_request_items_capital')) = 2
    THEN 'PASS ' ELSE 'FAIL ' END || E'1  both triggers are installed\n';
  v_report := v_report || CASE WHEN pg_get_functiondef('public._loan_capital_share(uuid,boolean)'::regprocedure) ILIKE '%FOR SHARE%'
    THEN 'PASS ' ELSE 'FAIL ' END || E'2  the Capital Share is read with a lock until the transaction ends\n';

  -- 2. Put this farmer's Capital Share at exactly 500 through the ledger --------
  v_now := public._loan_capital_share(v_farmer, false);
  IF v_now <> 500 THEN
    INSERT INTO capital_contribution_events (farmer_id, amount, source, note)
    VALUES (v_farmer, 500 - v_now, 'manual_adjustment', 'capital eligibility test (rolled back)');
  END IF;
  v_report := v_report || CASE WHEN public._loan_capital_share(v_farmer, false) = 500 THEN 'PASS ' ELSE 'FAIL ' END
    || E'3  the Capital Share is read from member_capital_shares (set to 500 for the test): ' || public._loan_capital_share(v_farmer, false) || E'\n';

  -- 3. A loan: 300 and 500 pass, 600 is refused ---------------------------------
  INSERT INTO farmer_loans (farmer_id, reference_no, issued_date, total_value, amount_paid, status)
  VALUES (v_farmer, 'X', CURRENT_DATE, 100, 0, 'active') RETURNING id INTO v_loan;

  BEGIN
    INSERT INTO farmer_loan_items (loan_id, item_name, quantity, unit, unit_price, line_total) VALUES (v_loan, 'Item 300', 1, 'bag', 300, 300);
    v_report := v_report || E'PASS 4  a loan item worth 300 is allowed (Capital Share 500)\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'FAIL 4  300 was refused: ' || SQLERRM || E'\n';
  END;
  BEGIN
    INSERT INTO farmer_loan_items (loan_id, item_name, quantity, unit, unit_price, line_total) VALUES (v_loan, 'Item 500', 1, 'bag', 500, 500);
    v_report := v_report || E'PASS 5  a loan item worth exactly 500 is allowed (equal to the Capital Share)\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'FAIL 5  500 was refused: ' || SQLERRM || E'\n';
  END;
  BEGIN
    INSERT INTO farmer_loan_items (loan_id, item_name, quantity, unit, unit_price, line_total) VALUES (v_loan, 'Item 600', 1, 'bag', 600, 600);
    v_report := v_report || E'FAIL 6  a loan item worth 600 was allowed\n';
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
    v_report := v_report || CASE WHEN v_msg LIKE 'Loan not allowed:%600.00%500.00%' THEN 'PASS ' ELSE 'FAIL ' END
      || E'6  a loan item worth 600 is refused with a readable message: ' || v_msg || E'\n';
  END;
  -- The value is quantity x price even when a smaller line total is sent.
  BEGIN
    INSERT INTO farmer_loan_items (loan_id, item_name, quantity, unit, unit_price, line_total) VALUES (v_loan, '2 x 300', 2, 'bag', 300, 1);
    v_report := v_report || E'FAIL 7  2 x 300 with a line total of 1 was allowed\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || E'PASS 7  quantity x price is used, so a small line total cannot get past the rule\n';
  END;

  -- 4. A request: the same rule -------------------------------------------------
  INSERT INTO loan_requests (farmer_id, status, total_value) VALUES (v_farmer, 'pending', 100) RETURNING id INTO v_req;
  BEGIN
    INSERT INTO loan_request_items (request_id, item_name, unit, quantity, unit_price, line_total) VALUES (v_req, 'Item 500', 'bag', 1, 500, 500);
    v_report := v_report || E'PASS 8  a request line worth 500 is allowed\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'FAIL 8  ' || SQLERRM || E'\n';
  END;
  BEGIN
    INSERT INTO loan_request_items (request_id, item_name, unit, quantity, unit_price, line_total) VALUES (v_req, 'Item 600', 'bag', 1, 600, 600);
    v_report := v_report || E'FAIL 9  a request line worth 600 was allowed\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || E'PASS 9  a request line worth 600 is refused\n';
  END;

  -- 5. Capital Share changes between request and approval -----------------------
  INSERT INTO capital_contribution_events (farmer_id, amount, source, note)
  VALUES (v_farmer, -300, 'manual_adjustment', 'capital eligibility test (rolled back)');
  v_report := v_report || CASE WHEN public._loan_capital_share(v_farmer, false) = 200 THEN 'PASS ' ELSE 'FAIL ' END
    || E'10 the Capital Share fell to 200: ' || public._loan_capital_share(v_farmer, false) || E'\n';
  BEGIN
    INSERT INTO farmer_loan_items (loan_id, item_name, quantity, unit, unit_price, line_total) VALUES (v_loan, 'Item 300 again', 1, 'bag', 300, 300);
    v_report := v_report || E'FAIL 11 an item worth 300 was allowed after the Capital Share fell to 200\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || E'PASS 11 the same 300 item is now refused: the check uses the CURRENT Capital Share (an approval after the Capital Share fell is refused)\n';
  END;

  -- 6. Zero Capital Share -------------------------------------------------------
  INSERT INTO capital_contribution_events (farmer_id, amount, source, note)
  VALUES (v_farmer, -200, 'manual_adjustment', 'capital eligibility test (rolled back)');
  BEGIN
    INSERT INTO farmer_loan_items (loan_id, item_name, quantity, unit, unit_price, line_total) VALUES (v_loan, 'Cheap', 1, 'bag', 1, 1);
    v_report := v_report || E'FAIL 12 an item was allowed with a Capital Share of 0\n';
  EXCEPTION WHEN OTHERS THEN
    v_msg := SQLERRM;
    v_report := v_report || CASE WHEN v_msg LIKE '%Capital Share is ₱0.00%' THEN 'PASS ' ELSE 'FAIL ' END
      || E'12 a Capital Share of 0 allows no loan item: ' || v_msg || E'\n';
  END;

  v_fail := (length(v_report) - length(replace(v_report, E'\nFAIL ', ''))) / 6;
  RAISE EXCEPTION E'CAPITAL SHARE LOAN ELIGIBILITY TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_report, v_fail;
END
$test$;
