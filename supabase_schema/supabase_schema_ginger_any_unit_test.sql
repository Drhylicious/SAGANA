-- ============================================================
-- SAGANA — Ginger / DA-AMAD in the harvest's own unit: scenario test
--
--   1. a Ginger harvest can be recorded in a non-kg unit (it used to be refused);
--      an unknown unit is still refused
--   2. the batch, the Market Linking request and the recorded sale all carry that
--      unit, and the sale amount is quantity x price in that unit
--   3. the batch figures still add up
--   4. Ginger is still refused by Marketplace / Offer / Informal Sale
--
-- It changes nothing: it ends by raising an error on purpose, which rolls
-- everything back, and the error text IS the report (PASS / FAIL / SKIP lines).
--
-- Run supabase_schema_ginger_any_unit.sql first, then this whole file.
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
  v_unit TEXT;
  v_gcm UUID; v_gfc UUID; v_gh UUID; v_gb UUID; v_gname TEXT;
  v_prog UUID; v_prog2 UUID;
  gb   inventory_batches%ROWTYPE;
  prog market_linking_programs%ROWTYPE;
  sale market_linking_sales%ROWTYPE;
  v_msg TEXT;
BEGIN
  SELECT user_id INTO F FROM user_roles WHERE role = 'farmer' AND status = 'active'
    AND NOT COALESCE(pending_acknowledgement, false) LIMIT 1;
  SELECT user_id INTO M FROM user_roles WHERE role = 'admin' AND status = 'active' LIMIT 1;
  SELECT name INTO v_unit FROM units WHERE is_active AND lower(name) <> 'kg' ORDER BY name LIMIT 1;
  SELECT id INTO v_gcm FROM crop_master WHERE exclusive_channel = 'da_amad_market_linking' LIMIT 1;

  IF F IS NULL OR M IS NULL THEN
    RAISE EXCEPTION E'GINGER UNIT TEST REPORT\nSKIP everything: needs an active farmer and an active admin (found: farmer=%, admin=%)', F, M;
  END IF;
  IF v_gcm IS NULL THEN
    RAISE EXCEPTION E'GINGER UNIT TEST REPORT\nSKIP everything: no crop is reserved for DA-AMAD in crop_master.';
  END IF;
  IF v_unit IS NULL THEN
    RAISE EXCEPTION E'GINGER UNIT TEST REPORT\nSKIP everything: the units list has no active unit other than kg to test with.';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'market_linking_sales' AND column_name = 'unit') THEN
    RAISE EXCEPTION E'GINGER UNIT TEST REPORT\nSKIP everything: run supabase_schema_ginger_any_unit.sql first.';
  END IF;
  v_rep := v_rep || 'INFO farmer ' || F || ', test unit "' || v_unit || E'"\n';

  SELECT crop_name INTO v_gname FROM crop_master WHERE id = v_gcm;
  SELECT id INTO v_gfc FROM farmer_crops WHERE farmer_id = F AND crop_master_id = v_gcm LIMIT 1;
  IF v_gfc IS NULL THEN
    INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id)
      SELECT F, cm.crop_name, cm.category, cm.id FROM crop_master cm WHERE cm.id = v_gcm RETURNING id INTO v_gfc;
  END IF;
  UPDATE farmer_crops SET photo_url = COALESCE(NULLIF(photo_url, ''), 'https://example.invalid/zz-ginger-unit.jpg')
   WHERE id = v_gfc;
  IF NOT EXISTS (SELECT 1 FROM da_amad_enrollments WHERE farmer_id = F AND status = 'approved') THEN
    IF EXISTS (SELECT 1 FROM da_amad_enrollments WHERE farmer_id = F AND status = 'pending') THEN
      UPDATE da_amad_enrollments SET status = 'approved', reviewed_at = now(), reviewed_by = M
       WHERE farmer_id = F AND status = 'pending';
    ELSE
      INSERT INTO da_amad_enrollments (farmer_id, status, reviewed_at, reviewed_by) VALUES (F, 'approved', now(), M);
    END IF;
  END IF;

  -- ═════ 1. Harvest in a non-kg unit ═════
  v_msg := NULL;
  BEGIN
    INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
      VALUES (F, v_gfc, v_gname, 1, DATE '2096-03-06', 'zz-not-a-unit');
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  v_rep := v_rep || pg_temp.chk(v_msg LIKE 'Unknown unit%', '1.1 an unknown unit is still refused', v_msg);

  v_msg := NULL;
  BEGIN
    INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
      VALUES (F, v_gfc, v_gname, 8.50, DATE '2096-03-07', v_unit) RETURNING id INTO v_gh;
  EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  v_rep := v_rep || pg_temp.chk(v_gh IS NOT NULL AND v_msg IS NULL,
    '1.2 a Ginger harvest of 8.50 ' || v_unit || ' is accepted (no kg-only rule)', COALESCE(v_msg, 'recorded'));
  IF v_gh IS NULL THEN
    RAISE EXCEPTION E'GINGER UNIT TEST REPORT (nothing was saved)\n%\nFAILED CHECKS: stopped early', v_rep;
  END IF;

  INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, quantity_kg, available_kg, status, is_coop_eligible)
    VALUES (F, v_gh, v_gfc, v_gname, 8.50, 8.50, 'available', FALSE) RETURNING id INTO v_gb;
  SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
  v_rep := v_rep || pg_temp.chk(gb.unit = v_unit AND gb.exclusive_channel = 'da_amad_market_linking',
    '1.3 the batch carries the harvest unit and the exclusive channel', gb.unit || ' / ' || COALESCE(gb.exclusive_channel, 'none'));

  -- ═════ 2. The request and the sale carry the same unit ═════
  PERFORM pg_temp.as_user(F);
  v_prog  := submit_ginger_for_sale(v_gb, 3.45);
  v_prog2 := submit_ginger_for_sale(v_gb, 1.00);
  RESET ROLE;
  SELECT * INTO prog FROM market_linking_programs WHERE id = v_prog;
  v_rep := v_rep || pg_temp.chk(prog.unit = v_unit AND prog.volume_kg = 3.45,
    '2.1 the Market Linking request is 3.45 ' || v_unit, prog.volume_kg || ' ' || prog.unit);

  PERFORM pg_temp.as_user(M);
  UPDATE market_linking_programs
     SET status = 'buyer_found', buyer_name = 'Unit Test Buyer', price_per_kg = 45.50,
         requested_volume_kg = 3.45, buyer_found_at = now()
   WHERE id = v_prog;
  PERFORM complete_market_linking(v_prog, v_gb, 3.45, 'Unit Test Buyer', NULL, 45.50, NULL);
  RESET ROLE;
  SELECT * INTO prog FROM market_linking_programs WHERE id = v_prog;
  SELECT * INTO sale FROM market_linking_sales WHERE program_id = v_prog ORDER BY completed_at DESC LIMIT 1;
  v_rep := v_rep || pg_temp.chk(sale.id IS NOT NULL AND sale.unit = v_unit AND sale.confirmed_volume_kg = 3.45
      AND sale.price_per_kg = 45.50 AND sale.total_amount = 156.98,
    '2.2 the recorded sale is 3.45 ' || v_unit || ' x 45.50 = 156.98', COALESCE(sale.confirmed_volume_kg || ' ' || sale.unit || ' = ' || sale.total_amount, 'no sale row'));
  v_rep := v_rep || pg_temp.chk(prog.status = 'completed' AND prog.unit = v_unit,
    '2.3 the request is completed and keeps its unit', prog.status || ' / ' || prog.unit);

  -- The Farmer's notice names the unit, once supabase_schema_notification_units.sql ran.
  IF to_regprocedure('public.record_market_linking_sale(uuid,numeric,numeric,text)') IS NOT NULL
     AND pg_get_functiondef('public.record_market_linking_sale(uuid,numeric,numeric,text)'::regprocedure) LIKE '%v_prog.unit%' THEN
    -- Two notices share the title "Ginger Sale Completed": a generic one from a
    -- trigger ("... has been completed.") and the sale notice that carries the
    -- quantity ("3.45 bag of Ginger was sold to ..."). Read the second.
    SELECT body INTO v_msg FROM notifications
     WHERE user_id = F AND title IN ('Ginger Sale Completed', 'Ginger Sale Recorded')
       AND body LIKE '%was sold to%'
     LIMIT 1;
    v_rep := v_rep || pg_temp.chk(v_msg LIKE '%3.45 ' || v_unit || ' of%' AND v_msg NOT LIKE '% kg %',
      '2.4 the Farmer''s sale notice names the unit', v_msg);
  ELSE
    v_rep := v_rep || E'SKIP 2.4 the Farmer''s sale notice names the unit (run supabase_schema_notification_units.sql to test it)
