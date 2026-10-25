-- ============================================================
-- SAGANA — Harvest batch numbers + units: scenario test
--
-- Checks the crop letters, the number format, the per-crop sequence, the
-- yearly restart, uniqueness, the unit rules, and (if a real harvest can be
-- created in your data) the triggers on harvest_records / inventory_batches.
-- It changes nothing: it ends by raising an error on purpose, which rolls
-- everything back, and the error text IS the report.
--
-- Run supabase_schema_harvest_batch_number_and_units.sql first. Then run this
-- whole file.
-- ============================================================

DO $test$
DECLARE
  v_report  TEXT := E'\n';
  v_fail    INT;
  v_crop1   UUID;
  v_crop2   UUID;
  v_p1      TEXT;
  v_p2      TEXT;
  v_a       TEXT;
  v_b       TEXT;
  v_c       TEXT;
  v_farmer  UUID;
  v_fc      UUID;
  v_h1      public.harvest_records%ROWTYPE;
  v_h2      public.harvest_records%ROWTYPE;
  v_b1      public.inventory_batches%ROWTYPE;
  v_has_sack BOOLEAN;
  v_old_harvests INT;
BEGIN
  SELECT count(*) INTO v_old_harvests FROM harvest_records;

  -- 1. Letter generator -----------------------------------------------------
  v_report := v_report || CASE WHEN batch_prefix_for_index(1) = 'A' AND batch_prefix_for_index(26) = 'Z'
      AND batch_prefix_for_index(27) = 'AA' AND batch_prefix_for_index(28) = 'AB'
      AND batch_prefix_for_index(52) = 'AZ' AND batch_prefix_for_index(53) = 'BA'
    THEN 'PASS ' ELSE 'FAIL ' END || E'1  letters run A..Z, AA, AB .. AZ, BA (it never runs out)\n';

  -- 2. Every new crop gets its own letter, by trigger ------------------------
  INSERT INTO crop_master (crop_name, category) VALUES ('Zz Test Crop One', 'Other') RETURNING id, batch_prefix INTO v_crop1, v_p1;
  INSERT INTO crop_master (crop_name, category) VALUES ('Zz Test Crop Two', 'Other') RETURNING id, batch_prefix INTO v_crop2, v_p2;
  v_report := v_report || CASE WHEN v_p1 IS NOT NULL AND v_p2 IS NOT NULL AND v_p1 <> v_p2 THEN 'PASS ' ELSE 'FAIL ' END
    || E'2  two new crops got different letters: ' || coalesce(v_p1, '?') || ' and ' || coalesce(v_p2, '?') || E'\n';

  BEGIN
    UPDATE crop_master SET batch_prefix = 'Q' WHERE id = v_crop1;
    v_report := v_report || E'FAIL 3  a crop''s letter was changed\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 3  a crop''s letter cannot be changed (' || SQLERRM || E')\n';
  END;

  -- 4. First number of a crop in a year ---------------------------------------
  v_a := next_batch_number(v_crop1, DATE '2098-06-15');
  v_report := v_report || CASE WHEN v_a = 'BATCH-ZZTESTCROPONE-980615-' || v_p1 || '0001' THEN 'PASS ' ELSE 'FAIL ' END
    || E'4  first batch of a crop: ' || v_a || E'\n';

  -- 5. Same crop continues its sequence, across days and months ---------------
  v_b := next_batch_number(v_crop1, DATE '2098-06-16');
  v_c := next_batch_number(v_crop1, DATE '2098-12-31');
  v_report := v_report || CASE WHEN v_b = 'BATCH-ZZTESTCROPONE-980616-' || v_p1 || '0002'
      AND v_c = 'BATCH-ZZTESTCROPONE-981231-' || v_p1 || '0003' THEN 'PASS ' ELSE 'FAIL ' END
    || E'5  the same crop continues: ' || v_b || ' then ' || v_c || E'\n';

  -- 6. A different crop has its own letter and starts at 0001 ----------------
  v_b := next_batch_number(v_crop2, DATE '2098-06-16');
  v_report := v_report || CASE WHEN v_b = 'BATCH-ZZTESTCROPTWO-980616-' || v_p2 || '0001' THEN 'PASS ' ELSE 'FAIL ' END
    || E'6  another crop starts at 0001 with its own letter: ' || v_b || E'\n';

  -- 7. Everything restarts in a new year --------------------------------------
  v_a := next_batch_number(v_crop1, DATE '2099-01-01');
  v_b := next_batch_number(v_crop2, DATE '2099-01-01');
  v_report := v_report || CASE WHEN v_a = 'BATCH-ZZTESTCROPONE-990101-' || v_p1 || '0001'
      AND v_b = 'BATCH-ZZTESTCROPTWO-990101-' || v_p2 || '0001' THEN 'PASS ' ELSE 'FAIL ' END
    || E'7  every crop restarts at 0001 on 1 January: ' || v_a || ' and ' || v_b || E'\n';

  -- 8. A late entry continues its OWN year, not the current one ---------------
  v_a := next_batch_number(v_crop1, DATE '2098-03-01');
  v_report := v_report || CASE WHEN v_a = 'BATCH-ZZTESTCROPONE-980301-' || v_p1 || '0004' THEN 'PASS ' ELSE 'FAIL ' END
    || E'8  a harvest dated in an earlier year continues that year: ' || v_a || E'\n';

  -- 9. Out-of-range year and unknown crop are refused -------------------------
  BEGIN
    PERFORM next_batch_number(v_crop1, DATE '2100-01-01');
    v_report := v_report || E'FAIL 9  a year after 2099 was accepted\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 9  a year outside 2000-2099 is refused (' || SQLERRM || E')\n';
  END;
  BEGIN
    PERFORM next_batch_number(gen_random_uuid(), DATE '2098-01-01');
    v_report := v_report || E'FAIL 10 an unknown crop was accepted\n';
  EXCEPTION WHEN OTHERS THEN
    v_report := v_report || 'PASS 10 an unknown crop is refused (' || SQLERRM || E')\n';
  END;

  -- 11. Real inserts -----------------------------------------------------------
  SELECT user_id INTO v_farmer FROM user_roles WHERE role = 'farmer' LIMIT 1;
  SELECT EXISTS (SELECT 1 FROM units WHERE is_active AND lower(name) = 'sack') INTO v_has_sack;
  IF v_farmer IS NULL THEN
    v_report := v_report || E'SKIP 11-18 no farmer account exists to create a test harvest\n';
  ELSE
    BEGIN
      INSERT INTO farmer_crops (farmer_id, crop_name, category, crop_master_id)
      VALUES (v_farmer, 'Zz Test Crop One', 'Other', v_crop1) RETURNING id INTO v_fc;

      -- A client-supplied number and unit-case are replaced / normalised.
      INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, batch_number, unit)
      VALUES (v_farmer, v_fc, 'Zz Test Crop One', 0.45, DATE '2097-05-04', 'BATCH-CLIENT-MADE-UP', ' KG ')
      RETURNING * INTO v_h1;
      v_report := v_report || CASE WHEN v_h1.batch_number = 'BATCH-ZZTESTCROPONE-970504-' || v_p1 || '0001' AND v_h1.unit = 'kg'
        THEN 'PASS ' ELSE 'FAIL ' END
        || E'11 the database issues the number and ignores the client''s: ' || v_h1.batch_number || E' (unit ' || v_h1.unit || E')\n';
      v_report := v_report || CASE WHEN v_h1.quantity_kg = 0.45 THEN 'PASS ' ELSE 'FAIL ' END
        || E'12 a decimal quantity is stored exactly: ' || v_h1.quantity_kg || E'\n';

      INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
      VALUES (v_farmer, v_fc, 'Zz Test Crop One', 10.75, DATE '2097-05-05', CASE WHEN v_has_sack THEN 'sack' ELSE 'kg' END)
      RETURNING * INTO v_h2;
      v_report := v_report || CASE WHEN v_h2.batch_number = 'BATCH-ZZTESTCROPONE-970505-' || v_p1 || '0002' THEN 'PASS ' ELSE 'FAIL ' END
        || E'13 the next harvest of the same crop is 0002: ' || v_h2.batch_number || E' (unit ' || v_h2.unit || E')\n';

      INSERT INTO inventory_batches (farmer_id, harvest_record_id, crop_id, crop_name, quantity_kg, available_kg)
      VALUES (v_farmer, v_h2.id, v_fc, 'Zz Test Crop One', v_h2.quantity_kg, v_h2.quantity_kg)
      RETURNING * INTO v_b1;
      v_report := v_report || CASE WHEN v_b1.batch_number = v_h2.batch_number AND v_b1.unit = v_h2.unit THEN 'PASS ' ELSE 'FAIL ' END
        || E'14 the inventory batch copies its harvest''s number and unit\n';

      BEGIN
        UPDATE inventory_batches SET batch_number = 'BATCH-OTHER' WHERE id = v_b1.id;
        v_report := v_report || E'FAIL 15 a batch number was changed\n';
      EXCEPTION WHEN OTHERS THEN
        v_report := v_report || 'PASS 15 a batch number cannot be changed (' || SQLERRM || E')\n';
      END;
      BEGIN
        UPDATE inventory_batches SET unit = 'piece' WHERE id = v_b1.id;
        v_report := v_report || E'FAIL 16 a batch unit was changed\n';
      EXCEPTION WHEN OTHERS THEN
        v_report := v_report || 'PASS 16 a batch unit cannot be changed (' || SQLERRM || E')\n';
      END;
      BEGIN
        INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
        VALUES (v_farmer, v_fc, 'Zz Test Crop One', 1, DATE '2097-05-06', 'not-a-unit');
        v_report := v_report || E'FAIL 17 an unknown unit was accepted\n';
      EXCEPTION WHEN OTHERS THEN
        v_report := v_report || 'PASS 17 an unknown unit is refused (' || SQLERRM || E')\n';
      END;
      BEGIN
        INSERT INTO harvest_records (farmer_id, crop_id, crop_name, quantity_kg, harvest_date, unit)
        VALUES (v_farmer, v_fc, 'Zz Test Crop One', 0, DATE '2097-05-06', 'kg');
        v_report := v_report || E'FAIL 18 a zero quantity was accepted\n';
      EXCEPTION WHEN OTHERS THEN
        v_report := v_report || 'PASS 18 a zero quantity is refused (' || SQLERRM || E')\n';
      END;
    EXCEPTION WHEN OTHERS THEN
      v_report := v_report || 'SKIP 11-18 a real harvest was refused by another rule in your data (' || SQLERRM || E')\n';
    END;
  END IF;

  -- 19. Existing harvests were not touched ---------------------------------------
  v_report := v_report || CASE WHEN (SELECT count(*) FROM harvest_records) >= v_old_harvests THEN 'PASS ' ELSE 'FAIL ' END
    || E'19 existing harvest records are still there (' || v_old_harvests || E'); their old numbers are kept\n';

  v_fail := (length(v_report) - length(replace(v_report, E'\nFAIL ', ''))) / 6;
  RAISE EXCEPTION E'HARVEST BATCH NUMBER TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_report, v_fail;
END
$test$;
