-- ============================================================
-- SAGANA — Backend rule tests: market visibility, order access, Ginger/DA-AMAD
-- channels, inventory Source, price editing, wording.
--
-- NOTHING IS KEPT. Everything runs in one transaction that ends in a deliberate
-- error (the report), so every change the tests make is undone.
--
-- Run it in the Supabase SQL editor AFTER the five market scripts and
-- supabase_schema_order_wording_price_visibility.sql.
--
-- It picks real accounts and rows from your data (a buyer, an approved farmer,
-- a Manager, a Cooperative Market listing, a Ginger batch...) and tries the
-- forbidden and the allowed action as each. The report lists one line per test:
-- PASS, FAIL (with what happened) or SKIP (the data to test with does not exist
-- yet). It appears as the error message at the end: read that as the result.
--
-- Expected: no FAIL. This file has been written but NOT yet run against your
-- database.
-- ============================================================

BEGIN;

CREATE TEMP TABLE r (n serial, test text, result text, detail text) ON COMMIT DROP;

-- Acts as the given user for the rest of the current block (RLS applies).
CREATE FUNCTION pg_temp.as_user(p_uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END;
$$;

-- ── T1. A Buyer cannot read listings of a market Buyers cannot see ─────────
DO $$
DECLARE v_buyer uuid; v_n int;
BEGIN
  SELECT user_id INTO v_buyer FROM user_roles WHERE role='buyer' AND status='active' LIMIT 1;
  IF v_buyer IS NULL THEN INSERT INTO r(test,result,detail) VALUES ('T1 buyer cannot read farmer-only listings','SKIP','no active buyer'); RETURN; END IF;
  PERFORM pg_temp.as_user(v_buyer);
  SELECT count(*) INTO v_n FROM marketplace_listings ml
   WHERE NOT COALESCE((SELECT mt.buyer_visible FROM market_types mt WHERE mt.code = ml.crop_type), TRUE);
  RESET ROLE;
  INSERT INTO r(test,result,detail) VALUES ('T1 buyer cannot read farmer-only listings',
    CASE WHEN v_n = 0 THEN 'PASS' ELSE 'FAIL' END, v_n || ' farmer-only listing(s) visible to the buyer');
END $$;

-- ── T2. An approved Farmer reads every approved listing ────────────────────
DO $$
DECLARE v_farmer uuid; v_visible int; v_total int;
BEGIN
  SELECT user_id INTO v_farmer FROM user_roles WHERE role='farmer' AND status='active' LIMIT 1;
  IF v_farmer IS NULL THEN INSERT INTO r(test,result,detail) VALUES ('T2 approved farmer reads both markets','SKIP','no active farmer'); RETURN; END IF;
  SELECT count(*) INTO v_total FROM marketplace_listings WHERE status='approved';
  PERFORM pg_temp.as_user(v_farmer);
  SELECT count(*) INTO v_visible FROM marketplace_listings WHERE status='approved';
  RESET ROLE;
  INSERT INTO r(test,result,detail) VALUES ('T2 approved farmer reads both markets',
    CASE WHEN v_visible = v_total THEN 'PASS' ELSE 'FAIL' END, v_visible || ' of ' || v_total || ' approved listings visible');
END $$;

-- ── T3. A Buyer cannot ORDER a farmer-only listing (backend) ───────────────
DO $$
DECLARE v_buyer uuid; v_listing uuid; v_msg text;
BEGIN
  SELECT user_id INTO v_buyer FROM user_roles WHERE role='buyer' AND status='active' LIMIT 1;
  SELECT ml.id INTO v_listing FROM marketplace_listings ml JOIN market_types mt ON mt.code = ml.crop_type
   WHERE NOT mt.buyer_visible AND ml.status='approved' AND ml.remaining_kg > 0 LIMIT 1;
  IF v_buyer IS NULL OR v_listing IS NULL THEN INSERT INTO r(test,result,detail) VALUES ('T3 buyer cannot order a farmer-only listing','SKIP','needs an active buyer and an approved Cooperative Market listing with stock'); RETURN; END IF;
  PERFORM pg_temp.as_user(v_buyer);
  BEGIN
    PERFORM place_order(v_listing, 0.1);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  RESET ROLE;
  INSERT INTO r(test,result,detail) VALUES ('T3 buyer cannot order a farmer-only listing',
    CASE WHEN v_msg ILIKE '%Cooperative Market%' THEN 'PASS' ELSE 'FAIL' END, coalesce(v_msg, 'the order was accepted'));
END $$;

-- ── T4. A Farmer cannot buy their OWN listing (backend) ────────────────────
DO $$
DECLARE v_farmer uuid; v_listing uuid; v_msg text;
BEGIN
  SELECT ml.id, ml.farmer_id INTO v_listing, v_farmer FROM marketplace_listings ml
   JOIN user_roles ur ON ur.user_id = ml.farmer_id AND ur.status='active'
   WHERE ml.status='approved' AND ml.remaining_kg > 0 LIMIT 1;
  IF v_listing IS NULL THEN INSERT INTO r(test,result,detail) VALUES ('T4 farmer cannot buy own listing','SKIP','no approved listing with stock'); RETURN; END IF;
  PERFORM pg_temp.as_user(v_farmer);
  BEGIN
    PERFORM place_order(v_listing, 0.1);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  RESET ROLE;
  INSERT INTO r(test,result,detail) VALUES ('T4 farmer cannot buy own listing',
    CASE WHEN v_msg ILIKE '%own listing%' THEN 'PASS' ELSE 'FAIL' END, coalesce(v_msg, 'the order was accepted'));
END $$;

-- ── T5. A Farmer CAN buy another farmer's farmer-only listing ──────────────
DO $$
DECLARE v_seller uuid; v_buyer uuid; v_listing uuid; v_msg text; v_id uuid;
BEGIN
  SELECT ml.id, ml.farmer_id INTO v_listing, v_seller FROM marketplace_listings ml JOIN market_types mt ON mt.code = ml.crop_type
   WHERE NOT mt.buyer_visible AND ml.status='approved' AND ml.remaining_kg > 0 LIMIT 1;
  SELECT user_id INTO v_buyer FROM user_roles WHERE role='farmer' AND status='active' AND user_id <> coalesce(v_seller, '00000000-0000-0000-0000-000000000000'::uuid) LIMIT 1;
  IF v_listing IS NULL OR v_buyer IS NULL THEN INSERT INTO r(test,result,detail) VALUES ('T5 farmer can buy another farmer''s Cooperative listing','SKIP','needs a Cooperative listing with stock and a second active farmer'); RETURN; END IF;
  PERFORM pg_temp.as_user(v_buyer);
  BEGIN
    v_id := place_order(v_listing, 0.1);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM;
  END;
  RESET ROLE;
  INSERT INTO r(test,result,detail) VALUES ('T5 farmer can buy another farmer''s Cooperative listing',
    CASE WHEN v_id IS NOT NULL THEN 'PASS' ELSE 'FAIL' END, coalesce(v_msg, 'order ' || v_id));
END $$;

-- ── T6. A Buyer reads Public Market prices only ────────────────────────────
DO $$
DECLARE v_buyer uuid; v_n int;
BEGIN
  SELECT user_id INTO v_buyer FROM user_roles WHERE role='buyer' AND status='active' LIMIT 1;
  IF v_buyer IS NULL THEN INSERT INTO r(test,result,detail) VALUES ('T6 buyer reads public prices only','SKIP','no active buyer'); RETURN; END IF;
  PERFORM pg_temp.as_user(v_buyer);
  SELECT count(*) INTO v_n FROM price_records pr
   WHERE NOT COALESCE((SELECT mt.buyer_visible FROM market_types mt WHERE mt.code = pr.price_type), TRUE);
  RESET ROLE;
  INSERT INTO r(test,result,detail) VALUES ('T6 buyer reads public prices only',
    CASE WHEN v_n = 0 THEN 'PASS' ELSE 'FAIL' END, v_n || ' farmer-only price record(s) visible');
END $$;

-- ── T7. Order history still works for a Buyer (my_order_listings) ──────────
DO $$
DECLARE v_buyer uuid; v_expected int; v_got int;
BEGIN
  SELECT o.buyer_id INTO v_buyer FROM orders o JOIN user_roles ur ON ur.user_id=o.buyer_id AND ur.role='buyer' GROUP BY o.buyer_id ORDER BY count(*) DESC LIMIT 1;
  IF v_buyer IS NULL THEN INSERT INTO r(test,result,detail) VALUES ('T7 buyer order history keeps listing details','SKIP','no buyer has orders'); RETURN; END IF;
  SELECT count(DISTINCT listing_id) INTO v_expected FROM orders WHERE buyer_id = v_buyer;
  PERFORM pg_temp.as_user(v_buyer);
  SELECT count(*) INTO v_got FROM my_order_listings;
  RESET ROLE;
  INSERT INTO r(test,result,detail) VALUES ('T7 buyer order history keeps listing details',
    CASE WHEN v_got = v_expected THEN 'PASS' ELSE 'FAIL' END, v_got || ' of ' || v_expected || ' ordered listings readable');
END $$;

-- ── T8. A crop with an exclusive channel cannot use the other channels ─────
DO $$
DECLARE v_batch uuid; v_farmer uuid; v_crop text; v_msg text;
BEGIN
  SELECT ib.id, ib.farmer_id, ib.crop_name INTO v_batch, v_farmer, v_crop FROM inventory_batches ib WHERE ib.exclusive_channel IS NOT NULL LIMIT 1;
  IF v_batch IS NULL THEN INSERT INTO r(test,result,detail) VALUES ('T8 reserved crop refused by Informal Sale / Offer / Marketplace','SKIP','no batch of a reserved crop'); RETURN; END IF;

  BEGIN INSERT INTO informal_sales (farmer_id, inventory_batch_id, crop_name, quantity_kg, buyer_name, amount) VALUES (v_farmer, v_batch, v_crop, 1, 'test', 1);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  INSERT INTO r(test,result,detail) VALUES ('T8a reserved crop refused: Informal Sale',
    CASE WHEN v_msg ILIKE '%can only be sold through%' THEN 'PASS' ELSE 'FAIL' END, coalesce(v_msg,'accepted'));

  v_msg := NULL;
  BEGIN INSERT INTO cooperative_purchase_offers (farmer_id, inventory_batch_id, crop_name, offered_quantity_kg) VALUES (v_farmer, v_batch, v_crop, 1);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  INSERT INTO r(test,result,detail) VALUES ('T8b reserved crop refused: Offer to Cooperative',
    CASE WHEN v_msg ILIKE '%can only be sold through%' THEN 'PASS' ELSE 'FAIL' END, coalesce(v_msg,'accepted'));

  v_msg := NULL;
  PERFORM pg_temp.as_user(v_farmer);
  BEGIN PERFORM create_listing_with_reservation(v_batch, v_crop, NULL, 1, 10, NULL, 'test');
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  INSERT INTO r(test,result,detail) VALUES ('T8c reserved crop refused: Marketplace listing',
    CASE WHEN v_msg ILIKE '%can only be sold through%' THEN 'PASS' ELSE 'FAIL' END, coalesce(v_msg,'accepted'));
END $$;

-- ── T9. Market Linking refuses a batch that is not a reserved crop ─────────
DO $$
DECLARE v_batch uuid; v_farmer uuid; v_crop text; v_msg text;
BEGIN
  SELECT ib.id, ib.farmer_id, ib.crop_name INTO v_batch, v_farmer, v_crop FROM inventory_batches ib WHERE ib.exclusive_channel IS NULL LIMIT 1;
  IF v_batch IS NULL THEN INSERT INTO r(test,result,detail) VALUES ('T9 Market Linking refuses an ordinary crop','SKIP','no ordinary batch'); RETURN; END IF;
  BEGIN INSERT INTO market_linking_programs (farmer_id, crop_name, season_year, status, inventory_batch_id, volume_kg) VALUES (v_farmer, v_crop, 2026, 'submitted', v_batch, 1);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  INSERT INTO r(test,result,detail) VALUES ('T9 Market Linking refuses an ordinary crop',
    CASE WHEN v_msg ILIKE '%only for crops reserved%' THEN 'PASS' ELSE 'FAIL' END, coalesce(v_msg,'accepted'));
END $$;

-- ── T10. Inventory Source is required and capped at 150 ────────────────────
DO $$
DECLARE v_msg text;
BEGIN
  BEGIN INSERT INTO cooperative_inventory (item_name, category, unit) VALUES ('zz_source_test','Seeds','kg');
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  INSERT INTO r(test,result,detail) VALUES ('T10a inventory item without Source refused',
    CASE WHEN v_msg ILIKE '%Source is required%' THEN 'PASS' ELSE 'FAIL' END, coalesce(v_msg,'accepted'));
  v_msg := NULL;
  BEGIN INSERT INTO cooperative_inventory (item_name, category, unit, source) VALUES ('zz_source_test','Seeds','kg', repeat('x',151));
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  INSERT INTO r(test,result,detail) VALUES ('T10b Source over 150 characters refused',
    CASE WHEN v_msg ILIKE '%150 characters%' THEN 'PASS' ELSE 'FAIL' END, coalesce(v_msg,'accepted'));
  v_msg := NULL;
  BEGIN INSERT INTO cooperative_inventory (item_name, category, unit, source) VALUES ('zz_source_test','Seeds','kg','DA donation');
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  INSERT INTO r(test,result,detail) VALUES ('T10c item with a Source accepted',
    CASE WHEN v_msg IS NULL THEN 'PASS' ELSE 'FAIL' END, coalesce(v_msg,'accepted'));
END $$;

-- ── T11. admin_update_listing_price follows the LISTING's market type ──────
DO $$
DECLARE v_admin uuid; v_coop uuid; v_pub uuid; v_msg_a text; v_msg_b text;
BEGIN
  SELECT ur.user_id INTO v_admin FROM user_roles ur JOIN admin_profiles ap ON ap.user_id = ur.user_id WHERE ur.role='admin' LIMIT 1;
  SELECT ml.id INTO v_coop FROM marketplace_listings ml JOIN market_types mt ON mt.code=ml.crop_type WHERE mt.manager_sets_price AND ml.status='approved' LIMIT 1;
  SELECT ml.id INTO v_pub  FROM marketplace_listings ml JOIN market_types mt ON mt.code=ml.crop_type WHERE NOT mt.manager_sets_price AND ml.status='approved' LIMIT 1;
  IF v_admin IS NULL THEN INSERT INTO r(test,result,detail) VALUES ('T11 Manager price edit','SKIP','no Manager with an admin profile'); RETURN; END IF;

  -- Do both attempts as the Manager, but write the results only after switching
  -- back: the Manager's role cannot write to the test table.
  PERFORM pg_temp.as_user(v_admin);
  IF v_coop IS NOT NULL THEN
    BEGIN PERFORM admin_update_listing_price(v_coop, 21); EXCEPTION WHEN OTHERS THEN v_msg_a := SQLERRM; END;
  END IF;
  IF v_pub IS NOT NULL THEN
    BEGIN PERFORM admin_update_listing_price(v_pub, 21); EXCEPTION WHEN OTHERS THEN v_msg_b := SQLERRM; END;
  END IF;
  RESET ROLE;

  IF v_coop IS NOT NULL THEN
    INSERT INTO r(test,result,detail) VALUES ('T11a Manager can edit a Cooperative listing price',
      CASE WHEN v_msg_a IS NULL THEN 'PASS' ELSE 'FAIL' END, coalesce(v_msg_a,'updated'));
  ELSE
    INSERT INTO r(test,result,detail) VALUES ('T11a Manager can edit a Cooperative listing price','SKIP','no approved Cooperative listing');
  END IF;
  IF v_pub IS NOT NULL THEN
    INSERT INTO r(test,result,detail) VALUES ('T11b Manager cannot edit a Public listing price',
      CASE WHEN v_msg_b ILIKE '%Only Cooperative Market%' THEN 'PASS' ELSE 'FAIL' END, coalesce(v_msg_b,'updated'));
  ELSE
    INSERT INTO r(test,result,detail) VALUES ('T11b Manager cannot edit a Public listing price','SKIP','no approved Public listing');
  END IF;
END $$;

-- ── T12. The app cannot assign an exclusive channel ────────────────────────
DO $$
DECLARE v_admin uuid; v_msg text;
BEGIN
  SELECT user_id INTO v_admin FROM user_roles WHERE role='admin' LIMIT 1;
  IF v_admin IS NULL THEN INSERT INTO r(test,result,detail) VALUES ('T12 exclusive channel cannot be set from the app','SKIP','no Manager'); RETURN; END IF;
  PERFORM pg_temp.as_user(v_admin);
  BEGIN UPDATE crop_master SET exclusive_channel = 'da_amad_market_linking' WHERE id = (SELECT id FROM crop_master WHERE exclusive_channel IS NULL LIMIT 1);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  INSERT INTO r(test,result,detail) VALUES ('T12 exclusive channel cannot be set from the app',
    CASE WHEN v_msg ILIKE '%database administrator%' THEN 'PASS' ELSE 'FAIL' END, coalesce(v_msg,'accepted'));
END $$;

-- ── T13. Order wording: Pending Order / Disapproved ────────────────────────
DO $$
DECLARE v_user uuid; v_title text; v_body text;
BEGIN
  SELECT user_id INTO v_user FROM user_roles WHERE role='buyer' LIMIT 1;
  IF v_user IS NULL THEN INSERT INTO r(test,result,detail) VALUES ('T13 order wording','SKIP','no buyer'); RETURN; END IF;
  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (v_user, 'order', 'Order Rejected', 'Your order for Tomato was rejected. Reason: it was rejected before', FALSE)
  RETURNING title, body INTO v_title, v_body;
  INSERT INTO r(test,result,detail) VALUES ('T13a rejected order notice reads Disapproved',
    CASE WHEN v_title = 'Order Disapproved' AND v_body = 'Your order for Tomato was disapproved. Reason: it was rejected before' THEN 'PASS' ELSE 'FAIL' END, v_title || ' / ' || v_body);
  INSERT INTO notifications (user_id, type, title, body, is_read)
  VALUES (v_user, 'order', 'Order Pending Review', 'Your order for Tomato was placed and is pending review.', FALSE)
  RETURNING title, body INTO v_title, v_body;
  INSERT INTO r(test,result,detail) VALUES ('T13b pending order notice reads Pending Order',
    CASE WHEN v_title = 'Pending Order' AND v_body ILIKE '%pending order%' THEN 'PASS' ELSE 'FAIL' END, v_title || ' / ' || v_body);
END $$;

-- ── Report ─────────────────────────────────────────────────────────────────
-- Delivered as an ERROR message on purpose: an error aborts the whole
-- transaction, so every change the tests made is undone and nothing is kept.
-- The SQL editor shows the message in full: read it as the result.
DO $$
DECLARE rep text;
BEGIN
  SELECT string_agg(rpad(result, 5) || ' ' || test || '  —  ' || coalesce(detail, ''), E'\n' ORDER BY n)
    INTO rep FROM r;
  RAISE EXCEPTION E'\nMARKET RULES TEST REPORT (nothing was kept)\n\n%\n\nFAIL: %   PASS: %   SKIP: %',
    rep,
    (SELECT count(*) FROM r WHERE result = 'FAIL'),
    (SELECT count(*) FROM r WHERE result = 'PASS'),
    (SELECT count(*) FROM r WHERE result = 'SKIP');
END $$;
