-- ============================================================
-- SAGANA — Edit Listing changes three fields only: scenario test
--
--   1. a PENDING listing: quantity, price and description can be edited directly; a
--      photo refresh is refused
--   2. a PUBLISHED listing: an edit submitted with a photo is refused; without one it
--      waits for approval, the live listing is untouched, and on approval ONLY
--      quantity, price and description change (photo, crop, unit, batch, status stay)
--   3. a disapproval keeps the published listing as it is
--
-- It changes nothing: it ends by raising an error on purpose, which rolls
-- everything back, and the error text IS the report (PASS / FAIL / SKIP lines).
--
-- Run supabase_schema_listing_edit_fields.sql first, then this whole file.
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
  v_rep  TEXT := E'\n';
  v_fail INT;
  F UUID; M UUID;
  v_mtype TEXT;
  v_unit  TEXT;
  v_name  CONSTANT TEXT := 'Zz Edit Fields Test Crop';
  v_cm UUID; v_fc UUID; v_h UUID; v_batch UUID; v_pend UUID; v_live UUID; v_req UUID; v_req2 UUID;
  l0  marketplace_listings%ROWTYPE;
  l   marketplace_listings%ROWTYPE;
  rq  listing_edit_requests%ROWTYPE;
  v_msg TEXT;
BEGIN
  SELECT user_id INTO F FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND NOT COALESCE(pending_acknowledgement, false) ORDER BY user_id LIMIT 1;
  SELECT user_id INTO M FROM user_roles WHERE role = 'admin' AND status = 'active' ORDER BY user_id LIMIT 1;
  SELECT code INTO v_mtype FROM market_types WHERE buyer_visible AND is_active ORDER BY sort_order LIMIT 1;
  SELECT CASE WHEN EXISTS (SELECT 1 FROM units WHERE is_active AND lower(name) = 'sack') THEN 'sack' ELSE 'kg' END INTO v_unit;

  IF F IS NULL OR M IS NULL OR v_mtype IS NULL THEN
    RAISE EXCEPTION E'LISTING EDIT FIELDS TEST REPORT\nSKIP everything: needs an active farmer, an admin and a buyer-visible market type (found: farmer=%, admin=%, market=%)', F, M, v_mtype;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'request_listing_edit'
                 AND pg_get_functiondef(oid) LIKE '%cannot be changed in an edit%') THEN
    RAISE EXCEPTION E'LISTING EDIT FIELDS TEST REPORT\nSKIP everything: run supabase_schema_listing_edit_fields.sql first.';
  END IF;

  INSERT INTO crop_master (crop_name, category, crop_type) VALUES (v_name, 'Other', v_mtype) RETURNING id INTO v_cm;
  INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id, photo_url)
    VALUES (F, v_name, 'Other', v_cm, 'https://example.invalid/zz-fields-1.jpg') RETURNING id INTO v_fc;
  INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
    VALUES (F, v_fc, v_name, 12.00, DATE '2096-03-09', v_unit) RETURNING id INTO v_h;
  INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, quantity_kg, available_kg,
                                 status, is_coop_eligible, crop_type)
    VALUES (F, v_h, v_fc, v_name, 12.00, 12.00, 'available', TRUE, v_mtype) RETURNING id INTO v_batch;

  PERFORM pg_temp.as_user(F);
  v_pend := create_listing_with_reservation(v_batch, v_name, NULL, 3.00, 10.00, NULL, 'Pending description');
  v_live := create_listing_with_reservation(v_batch, v_name, NULL, 4.00, 12.50, NULL, 'Live description');
  RESET ROLE;
  PERFORM pg_temp.as_user(M);
  PERFORM approve_listing(v_live);
  RESET ROLE;

  -- ═════ 1. Pending Approval listing: edited directly ═════
  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM update_my_listing(v_pend, 3.50, 11.25, 'Pending, edited', TRUE); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%cannot be changed in an edit%', '1.1 a photo refresh is refused', v_msg);

  PERFORM pg_temp.as_user(F);
  PERFORM update_my_listing(v_pend, 3.50, 11.25, 'Pending, edited', FALSE);
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_pend;
  v_rep := v_rep || pg_temp.chk(l.volume_kg = 3.50 AND l.price_per_kg = 11.25 AND l.description = 'Pending, edited' AND l.status = 'pending_review',
    '1.2 quantity, price and description are edited directly and it stays Pending Approval',
    l.volume_kg || ' @ ' || l.price_per_kg || ' ' || l.status);

  -- ═════ 2. Published listing: submitted for approval ═════
  SELECT * INTO l0 FROM marketplace_listings WHERE id = v_live;

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM request_listing_edit(v_live, 5.00, 14.00, 'Live, edited', 'https://example.invalid/x/listing_photos/' || F::text || '/new.jpg'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE '%cannot be changed in an edit%', '2.1 an edit that carries a photo is refused (even the Farmer''s own upload)', v_msg);

  PERFORM pg_temp.as_user(F);
  v_req := request_listing_edit(v_live, 5.00, 14.00, 'Live, edited');
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_live;
  SELECT * INTO rq FROM listing_edit_requests WHERE id = v_req;
  v_rep := v_rep || pg_temp.chk(rq.status = 'pending' AND rq.proposed_photo_url IS NULL
      AND l.volume_kg = l0.volume_kg AND l.price_per_kg = l0.price_per_kg AND l.description = l0.description AND l.status = 'approved',
    '2.2 the edit waits for approval; the live listing is unchanged', rq.status || ' / live ' || l.volume_kg || ' @ ' || l.price_per_kg);

  PERFORM pg_temp.as_user(M);
  PERFORM approve_listing_edit(v_req);
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_live;
  v_rep := v_rep || pg_temp.chk(l.volume_kg = 5.00 AND l.price_per_kg = 14.00 AND l.description = 'Live, edited',
    '2.3 on approval, quantity, price and description are applied', l.volume_kg || ' @ ' || l.price_per_kg || ' / ' || l.description);
  v_rep := v_rep || pg_temp.chk(l.photo_url IS NOT DISTINCT FROM l0.photo_url AND l.crop_name = l0.crop_name
      AND l.unit = l0.unit AND l.inventory_batch_id IS NOT DISTINCT FROM l0.inventory_batch_id AND l.status = 'approved',
    '2.4 the photo, crop, unit, batch and status did not change', COALESCE(l.photo_url, 'no photo') || ' / ' || l.unit || ' / ' || l.status);

  -- ═════ 3. Disapproval keeps the published listing ═════
  PERFORM pg_temp.as_user(F);
  v_req2 := request_listing_edit(v_live, 6.00, 30.00, 'Too ambitious');
  RESET ROLE;
  PERFORM pg_temp.as_user(M);
  PERFORM reject_listing_edit(v_req2, 'The price is too far above the market price.');
  RESET ROLE;
  SELECT * INTO l FROM marketplace_listings WHERE id = v_live;
  SELECT * INTO rq FROM listing_edit_requests WHERE id = v_req2;
  v_rep := v_rep || pg_temp.chk(rq.status = 'rejected' AND l.volume_kg = 5.00 AND l.price_per_kg = 14.00 AND l.status = 'approved',
    '3.1 a disapproved edit leaves the published listing as it was', rq.status || ' / live ' || l.volume_kg || ' @ ' || l.price_per_kg);

  v_fail := (length(v_rep) - length(replace(v_rep, E'\nFAIL ', ''))) / 6;
  RAISE EXCEPTION E'LISTING EDIT FIELDS TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_rep, v_fail;
END
$test$;
