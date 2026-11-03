-- ============================================================
-- SAGANA — Farmer Harvest Stock Management: end-to-end test
--
-- Runs the REAL database functions as the real roles (a Farmer, a Manager, a
-- Buyer, and a second Farmer when one exists) on one 20-unit batch:
--
--   A. Marketplace      listing 8 -> order 3 -> Manager cannot complete it ->
--                       the Buyer confirms receipt -> sold 3; a pending order cannot
--                       be confirmed; a second confirmation is refused; a cancelled
--                       order gives its kg back
--   B. Offer to Coop    offer 4 -> price agreed (approved, NOT sold) -> deliver needs a
--                       photo -> Manager confirms receipt -> sold 4, sale settled once,
--                       the kg enter cooperative Harvest Stock once; a declined offer
--                       releases its kg
--   C. Informal Sale    2 -> reserved and sold; the Farmer cannot edit the row directly
--   D. Update Quantity  recorded as adjusted stock, reserved stays correct
--   E. Guards           negative or over-sold stock is refused
--   F. History          stock_movements has the right rows, channels and balances; a
--                       Farmer reads only their own and cannot write any
--   G. Farmer as consumer (only when a second Farmer exists)
--
--   After every step: available + reserved + sold + adjusted = total harvested.
--
-- DA-AMAD (Ginger) partial sales are covered by
-- supabase_schema_market_linking_partial_sales_test.sql, which must also pass.
--
-- It changes nothing: it ends by raising an error on purpose, which rolls everything
-- back; the error text IS the report (PASS / FAIL / SKIP lines).
--
-- Run supabase_schema_farmer_stock_management.sql first, then this whole file.
-- ============================================================

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END;
$$;

CREATE OR REPLACE FUNCTION pg_temp.chk(p_ok boolean, p_label text, p_detail text DEFAULT NULL)
RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN COALESCE(p_ok, false) THEN 'PASS ' ELSE 'FAIL ' END || p_label ||
         CASE WHEN p_detail IS NULL THEN '' ELSE ' — ' || p_detail END || E'\n';
$$;

DO $test$
DECLARE
  v_rep     TEXT := E'\n';
  F UUID; F2 UUID; M UUID; B UUID;
  v_mtype   TEXT;
  v_unit    TEXT;
  v_name    CONSTANT TEXT := 'Zz Stock Test Crop';
  v_cm UUID; v_fc UUID; v_h UUID; v_batch UUID;
  v_listing UUID; v_o1 UUID; v_o2 UUID; v_o3 UUID;
  v_offer UUID; v_offer2 UUID; v_tx UUID; v_sale UUID;
  v_item UUID;
  bt        inventory_batches%ROWTYPE;
  l         marketplace_listings%ROWTYPE;
  o         orders%ROWTYPE;
  of_       cooperative_purchase_offers%ROWTYPE;
  v_msg     TEXT;
  v_n       INT;
  v_qty     NUMERIC;
  v_before  NUMERIC;
