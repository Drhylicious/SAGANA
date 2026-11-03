-- ============================================================
-- SAGANA — Farmer loan requests: scenario test
--
-- Runs the loan-request flow as the real database sees it, signed in as a Farmer
-- and as a Manager / Officer in turn, and prints PASS / FAIL for each rule. It
-- changes nothing: it ends by raising an error on purpose, which rolls everything
-- back, and the error text IS the report (in the Supabase SQL editor the report
-- appears as the error message).
--
-- Run supabase_schema_farmer_loan_requests.sql first. Then run this whole file.
--
-- It needs: an ACTIVE farmer, a Manager or Officer, and one loan-eligible inventory
-- item with at least 3 units in stock. They are found automatically; if none is
-- found the error says what is missing.
-- ============================================================

DO $test$
DECLARE
  v_report  TEXT := E'\n';
  v_fail    INT;
  v_farmer  UUID;
  v_staff   UUID;
  v_other   UUID;
  v_inv     UUID;
  v_name    TEXT;
  v_stock0  NUMERIC;
  v_stock   NUMERIC;
  v_price   NUMERIC;
  v_req     UUID;
  v_no      TEXT;
  v_req2    UUID;
  v_n       INT;
  v_status  TEXT;
  v_loan    UUID;
  v_ref     TEXT;
  v_capital NUMERIC;
  v_json    JSONB;
  v_actor   UUID;
