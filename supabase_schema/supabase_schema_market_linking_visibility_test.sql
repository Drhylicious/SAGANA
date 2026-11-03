-- ============================================================
-- SAGANA — Market Linking buyer visibility + enrollment acknowledgement: test
--
-- As a real Farmer, a second Farmer, and a Manager from your data:
--   * the Farmer sees the buyer the Manager saves, on their own request only;
--     another Farmer sees nothing of it;
--   * editing the buyer while the request is active changes nothing but the
--     buyer (status, quantity, price, stock untouched) and the Farmer is told;
--   * the address is gone (the old 5-argument call no longer exists);
--   * every completed sale keeps the buyer it was recorded for, even after the
--     buyer is edited, and the buyer stays on the completed request;
--   * the enrollment congratulations is acknowledged once, by its own Farmer.
-- It changes nothing: it ends by raising an error on purpose, which rolls
-- everything back; the error text IS the report.
-- Run first: supabase_schema_market_linking_visibility_and_ack.sql.
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
  F UUID; F2 UUID; M UUID;
  v_gcm UUID; v_gfc UUID; v_gh UUID; v_gb UUID; v_gname TEXT; v_p UUID; v_enr UUID;
  v_msg TEXT; v_n INT;
  pr  market_linking_programs%ROWTYPE;
  pr0 market_linking_programs%ROWTYPE;
  gb  inventory_batches%ROWTYPE;
  gb0 inventory_batches%ROWTYPE;
  sl  market_linking_sales%ROWTYPE;
  v_ack TIMESTAMPTZ;