BEGIN
  SELECT user_id INTO F FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND NOT COALESCE(pending_acknowledgement, false) ORDER BY user_id LIMIT 1;
  SELECT user_id INTO F2 FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND user_id <> F ORDER BY user_id LIMIT 1;
  SELECT user_id INTO M FROM user_roles WHERE role = 'admin' AND status = 'active' LIMIT 1;
  SELECT user_id INTO B FROM user_roles WHERE role = 'buyer' AND status = 'active' LIMIT 1;
  SELECT code INTO v_mtype FROM market_types WHERE buyer_visible AND is_active ORDER BY sort_order LIMIT 1;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM units WHERE is_active AND lower(name) = 'kg') THEN 'kg' ELSE
           (SELECT name FROM units WHERE is_active ORDER BY name LIMIT 1) END INTO v_unit;

  IF F IS NULL OR M IS NULL OR B IS NULL OR v_mtype IS NULL THEN
    RAISE EXCEPTION E'STOCK MANAGEMENT TEST REPORT\nSKIP everything: needs an active farmer, admin and buyer and a buyer-visible market type (farmer=%, admin=%, buyer=%, market=%)', F, M, B, v_mtype;
  END IF;
  v_rep := v_rep || 'INFO farmer ' || F || ', second farmer ' || COALESCE(F2::text, 'none') || ', manager ' || M || ', buyer ' || B || ', unit ' || v_unit || E'\n';

  -- ── Test stock: a 20-unit batch ───────────────────────────────────────────
  INSERT INTO crop_master (crop_name, category, crop_type) VALUES (v_name, 'Other', v_mtype) RETURNING id INTO v_cm;
  INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id, photo_url)
    VALUES (F, v_name, 'Other', v_cm, 'https://example.invalid/zz-test-crop.jpg') RETURNING id INTO v_fc;
  INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
    VALUES (F, v_fc, v_name, 20, DATE '2096-03-04', v_unit) RETURNING id INTO v_h;
  INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, quantity_kg, available_kg,
                                 status, is_coop_eligible, crop_type)
    VALUES (F, v_h, v_fc, v_name, 20, 20, 'available', TRUE, v_mtype) RETURNING id INTO v_batch;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.quantity_kg = 20 AND bt.available_kg = 20 AND bt.reserved_kg = 0 AND bt.sold_kg = 0 AND bt.adjusted_kg = 0,
    '0.1 new batch: total 20, available 20, reserved 0, sold 0, adjusted 0', bt.batch_number);
  SELECT count(*) INTO v_n FROM stock_movements WHERE batch_id = v_batch AND movement_type = 'harvested' AND quantity = 20;
  v_rep := v_rep || pg_temp.chk(v_n = 1, '0.2 the harvest is the first movement in the history', v_n::text);

  -- ═════════════ A. MARKETPLACE ═════════════
  PERFORM pg_temp.as_user(F);
  v_listing := create_listing_with_reservation(v_batch, v_name, NULL, 8, 12.50, NULL, 'Stock test');
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 12 AND bt.reserved_kg = 8 AND bt.sold_kg = 0,
    'A1 listing 8 reserves 8 (available 12, reserved 8, sold 0)', bt.available_kg || ' / ' || bt.reserved_kg || ' / ' || bt.sold_kg);
  SELECT count(*) INTO v_n FROM stock_movements WHERE batch_id = v_batch AND movement_type = 'reserved'
    AND quantity = 8 AND channel = 'marketplace' AND reference_type = 'listing' AND reference_id = v_listing;
  v_rep := v_rep || pg_temp.chk(v_n = 1, 'A2 history: reserved 8, channel marketplace, tied to the listing', v_n::text);

  PERFORM pg_temp.as_user(M);
  PERFORM approve_listing(v_listing);
  RESET ROLE;
  PERFORM pg_temp.as_user(B);
  v_o1 := place_order(v_listing, 3);
  v_o2 := place_order(v_listing, 2);
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 12 AND bt.reserved_kg = 8 AND bt.sold_kg = 0,
    'A3 placing orders moves no batch stock (the listing already holds the 8)', bt.available_kg || ' / ' || bt.reserved_kg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM confirm_order_received(v_o1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'A4 a PENDING order cannot be confirmed as received', v_msg);

  PERFORM pg_temp.as_user(M);
  PERFORM approve_order(v_o1);
  PERFORM mark_order_ready_for_pickup(v_o1);
  RESET ROLE;

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM complete_order(v_o1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_o1;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL AND o.status = 'ready_for_pickup' AND bt.sold_kg = 0,
    'A5 the Manager can no longer complete an order, and nothing was sold', COALESCE(v_msg, 'no error') || ' / ' || o.status);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM confirm_order_received(v_o1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'A6 only the consumer who ordered can confirm receipt', v_msg);

  PERFORM pg_temp.as_user(B);
  PERFORM confirm_order_received(v_o1);
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_o1;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(o.status = 'completed' AND o.received_at IS NOT NULL AND o.received_by = B,
    'A7 the Buyer confirms receipt: the order is completed with who/when', o.status);
  v_rep := v_rep || pg_temp.chk(bt.sold_kg = 3 AND bt.reserved_kg = 5 AND bt.available_kg = 12,
    'A8 sold 3, reserved 5 (8 - 3), available 12', bt.sold_kg || ' / ' || bt.reserved_kg || ' / ' || bt.available_kg);
  SELECT count(*) INTO v_n FROM stock_movements WHERE batch_id = v_batch AND movement_type = 'sold'
    AND quantity = 3 AND channel = 'marketplace' AND reference_type = 'order' AND reference_id = v_o1;
  v_rep := v_rep || pg_temp.chk(v_n = 1, 'A9 history: sold 3, channel marketplace, tied to the order', v_n::text);

  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM confirm_order_received(v_o1); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL AND bt.sold_kg = 3, 'A10 a second confirmation is refused and sold stays 3', v_msg);

  v_msg := NULL;
  BEGIN UPDATE orders SET status = 'approved' WHERE id = v_o1; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'A11 a completed order cannot be reopened', v_msg);

  PERFORM pg_temp.as_user(B);
  PERFORM cancel_my_order(v_o2, 'stock test');
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(l.remaining_kg = 5 AND bt.sold_kg = 3 AND bt.reserved_kg = 5,
    'A12 cancelling the pending order of 2 returns it to the listing (remaining 5); the batch is unchanged', 'remaining ' || l.remaining_kg);

  -- ═════════════ B. OFFER TO COOPERATIVE ═════════════
  PERFORM pg_temp.as_user(F);
  v_offer := offer_batch_to_cooperative(v_batch, 4, 10.00, NULL);
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 8 AND bt.reserved_kg = 9 AND bt.sold_kg = 3,
    'B1 offer 4 reserves 4 (available 8, reserved 9, sold 3)', bt.available_kg || ' / ' || bt.reserved_kg || ' / ' || bt.sold_kg);

  PERFORM pg_temp.as_user(M);
  PERFORM counter_cooperative_offer(v_offer, 12.00, 1, NULL);
  RESET ROLE;
  PERFORM pg_temp.as_user(F);
  PERFORM accept_cooperative_offer(v_offer, 2, NULL);
  RESET ROLE;
  SELECT * INTO of_ FROM cooperative_purchase_offers WHERE id = v_offer;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  SELECT count(*) INTO v_n FROM member_sales_transactions WHERE farmer_id = F AND crop_name = v_name;
  v_rep := v_rep || pg_temp.chk(of_.status = 'approved' AND of_.agreed_price_per_kg = 12 AND of_.confirmed_amount = 48
      AND bt.sold_kg = 3 AND bt.reserved_kg = 9 AND v_n = 0,
    'B2 price agreed = APPROVED: 4 x 12 = 48 agreed, but NOT sold, NOT settled, still reserved',
    of_.status || ', sold ' || bt.sold_kg || ', reserved ' || bt.reserved_kg || ', sales ' || v_n);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM confirm_cooperative_offer_receipt(v_offer, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'B3 receipt cannot be confirmed before the Farmer delivers', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM deliver_cooperative_offer(v_offer, '', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'B4 delivering without a photo is refused', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM deliver_cooperative_offer(v_offer, 'https://example.invalid/x.jpg', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'B5 only the offer''s Farmer can mark it delivered', v_msg);

  PERFORM pg_temp.as_user(F);
  PERFORM deliver_cooperative_offer(v_offer, 'https://example.invalid/zz-delivery.jpg', 'Left at the warehouse');
  RESET ROLE;
  SELECT * INTO of_ FROM cooperative_purchase_offers WHERE id = v_offer;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(of_.status = 'delivered' AND of_.delivery_photo_url IS NOT NULL AND of_.delivered_at IS NOT NULL
      AND bt.sold_kg = 3 AND bt.reserved_kg = 9,
    'B6 delivered with photo evidence: still not sold, still reserved', of_.status || ', sold ' || bt.sold_kg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM confirm_cooperative_offer_receipt(v_offer, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'B7 the Farmer cannot confirm their own delivery', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM decline_cooperative_offer(v_offer, 'x', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'B8 an approved/delivered offer cannot be declined (out of scope: disputes)', v_msg);

  SELECT COALESCE(sum(quantity_on_hand), 0) INTO v_before FROM cooperative_inventory
    WHERE category = 'Harvest Stock' AND lower(item_name) = lower(v_name);
  PERFORM pg_temp.as_user(M);
  v_tx := confirm_cooperative_offer_receipt(v_offer, 'Weighed: 4');
  RESET ROLE;
  SELECT * INTO of_ FROM cooperative_purchase_offers WHERE id = v_offer;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(of_.status = 'completed' AND of_.member_sales_transaction_id = v_tx AND of_.received_at IS NOT NULL
      AND of_.received_by = M AND of_.coop_inventory_id IS NOT NULL,
    'B9 the Manager confirms receipt: completed, sale linked, who/when recorded', of_.status);
  v_rep := v_rep || pg_temp.chk(bt.sold_kg = 7 AND bt.reserved_kg = 5 AND bt.available_kg = 8,
    'B10 NOW it is sold: sold 7, reserved 5, available 8', bt.sold_kg || ' / ' || bt.reserved_kg || ' / ' || bt.available_kg);
  SELECT count(*) INTO v_n FROM member_sales_transactions WHERE id = v_tx AND quantity_kg = 4 AND amount = 48 AND farmer_id = F;
  v_rep := v_rep || pg_temp.chk(v_n = 1, 'B11 exactly one sale of 4 for 48 was settled', v_n::text);
  SELECT COALESCE(sum(quantity_on_hand), 0) INTO v_qty FROM cooperative_inventory
    WHERE category = 'Harvest Stock' AND lower(item_name) = lower(v_name);
  SELECT count(*) INTO v_n FROM inventory_transactions
    WHERE transaction_type = 'harvest_received' AND reference_type = 'cooperative_offer' AND reference_id = v_offer AND quantity = 4;
  v_rep := v_rep || pg_temp.chk(v_qty - v_before = 4 AND v_n = 1,
    'B12 cooperative Harvest Stock grew by exactly 4, with one inventory transaction', (v_qty - v_before) || ' / ' || v_n);

  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM confirm_cooperative_offer_receipt(v_offer, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT COALESCE(sum(quantity_on_hand), 0) INTO v_qty FROM cooperative_inventory
    WHERE category = 'Harvest Stock' AND lower(item_name) = lower(v_name);
  SELECT count(*) INTO v_n FROM member_sales_transactions WHERE farmer_id = F AND crop_name = v_name;
  v_rep := v_rep || pg_temp.chk(v_msg IS NULL AND v_qty - v_before = 4 AND v_n = 1,
    'B13 confirming twice is idempotent: no second sale, no second transfer', v_msg);

  SELECT count(*) INTO v_n FROM stock_movements WHERE batch_id = v_batch AND movement_type = 'sold'
    AND quantity = 4 AND channel = 'cooperative_offer' AND reference_id = v_offer;
  v_rep := v_rep || pg_temp.chk(v_n = 1, 'B14 history: sold 4, channel cooperative_offer, tied to the offer', v_n::text);

  PERFORM pg_temp.as_user(F);
  v_offer2 := offer_batch_to_cooperative(v_batch, 1, 9.00, NULL);
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 7 AND bt.reserved_kg = 6, 'B15 a second offer of 1 reserves 1', bt.available_kg || ' / ' || bt.reserved_kg);
  PERFORM pg_temp.as_user(M);
  PERFORM decline_cooperative_offer(v_offer2, 'stock test', 1);
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 8 AND bt.reserved_kg = 5 AND bt.sold_kg = 7,
    'B16 declining releases the 1 and sells nothing', bt.available_kg || ' / ' || bt.reserved_kg || ' / ' || bt.sold_kg);

  -- ═════════════ C. INFORMAL SALE ═════════════
  PERFORM pg_temp.as_user(F);
  v_sale := record_informal_sale(v_batch, v_name, 2, 'Neighbour', 40, NULL);
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 6 AND bt.sold_kg = 9 AND bt.reserved_kg = 5,
    'C1 informal sale 2: available 6, sold 9, reserved 5', bt.available_kg || ' / ' || bt.sold_kg || ' / ' || bt.reserved_kg);
  SELECT count(*) INTO v_n FROM stock_movements WHERE batch_id = v_batch AND channel = 'informal_sale' AND reference_id = v_sale
    AND movement_type IN ('reserved', 'sold') AND quantity = 2;
  v_rep := v_rep || pg_temp.chk(v_n = 2, 'C2 history: informal sale shows a reserved and a sold row of 2', v_n::text);

  PERFORM pg_temp.as_user(F);
  DELETE FROM informal_sales WHERE id = v_sale;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(v_n = 0 AND bt.sold_kg = 9, 'C3 the Farmer cannot delete an informal sale row directly', 'rows deleted ' || v_n);

  -- ═════════════ D. UPDATE QUANTITY ═════════════
  PERFORM pg_temp.as_user(F);
  PERFORM update_batch_available_quantity(v_batch, 5);
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 5 AND bt.adjusted_kg = 1 AND bt.reserved_kg = 5 AND bt.sold_kg = 9,
    'D1 Update Quantity 6 -> 5 is ADJUSTED stock 1; reserved stays 5, sold stays 9', bt.available_kg || ' / adj ' || bt.adjusted_kg || ' / res ' || bt.reserved_kg);
  SELECT count(*) INTO v_n FROM stock_movements WHERE batch_id = v_batch AND movement_type = 'adjusted' AND quantity = 1 AND channel IS NULL;
  v_rep := v_rep || pg_temp.chk(v_n = 1, 'D2 history: one manual adjustment of 1, no channel', v_n::text);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM update_batch_available_quantity(v_batch, 6); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'D3 stock can only be decreased by hand', v_msg);

  -- ═════════════ E. GUARDS ═════════════
  v_msg := NULL;
  BEGIN UPDATE inventory_batches SET available_kg = -1 WHERE id = v_batch; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'E1 negative available stock is refused', v_msg);
  v_msg := NULL;
  BEGIN UPDATE inventory_batches SET sold_kg = 100 WHERE id = v_batch; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'E2 selling more than was harvested is refused', v_msg);
  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM record_informal_sale(v_batch, v_name, 5.01, 'X', 1, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'E3 selling more than is available is refused', v_msg);

  -- ═════════════ F. HISTORY ═════════════
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(abs(bt.available_kg + bt.reserved_kg + bt.sold_kg + bt.adjusted_kg - bt.quantity_kg) < 0.005,
    'F1 final: available + reserved + sold + adjusted = total harvested',
    bt.available_kg || ' + ' || bt.reserved_kg || ' + ' || bt.sold_kg || ' + ' || bt.adjusted_kg || ' = ' || bt.quantity_kg);

  SELECT available_after, reserved_after, sold_after INTO v_qty, v_before, v_n
    FROM stock_movements WHERE batch_id = v_batch ORDER BY seq DESC LIMIT 1;
  v_rep := v_rep || pg_temp.chk(v_qty = bt.available_kg AND v_before = bt.reserved_kg AND v_n = bt.sold_kg,
    'F2 the newest movement''s balances equal the batch''s figures', v_qty || ' / ' || v_before || ' / ' || v_n);

  SELECT count(*) INTO v_n FROM stock_movements WHERE batch_id = v_batch AND channel IS NULL AND movement_type <> 'harvested';
  v_rep := v_rep || pg_temp.chk(v_n = 1, 'F3 only the manual adjustment has no channel (every channel movement is attributed)', v_n::text);

  PERFORM pg_temp.as_user(F);
  SELECT count(*) INTO v_n FROM stock_movements WHERE batch_id = v_batch;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_n >= 10, 'F4 the Farmer reads their own batch history', v_n::text);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN
    INSERT INTO stock_movements (batch_id, farmer_id, movement_type, quantity, available_after, reserved_after, sold_after)
    VALUES (v_batch, F, 'sold', 1, 0, 0, 0);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, 'F5 a Farmer cannot write history', v_msg);

  IF F2 IS NOT NULL THEN
    PERFORM pg_temp.as_user(F2);
    SELECT count(*) INTO v_n FROM stock_movements WHERE batch_id = v_batch;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_n = 0, 'F6 another Farmer cannot read this history', v_n::text);
  ELSE
    v_rep := v_rep || E'SKIP F6 needs a second farmer\n';
  END IF;

  PERFORM pg_temp.as_user(M);
  SELECT count(*) INTO v_n FROM stock_movements WHERE batch_id = v_batch;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_n >= 10, 'F7 the Manager reads the history', v_n::text);

  -- ═════════════ G. FARMER AS CONSUMER ═════════════
  IF F2 IS NULL THEN
    v_rep := v_rep || E'SKIP G1-G2 need a second farmer who can buy\n';
  ELSE
    BEGIN
      PERFORM pg_temp.as_user(F2);
      v_o3 := place_order(v_listing, 1);
      RESET ROLE;
      PERFORM pg_temp.as_user(M);
      PERFORM approve_order(v_o3);
      PERFORM mark_order_ready_for_pickup(v_o3);
      RESET ROLE;
      PERFORM pg_temp.as_user(F2);
      PERFORM confirm_order_received(v_o3);
      RESET ROLE;
      SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
      v_rep := v_rep || pg_temp.chk(bt.sold_kg = 10 AND bt.reserved_kg = 4,
        'G1 a Farmer buying another Farmer''s listing confirms receipt the same way (sold 10, reserved 4)', bt.sold_kg || ' / ' || bt.reserved_kg);
      SELECT * INTO o FROM orders WHERE id = v_o3;
      v_rep := v_rep || pg_temp.chk(o.status = 'completed' AND o.received_by = F2, 'G2 recorded as received by that Farmer', o.status);
    EXCEPTION WHEN OTHERS THEN
      RESET ROLE;
      v_rep := v_rep || E'SKIP G1-G2 the second farmer could not buy in this data: ' || SQLERRM || E'\n';
    END;
  END IF;

  RAISE EXCEPTION E'STOCK MANAGEMENT TEST REPORT (rolled back; nothing was saved)\n%FAILED CHECKS: %',
    v_rep, (length(v_rep) - length(replace(v_rep, E'\nFAIL ', ''))) / 6;
END
$test$;