';
  END IF;

  -- ═════ 3. The batch still adds up ═════
  SELECT * INTO gb FROM inventory_batches WHERE id = v_gb;
  v_rep := v_rep || pg_temp.chk(gb.sold_kg = 3.45 AND gb.available_kg = 4.05
      AND gb.available_kg + gb.reserved_kg + gb.sold_kg + gb.adjusted_kg = gb.quantity_kg,
    '3.1 batch: sold 3.45, available 4.05, 1.00 still reserved; the figures add up to 8.50',
    'available ' || gb.available_kg || ' + reserved ' || gb.reserved_kg || ' + sold ' || gb.sold_kg || ' + adjusted ' || gb.adjusted_kg || ' = ' || gb.quantity_kg || ' ' || gb.unit);

  -- ═════ 4. Ginger stays on its own channel ═════
  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM create_listing_with_reservation(v_gb, v_gname, NULL, 1.25, 12.50, NULL, 'x'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg ILIKE '%can only be sold through%', '4.1 Ginger still cannot be listed on the Marketplace', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM offer_batch_to_cooperative(v_gb, 1.25, 12.50, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '4.2 Ginger still cannot be offered to the Cooperative', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN PERFORM record_informal_sale(v_gb, v_gname, 1.25, 'X', 10, NULL); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '4.3 Ginger still cannot be sold informally', v_msg);

  v_fail := (length(v_rep) - length(replace(v_rep, E'\nFAIL ', ''))) / 6;
  RAISE EXCEPTION E'GINGER UNIT TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_rep, v_fail;
END
$test$;
