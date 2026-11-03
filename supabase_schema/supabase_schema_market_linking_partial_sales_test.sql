-- ============================================================
-- SAGANA — Crop photos, selling rules and Market Linking partial sales:
--          scenario test
--
-- Runs the REAL database functions as a real Farmer, Manager and Buyer from
-- your data:
--   1. Photo rules: without the Farmer's own crop photo a Marketplace listing and
--      an Offer to Cooperative are refused, an Informal Sale is allowed; once the
--      photo is set both work, and the listing shows the Farmer's photo (not a
--      catalog image).
--   2. Crop requests: approving a request (even one that carries a photo) sets no
--      Crop Master image and gives the Farmer's crop no photo.
--   3. Market Linking (Ginger): photo required; submitting reserves stock;
--      Stage 2 Buyer Details (buyer information only: sells nothing, deducts
--      nothing); Stage 3 Complete Sale (needs saved Buyer Details; 80 submitted
--      -> 50 sold leaves 30 reserved; the rest completes it; over-selling and
--      selling a closed request are refused); cancellation starts with the
--      Farmer (reason required), the Manager/Officer approves or declines (a
--      reason is required to decline), nobody can cancel any other way, stock
--      is released only on approval and only the unsold part, sales are kept;
--      a request made before reservations existed still works; amounts are
--      computed to the centavo; Farmer, Manager and Buyer see what they should;
--      nothing becomes Cooperative stock or revenue.
-- It changes nothing: it ends by raising an error on purpose, which rolls
-- everything back; the error text IS the report.
-- Run first: supabase_schema_crop_photos_selling_rules.sql, then
-- supabase_schema_market_linking_partial_sales.sql, then
-- supabase_schema_market_linking_buyer_cancellation.sql, then
-- supabase_schema_market_linking_visibility_and_ack.sql.

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
  v_rep   TEXT := E'\n';
  v_fail  INT;
  F UUID; M UUID; B UUID;
  v_mtype TEXT;
  v_msg   TEXT;
  v_n     INT;
  v_tot   NUMERIC;
  v_qty   NUMERIC;
  -- 1. photo rules
  v_cm UUID; v_fc UUID; v_h UUID; v_batch UUID; v_listing UUID; v_offer UUID;
  bt  inventory_batches%ROWTYPE;
  l   marketplace_listings%ROWTYPE;
  fcr farmer_crops%ROWTYPE;
  -- 2. crop request
  v_rfc UUID; v_req UUID; v_img TEXT; v_rmaster UUID;
  -- 3. market linking
  v_gcm UUID; v_gfc UUID; v_gh UUID; v_gb UUID; v_gname TEXT;
  v_p1 UUID; v_p2 UUID; v_p3 UUID; v_p4 UUID; v_p5 UUID; v_sale UUID;
  gb   inventory_batches%ROWTYPE;
  pr   market_linking_programs%ROWTYPE;
  sl   market_linking_sales%ROWTYPE;
  v_mst_before INT; v_mst_after INT;