BEGIN
  SELECT user_id INTO F FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND NOT COALESCE(pending_acknowledgement, false) ORDER BY user_id LIMIT 1;
  SELECT user_id INTO F2 FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND user_id <> F ORDER BY user_id LIMIT 1;
  SELECT user_id INTO M FROM user_roles WHERE role = 'admin' AND status = 'active' LIMIT 1;
  SELECT id INTO v_gcm FROM crop_master WHERE exclusive_channel = 'da_amad_market_linking' LIMIT 1;
  IF F IS NULL OR M IS NULL OR v_gcm IS NULL THEN
    RAISE EXCEPTION E'VISIBILITY TEST REPORT\nSKIP everything: needs an active farmer, an admin and a crop reserved for DA-AMAD (found: farmer=%, admin=%, crop=%)', F, M, v_gcm;
  END IF;
  v_rep := v_rep || 'INFO farmer ' || F || ', second farmer ' || coalesce(F2::text, 'none') || ', manager ' || M || E'\n';

  SELECT crop_name INTO v_gname FROM crop_master WHERE id = v_gcm;
  SELECT id INTO v_gfc FROM farmer_crops WHERE farmer_id = F AND crop_master_id = v_gcm LIMIT 1;
  IF v_gfc IS NULL THEN
    INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id)
      SELECT F, cm.crop_name, cm.category, cm.id FROM crop_master cm WHERE cm.id = v_gcm RETURNING id INTO v_gfc;
  END IF;
  UPDATE farmer_crops SET photo_url = COALESCE(NULLIF(photo_url, ''), 'https://example.invalid/zz-vis-ginger.jpg') WHERE id = v_gfc;
  IF NOT EXISTS (SELECT 1 FROM da_amad_enrollments WHERE farmer_id = F AND status = 'approved') THEN
    DELETE FROM da_amad_enrollments WHERE farmer_id = F AND status = 'pending';
    INSERT INTO da_amad_enrollments (farmer_id, status, reviewed_at, reviewed_by) VALUES (F, 'approved', now(), M);
  END IF;
  INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
    VALUES (F, v_gfc, v_gname, 50, DATE '2096-05-01', 'kg') RETURNING id INTO v_gh;
  INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, quantity_kg, available_kg, status, is_coop_eligible)
    VALUES (F, v_gh, v_gfc, v_gname, 50, 50, 'available', FALSE) RETURNING id INTO v_gb;

  PERFORM pg_temp.as_user(F);
  v_p := submit_ginger_for_sale(v_gb, 20);
  RESET ROLE;

  -- 1. Before the Manager saves a buyer, the Farmer sees the request with no buyer
  PERFORM pg_temp.as_user(F);
  SELECT * INTO pr FROM market_linking_programs WHERE id = v_p;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(pr.id IS NOT NULL AND pr.buyer_name IS NULL AND pr.status = 'submitted',
    '1 the Farmer sees their own request, with no buyer yet (Awaiting Buyer Details)', coalesce(pr.buyer_name, 'no buyer') || ' / ' || coalesce(pr.status, '-'));

  -- 2. The Manager saves the buyer: the Farmer sees the same details
  PERFORM pg_temp.as_user(M);
  PERFORM save_market_linking_buyer_details(v_p, 'Buyer A', '0917 111 1111', 'a@example.com');
  RESET ROLE;
  PERFORM pg_temp.as_user(F);
  SELECT * INTO pr FROM market_linking_programs WHERE id = v_p;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(pr.buyer_name = 'Buyer A' AND pr.buyer_contact = '0917 111 1111' AND pr.buyer_email = 'a@example.com' AND pr.status = 'buyer_found',
    '2 the Farmer sees the saved Buyer Details: name, contact and e-mail', coalesce(pr.buyer_name, '-') || ' / ' || coalesce(pr.buyer_contact, '-') || ' / ' || coalesce(pr.buyer_email, '-'));
  SELECT count(*) INTO v_n FROM notifications WHERE user_id = F AND title = 'A Buyer Was Found' AND body LIKE '%Buyer A%';
  v_rep := v_rep || pg_temp.chk(v_n >= 1, '2b the Farmer is told a buyer was found', v_n::text);

  -- 3. Another Farmer sees nothing of it
  IF F2 IS NULL THEN
    v_rep := v_rep || E'SKIP 3   no second active farmer to test privacy against\n';
  ELSE
    PERFORM pg_temp.as_user(F2);
    SELECT count(*) INTO v_n FROM market_linking_programs WHERE id = v_p;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_n = 0, '3 another Farmer cannot see this request or its buyer', v_n::text);
  END IF;

  -- 4. Editing the buyer changes only the buyer
  SELECT * INTO pr0 FROM market_linking_programs WHERE id = v_p;
  SELECT * INTO gb0 FROM inventory_batches WHERE id = v_gb;
  PERFORM pg_temp.as_user(M);
  PERFORM save_market_linking_buyer_details(v_p, 'Buyer A', '0917 222 2222', 'a2@example.com');
  RESET ROLE;
  SELECT * INTO pr FROM market_linking_programs WHERE id = v_p;
  SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
  v_rep := v_rep || pg_temp.chk(pr.buyer_contact = '0917 222 2222' AND pr.buyer_email = 'a2@example.com'
      AND pr.status = pr0.status AND pr.volume_kg = pr0.volume_kg AND pr.reserved_kg = pr0.reserved_kg
      AND pr.sold_kg = pr0.sold_kg AND pr.price_per_kg IS NOT DISTINCT FROM pr0.price_per_kg
      AND gb.available_kg = gb0.available_kg AND gb.sold_kg = gb0.sold_kg,
    '4 editing the buyer changes only the buyer: status, quantity, price and stock are untouched', pr.status || ', reserved ' || pr.reserved_kg || ', available ' || gb.available_kg);
  PERFORM pg_temp.as_user(F);
  SELECT * INTO pr FROM market_linking_programs WHERE id = v_p;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(pr.buyer_contact = '0917 222 2222', '4b the Farmer sees the correction without doing anything', pr.buyer_contact);
  SELECT count(*) INTO v_n FROM notifications WHERE user_id = F AND title = 'Buyer Details Updated';
  v_rep := v_rep || pg_temp.chk(v_n >= 1, '4c the Farmer is told the details were updated', v_n::text);

  -- 5. No address any more
  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM save_market_linking_buyer_details(v_p, 'Buyer A', '0917', 'a@example.com', 'Baguio City'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '5 Buyer Details no longer accept an address', v_msg);

  -- 6. Each sale keeps the buyer it was recorded for
  PERFORM pg_temp.as_user(M);
  PERFORM record_market_linking_sale(v_p, 5, 40, NULL);
  PERFORM save_market_linking_buyer_details(v_p, 'Buyer B', '0917 333 3333', 'b@example.com');
  PERFORM record_market_linking_sale(v_p, 5, 41, 'second buyer');
  RESET ROLE;
  SELECT * INTO sl FROM market_linking_sales WHERE program_id = v_p AND price_per_kg = 40;
  v_rep := v_rep || pg_temp.chk(sl.buyer_name = 'Buyer A' AND sl.buyer_contact = '0917 222 2222' AND sl.buyer_email = 'a2@example.com',
    '6a the first sale still names Buyer A (contact and e-mail as they were), after the buyer was changed', sl.buyer_name || ' / ' || coalesce(sl.buyer_contact, '-') || ' / ' || coalesce(sl.buyer_email, '-'));
  SELECT * INTO sl FROM market_linking_sales WHERE program_id = v_p AND price_per_kg = 41;
  v_rep := v_rep || pg_temp.chk(sl.buyer_name = 'Buyer B' AND sl.buyer_email = 'b@example.com' AND sl.total_amount = 205.00,
    '6b the second sale names Buyer B: 5 x 41 = 205.00', sl.buyer_name || ' / ' || coalesce(sl.buyer_email, '-') || ' / ' || sl.total_amount);

  -- 7. Completed: the buyer stays, and the Farmer still sees it
  PERFORM pg_temp.as_user(M);
  PERFORM record_market_linking_sale(v_p, 10, 42, NULL);
  RESET ROLE;
  PERFORM pg_temp.as_user(F);
  SELECT * INTO pr FROM market_linking_programs WHERE id = v_p;
  SELECT count(*) INTO v_n FROM market_linking_sales WHERE program_id = v_p AND buyer_name IS NOT NULL AND buyer_contact IS NOT NULL;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(pr.status = 'completed' AND pr.buyer_name = 'Buyer B' AND v_n = 3,
    '7 completed: the request keeps its buyer and all 3 sales keep theirs; the Farmer sees them all', pr.status || ', ' || coalesce(pr.buyer_name, '-') || ', sales ' || v_n);
  v_msg := NULL;
  PERFORM pg_temp.as_user(M);
  BEGIN PERFORM save_market_linking_buyer_details(v_p, 'Changed', '0917', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%already closed%', '7b a completed request''s buyer can no longer be changed', v_msg);

  -- 8. The Farmer cannot write buyer details
  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM save_market_linking_buyer_details(v_p, 'Self', '0917', NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%Unauthorized%', '8 Buyer Details are read-only for a Farmer', v_msg);

  -- 9. Enrollment congratulations: acknowledged once, by its own Farmer
  SELECT id INTO v_enr FROM da_amad_enrollments WHERE farmer_id = F AND status = 'approved' ORDER BY reviewed_at DESC NULLS LAST LIMIT 1;
  UPDATE da_amad_enrollments SET acknowledged_at = NULL WHERE id = v_enr;
  IF F2 IS NOT NULL THEN
    PERFORM pg_temp.as_user(F2);
    PERFORM acknowledge_da_amad_enrollment(v_enr);
    RESET ROLE;
    SELECT acknowledged_at INTO v_ack FROM da_amad_enrollments WHERE id = v_enr;
    v_rep := v_rep || pg_temp.chk(v_ack IS NULL, '9a another Farmer cannot acknowledge this enrollment', coalesce(v_ack::text, 'still unacknowledged'));
  END IF;
  PERFORM pg_temp.as_user(F);
  PERFORM acknowledge_da_amad_enrollment(v_enr);
  RESET ROLE;
  SELECT acknowledged_at INTO v_ack FROM da_amad_enrollments WHERE id = v_enr;
  v_rep := v_rep || pg_temp.chk(v_ack IS NOT NULL, '9b tapping Continue records the acknowledgement', coalesce(v_ack::text, 'not set'));
  UPDATE da_amad_enrollments SET acknowledged_at = acknowledged_at - interval '1 day' WHERE id = v_enr;
  SELECT acknowledged_at INTO v_ack FROM da_amad_enrollments WHERE id = v_enr;
  PERFORM pg_temp.as_user(F);
  PERFORM acknowledge_da_amad_enrollment(v_enr);
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk((SELECT acknowledged_at FROM da_amad_enrollments WHERE id = v_enr) = v_ack,
    '9c acknowledging again changes nothing (it stays remembered)', v_ack::text);

  v_fail := (length(v_rep) - length(replace(v_rep, E'\nFAIL ', ''))) / 6;
  RAISE EXCEPTION E'VISIBILITY TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_rep, v_fail;
END
$test$;