BEGIN
  SELECT ur.user_id INTO v_farmer FROM user_roles ur WHERE ur.role = 'farmer' AND ur.status = 'active' ORDER BY ur.user_id LIMIT 1;
  SELECT ur.user_id INTO v_staff  FROM user_roles ur WHERE ur.role IN ('admin', 'officer') AND ur.status = 'active' ORDER BY (ur.role = 'admin') DESC LIMIT 1;
  SELECT ur.user_id INTO v_other  FROM user_roles ur WHERE ur.role = 'farmer' AND ur.status = 'active' AND ur.user_id <> COALESCE(v_farmer, '00000000-0000-0000-0000-000000000000') LIMIT 1;
  SELECT ci.id, ci.item_name, ci.quantity_on_hand, lim.unit_price INTO v_inv, v_name, v_stock0, v_price
    FROM loan_items_master lim JOIN cooperative_inventory ci ON ci.id = lim.inventory_item_id
   WHERE lim.is_loan_eligible AND ci.is_active AND ci.quantity_on_hand >= 3 AND lim.unit_price > 0
   ORDER BY ci.quantity_on_hand DESC LIMIT 1;

  IF v_farmer IS NULL OR v_staff IS NULL OR v_inv IS NULL THEN
    RAISE EXCEPTION 'Nothing suitable found. Need an ACTIVE farmer (found: %), a Manager/Officer (found: %) and a loan-eligible, active inventory item with at least 3 in stock and a price above 0 (found: %).',
      COALESCE(v_farmer::text, 'none'), COALESCE(v_staff::text, 'none'), COALESCE(v_inv::text, 'none');
  END IF;

  -- The farmer has NO capital shares: the removed gate must not matter.
  SELECT COALESCE(total_contribution, 0) INTO v_capital FROM member_capital_shares WHERE farmer_id = v_farmer;
  DELETE FROM member_capital_shares WHERE farmer_id = v_farmer;

  -- 1. The catalog shows the live stock -------------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT quantity_on_hand INTO v_stock FROM public.list_loanable_items() WHERE inventory_item_id = v_inv;
  EXECUTE 'RESET ROLE';
  v_report := v_report || CASE WHEN v_stock = v_stock0 THEN 'PASS ' ELSE 'FAIL ' END
    || E'1  the loan catalog shows the real stock on hand (' || COALESCE(v_stock::text, 'null') || E')\n';

  -- 2. More than the stock is refused ---------------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.submit_loan_request(jsonb_build_array(jsonb_build_object('inventoryItemId', v_inv, 'quantity', v_stock0 + 1)));
    v_report := v_report || E'FAIL 2  a request for more than the stock was accepted\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 2  more than the stock is refused (' || SQLERRM || E')\n';
  END;
  -- 3. Zero / negative / too many decimals are refused ----------------------
  BEGIN
    PERFORM public.submit_loan_request(jsonb_build_array(jsonb_build_object('inventoryItemId', v_inv, 'quantity', 0)));
    v_report := v_report || E'FAIL 3a a zero quantity was accepted\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 3a a zero quantity is refused (' || SQLERRM || E')\n';
  END;
  BEGIN
    PERFORM public.submit_loan_request(jsonb_build_array(jsonb_build_object('inventoryItemId', v_inv, 'quantity', 1.234)));
    v_report := v_report || E'FAIL 3b three decimals were accepted\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 3b more than 2 decimals is refused (' || SQLERRM || E')\n';
  END;
  -- 4. The same item twice is refused ---------------------------------------
  BEGIN
    PERFORM public.submit_loan_request(jsonb_build_array(
      jsonb_build_object('inventoryItemId', v_inv, 'quantity', 1),
      jsonb_build_object('inventoryItemId', v_inv, 'quantity', 1)));
    v_report := v_report || E'FAIL 4  the same item twice was accepted\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 4  the same item twice is refused (' || SQLERRM || E')\n';
  END;
  EXECUTE 'RESET ROLE';

  -- 5. A valid request: pending, numbered, priced by the catalog -----------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT s.new_request_id, s.new_request_no INTO v_req, v_no
    FROM public.submit_loan_request(
      jsonb_build_array(jsonb_build_object('inventoryItemId', v_inv, 'quantity', 2, 'unitPrice', 0.01)),
      'test request', 'test-key-1') s;
  -- A replay with the same key returns the same request.
  SELECT s.new_request_id INTO v_req2 FROM public.submit_loan_request(
      jsonb_build_array(jsonb_build_object('inventoryItemId', v_inv, 'quantity', 2)), NULL, 'test-key-1') s;
  EXECUTE 'RESET ROLE';
  SELECT status, total_value INTO v_status, v_stock FROM loan_requests WHERE id = v_req;
  v_report := v_report || CASE WHEN v_status = 'pending' AND v_no ~ '^LQR-[0-9]{8}-[A-Z]+[0-9]{3}$'
      AND v_stock = round(2 * v_price, 2) THEN 'PASS ' ELSE 'FAIL ' END
    || E'5  valid request is pending, numbered ' || v_no || ' and priced from the catalog (a client price is ignored)' || E'\n';
  v_report := v_report || CASE WHEN v_req2 = v_req THEN 'PASS ' ELSE 'FAIL ' END
    || E'6  a replay with the same key returns the same request, no duplicate\n';

  -- 7. Staff were told ------------------------------------------------------
  SELECT count(*) INTO v_n FROM notifications
   WHERE user_id = v_staff AND title = 'New Loan Request' AND created_at > NOW() - INTERVAL '1 minute';
  v_report := v_report || CASE WHEN v_n > 0 THEN 'PASS ' ELSE 'FAIL ' END || E'7  staff were notified of the new request\n';

  -- 8. The request did not take stock --------------------------------------
  SELECT quantity_on_hand INTO v_stock FROM cooperative_inventory WHERE id = v_inv;
  v_report := v_report || CASE WHEN v_stock = v_stock0 THEN 'PASS ' ELSE 'FAIL ' END
    || E'8  a pending request does not move stock\n';

  -- 9. A Farmer cannot read the tables, and cannot review ------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT count(*) INTO v_n FROM public.loan_requests;
  v_report := v_report || CASE WHEN v_n = 0 THEN 'PASS ' ELSE 'FAIL ' END
    || E'9a a farmer cannot read loan_requests directly (rows seen: ' || v_n || E')\n';
  v_json := public.get_my_loan_requests();
  v_report := v_report || CASE WHEN jsonb_array_length(v_json) >= 1 AND NOT (v_json->0 ? 'reviewed_by') THEN 'PASS ' ELSE 'FAIL ' END
    || E'9b get_my_loan_requests() returns the farmer''s own request with no reviewer\n';
  BEGIN
    PERFORM public.review_loan_request(v_req, 'approve', NULL, 100, CURRENT_DATE + 30, NULL);
    v_report := v_report || E'FAIL 9c a farmer approved their own request\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 9c a farmer cannot review a request (' || SQLERRM || E')\n';
  END;
  EXECUTE 'RESET ROLE';

  -- 10. Another farmer cannot cancel it ------------------------------------
  IF v_other IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
      PERFORM public.cancel_loan_request(v_req);
      v_report := v_report || E'FAIL 10 another farmer cancelled the request\n';
    EXCEPTION WHEN OTHERS THEN
      v_report := v_report || 'PASS 10 another farmer cannot cancel it (' || SQLERRM || E')\n';
    END;
    EXECUTE 'RESET ROLE';
  END IF;

  -- 11. Disapproval needs a reason -----------------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.review_loan_request(v_req, 'disapprove', '   ');
    v_report := v_report || E'FAIL 11 a disapproval without a reason was accepted\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 11 a disapproval needs a reason (' || SQLERRM || E')\n';
  END;
  EXECUTE 'RESET ROLE';

  -- 12. Approve: the loan is issued with NO capital shares ------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT r.out_loan_id, r.out_reference_no INTO v_loan, v_ref
    FROM public.review_loan_request(v_req, 'approve', 'ok', 250, CURRENT_DATE + 30, NULL) r;
  EXECUTE 'RESET ROLE';
  SELECT status, reviewed_by INTO v_status, v_actor FROM loan_requests WHERE id = v_req;
  v_report := v_report || CASE WHEN v_status = 'approved' AND v_actor = v_staff AND v_loan IS NOT NULL AND v_ref LIKE 'LRN-%' THEN 'PASS ' ELSE 'FAIL ' END
    || E'12 approval issued loan ' || COALESCE(v_ref, 'none') || E' with no capital shares, and saved the deciding staff member\n';

  SELECT quantity_on_hand INTO v_stock FROM cooperative_inventory WHERE id = v_inv;
  v_report := v_report || CASE WHEN v_stock = v_stock0 - 2 THEN 'PASS ' ELSE 'FAIL ' END
    || E'13 stock moved exactly once (' || v_stock0 || ' -> ' || v_stock || E')\n';
  SELECT count(*) INTO v_n FROM inventory_transactions WHERE reference_id = v_loan AND reference_type = 'loan';
  v_report := v_report || CASE WHEN v_n = 1 THEN 'PASS ' ELSE 'FAIL ' END || E'14 one inventory log line for the loan\n';

  -- 15. Deciding twice is refused ------------------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.review_loan_request(v_req, 'approve', NULL, 250, CURRENT_DATE + 30, NULL);
    v_report := v_report || E'FAIL 15 an approved request was approved again\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 15 a decided request cannot be decided again (' || SQLERRM || E')\n';
  END;
  EXECUTE 'RESET ROLE';

  -- 16. History: who did what ----------------------------------------------
  SELECT count(*) INTO v_n FROM workflow_events
   WHERE entity_type = 'loan_request' AND entity_id = v_req
     AND ((action = 'submitted' AND actor_id = v_farmer AND actor_role = 'farmer')
       OR (action = 'approved'  AND actor_id = v_staff));
  v_report := v_report || CASE WHEN v_n = 2 THEN 'PASS ' ELSE 'FAIL ' END
    || E'16a the request history names the farmer (submitted) and the staff member (approved)\n';
  SELECT count(*) INTO v_n FROM workflow_events
   WHERE entity_type = 'loan' AND entity_id = v_loan AND action = 'issued' AND actor_id = v_staff;
  v_report := v_report || CASE WHEN v_n = 1 THEN 'PASS ' ELSE 'FAIL ' END
    || E'16b the loan history records who issued it\n';

  -- 17. Stock that ran out between request and approval blocks the approval --
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  SELECT s.new_request_id INTO v_req2 FROM public.submit_loan_request(
      jsonb_build_array(jsonb_build_object('inventoryItemId', v_inv, 'quantity', 1))) s;
  EXECUTE 'RESET ROLE';
  UPDATE cooperative_inventory SET quantity_on_hand = 0 WHERE id = v_inv;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_staff, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.review_loan_request(v_req2, 'approve', NULL, 100, CURRENT_DATE + 30, NULL);
    v_report := v_report || E'FAIL 17 approved with no stock\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 17 approval is refused when the stock has run out (' || SQLERRM || E')\n';
  END;
  EXECUTE 'RESET ROLE';
  SELECT status INTO v_status FROM loan_requests WHERE id = v_req2;
  v_report := v_report || CASE WHEN v_status = 'pending' THEN 'PASS ' ELSE 'FAIL ' END
    || E'18 the refused approval left the request pending\n';

  -- 19. A zero-stock item cannot be requested ------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.submit_loan_request(jsonb_build_array(jsonb_build_object('inventoryItemId', v_inv, 'quantity', 1)));
    v_report := v_report || E'FAIL 19 an out-of-stock item was accepted\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 19 an item with zero stock cannot be requested (' || SQLERRM || E')\n';
  END;
  -- 20. The farmer cancels a pending request -------------------------------
  PERFORM public.cancel_loan_request(v_req2);
  EXECUTE 'RESET ROLE';
  SELECT status INTO v_status FROM loan_requests WHERE id = v_req2;
  v_report := v_report || CASE WHEN v_status = 'cancelled' THEN 'PASS ' ELSE 'FAIL ' END
    || E'20 the farmer can cancel a pending request\n';

  v_fail := (length(v_report) - length(replace(v_report, E'\nFAIL ', ''))) / 6;
  -- Raising rolls EVERYTHING above back, then shows the report.
  RAISE EXCEPTION E'LOAN REQUEST TEST REPORT (nothing was saved; the farmer''s capital row was only removed inside this test)\n% \nFAILED CHECKS: %', v_report, v_fail;
END
$test$;
