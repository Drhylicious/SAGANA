-- ============================================================
-- SAGANA — Farmer "+ Unit": scenario test
--
-- As a real Farmer, a Buyer and a Manager from your data: a Farmer can add a
-- unit and then use it for a harvest; a duplicate (any case) and a badly
-- formed name are refused; a Farmer cannot rename or delete a unit; a Buyer
-- cannot add one; the 10-a-day limit holds. It changes nothing: it ends by
-- raising an error on purpose, which rolls everything back; the error text IS
-- the report. Run supabase_schema_farmer_add_unit.sql first.
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
  F UUID; B UUID;
  v_id   UUID;
  v_row  units%ROWTYPE;
  v_msg  TEXT;
  v_n    INT;
  v_cm UUID; v_fc UUID; v_h harvest_records%ROWTYPE;
  v_mtype TEXT;
BEGIN
  SELECT user_id INTO F FROM user_roles WHERE role = 'farmer' AND status = 'active' LIMIT 1;
  SELECT user_id INTO B FROM user_roles WHERE role = 'buyer' AND status = 'active' LIMIT 1;
  IF F IS NULL THEN
    RAISE EXCEPTION E'FARMER +UNIT TEST REPORT\nSKIP everything: no active farmer account';
  END IF;

  -- 1. A Farmer adds a unit
  PERFORM pg_temp.as_user(F);
  INSERT INTO units (name) VALUES ('zz bunch') RETURNING id INTO v_id;
  RESET ROLE;
  SELECT * INTO v_row FROM units WHERE id = v_id;
  v_rep := v_rep || pg_temp.chk(v_row.name = 'zz bunch' AND v_row.is_active AND v_row.created_by = F,
    '1 a Farmer can add a unit; it is active and stamped with the Farmer', v_row.name || ' / active=' || v_row.is_active);

  -- 2. It is visible to every signed-in account at once (no refresh needed)
  IF B IS NOT NULL THEN
    PERFORM pg_temp.as_user(B);
    SELECT count(*) INTO v_n FROM units WHERE name = 'zz bunch' AND is_active;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_n = 1, '2 the new unit is readable by another account straight away', v_n::text);
  END IF;

  -- 3. Duplicate (any case) and bad names are refused
  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN INSERT INTO units (name) VALUES ('zz bunch'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3a the same name again is refused', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN INSERT INTO units (name) VALUES ('ZZ Bunch'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3b ... in capital letters too', v_msg);

  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  BEGIN INSERT INTO units (name) VALUES ('bad;name'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
  RESET ROLE;
  v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '3c a name with forbidden characters is refused', v_msg);

  -- 4. A Farmer cannot rename, deactivate or delete a unit
  PERFORM pg_temp.as_user(F);
  UPDATE units SET name = 'zz renamed' WHERE id = v_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  DELETE FROM units WHERE id = v_id;
  RESET ROLE;
  SELECT * INTO v_row FROM units WHERE id = v_id;
  v_rep := v_rep || pg_temp.chk(v_n = 0 AND v_row.name = 'zz bunch',
    '4 a Farmer cannot rename or delete a unit (even their own)', 'rows renamed ' || v_n || ', name now ' || coalesce(v_row.name, '(deleted)'));

  -- 5. A Buyer cannot add one
  IF B IS NOT NULL THEN
    v_msg := NULL;
    PERFORM pg_temp.as_user(B);
    BEGIN INSERT INTO units (name) VALUES ('zz buyer unit'); EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; END;
    RESET ROLE;
    v_rep := v_rep || pg_temp.chk(v_msg IS NOT NULL, '5 a Buyer cannot add a unit', v_msg);
  END IF;

  -- 6. The new unit works for a harvest (the harvest trigger accepts only listed units)
  SELECT code INTO v_mtype FROM market_types WHERE is_active ORDER BY sort_order LIMIT 1;
  INSERT INTO crop_master (crop_name, category, crop_type) VALUES ('Zz Unit Test Crop', 'Other', v_mtype) RETURNING id INTO v_cm;
  INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id) VALUES (F, 'Zz Unit Test Crop', 'Other', v_cm) RETURNING id INTO v_fc;
  INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
    VALUES (F, v_fc, 'Zz Unit Test Crop', 0.45, DATE '2096-04-01', 'zz bunch') RETURNING * INTO v_h;
  v_rep := v_rep || pg_temp.chk(v_h.unit = 'zz bunch' AND v_h.quantity_kg = 0.45,
    '6 a harvest of 0.45 can be recorded in the Farmer''s new unit', v_h.quantity_kg || ' ' || v_h.unit);

  -- 7. At most 10 additions in 24 hours
  v_msg := NULL;
  PERFORM pg_temp.as_user(F);
  FOR i IN 1..12 LOOP
    BEGIN
      INSERT INTO units (name) VALUES ('zz u' || i);
    EXCEPTION WHEN OTHERS THEN v_msg := SQLERRM; EXIT;
    END;
  END LOOP;
  RESET ROLE;
  SELECT count(*) INTO v_n FROM units WHERE created_by = F AND created_at > now() - interval '24 hours';
  v_rep := v_rep || pg_temp.chk(v_n = 10 AND v_msg ILIKE '%most units%',
    '7 a Farmer can add at most 10 units a day', v_n || ' added; ' || coalesce(v_msg, 'no limit hit'));

  v_fail := (length(v_rep) - length(replace(v_rep, E'\nFAIL ', ''))) / 6;
  RAISE EXCEPTION E'FARMER +UNIT TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_rep, v_fail;
END
$test$;
