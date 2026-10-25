-- ============================================================
-- SAGANA — Selling channels: end-to-end decimal scenario test
--
-- Runs the REAL database functions, as the real roles (a Farmer, a Manager, a
-- Buyer), through all four selling channels with decimal quantities and prices:
--
--   Marketplace          create listing 4.25 @ 12.50 -> Manager approves ->
--                        Buyer orders 1.25 / 0.45 / 2.55 (one cancelled) ->
--                        Manager approves and completes
--   Offer to Cooperative offer 2.50 @ 80.40 -> counteroffer 75.25 -> accepted;
--                        a second offer 0.45 @ 10.00 is declined
--   Informal Sale        1.25 for 125.75, then the rest for 99.99
--   DA-AMAD (Ginger)     submit 3.45 -> buyer found at 45.50 -> completed;
--                        Ginger refused by the other three channels
--
-- and then checks what the Farmer's Transaction History and the Manager's Sales
-- Report read: the right rows, once each, in the right channel, with amounts
-- that add up, and that cancelled / declined / unfinished things are not sales.
-- The inventory batch is checked after every channel (available + sold = total).
--
-- It changes nothing: it ends by raising an error on purpose, which rolls
-- everything back, and the error text IS the report (PASS / FAIL / SKIP lines).
--
-- Run, in this order: supabase_schema_harvest_batch_number_and_units.sql,
-- supabase_schema_selling_channels_integrity.sql, then this whole file.
-- It picks one active Farmer, one active Manager (admin) and one active Buyer
-- from your data. A SKIP means the data to test that step does not exist.
-- If a step stops with a raw database error instead of the report, paste it.
-- ============================================================

CREATE OR REPLACE FUNCTION pg_temp.as_user(p_uid uuid) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.jwt.claim.sub', p_uid::text, true);
  EXECUTE 'SET LOCAL ROLE authenticated';
END;
$$;

-- Builds one report line. Only ever called while the role is reset.
CREATE OR REPLACE FUNCTION pg_temp.chk(p_ok boolean, p_label text, p_detail text DEFAULT NULL)
RETURNS text LANGUAGE sql AS $$
  SELECT CASE WHEN COALESCE(p_ok, false) THEN 'PASS ' ELSE 'FAIL ' END || p_label ||
         CASE WHEN p_detail IS NULL THEN '' ELSE ' — ' || p_detail END || E'\n';
$$;

DO $test$
DECLARE
  v_rep     TEXT := E'\n';
  v_fail    INT;
  F UUID; M UUID; B UUID;                   -- farmer, manager, buyer
  v_mtype   TEXT;
  v_unit    TEXT;
  v_name    CONSTANT TEXT := 'Zz Channel Test Crop';
  v_cm      UUID; v_fc UUID; v_h UUID; v_batch UUID;
  v_listing UUID; v_o1 UUID; v_o2 UUID; v_o3 UUID; v_o4 UUID;
  v_offer   UUID; v_offer2 UUID; v_tx UUID; v_round INT;
  v_sale1   UUID; v_sale2 UUID;
  bt        inventory_batches%ROWTYPE;
  l         marketplace_listings%ROWTYPE;
  o         orders%ROWTYPE;
  of_       cooperative_purchase_offers%ROWTYPE;
  t         member_sales_transactions%ROWTYPE;
  s         informal_sales%ROWTYPE;
  v_msg     TEXT;
  v_tot     NUMERIC;
  v_cnt     INT;
  -- Ginger
  v_gcm UUID; v_gfc UUID; v_gh UUID; v_gb UUID; v_prog UUID; v_prog2 UUID;
  v_gname   TEXT;
  gb        inventory_batches%ROWTYPE;
  prog      market_linking_programs%ROWTYPE;
  f_mkt NUMERIC; f_off NUMERIC; f_inf NUMERIC; f_da NUMERIC;
  n_mkt INT; n_off INT; n_inf INT; n_da INT;
  v_expected NUMERIC;
  v_who     TEXT;
