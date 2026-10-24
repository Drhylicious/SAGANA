-- ============================================================
-- SAGANA — Offer to Cooperative negotiation: scenario test
--
-- Runs the whole negotiation as the real database sees it, signed in as a
-- Farmer and as a Manager in turn, and prints PASS / FAIL for each rule. It
-- changes nothing: the script ends by raising an error on purpose, which rolls
-- everything back, and the error text IS the report. (In the Supabase SQL
-- editor the report appears as the error message.)
--
-- Run supabase_schema_coop_offer_negotiation.sql first.
--
-- STEP 1 (optional). The ids below are found automatically when left NULL. To
--         choose them yourself, find them with these queries and paste them
--         into the DECLARE section:
--
--   -- an eligible batch with kg available (not Ginger):
--   SELECT b.id AS batch_id, b.farmer_id, b.crop_name, b.available_kg
--   FROM public.inventory_batches b
--   WHERE b.is_coop_eligible AND b.available_kg >= 20
--   ORDER BY b.available_kg DESC LIMIT 5;
--
--   -- a Manager or Officer:
--   SELECT user_id, role FROM public.user_roles WHERE role IN ('admin','officer') LIMIT 5;
--
--   -- a DIFFERENT farmer, to prove one farmer cannot touch another's offer
--   -- (optional; leave NULL to skip):
--   SELECT user_id FROM public.user_roles WHERE role = 'farmer' AND status = 'active' LIMIT 5;
--
--   -- a Ginger batch (optional; leave NULL to skip). Ginger must be refused:
--   SELECT b.id FROM public.inventory_batches b WHERE b.exclusive_channel IS NOT NULL LIMIT 1;
--
-- STEP 2. Run this whole file. The result is an "error" whose text is the
--         report (that is how nothing gets saved).
-- ============================================================

DO $test$
DECLARE
  -- ── paste your ids here ──────────────────────────────────
  v_batch         UUID := NULL;   -- eligible batch, >= 20 kg available
  v_farmer        UUID := NULL;   -- the batch's owner (batch.farmer_id)
  v_manager       UUID := NULL;   -- a Manager or Officer
  v_other_farmer  UUID := NULL;   -- optional: another farmer
  v_ginger_batch  UUID := NULL;   -- optional: a Ginger / DA-AMAD-only batch
  -- ─────────────────────────────────────────────────────────

  v_report   TEXT := E'\n';
  v_fail     INT  := 0;
  v_offer    UUID;
  v_offer2   UUID;
  v_offer3   UUID;
  v_tx       UUID;
  v_avail0   NUMERIC;
  v_avail    NUMERIC;
  v_row      RECORD;
  v_n        INT;
  v_round    INT;

  v_history  TEXT;
  v_tx0      INT;
  v_q        NUMERIC := 100;   -- main offer size (scaled down for a small batch)
  v_q2       NUMERIC;          -- declined offer
  v_q3       NUMERIC;          -- cancelled / extra offers
  v_n_elig   INT;
  v_max_av   NUMERIC;
