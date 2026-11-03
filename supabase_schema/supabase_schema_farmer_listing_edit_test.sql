-- ============================================================
-- SAGANA — Farmer edits a listing: end-to-end scenario test
--
-- Runs the REAL update_my_listing() as a real Farmer, with a Manager approving and
-- a Buyer ordering, and checks the stock after every step:
--   1. edit while Pending Approval (quantity, price, description)
--   2. Manager approves, Buyer orders 1.25
--   3. edit while Approved: more quantity, then a new price, then less quantity
--      -> the batch, the listing's remaining quantity and the existing order stay right
--   4. refusals: not above what is ordered, more than the batch has, price 0,
--      3 decimals, empty description, someone else's listing
--   5. withdraw is still refused once Approved; the unit never changes
--   6. a Sold Out listing can no longer be edited
--
-- It changes nothing: it ends by raising an error on purpose, which rolls
-- everything back, and the error text IS the report (PASS / FAIL / SKIP lines).
--
-- Run supabase_schema_farmer_listing_edit.sql first, then this whole file.
--
-- NOTE: steps 3-6 edit an APPROVED listing directly. That is the behaviour of
-- supabase_schema_farmer_listing_edit.sql alone. Once
-- supabase_schema_listing_edit_approval.sql has been applied those edits become
-- requests, so use supabase_schema_listing_edit_approval_test.sql instead.
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
  v_fail    INT;
  F UUID; F2 UUID; M UUID; B UUID;
  v_mtype   TEXT;
  v_unit    TEXT;
  v_name    CONSTANT TEXT := 'Zz Listing Edit Test Crop';
  v_cm UUID; v_fc UUID; v_h UUID; v_batch UUID; v_listing UUID; v_o1 UUID; v_o2 UUID;
  bt        inventory_batches%ROWTYPE;
  l         marketplace_listings%ROWTYPE;
  o         orders%ROWTYPE;
  v_msg     TEXT;