BEGIN
  SELECT user_id INTO F FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND NOT COALESCE(pending_acknowledgement, false) LIMIT 1;
  SELECT user_id INTO M FROM user_roles WHERE role = 'admin' AND status = 'active' LIMIT 1;
  SELECT user_id INTO B FROM user_roles WHERE role = 'buyer' AND status = 'active' LIMIT 1;
  SELECT code INTO v_mtype FROM market_types WHERE buyer_visible AND is_active ORDER BY sort_order LIMIT 1;
  IF F IS NULL OR M IS NULL OR B IS NULL OR v_mtype IS NULL THEN
    RAISE EXCEPTION E'PHOTOS + MARKET LINKING TEST REPORT\nSKIP everything: needs an active farmer, admin and buyer and a buyer-visible market type (found: farmer=%, admin=%, buyer=%, market=%)', F, M, B, v_mtype;
  END IF;
  v_rep := v_rep || 'INFO farmer ' || F || ', manager ' || M || ', buyer ' || B || E'\n';

  -- ═════════════ 1. PHOTO RULES ═════════════
  INSERT INTO crop_master (crop_name, category, crop_type) VALUES ('Zz Photo Test Crop', 'Other', v_mtype) RETURNING id INTO v_cm;
  INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id)
    VALUES (F, 'Zz Photo Test Crop', 'Other', v_cm) RETURNING id INTO v_fc;
  INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
    VALUES (F, v_fc, 'Zz Photo Test Crop', 10, DATE '2096-04-02', 'kg') RETURNING id INTO v_h;
  INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, quantity_kg, available_kg,
                                 status, is_coop_eligible, crop_type)
    VALUES (F, v_h, v_fc, 'Zz Photo Test Crop', 10, 10, 'available', TRUE, v_mtype) RETURNING id INTO v_batch;

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM create_listing_with_reservation(v_batch, 'Zz Photo Test Crop', NULL, 2, 10, 'https://example.invalid/catalog.jpg', 'photo test');
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%PHOTO_REQUIRED%' AND bt.available_kg = 10,
    '1.1 a Marketplace listing is refused without the Farmer''s own photo (and takes no stock)', coalesce(v_msg, 'not refused') || ' / available ' || bt.available_kg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM offer_batch_to_cooperative(v_batch, 2, 10.00, NULL);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%PHOTO_REQUIRED%' AND bt.available_kg = 10,
    '1.2 an Offer to Cooperative is refused without the photo (and takes no stock)', coalesce(v_msg, 'not refused') || ' / available ' || bt.available_kg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM record_informal_sale(v_batch, 'Zz Photo Test Crop', 1, 'Walk-in buyer', 10, NULL);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  SELECT * INTO bt FROM inventory_batches WHERE id = v_batch;
  v_rep := v_rep || pg_temp.chk(v_msg IS NULL AND bt.available_kg = 9 AND bt.sold_kg = 1,
    '1.3 an Informal Sale needs no photo: 1 recorded, 9 left', coalesce(v_msg, 'ok') || ' / available ' || bt.available_kg || ', sold ' || bt.sold_kg);

  UPDATE farmer_crops SET photo_url = 'https://example.invalid/own-photo.jpg' WHERE id = v_fc;
  SELECT * INTO fcr FROM farmer_crops WHERE id = v_fc;
  v_rep := v_rep || pg_temp.chk(fcr.photo_captured_at IS NOT NULL,
    '1.4 setting the photo stamps when it was taken', coalesce(fcr.photo_captured_at::text, 'no stamp'));

  PERFORM pg_temp.as_user(F);
  v_listing := create_listing_with_reservation(v_batch, 'Zz Photo Test Crop', NULL, 2, 10, 'https://example.invalid/catalog.jpg', 'photo test');
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_listing;
  v_rep := v_rep || pg_temp.chk(l.photo_url = 'https://example.invalid/own-photo.jpg',
    '1.5 with the photo, the listing is created and shows the Farmer''s photo, not the catalog image', l.photo_url);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN v_offer := offer_batch_to_cooperative(v_batch, 2, 10.00, NULL);
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NULL AND v_offer IS NOT NULL,
    '1.6 with the photo, an Offer to Cooperative is accepted', coalesce(v_msg, 'ok'));

  -- ═════════════ 2. CROP REQUESTS CARRY AND INHERIT NO IMAGE ═════════════
  INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id)
    VALUES (F, 'Zz Request Crop', 'Other', NULL) RETURNING id INTO v_rfc;
  INSERT INTO crop_requests (farmer_id, farmer_crop_id, requested_name, category, crop_type, photo_url, status)
    VALUES (F, v_rfc, 'Zz Request Crop', 'Other', v_mtype, 'https://example.invalid/request-photo.jpg', 'pending')
    RETURNING id INTO v_req;
  PERFORM pg_temp.as_user(M);
  v_rmaster := approve_crop_request(v_req, NULL, NULL);
  RESET ROLE;
  SELECT image_url INTO v_img FROM crop_master WHERE id = v_rmaster;
  SELECT * INTO fcr FROM farmer_crops WHERE id = v_rfc;
  v_rep := v_rep || pg_temp.chk(v_img IS NULL,
    '2.1 approving a request (even one with a photo) sets no Crop Master image', coalesce(v_img, 'none'));
  v_rep := v_rep || pg_temp.chk(fcr.crop_master_id = v_rmaster AND fcr.photo_url IS NULL,
    '2.2 the approved crop is linked to the catalog but has NO photo of its own yet', 'master ' || coalesce(fcr.crop_master_id::text, 'null') || ', photo ' || coalesce(fcr.photo_url, 'none'));

  -- ═════════════ 3. MARKET LINKING (Ginger): request -> buyer details -> complete sale ═════════════
  SELECT id INTO v_gcm FROM crop_master WHERE exclusive_channel = 'da_amad_market_linking' LIMIT 1;
  IF v_gcm IS NULL THEN
    v_rep := v_rep || E'SKIP 3   no crop is reserved for DA-AMAD in crop_master, so the Market Linking steps cannot run\n';
  ELSE
    SELECT crop_name INTO v_gname FROM crop_master WHERE id = v_gcm;
    SELECT id INTO v_gfc FROM farmer_crops WHERE farmer_id = F AND crop_master_id = v_gcm LIMIT 1;
    IF v_gfc IS NULL THEN
      INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id)
        SELECT F, cm.crop_name, cm.category, cm.id FROM crop_master cm WHERE cm.id = v_gcm RETURNING id INTO v_gfc;
    END IF;
    UPDATE farmer_crops SET photo_url = NULL WHERE id = v_gfc;   -- start without a photo
    IF NOT EXISTS (SELECT 1 FROM da_amad_enrollments WHERE farmer_id = F AND status = 'approved') THEN
      IF EXISTS (SELECT 1 FROM da_amad_enrollments WHERE farmer_id = F AND status = 'pending') THEN
        UPDATE da_amad_enrollments SET status = 'approved', reviewed_at = now(), reviewed_by = M
         WHERE farmer_id = F AND status = 'pending';
      ELSE
        INSERT INTO da_amad_enrollments (farmer_id, status, reviewed_at, reviewed_by) VALUES (F, 'approved', now(), M);
      END IF;
    END IF;
    INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
      VALUES (F, v_gfc, v_gname, 100, DATE '2096-04-03', 'kg') RETURNING id INTO v_gh;
    INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, quantity_kg, available_kg, status, is_coop_eligible)
      VALUES (F, v_gh, v_gfc, v_gname, 100, 100, 'available', FALSE) RETURNING id INTO v_gb;

    SELECT count(*) INTO v_mst_before FROM member_sales_transactions WHERE crop_name = v_gname;

    -- 3.1 a photo is required to submit
    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM submit_ginger_for_sale(v_gb, 80); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(v_msg LIKE '%PHOTO_REQUIRED%' AND gb.available_kg = 100,
      '3.1 Market Linking submission is refused without the actual crop photo (and takes no stock)', coalesce(v_msg, 'not refused') || ' / available ' || gb.available_kg);
    UPDATE farmer_crops SET photo_url = 'https://example.invalid/own-ginger.jpg' WHERE id = v_gfc;

    -- 3.2 Stage 1: the Farmer submits 80, which is reserved
    PERFORM pg_temp.as_user(F);
    v_p1 := submit_ginger_for_sale(v_gb, 80);
    RESET ROLE;
    SELECT * INTO pr FROM market_linking_programs WHERE id = v_p1;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(pr.volume_kg = 80 AND pr.reserved_kg = 80 AND pr.sold_kg = 0 AND pr.status = 'submitted' AND gb.available_kg = 20,
      '3.2 submitting 80 of 100 reserves it: request holds 80, batch shows 20 available', 'request ' || pr.volume_kg || '/' || pr.reserved_kg || ', available ' || gb.available_kg);

    -- 3.3 a sale cannot be recorded before the buyer's details are saved
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN PERFORM record_market_linking_sale(v_p1, 10, 45, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%Save the buyer%', '3.3 Complete Sale is refused until Buyer Details are saved', v_msg);

    -- 3.4 Stage 2: Buyer Details are buyer information only
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN PERFORM save_market_linking_buyer_details(v_p1, '  ', '0917 000 0001', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3.4a Buyer Details need the buyer''s name', v_msg);
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN PERFORM save_market_linking_buyer_details(v_p1, 'Buyer A', '', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3.4b ... and a contact number', v_msg);
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN PERFORM save_market_linking_buyer_details(v_p1, 'Buyer A', '0917 000 0001', 'not-an-email'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3.4c ... and a valid e-mail when one is given', v_msg);
    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM save_market_linking_buyer_details(v_p1, 'Farmer self', '0917', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%Unauthorized%', '3.4d only a Manager or Officer can save Buyer Details', v_msg);

    PERFORM pg_temp.as_user(M);
    PERFORM save_market_linking_buyer_details(v_p1, 'Buyer A', '0917 000 0001', 'buyer.a@example.com');
    RESET ROLE;
    SELECT * INTO pr FROM market_linking_programs WHERE id = v_p1;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    SELECT count(*) INTO v_n FROM market_linking_sales WHERE program_id = v_p1;
    v_rep := v_rep || pg_temp.chk(pr.status = 'buyer_found' AND pr.buyer_name = 'Buyer A' AND pr.buyer_contact = '0917 000 0001'
        AND pr.buyer_email = 'buyer.a@example.com',
      '3.5 Buyer Details saved: name, contact and e-mail; the request is Buyer Found', pr.status || ' / ' || coalesce(pr.buyer_name, '-'));

    v_rep := v_rep || pg_temp.chk(pr.sold_kg = 0 AND pr.reserved_kg = 80 AND v_n = 0 AND gb.sold_kg = 0 AND gb.available_kg = 20
        AND pr.price_per_kg IS NULL AND pr.completed_at IS NULL,
      '3.6 saving Buyer Details sold nothing, completed nothing and deducted no stock (still 80 reserved)', 'sold ' || pr.sold_kg || ', reserved ' || pr.reserved_kg || ', sales ' || v_n || ', batch sold ' || gb.sold_kg);

    -- 3.7 Stage 3: Complete Sale — a partial purchase, 50 @ 45.50
    PERFORM pg_temp.as_user(M);
    v_sale := record_market_linking_sale(v_p1, 50, 45.50, 'first truck');
    RESET ROLE;
    SELECT * INTO pr FROM market_linking_programs WHERE id = v_p1;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    SELECT * INTO sl FROM market_linking_sales WHERE id = v_sale;
    v_rep := v_rep || pg_temp.chk(sl.confirmed_volume_kg = 50 AND sl.total_amount = 2275.00 AND sl.farmer_id = F AND sl.recorded_by = M
        AND sl.buyer_name = 'Buyer A' AND sl.buyer_contact = '0917 000 0001',
      '3.7 the sale is recorded for the saved buyer: 50 x 45.50 = 2275.00, owned by the Farmer, recorded by the Manager', sl.confirmed_volume_kg || ' x ' || sl.price_per_kg || ' = ' || sl.total_amount);
    v_rep := v_rep || pg_temp.chk(pr.sold_kg = 50 AND pr.reserved_kg = 30 AND pr.status = 'buyer_found' AND pr.volume_kg - pr.sold_kg = 30,
      '3.8 partial purchase: 50 sold, the unsold 30 stay reserved for the Farmer (not deducted)', 'sold ' || pr.sold_kg || ', reserved ' || pr.reserved_kg || ', ' || pr.status);
    v_rep := v_rep || pg_temp.chk(gb.sold_kg = 50 AND gb.available_kg = 20 AND gb.available_kg + gb.sold_kg + pr.reserved_kg = gb.quantity_kg,
      '3.9 batch: 50 sold, 20 available, 30 still reserved = 100 (nothing deducted twice)', 'sold ' || gb.sold_kg || ', available ' || gb.available_kg);

    -- 3.10 over-selling and bad inputs refused
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN PERFORM record_market_linking_sale(v_p1, 31, 46, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%more than this request has left%' AND gb.sold_kg = 50,
      '3.10 selling more than the 30 left is refused', coalesce(v_msg, 'not refused'));
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN PERFORM record_market_linking_sale(v_p1, 10, 0, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3.11a a sale at no price is refused', v_msg);
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN PERFORM record_market_linking_sale(v_p1, 1.234, 46, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3.11b a third decimal in the quantity is refused', v_msg);

    -- 3.12 Stage 4: the rest is sold -> Completed
    PERFORM pg_temp.as_user(M);
    PERFORM record_market_linking_sale(v_p1, 30, 46.00, NULL);
    RESET ROLE;
    SELECT * INTO pr FROM market_linking_programs WHERE id = v_p1;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(pr.status = 'completed' AND pr.sold_kg = 80 AND pr.reserved_kg = 0 AND pr.completed_at IS NOT NULL,
      '3.12 selling the last 30 completes the request: Completed, sold 80, nothing reserved', pr.status || ', sold ' || pr.sold_kg || ', reserved ' || pr.reserved_kg);
    v_rep := v_rep || pg_temp.chk(gb.sold_kg = 80 AND gb.available_kg = 20 AND gb.status = 'available',
      '3.13 batch: 80 sold, 20 available', 'sold ' || gb.sold_kg || ', available ' || gb.available_kg || ', ' || gb.status);

    -- 3.14 a completed request cannot be sold from, changed, or cancelled
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN PERFORM record_market_linking_sale(v_p1, 1, 46, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%already closed%' AND gb.sold_kg = 80,
      '3.14a a completed request cannot be sold from again', coalesce(v_msg, 'not refused'));
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN PERFORM save_market_linking_buyer_details(v_p1, 'Other', '0917', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%already closed%', '3.14b ... nor its buyer details changed', v_msg);
    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM request_market_linking_cancellation(v_p1, 'changed my mind'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%already closed%', '3.14c ... nor cancelled by the Farmer', v_msg);

    -- 3.15 more than is left on the batch cannot be submitted
    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM submit_ginger_for_sale(v_gb, 40); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%more than this batch has available%', '3.15 submitting more than the batch has left is refused', v_msg);

    -- ───────────── CANCELLATION starts with the Farmer ─────────────
    PERFORM pg_temp.as_user(F);
    v_p2 := submit_ginger_for_sale(v_gb, 20);
    RESET ROLE;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(gb.available_kg = 0 AND gb.status = 'reserved',
      '3.16 submitting the last 20 reserves it all (status reserved, not sold out)', 'available ' || gb.available_kg || ', ' || gb.status);

    -- 3.17 the Manager/Officer cannot cancel on their own
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN UPDATE market_linking_programs SET status = 'cancelled' WHERE id = v_p2; EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    SELECT * INTO pr FROM market_linking_programs WHERE id = v_p2;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%only be cancelled after the farmer asks%' AND pr.status = 'submitted',
      '3.17a a Manager cannot cancel a request by changing its status', coalesce(v_msg, 'not refused'));
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN PERFORM close_market_linking_request(v_p2, 'x'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3.17b ... nor by calling the closing function (not available to the app)', v_msg);
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN PERFORM respond_to_market_linking_cancellation(v_p2, TRUE, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%no cancellation request waiting%', '3.17c ... nor approve a cancellation nobody asked for', v_msg);

    -- 3.18 the Farmer asks: a reason is required; only the owner can ask
    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM request_market_linking_cancellation(v_p2, '   '); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3.18a a cancellation request needs a reason', v_msg);
    v_msg := NULL;
    PERFORM pg_temp.as_user(B);
    BEGIN PERFORM request_market_linking_cancellation(v_p2, 'not mine'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3.18b only the Farmer who owns the request can ask', v_msg);

    PERFORM pg_temp.as_user(F);
    PERFORM request_market_linking_cancellation(v_p2, 'Buyer backed out');
    RESET ROLE;
    SELECT * INTO pr FROM market_linking_programs WHERE id = v_p2;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(pr.cancellation_status = 'requested' AND pr.cancellation_reason = 'Buyer backed out' AND pr.status = 'submitted'
        AND pr.reserved_kg = 20 AND gb.available_kg = 0,
      '3.19 the Farmer''s request shows Cancellation Requested and releases NOTHING yet (20 still reserved)', pr.cancellation_status || ', reserved ' || pr.reserved_kg || ', available ' || gb.available_kg);
    SELECT count(*) INTO v_n FROM notifications WHERE user_id = M AND title = 'Market Linking Cancellation Requested';
    v_rep := v_rep || pg_temp.chk(v_n >= 1, '3.20 the Manager is notified of the request', v_n::text);

    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM request_market_linking_cancellation(v_p2, 'again'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%already asked%', '3.21 asking twice while it is under review is refused', v_msg);
    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM respond_to_market_linking_cancellation(v_p2, TRUE, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%Unauthorized%', '3.22 the Farmer cannot approve their own cancellation', v_msg);

    -- 3.23 declining needs a reason and releases nothing
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN PERFORM respond_to_market_linking_cancellation(v_p2, FALSE, '  '); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%reason for declining%', '3.23a declining a cancellation needs a reason', v_msg);
    PERFORM pg_temp.as_user(M);
    PERFORM respond_to_market_linking_cancellation(v_p2, FALSE, 'Buyer confirmed again');
    RESET ROLE;
    SELECT * INTO pr FROM market_linking_programs WHERE id = v_p2;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(pr.cancellation_status = 'rejected' AND pr.cancellation_review_notes = 'Buyer confirmed again' AND pr.status = 'submitted'
        AND pr.reserved_kg = 20 AND gb.available_kg = 0,
      '3.23b declined with a reason: request stays open, still 20 reserved, nothing released', pr.cancellation_status || ', reserved ' || pr.reserved_kg);
    SELECT count(*) INTO v_n FROM notifications WHERE user_id = F AND title = 'Cancellation Declined' AND body LIKE '%Buyer confirmed again%';
    v_rep := v_rep || pg_temp.chk(v_n >= 1, '3.24 the Farmer is notified, with the reason', v_n::text);

    -- 3.25 the Farmer may ask again; approval releases the reservation
    PERFORM pg_temp.as_user(F);
    PERFORM request_market_linking_cancellation(v_p2, 'Buyer really backed out');
    RESET ROLE;
    PERFORM pg_temp.as_user(M);
    PERFORM respond_to_market_linking_cancellation(v_p2, TRUE, NULL);
    RESET ROLE;
    SELECT * INTO pr FROM market_linking_programs WHERE id = v_p2;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(pr.status = 'cancelled' AND pr.cancellation_status = 'approved' AND pr.reserved_kg = 0
        AND gb.available_kg = 20 AND gb.sold_kg = 80 AND gb.status = 'available',
      '3.25 approved: the request is Cancelled and the 20 reserved kg go back to the Farmer''s stock', pr.status || ', available ' || gb.available_kg || ', sold ' || gb.sold_kg);
    SELECT count(*) INTO v_n FROM notifications WHERE user_id = F AND title = 'Cancellation Approved';
    v_rep := v_rep || pg_temp.chk(v_n >= 1, '3.26 the Farmer is notified of the approval', v_n::text);
    v_msg := NULL;
    PERFORM pg_temp.as_user(M);
    BEGIN PERFORM respond_to_market_linking_cancellation(v_p2, TRUE, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL AND gb.available_kg = 20, '3.27 approving twice releases nothing twice', coalesce(v_msg, 'accepted') || ' / available ' || gb.available_kg);

    -- 3.28 a partial sale, then cancellation of the rest: the sale is preserved
    PERFORM pg_temp.as_user(F);
    v_p3 := submit_ginger_for_sale(v_gb, 10);
    RESET ROLE;
    PERFORM pg_temp.as_user(M);
    PERFORM save_market_linking_buyer_details(v_p3, 'Buyer C', '0917 000 0003', NULL);
    PERFORM record_market_linking_sale(v_p3, 4, 40, NULL);
    RESET ROLE;
    PERFORM pg_temp.as_user(F);
    PERFORM request_market_linking_cancellation(v_p3, 'Buyer wants no more');
    RESET ROLE;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(gb.available_kg = 10 AND gb.sold_kg = 84,
      '3.28a while the cancellation is under review nothing is released (10 available, 84 sold, 6 still reserved)', 'available ' || gb.available_kg || ', sold ' || gb.sold_kg);
    PERFORM pg_temp.as_user(M);
    PERFORM respond_to_market_linking_cancellation(v_p3, TRUE, NULL);
    RESET ROLE;
    SELECT * INTO pr FROM market_linking_programs WHERE id = v_p3;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    SELECT count(*) INTO v_n FROM market_linking_sales WHERE program_id = v_p3;
    v_rep := v_rep || pg_temp.chk(pr.status = 'completed' AND pr.sold_kg = 4 AND pr.reserved_kg = 0 AND v_n = 1
        AND gb.sold_kg = 84 AND gb.available_kg = 16 AND gb.available_kg + gb.sold_kg = gb.quantity_kg,
      '3.28b approved: the 4 kg sale is preserved, only the unsold 6 kg come back (16 available + 84 sold = 100)', pr.status || ', sold ' || pr.sold_kg || ', available ' || gb.available_kg || ', sales ' || v_n);

    -- 3.29 a request made before reservations existed (nothing reserved) still works end to end
    INSERT INTO market_linking_programs (farmer_id, crop_name, season_year, status, inventory_batch_id, volume_kg)
      VALUES (F, v_gname, 2096, 'submitted', v_gb, 10) RETURNING id INTO v_p5;
    PERFORM pg_temp.as_user(M);
    PERFORM save_market_linking_buyer_details(v_p5, 'Buyer D', '0917 000 0004', NULL);
    PERFORM record_market_linking_sale(v_p5, 4.45, 40.10, 'decimal sale');
    RESET ROLE;
    SELECT * INTO pr FROM market_linking_programs WHERE id = v_p5;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    SELECT * INTO sl FROM market_linking_sales WHERE program_id = v_p5;
    v_rep := v_rep || pg_temp.chk(sl.total_amount = 178.45,
      '3.29a 4.45 x 40.10 = 178.45 (178.445 rounded to the centavo)', sl.total_amount::text);
    v_rep := v_rep || pg_temp.chk(pr.reserved_kg = 0 AND pr.sold_kg = 4.45 AND gb.available_kg = 11.55 AND gb.sold_kg = 88.45,
      '3.29b an older, unreserved request takes its sale from the batch once: available 11.55, sold 88.45', 'available ' || gb.available_kg || ', sold ' || gb.sold_kg);
    PERFORM pg_temp.as_user(F);
    PERFORM request_market_linking_cancellation(v_p5, 'Buyer wants no more');
    RESET ROLE;
    PERFORM pg_temp.as_user(M);
    PERFORM respond_to_market_linking_cancellation(v_p5, TRUE, NULL);
    RESET ROLE;
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    v_rep := v_rep || pg_temp.chk(gb.available_kg = 11.55 AND gb.sold_kg = 88.45 AND gb.available_kg + gb.sold_kg = gb.quantity_kg,
      '3.29c cancelling it releases nothing it never reserved (11.55 + 88.45 = 100)', 'available ' || gb.available_kg || ', sold ' || gb.sold_kg);

    -- 3.30 the ledger adds up to the batch, and reports read the same rows
    SELECT COALESCE(sum(confirmed_volume_kg), 0), COALESCE(sum(total_amount), 0), count(*)
      INTO v_qty, v_tot, v_n FROM market_linking_sales WHERE inventory_batch_id = v_gb;
    v_rep := v_rep || pg_temp.chk(v_qty = 88.45 AND v_tot = 3993.45 AND v_n = 4,
      '3.30 the ledger: 4 sales, 88.45 sold = the batch''s Sold, worth 2275.00 + 1380.00 + 160.00 + 178.45 = 3993.45', v_n || ' sales, ' || v_qty || ', ' || v_tot);

    PERFORM pg_temp.as_user(F);
    SELECT count(*), COALESCE(sum(total_amount), 0) INTO v_n, v_tot FROM market_linking_sales WHERE inventory_batch_id = v_gb;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_n = 4 AND v_tot = 3993.45, '3.31 the Farmer sees the same 4 sales in Transaction History', v_n || ' sales, ' || v_tot);
    PERFORM pg_temp.as_user(M);
    SELECT count(*), COALESCE(sum(total_amount), 0) INTO v_n, v_tot FROM market_linking_sales WHERE inventory_batch_id = v_gb;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_n = 4 AND v_tot = 3993.45, '3.32 the Manager sees the same 4 sales in the Sales Report', v_n || ' sales, ' || v_tot);
    PERFORM pg_temp.as_user(B);
    SELECT count(*) INTO v_n FROM market_linking_sales;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_n = 0, '3.33 a Buyer sees none of them', v_n::text);

    -- 3.34 who may record a sale
    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN PERFORM record_market_linking_sale(v_p3, 1, 10, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%Unauthorized%', '3.34 a Farmer cannot record a Market Linking sale', v_msg);
    v_msg := NULL;
    PERFORM pg_temp.as_user(B);
    BEGIN PERFORM record_market_linking_sale(v_p3, 1, 10, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%Unauthorized%', '3.35 a Buyer cannot record a Market Linking sale', v_msg);
    v_msg := NULL;
    PERFORM pg_temp.as_user(F);
    BEGIN INSERT INTO market_linking_sales (program_id, farmer_id, crop_name, buyer_name, confirmed_volume_kg, price_per_kg, total_amount)
          VALUES (v_p3, F, v_gname, 'Direct', 1, 1, 1);
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3.36 sales cannot be written directly (only through the checked function)', v_msg);

    -- 3.37 the Farmer owns the sale: nothing became Cooperative stock or revenue
    SELECT count(*) INTO v_mst_after FROM member_sales_transactions WHERE crop_name = v_gname;
    v_rep := v_rep || pg_temp.chk(v_mst_after = v_mst_before,
      '3.37 no Cooperative sale was created: Market Linking is the Farmer''s own sale', v_mst_before || ' -> ' || v_mst_after);

    -- 3.38 the batch ties out the way every other channel's does
    SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
    SELECT COALESCE(sum(reserved_kg), 0) INTO v_qty FROM market_linking_programs
      WHERE inventory_batch_id = v_gb AND status IN ('submitted', 'buyer_found');
    v_rep := v_rep || pg_temp.chk(gb.available_kg + gb.sold_kg + v_qty = gb.quantity_kg,
      '3.38 available + sold + still-reserved = harvested (no stock created or lost)', gb.available_kg || ' + ' || gb.sold_kg || ' + ' || v_qty || ' = ' || gb.quantity_kg);
  END IF;

  v_fail := (length(v_rep) - length(replace(v_rep, E'\nFAIL ', ''))) / 6;
  RAISE EXCEPTION E'PHOTOS + MARKET LINKING TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_rep, v_fail;
END
$test$;