BEGIN
  -- Blank ids are filled in automatically (the first suitable rows found).
  IF v_batch IS NULL THEN
    SELECT b.id, b.farmer_id INTO v_batch, v_farmer
    FROM inventory_batches b
    JOIN user_roles r ON r.user_id = b.farmer_id AND r.role = 'farmer' AND r.status = 'active'
    WHERE b.is_coop_eligible AND b.exclusive_channel IS NULL AND b.available_kg >= 20
    ORDER BY b.available_kg DESC LIMIT 1;
  ELSIF v_farmer IS NULL THEN
    SELECT farmer_id INTO v_farmer FROM inventory_batches WHERE id = v_batch;
  END IF;
  IF v_manager IS NULL THEN
    SELECT user_id INTO v_manager FROM user_roles WHERE role IN ('admin', 'officer') ORDER BY (role = 'admin') DESC LIMIT 1;
  END IF;
  IF v_other_farmer IS NULL THEN
    SELECT user_id INTO v_other_farmer FROM user_roles
    WHERE role = 'farmer' AND status = 'active' AND user_id <> COALESCE(v_farmer, '00000000-0000-0000-0000-000000000000') LIMIT 1;
  END IF;
  IF v_ginger_batch IS NULL THEN
    SELECT id INTO v_ginger_batch FROM inventory_batches WHERE exclusive_channel IS NOT NULL LIMIT 1;
  END IF;

  IF v_batch IS NULL OR v_farmer IS NULL OR v_manager IS NULL THEN
    SELECT count(*), COALESCE(max(available_kg), 0) INTO v_n_elig, v_max_av FROM inventory_batches WHERE is_coop_eligible AND exclusive_channel IS NULL;
    RAISE EXCEPTION 'Nothing suitable found. Need: a coop-eligible, non-DA-AMAD batch with at least 20 kg available whose owner is an ACTIVE farmer, plus a Manager/Officer. Found: % eligible batches (largest has % kg available); Manager/Officer: %. Fill in v_batch / v_farmer / v_manager by hand, or add stock.', v_n_elig, v_max_av, COALESCE(v_manager::text, 'none');
  END IF;

  SELECT available_kg INTO v_avail0 FROM inventory_batches WHERE id = v_batch;
  -- The scenario needs about 1.5 x the main offer free at once.
  v_q  := LEAST(100, floor(v_avail0 / 2));
  v_q2 := GREATEST(1, floor(v_q / 2));
  v_q3 := GREATEST(1, floor(v_q / 4));
  SELECT count(*) INTO v_tx0 FROM member_sales_transactions WHERE farmer_id = v_farmer;

  -- ── helper blocks are inlined: sign in as X ────────────────────────────
  -- (set_config + SET LOCAL ROLE; RESET ROLE returns to the SQL editor's role)

  -- 1. Farmer submits: 100 kg at P100 -------------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_offer := public.offer_batch_to_cooperative(v_batch, v_q, 100.00, 'first offer');
  EXECUTE 'RESET ROLE';

  SELECT * INTO v_row FROM cooperative_purchase_offers WHERE id = v_offer;
  SELECT available_kg INTO v_avail FROM inventory_batches WHERE id = v_batch;
  v_report := v_report || CASE WHEN v_row.status = 'pending' AND v_row.last_proposed_by = 'farmer'
      AND v_row.negotiation_round = 1 AND v_row.asking_price_per_kg = 100 AND v_row.current_price_per_kg = 100
    THEN 'PASS ' ELSE 'FAIL ' END || E'1  offer is pending, Farmer proposed last, round 1, ask 100\n';
  v_report := v_report || CASE WHEN v_avail = v_avail0 - v_q THEN 'PASS ' ELSE 'FAIL ' END
    || E'2  the offered kg reserved from the batch when the offer was made\n';

  -- 3. Farmer cannot counter their own price -------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.counter_cooperative_offer(v_offer, 120, 1, NULL);
    v_report := v_report || E'FAIL 3  Farmer countered their own latest price\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 3  Farmer cannot counter their own latest price (' || SQLERRM || E')\n';
  END;
  -- 4. Farmer cannot accept their own price --------------------------------
  BEGIN
    PERFORM public.accept_cooperative_offer(v_offer, 1, NULL);
    v_report := v_report || E'FAIL 4  Farmer accepted their own price\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 4  Farmer cannot accept their own price (' || SQLERRM || E')\n';
  END;
  EXECUTE 'RESET ROLE';

  -- 5. Another farmer cannot touch the offer -------------------------------
  IF v_other_farmer IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other_farmer, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
      PERFORM public.counter_cooperative_offer(v_offer, 60, 1, NULL);
      v_report := v_report || E'FAIL 5  another farmer countered this offer\n';
    EXCEPTION WHEN OTHERS THEN
      v_report := v_report || 'PASS 5  another farmer cannot counter it (' || SQLERRM || E')\n';
    END;
    BEGIN
      PERFORM public.cancel_cooperative_offer(v_offer, NULL);
      v_report := v_report || E'FAIL 6  another farmer cancelled this offer\n';
    EXCEPTION WHEN OTHERS THEN
      v_report := v_report || 'PASS 6  another farmer cannot cancel it (' || SQLERRM || E')\n';
    END;
    EXECUTE 'RESET ROLE';
  END IF;

  -- 7. Manager: a stale round is refused -----------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.counter_cooperative_offer(v_offer, 50, 99, NULL);
    v_report := v_report || E'FAIL 7  a wrong round number was accepted\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 7  a counteroffer on an outdated round is refused (' || SQLERRM || E')\n';
  END;
  -- 8. Manager counters P50 (round 1 -> 2) ---------------------------------
  v_round := public.counter_cooperative_offer(v_offer, 50, 1, 'too high');
  -- 9. Manager cannot accept their own price -------------------------------
  BEGIN
    PERFORM public.accept_cooperative_offer(v_offer, 2, NULL);
    v_report := v_report || E'FAIL 9  Manager accepted their own price\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 9  Manager cannot accept their own price (' || SQLERRM || E')\n';
  END;
  EXECUTE 'RESET ROLE';
  SELECT * INTO v_row FROM cooperative_purchase_offers WHERE id = v_offer;
  v_report := v_report || CASE WHEN v_round = 2 AND v_row.negotiation_round = 2 AND v_row.current_price_per_kg = 50
      AND v_row.last_proposed_by = 'cooperative' AND v_row.status = 'pending'
    THEN 'PASS ' ELSE 'FAIL ' END || E'8  counteroffer P50 recorded: round 2, Cooperative proposed last, still pending (no sale)\n';
  SELECT count(*) INTO v_n FROM member_sales_transactions WHERE farmer_id = v_farmer;
  v_report := v_report || CASE WHEN v_n = v_tx0 THEN 'PASS ' ELSE 'FAIL ' END || E'10 a counteroffer did NOT create a sale\n';

  -- 11. Farmer tries to accept the outdated round 1 ------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.accept_cooperative_offer(v_offer, 1, NULL);
    v_report := v_report || E'FAIL 11 an outdated price was accepted\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 11 Farmer cannot accept an outdated price (' || SQLERRM || E')\n';
  END;
  -- 12. Farmer counters P100 (round 2 -> 3) --------------------------------
  v_round := public.counter_cooperative_offer(v_offer, 100, 2, NULL);
  EXECUTE 'RESET ROLE';

  -- 13. Manager counters P80 (round 3 -> 4) --------------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_round := public.counter_cooperative_offer(v_offer, 80, 3, NULL);
  EXECUTE 'RESET ROLE';

  -- 14. Farmer accepts P80 on round 4: the sale is final -------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.accept_cooperative_offer(v_offer, 3, NULL);
    v_report := v_report || E'FAIL 14 accepted round 3 after the price moved to round 4\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 14 the price that moved on is refused (' || SQLERRM || E')\n';
  END;
  v_tx := public.accept_cooperative_offer(v_offer, 4, 'agreed');
  EXECUTE 'RESET ROLE';

  SELECT * INTO v_row FROM cooperative_purchase_offers WHERE id = v_offer;
  v_report := v_report || CASE WHEN v_row.status = 'confirmed' AND v_row.agreed_price_per_kg = 80
      AND v_row.confirmed_amount = 80 * v_q AND v_row.confirmed_quantity_kg = v_q
      AND v_row.member_sales_transaction_id = v_tx AND v_row.confirmed_by = v_manager
    THEN 'PASS ' ELSE 'FAIL ' END || E'15 accepted: agreed P80/kg x offered kg, settlement linked, credited to the Manager whose price it was\n';
  SELECT count(*) INTO v_n FROM member_sales_transactions WHERE id = v_tx AND farmer_id = v_farmer
    AND quantity_kg = v_q AND amount = 80 * v_q;
  v_report := v_report || CASE WHEN v_n = 1 THEN 'PASS ' ELSE 'FAIL ' END
    || E'16 exactly one sales transaction of the offered kg at 80/kg (Transaction History and Sales Report read this row)\n';
  SELECT available_kg INTO v_avail FROM inventory_batches WHERE id = v_batch;
  v_report := v_report || CASE WHEN v_avail = v_avail0 - v_q THEN 'PASS ' ELSE 'FAIL ' END
    || E'17 batch stock unchanged by the acceptance (still the kg reserved at offer time)\n';

  -- 18. No second settlement, from either side -----------------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.accept_cooperative_offer(v_offer, 4, NULL);
    v_report := v_report || E'FAIL 18 a closed offer was accepted again (Farmer)\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 18 Farmer cannot accept it again (' || SQLERRM || E')\n';
  END;
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  BEGIN
    PERFORM public.accept_cooperative_offer(v_offer, 4, NULL);
    v_report := v_report || E'FAIL 19 a closed offer was accepted again (Manager)\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 19 Manager cannot accept it again (' || SQLERRM || E')\n';
  END;
  BEGIN
    PERFORM public.decline_cooperative_offer(v_offer, NULL, NULL);
    v_report := v_report || E'FAIL 20 a settled offer was declined\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 20 a settled offer cannot be declined (' || SQLERRM || E')\n';
  END;
  EXECUTE 'RESET ROLE';
  SELECT count(*) INTO v_n FROM member_sales_transactions WHERE farmer_id = v_farmer AND id = v_tx;
  v_report := v_report || CASE WHEN v_n = 1 THEN 'PASS ' ELSE 'FAIL ' END || E'21 still exactly one settlement row\n';

  -- 22. The history is complete and ordered --------------------------------
  SELECT count(*) INTO v_n FROM cooperative_offer_events WHERE offer_id = v_offer;
  v_report := v_report || CASE WHEN v_n = 5 THEN 'PASS ' ELSE 'FAIL ' END
    || E'22 history has 5 steps (offer, 3 counteroffers, acceptance): found ' || v_n || E'\n';
  SELECT string_agg(action || ':' || actor_role || ':' || COALESCE(price_per_kg::text, '-'), ' > ' ORDER BY created_at, round)
    INTO v_history FROM cooperative_offer_events WHERE offer_id = v_offer;
  v_report := v_report || '   history: ' || v_history || E'\n';

  -- 23-25. The Cooperative declines a second offer; stock comes back ------
  SELECT available_kg INTO v_avail0 FROM inventory_batches WHERE id = v_batch;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_offer2 := public.offer_batch_to_cooperative(v_batch, v_q2, 90.00, NULL);
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  PERFORM public.decline_cooperative_offer(v_offer2, 'not buying this week', 1);
  EXECUTE 'RESET ROLE';
  SELECT * INTO v_row FROM cooperative_purchase_offers WHERE id = v_offer2;
  SELECT available_kg INTO v_avail FROM inventory_batches WHERE id = v_batch;
  v_report := v_report || CASE WHEN v_row.status = 'declined' AND v_row.member_sales_transaction_id IS NULL
    THEN 'PASS ' ELSE 'FAIL ' END || E'23 declined offer: status declined, no sale recorded\n';
  v_report := v_report || CASE WHEN v_avail = v_avail0 THEN 'PASS ' ELSE 'FAIL ' END
    || E'24 declined offer: the kg went back to the batch\n';
  SELECT count(*) INTO v_n FROM cooperative_offer_events WHERE offer_id = v_offer2 AND action IN ('offered', 'declined');
  v_report := v_report || CASE WHEN v_n = 2 THEN 'PASS ' ELSE 'FAIL ' END || E'25 the declined offer keeps its history\n';

  -- 26-27. The Farmer cancels a third offer; stock comes back -------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_offer3 := public.offer_batch_to_cooperative(v_batch, v_q3, 70.00, NULL);
  PERFORM public.cancel_cooperative_offer(v_offer3, 'changed my mind');
  BEGIN
    PERFORM public.cancel_cooperative_offer(v_offer3, NULL);
    v_report := v_report || E'FAIL 28 a cancelled offer was cancelled again\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 28 a cancelled offer cannot be cancelled again (' || SQLERRM || E')\n';
  END;
  EXECUTE 'RESET ROLE';
  SELECT * INTO v_row FROM cooperative_purchase_offers WHERE id = v_offer3;
  SELECT available_kg INTO v_avail FROM inventory_batches WHERE id = v_batch;
  v_report := v_report || CASE WHEN v_row.status = 'cancelled' THEN 'PASS ' ELSE 'FAIL ' END || E'26 cancelled offer: status cancelled\n';
  v_report := v_report || CASE WHEN v_avail = v_avail0 THEN 'PASS ' ELSE 'FAIL ' END || E'27 cancelled offer: the kg went back to the batch\n';

  -- 29. A Farmer cannot decline for the Cooperative -----------------------
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_farmer, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  v_offer3 := public.offer_batch_to_cooperative(v_batch, v_q3, 60.00, NULL);
  BEGIN
    PERFORM public.decline_cooperative_offer(v_offer3, NULL, NULL);
    v_report := v_report || E'FAIL 29 a Farmer declined on behalf of the Cooperative\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 29 only the Cooperative can decline (' || SQLERRM || E')\n';
  END;
  -- 30. Direct writes to the offers table are closed ----------------------
  BEGIN
    INSERT INTO cooperative_purchase_offers (farmer_id, inventory_batch_id, crop_name, offered_quantity_kg, status, confirmed_amount)
    VALUES (v_farmer, v_batch, 'Palay', 10, 'confirmed', 99999);
    v_report := v_report || E'FAIL 30 a Farmer inserted an offer row directly\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 30 a Farmer cannot insert offer rows directly (' || SQLERRM || E')\n';
  END;
  EXECUTE 'RESET ROLE';
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_manager, 'role', 'authenticated')::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
  UPDATE cooperative_purchase_offers SET confirmed_amount = 1 WHERE id = v_offer;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  EXECUTE 'RESET ROLE';
  v_report := v_report || CASE WHEN v_n = 0 THEN 'PASS ' ELSE 'FAIL ' END
    || E'31 a Manager cannot edit an offer row directly (rows changed: ' || v_n || E')\n';

  -- 32. Ginger is still refused -------------------------------------------
  IF v_ginger_batch IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', (SELECT farmer_id FROM inventory_batches WHERE id = v_ginger_batch), 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
      PERFORM public.offer_batch_to_cooperative(v_ginger_batch, 10, 50.00, NULL);
      v_report := v_report || E'FAIL 32 a DA-AMAD-only crop was offered to the Cooperative\n';
    EXCEPTION WHEN OTHERS THEN
      v_report := v_report || 'PASS 32 a DA-AMAD-only crop cannot be offered here (' || SQLERRM || E')\n';
    END;
    EXECUTE 'RESET ROLE';
  END IF;

  -- 33. Not the batch owner ------------------------------------------------
  IF v_other_farmer IS NOT NULL THEN
    PERFORM set_config('request.jwt.claims', json_build_object('sub', v_other_farmer, 'role', 'authenticated')::text, true);
    EXECUTE 'SET LOCAL ROLE authenticated';
    BEGIN
      PERFORM public.offer_batch_to_cooperative(v_batch, 10, 50.00, NULL);
      v_report := v_report || E'FAIL 33 a farmer offered somebody else''s batch\n';
    EXCEPTION WHEN OTHERS THEN
      v_report := v_report || 'PASS 33 a farmer cannot offer another farmer''s batch (' || SQLERRM || E')\n';
    END;
    EXECUTE 'RESET ROLE';
  END IF;

  -- Notifications written along the way ------------------------------------
  SELECT count(*) INTO v_n FROM notifications
  WHERE type = 'cooperative_offer' AND created_at > NOW() - INTERVAL '1 minute';
  v_report := v_report || CASE WHEN v_n > 0 THEN 'PASS ' ELSE 'FAIL ' END
    || E'34 notifications were written for offers, counteroffers, acceptance, decline and cancel: ' || v_n || E'\n';

  v_fail := (length(v_report) - length(replace(v_report, E'\nFAIL ', ''))) / 6;
  -- Raising rolls EVERYTHING above back, then shows the report.
  RAISE EXCEPTION E'NEGOTIATION TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_report, v_fail;
END
$test$;