BEGIN
  SELECT user_id INTO F FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND NOT COALESCE(pending_acknowledgement, false) ORDER BY user_id LIMIT 1;
  SELECT user_id INTO F2 FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND NOT COALESCE(pending_acknowledgement, false) AND user_id <> F ORDER BY user_id LIMIT 1;
  SELECT user_id INTO M FROM user_roles WHERE role = 'admin' AND status = 'active' LIMIT 1;
  SELECT user_id INTO B FROM user_roles WHERE role = 'buyer' AND status = 'active' LIMIT 1;
  SELECT code INTO v_mtype FROM market_types WHERE buyer_visible AND is_active ORDER BY sort_order LIMIT 1;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM units WHERE is_active AND lower(name) = 'sack') THEN 'sack' ELSE 'kg' END INTO v_unit;

  IF F IS NULL OR M IS NULL OR B IS NULL OR v_mtype IS NULL THEN
    RAISE EXCEPTION E'LISTING EDIT TEST REPORT\nSKIP everything: needs an active farmer, admin and buyer and a buyer-visible market type (found: farmer=%, admin=%, buyer=%, market=%)', F, M, B, v_mtype;
  END IF;
  IF to_regprocedure('public.update_my_listing(uuid,numeric,numeric,text,boolean)') IS NULL THEN
    RAISE EXCEPTION E'LISTING EDIT TEST REPORT\nSKIP everything: run supabase_schema_farmer_listing_edit.sql first.';
  END IF;
  v_rep := v_rep || 'INFO farmer ' || F || ', unit "' || v_unit || E'"\n';

  INSERT INTO crop_master (crop_name, category, crop_type) VALUES (v_name, 'Other', v_mtype) RETURNING id INTO v_cm;
  INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id, photo_url)
    VALUES (F, v_name, 'Other', v_cm, 'https://example.invalid/zz-edit-1.jpg') RETURNING id INTO v_fc;
  INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
    VALUES (F, v_fc, v_name, 10.75, DATE '2096-03-05', v_unit) RETURNING id INTO v_h;
  INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, quantity_kg, available_kg,
                                 status, is_coop_eligible, crop_type)
    VALUES (F, v_h, v_fc, v_name, 10.75, 10.75, 'available', TRUE, v_mtype) RETURNING id INTO v_batch;

  -- ═════ 1. Pending Approval ═════
  PERFORM pg_temp.as_user(F);
  v_listing := create_listing_with_reservation(v_batch, v_name, NULL, 4.25, 12.50, NULL, 'First description');
  PERFORM update_my_listing(v_listing, 5.50, 13.75, '  Second description ', FALSE);
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(l.volume_kg = 5.50 AND l.remaining_kg = 5.50 AND l.price_per_kg = 13.75
      AND l.description = 'Second description' AND l.status = 'pending_review',
    '1.1 pending listing edited: 5.50 @ 13.75, description trimmed, still Pending Approval',
    l.volume_kg || '/' || l.remaining_kg || ' @ ' || l.price_per_kg || ' ' || l.status);
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 5.25 AND bt.reserved_kg = 5.50,
    '1.2 the batch reserved the extra 1.25 (available 6.50 -> 5.25)', bt.available_kg || ' / reserved ' || bt.reserved_kg);
  v_rep := v_rep || pg_temp.chk(l.unit = v_unit, '1.3 the unit is still the harvest unit', l.unit);

  -- ═════ 2. Approve and order ═════
  PERFORM pg_temp.as_user(M);
  PERFORM approve_listing(v_listing);
  RESET ROLE;
  PERFORM pg_temp.as_user(B);
  v_o1 := place_order(v_listing, 1.25);
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_o1;
  v_rep := v_rep || pg_temp.chk(o.quantity_kg = 1.25 AND o.price_per_kg = 13.75 AND o.total_price = 17.19,
    '2.1 order 1.25 x 13.75 = 17.19 (17.1875 rounded)', o.quantity_kg || ' x ' || o.price_per_kg || ' = ' || o.total_price);

  -- ═════ 3. Edit while Approved ═════
  PERFORM pg_temp.as_user(F);
  PERFORM update_my_listing(v_listing, 6.00, 13.75, 'Approved description', FALSE);
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(l.status = 'approved' AND l.volume_kg = 6.00 AND l.remaining_kg = 4.75,
    '3.1 approved listing raised to 6.00: stays Approved, remaining 4.75 (6.00 - 1.25 ordered)', l.status || ' ' || l.volume_kg || '/' || l.remaining_kg);
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 4.75, '3.2 the batch reserved another 0.50 (available 4.75)', bt.available_kg::text);

  PERFORM pg_temp.as_user(F);
  PERFORM update_my_listing(v_listing, 6.00, 20.00, 'Approved description', FALSE);
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_o1;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  v_rep := v_rep || pg_temp.chk(l.price_per_kg = 20.00 AND o.price_per_kg = 13.75 AND o.total_price = 17.19 AND o.quantity_kg = 1.25,
    '3.3 new price 20.00 applies to the listing; the existing order keeps 1.25 @ 13.75 = 17.19',
    'listing ' || l.price_per_kg || ', order ' || o.price_per_kg || ' / ' || o.total_price);

  PERFORM pg_temp.as_user(B);
  v_o2 := place_order(v_listing, 0.50);
  RESET ROLE;
  SELECT * INTO o FROM orders WHERE id = v_o2;
  v_rep := v_rep || pg_temp.chk(o.price_per_kg = 20.00 AND o.total_price = 10.00,
    '3.4 a NEW order uses the new price: 0.50 x 20.00 = 10.00', o.price_per_kg || ' / ' || o.total_price);

  PERFORM pg_temp.as_user(F);
  PERFORM update_my_listing(v_listing, 2.00, 20.00, 'Approved description', FALSE);
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(l.volume_kg = 2.00 AND l.remaining_kg = 0.25,
    '3.5 lowered to 2.00 (1.75 ordered): remaining 0.25', l.volume_kg || '/' || l.remaining_kg);
  v_rep := v_rep || pg_temp.chk(bt.available_kg = 8.75 AND bt.reserved_kg = 2.00,
    '3.6 the batch got the 4.00 back (available 8.75, reserved 2.00)', bt.available_kg || ' / reserved ' || bt.reserved_kg);

  -- ═════ 4. Refusals ═════
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM update_my_listing(v_listing, 1.75, 20, 'x', FALSE); v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%more than the%already ordered%', '4.1 quantity equal to what is ordered is refused', v_msg);

  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM update_my_listing(v_listing, 99, 20, 'x', FALSE); v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%Not enough available quantity%', '4.2 more than the batch has is refused', v_msg);

  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM update_my_listing(v_listing, 3, 0, 'x', FALSE); v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%asking price greater than zero%', '4.3 price 0 is refused', v_msg);

  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM update_my_listing(v_listing, 3.456, 20, 'x', FALSE); v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%at most 2 decimal places for the quantity%', '4.4 a quantity with 3 decimals is refused', v_msg);

  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM update_my_listing(v_listing, 3, 20.125, 'x', FALSE); v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%at most 2 decimal places for the price%', '4.5 a price with 3 decimals is refused', v_msg);

  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM update_my_listing(v_listing, 3, 20, '   ', FALSE); v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%description is required%', '4.6 an empty description is refused', v_msg);

  IF F2 IS NOT NULL THEN
    PERFORM pg_temp.as_user(F2);
    BEGIN PERFORM update_my_listing(v_listing, 3, 20, 'x', FALSE); v_msg := NULL;
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg = 'Listing not found', '4.7 another Farmer cannot edit this listing', v_msg);
  ELSE
    v_rep := v_rep || E'SKIP 4.7 another Farmer cannot edit this listing (only one active farmer exists)\n';
  END IF;

  PERFORM pg_temp.as_user(B);
  BEGIN PERFORM update_my_listing(v_listing, 3, 20, 'x', FALSE); v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE 'Only an active Farmer%', '4.8 a Buyer cannot edit a listing', v_msg);

  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  v_rep := v_rep || pg_temp.chk(l.volume_kg = 2.00 AND l.remaining_kg = 0.25 AND l.price_per_kg = 20.00,
    '4.9 none of the refused edits changed anything', l.volume_kg || '/' || l.remaining_kg || ' @ ' || l.price_per_kg);

  -- ═════ 5. Withdraw is unchanged ═════
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM withdraw_listing(v_listing); v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE 'This listing cannot be withdrawn%', '5.1 an approved listing still cannot be withdrawn', v_msg);

  -- ═════ 6. Sold Out ═════
  PERFORM pg_temp.as_user(B);
  PERFORM place_order(v_listing, 0.25);
  RESET ROLE;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM update_my_listing(v_listing, 5, 20, 'x', FALSE); v_msg := NULL;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%sold out%', '6.1 a Sold Out listing can no longer be edited', v_msg);

  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(bt.available_kg + bt.reserved_kg + bt.sold_kg + bt.adjusted_kg = bt.quantity_kg,
    '6.2 the batch still adds up (available + reserved + sold + adjusted = harvested)',
    bt.available_kg || ' + ' || bt.reserved_kg || ' + ' || bt.sold_kg || ' + ' || bt.adjusted_kg || ' = ' || bt.quantity_kg);

  v_fail := (length(v_rep) - length(replace(v_rep, E'\nFAIL ', ''))) / 6;
  RAISE EXCEPTION E'LISTING EDIT TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_rep, v_fail;
END
$test$;