BEGIN
  -- ── Who plays whom ────────────────────────────────────────────────────────
  SELECT user_id INTO F FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND NOT COALESCE(pending_acknowledgement, false) LIMIT 1;
  SELECT user_id INTO M FROM user_roles WHERE role = 'admin' AND status = 'active' LIMIT 1;
  SELECT user_id INTO B FROM user_roles WHERE role = 'buyer' AND status = 'active' LIMIT 1;
  SELECT code INTO v_mtype FROM market_types WHERE buyer_visible AND is_active ORDER BY sort_order LIMIT 1;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM units WHERE is_active AND lower(name) = 'sack') THEN 'sack' ELSE 'kg' END INTO v_unit;

  IF F IS NULL OR M IS NULL OR B IS NULL OR v_mtype IS NULL THEN
    RAISE EXCEPTION E'SELLING CHANNELS TEST REPORT\nSKIP everything: needs an active farmer, an active admin, an active buyer and a buyer-visible market type (found: farmer=%, admin=%, buyer=%, market=%)', F, M, B, v_mtype;
  END IF;
  v_rep := v_rep || 'INFO farmer ' || F || ', manager ' || M || ', buyer ' || B || ', unit "' || v_unit || '", market ' || v_mtype || E'\n';

  -- ── Test stock: a crop, a harvest of 10.75 and its batch (as the SQL editor) ──
  INSERT INTO crop_master (crop_name, category, crop_type) VALUES (v_name, 'Other', v_mtype) RETURNING id INTO v_cm;
  INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id) VALUES (F, v_name, 'Other', v_cm) RETURNING id INTO v_fc;
  INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
    VALUES (F, v_fc, v_name, 10.75, DATE '2096-03-04', v_unit) RETURNING id INTO v_h;
  INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, quantity_kg, available_kg,
                                 status, is_coop_eligible, crop_type)
    VALUES (F, v_h, v_fc, v_name, 10.75, 10.75, 'available', TRUE, v_mtype) RETURNING id INTO v_batch;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.quantity_kg = 10.75 AND bt.available_kg = 10.75 AND bt.unit = v_unit,
    '0   test batch ' || bt.batch_number, bt.quantity_kg || ' ' || bt.unit);

  -- ═════════════ 1. MARKETPLACE ═════════════
  PERFORM pg_temp.as_user(F);
  v_listing := create_listing_with_reservation(v_batch, v_name, NULL, 4.25, 12.50, NULL, 'Decimal channel test');
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(l.volume_kg = 4.25 AND l.remaining_kg = 4.25 AND l.price_per_kg = 12.50
      AND l.status = 'pending_review' AND l.unit = v_unit,
    '1.1 listing created with 4.25 @ 12.50 and the batch unit', l.volume_kg || ' / ' || l.remaining_kg || ' @ ' || l.price_per_kg || ' ' || l.unit);
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 6.50, '1.2 the batch reserved exactly 4.25 (10.75 -> 6.50)', bt.available_kg::text);

  PERFORM pg_temp.as_user(M);
  PERFORM approve_listing(v_listing);
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  v_rep := v_rep || pg_temp.chk(l.status = 'approved', '1.3 Manager approves the decimal listing', l.status);

  PERFORM pg_temp.as_user(B);
  v_o1 := place_order(v_listing, 1.25);
  v_o2 := place_order(v_listing, 0.45);
  v_o3 := place_order(v_listing, 0.30);
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_o1;
  v_rep := v_rep || pg_temp.chk(o.quantity_kg = 1.25 AND o.price_per_kg = 12.50 AND o.total_price = 15.63 AND o.unit = v_unit AND o.status = 'pending',
    '1.4 order 1.25 x 12.50 = 15.63 (15.625 rounded to the centavo)', o.quantity_kg || ' x ' || o.price_per_kg || ' = ' || o.total_price || ' ' || o.unit);
  SELECT * INTO o FROM orders WHERE id = v_o2;
  v_rep := v_rep || pg_temp.chk(o.quantity_kg = 0.45 AND o.total_price = 5.63,
    '1.5 order 0.45 x 12.50 = 5.63 (5.625 rounded)', o.quantity_kg || ' x ' || o.price_per_kg || ' = ' || o.total_price);
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  v_rep := v_rep || pg_temp.chk(l.remaining_kg = 2.25, '1.6 remaining after 1.25 + 0.45 + 0.30 is 2.25 (4.25 - 2.00)', l.remaining_kg::text);

  PERFORM pg_temp.as_user(B);
  PERFORM cancel_my_order(v_o3, 'decimal test');
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  SELECT * INTO o FROM orders WHERE id = v_o3;
  v_rep := v_rep || pg_temp.chk(l.remaining_kg = 2.55 AND o.status = 'cancelled',
    '1.7 cancelling the 0.30 order gives exactly 0.30 back (2.55)', l.remaining_kg || ' / order ' || o.status);

  PERFORM pg_temp.as_user(M);
  PERFORM approve_order(v_o1);
  PERFORM approve_order(v_o2);
  PERFORM complete_order(v_o1);
  PERFORM complete_order(v_o2);
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.sold_kg = 1.70 AND bt.available_kg = 6.50,
    '1.8 two completed orders add exactly 1.70 to sold_kg', 'sold ' || bt.sold_kg || ', available ' || bt.available_kg);

  PERFORM pg_temp.as_user(B);
  v_o4 := place_order(v_listing, 2.55);
  RESET ROLE;
  PERFORM pg_temp.as_user(M);
  PERFORM approve_order(v_o4);
  PERFORM complete_order(v_o4);
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_o4;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(o.total_price = 31.88 AND l.remaining_kg = 0 AND l.status = 'sold',
    '1.9 the last 2.55 x 12.50 = 31.88; the listing is sold out', 'total ' || o.total_price || ', listing ' || l.status);
  v_rep := v_rep || pg_temp.chk(bt.sold_kg = 4.25 AND bt.available_kg = 6.50 AND bt.status = 'available',
    '1.10 batch: sold 4.25, available 6.50, status available', 'sold ' || bt.sold_kg || ' / available ' || bt.available_kg || ' / ' || bt.status);

  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM place_order(v_listing, 0.01); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '1.11 a sold-out listing refuses another order', v_msg);

  SELECT COALESCE(sum(total_price), 0), count(*) INTO v_tot, v_cnt FROM orders WHERE listing_id = v_listing AND status = 'completed';
  v_rep := v_rep || pg_temp.chk(v_tot = 53.14 AND v_cnt = 3,
    '1.12 completed marketplace revenue = 15.63 + 5.63 + 31.88 = 53.14 (3 orders; the cancelled one is not a sale)', v_tot || ' in ' || v_cnt || ' orders');

  -- ═════════════ 2. OFFER TO COOPERATIVE ═════════════
  PERFORM pg_temp.as_user(F);
  v_offer := offer_batch_to_cooperative(v_batch, 2.50, 80.40, NULL);
  RESET ROLE;
  SELECT * INTO of_ FROM cooperative_purchase_offers WHERE id = v_offer;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(of_.offered_quantity_kg = 2.50 AND of_.asking_price_per_kg = 80.40 AND of_.unit = v_unit AND bt.available_kg = 4.00,
    '2.1 offer 2.50 @ 80.40 reserves exactly 2.50 (6.50 -> 4.00)', of_.offered_quantity_kg || ' @ ' || of_.asking_price_per_kg || ', available ' || bt.available_kg);

  PERFORM pg_temp.as_user(M);
  v_round := counter_cooperative_offer(v_offer, 75.25, 1, NULL);
  RESET ROLE;
  PERFORM pg_temp.as_user(F);
  v_tx := accept_cooperative_offer(v_offer, v_round, NULL);
  RESET ROLE;
  SELECT * INTO of_ FROM cooperative_purchase_offers WHERE id = v_offer;
  SELECT * INTO t FROM member_sales_transactions WHERE id = v_tx;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(of_.status = 'confirmed' AND of_.agreed_price_per_kg = 75.25 AND of_.confirmed_amount = 188.13,
    '2.2 counter 75.25 accepted: 2.50 x 75.25 = 188.13 (188.125 rounded)', of_.status || ' @ ' || of_.agreed_price_per_kg || ' = ' || of_.confirmed_amount);
  v_rep := v_rep || pg_temp.chk(t.quantity_kg = 2.50 AND t.amount = 188.13 AND t.unit = v_unit AND t.crop_name = v_name,
    '2.3 the sale row has 2.50, 188.13 and the offer''s unit', t.quantity_kg || ' / ' || t.amount || ' / ' || t.unit);
  v_rep := v_rep || pg_temp.chk(bt.sold_kg = 6.75 AND bt.available_kg = 4.00,
    '2.4 the accepted offer counts as SOLD in the batch (4.25 + 2.50 = 6.75), available unchanged', 'sold ' || bt.sold_kg || ' / available ' || bt.available_kg);

  PERFORM pg_temp.as_user(F);
  v_offer2 := offer_batch_to_cooperative(v_batch, 0.45, 10.00, NULL);
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 3.55, '2.5 a second offer of 0.45 reserves exactly 0.45 (4.00 -> 3.55)', bt.available_kg::text);
  PERFORM pg_temp.as_user(M);
  PERFORM decline_cooperative_offer(v_offer2, 'decimal test', 1);
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  SELECT * INTO of_ FROM cooperative_purchase_offers WHERE id = v_offer2;
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 4.00 AND of_.status = 'declined' AND bt.sold_kg = 6.75,
    '2.6 declining gives exactly 0.45 back and sells nothing', 'available ' || bt.available_kg || ', sold ' || bt.sold_kg || ', offer ' || of_.status);

  -- ═════════════ 3. INFORMAL SALE ═════════════
  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM record_informal_sale(v_batch, v_name, 0, 'X', 10, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3.1 a zero quantity is refused', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM record_informal_sale(v_batch, v_name, 0.456, 'X', 10, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3.2 a third decimal in the quantity is refused, not silently rounded', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM record_informal_sale(v_batch, v_name, 1, 'X', -5, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3.3 a negative amount is refused', v_msg);

  PERFORM pg_temp.as_user(F);
  v_sale1 := record_informal_sale(v_batch, v_name, 1.25, 'Neighbor', 125.75, NULL);
  RESET ROLE;
  SELECT * INTO s FROM informal_sales WHERE id = v_sale1;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(s.quantity_kg = 1.25 AND s.amount = 125.75 AND s.unit = v_unit,
    '3.4 informal sale 1.25 for 125.75 stored exactly with the batch unit', s.quantity_kg || ' / ' || s.amount || ' / ' || s.unit);
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 2.75 AND bt.sold_kg = 8.00 AND bt.status = 'available',
    '3.5 batch: available 2.75, sold 8.00 (6.75 + 1.25)', 'available ' || bt.available_kg || ', sold ' || bt.sold_kg || ', ' || bt.status);

  -- Someone else cannot sell from this farmer's stock (2.75 is still there).
  v_msg := NULL;
  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM record_informal_sale(v_batch, v_name, 0.50, 'X', 1, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL AND bt.available_kg = 2.75,
    '3.6 another account cannot reserve this farmer''s stock', coalesce(v_msg, 'it was accepted') || ' (available ' || bt.available_kg || ')');

  PERFORM pg_temp.as_user(F);
  v_sale2 := record_informal_sale(v_batch, v_name, 2.75, 'Neighbor 2', 99.99, NULL);
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 0 AND bt.sold_kg = 10.75 AND bt.status = 'sold_out',
    '3.7 selling the last 2.75 empties the batch: sold 10.75 of 10.75, status sold_out (not "reserved")', 'available ' || bt.available_kg || ', sold ' || bt.sold_kg || ', ' || bt.status);
  v_rep := v_rep || pg_temp.chk(bt.available_kg + bt.sold_kg = bt.quantity_kg,
    '3.8 inventory adds up across Marketplace + Offer + Informal: available + sold = harvested', bt.available_kg || ' + ' || bt.sold_kg || ' = ' || bt.quantity_kg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM record_informal_sale(v_batch, v_name, 0.01, 'X', 1, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3.9 nothing more can be sold from an empty batch', v_msg);

  -- ═════════════ 4. DA-AMAD MARKET LINKING (Ginger) ═════════════
  SELECT id INTO v_gcm FROM crop_master WHERE exclusive_channel = 'da_amad_market_linking' LIMIT 1;
  IF v_gcm IS NULL THEN
    v_rep := v_rep || E'SKIP 4   no crop is reserved for DA-AMAD in crop_master, so the Ginger steps cannot run\n';
  ELSE
    SELECT crop_name INTO v_gname FROM crop_master WHERE id = v_gcm;
    SELECT id INTO v_gfc FROM farmer_crops WHERE farmer_id = F AND crop_master_id = v_gcm LIMIT 1;
    IF v_gfc IS NULL THEN
      INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id)
        SELECT F, cm.crop_name, cm.category, cm.id FROM crop_master cm WHERE cm.id = v_gcm RETURNING id INTO v_gfc;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM da_amad_enrollments WHERE farmer_id = F AND status = 'approved') THEN
      IF EXISTS (SELECT 1 FROM da_amad_enrollments WHERE farmer_id = F AND status = 'pending') THEN
        UPDATE da_amad_enrollments SET status = 'approved', reviewed_at = now(), reviewed_by = M
         WHERE farmer_id = F AND status = 'pending';
      ELSE
        INSERT INTO da_amad_enrollments (farmer_id, status, reviewed_at, reviewed_by) VALUES (F, 'approved', now(), M);
      END IF;
    END IF;
    INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
      VALUES (F, v_gfc, v_gname, 8.50, DATE '2096-03-05', 'kg') RETURNING id INTO v_gh;
    INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, quantity_kg, available_kg, status, is_coop_eligible)
      VALUES (F, v_gh, v_gfc, v_gname, 8.50, 8.50, 'available', FALSE) RETURNING id INTO v_gb;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(gb.exclusive_channel = 'da_amad_market_linking', '4.0 the Ginger batch carries its exclusive channel', coalesce(gb.exclusive_channel, 'none'));

    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM create_listing_with_reservation(v_gb, v_gname, NULL, 1.25, 12.50, NULL, 'x'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%can only be sold through%', '4.1 Ginger cannot be listed on the Marketplace', v_msg);

    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM offer_batch_to_cooperative(v_gb, 1.25, 12.50, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '4.2 Ginger cannot be offered to the Cooperative', v_msg);

    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM record_informal_sale(v_gb, v_gname, 1.25, 'X', 10, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '4.3 Ginger cannot be sold informally', v_msg);
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(gb.available_kg = 8.50, '4.3b the refused attempts took no stock from the Ginger batch', gb.available_kg::text);

    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM submit_ginger_for_sale(v_gb, 0); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '4.4 a zero Ginger quantity is refused', v_msg);

    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM submit_ginger_for_sale(v_gb, 99); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '4.5 more than the batch holds is refused', v_msg);

    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM submit_ginger_for_sale(v_gb, 1.234); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '4.6 a third decimal is refused', v_msg);

    PERFORM pg_temp.as_user(F);
    v_prog  := submit_ginger_for_sale(v_gb, 3.45);
    v_prog2 := submit_ginger_for_sale(v_gb, 1.00);
    RESET ROLE;
    SELECT * INTO prog FROM market_linking_programs WHERE id = v_prog;
    v_rep := v_rep || pg_temp.chk(prog.volume_kg = 3.45 AND prog.status = 'submitted', '4.7 Ginger 3.45 submitted for DA-AMAD', prog.volume_kg || ' / ' || prog.status);

    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN
      UPDATE market_linking_programs SET status = 'buyer_found', buyer_name = 'Buyer X' WHERE id = v_prog2;
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '4.8 a buyer cannot be recorded without a price and quantity', v_msg);

    PERFORM pg_temp.as_user(M);
    UPDATE market_linking_programs
       SET status = 'buyer_found', buyer_name = 'DA-AMAD Buyer', price_per_kg = 45.50,
           requested_volume_kg = 3.45, buyer_found_at = now()
     WHERE id = v_prog;
    PERFORM complete_market_linking(v_prog, v_gb, 3.45, 'DA-AMAD Buyer', NULL, 45.50, NULL);
    RESET ROLE;
    SELECT * INTO prog FROM market_linking_programs WHERE id = v_prog;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(prog.status = 'completed' AND prog.confirmed_volume_kg = 3.45 AND prog.price_per_kg = 45.50,
      '4.9 DA-AMAD sale completed at 3.45 @ 45.50', prog.status || ' ' || prog.confirmed_volume_kg || ' @ ' || prog.price_per_kg);
    v_rep := v_rep || pg_temp.chk(gb.available_kg = 5.05 AND gb.sold_kg = 3.45 AND gb.status = 'available',
      '4.10 Ginger batch: available 5.05, sold 3.45 (8.50 - 3.45)', 'available ' || gb.available_kg || ', sold ' || gb.sold_kg || ', ' || gb.status);
    v_rep := v_rep || pg_temp.chk(round(prog.confirmed_volume_kg * prog.price_per_kg, 2) = 156.98,
      '4.11 DA-AMAD amount 3.45 x 45.50 = 156.98 (156.975 rounded); the app computes it the same way', (prog.confirmed_volume_kg * prog.price_per_kg)::text);
  END IF;

  -- ═════════════ 5. TRANSACTION HISTORY and SALES REPORT read the same rows ═════════════
  -- The rules the app uses (admin_reports_repository / farmer_transaction_repository):
  --   Marketplace = completed orders; Offer = member_sales_transactions; Informal = every
  --   informal sale; DA-AMAD = completed programs. Read as the Manager (Sales Report), then
  --   as the Farmer (Transaction History): both must see the same rows and totals.
  FOR i IN 1..2 LOOP
    IF i = 1 THEN PERFORM pg_temp.as_user(M); ELSE PERFORM pg_temp.as_user(F); END IF;
    SELECT COALESCE(sum(total_price),0), count(*) INTO f_mkt, n_mkt FROM orders WHERE listing_id = v_listing AND status = 'completed';
    SELECT COALESCE(sum(amount),0), count(*) INTO f_off, n_off FROM member_sales_transactions WHERE crop_name = v_name;
    SELECT COALESCE(sum(amount),0), count(*) INTO f_inf, n_inf FROM informal_sales WHERE crop_name = v_name;
    IF v_gcm IS NOT NULL THEN
      SELECT COALESCE(sum(round(COALESCE(confirmed_volume_kg, requested_volume_kg, volume_kg) * price_per_kg, 2)),0), count(*)
        INTO f_da, n_da FROM market_linking_programs WHERE id IN (v_prog, v_prog2) AND status = 'completed';
    ELSE
      f_da := 0; n_da := 0;
    END IF;
    RESET ROLE;
    v_who := CASE WHEN i = 1 THEN 'Manager' ELSE 'Farmer' END;
    v_rep := v_rep || pg_temp.chk(f_mkt = 53.14 AND n_mkt = 3, '5.' || i || 'a ' || v_who || ' sees Marketplace: 3 completed orders = 53.14', f_mkt || ' in ' || n_mkt);
    v_rep := v_rep || pg_temp.chk(f_off = 188.13 AND n_off = 1, '5.' || i || 'b ' || v_who || ' sees Offer to Cooperative: 1 sale = 188.13 (the declined offer is not a sale)', f_off || ' in ' || n_off);
    v_rep := v_rep || pg_temp.chk(f_inf = 225.74 AND n_inf = 2, '5.' || i || 'c ' || v_who || ' sees Informal Sale: 2 sales = 125.75 + 99.99 = 225.74', f_inf || ' in ' || n_inf);
    IF v_gcm IS NOT NULL THEN
      v_rep := v_rep || pg_temp.chk(f_da = 156.98 AND n_da = 1, '5.' || i || 'd ' || v_who || ' sees DA-AMAD: 1 completed sale = 156.98 (the unfinished 1.00 submission is not a sale)', f_da || ' in ' || n_da);
    END IF;
  END LOOP;

  v_expected := CASE WHEN v_gcm IS NOT NULL THEN 623.99 ELSE 467.01 END;
  v_rep := v_rep || pg_temp.chk(f_mkt + f_off + f_inf + f_da = v_expected,
    '5.3 the four channels add up to the report total', (f_mkt + f_off + f_inf + f_da) || ' (expected ' || v_expected || ')');

  v_fail := (length(v_rep) - length(replace(v_rep, E'\nFAIL ', ''))) / 6;
  RAISE EXCEPTION E'SELLING CHANNELS TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_rep, v_fail;
END
$test$;
