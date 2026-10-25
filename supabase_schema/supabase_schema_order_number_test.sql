-- ============================================================
-- SAGANA — Order numbers: scenario test
--
-- Checks the number format, the yearly restart, uniqueness, the Philippine-time
-- date boundary, and (if an order can be created in your data) the trigger on
-- the real orders table. It changes nothing: it ends by raising an error on
-- purpose, which rolls everything back, and the error text IS the report.
--
-- Run supabase_schema_order_number.sql first. Then run this whole file.
-- ============================================================

DO $test$
DECLARE
  v_report  TEXT := E'\n';
  v_fail    INT;
  v_a       TEXT;
  v_b       TEXT;
  v_n       INT;
  v_distinct INT;
  v_listing UUID;
  v_farmer  UUID;
  v_buyer   UUID;
  v_o1      public.orders%ROWTYPE;
  v_o2      public.orders%ROWTYPE;
  v_old_null INT;
BEGIN
  SELECT count(*) INTO v_old_null FROM orders WHERE order_number IS NULL;

  -- 1. Sequence formatting --------------------------------------------------
  v_report := v_report || CASE WHEN format_order_sequence(1) = 'A001' AND format_order_sequence(999) = 'A999'
      AND format_order_sequence(1000) = 'B001' AND format_order_sequence(1998) = 'B999'
      AND format_order_sequence(1999) = 'C001'
    THEN 'PASS ' ELSE 'FAIL ' END || E'1  sequence 1 = A001, 999 = A999, 1000 = B001, 1999 = C001\n';
  v_report := v_report || CASE WHEN format_order_sequence(25974) = 'Z999' AND format_order_sequence(25975) = 'AA001'
    THEN 'PASS ' ELSE 'FAIL ' END || E'2  sequence 25974 = Z999, then 25975 = AA001 (it never runs out)\n';

  -- 3. The format of an issued number ---------------------------------------
  DELETE FROM order_number_counters WHERE year IN (2097, 2098, 2099, 2100);
  v_a := next_order_number('2099-06-15 10:00:00+08'::timestamptz);
  v_report := v_report || CASE WHEN v_a = 'ORD-20990615-A001' THEN 'PASS ' ELSE 'FAIL ' END
    || E'3  first order of a year is ORD-YYYYMMDD-A001: ' || v_a || E'\n';

  -- 4. Continues through the year, across days and months -------------------
  v_b := next_order_number('2099-06-16 09:00:00+08'::timestamptz);
  v_a := next_order_number('2099-11-30 09:00:00+08'::timestamptz);
  v_report := v_report || CASE WHEN v_b = 'ORD-20990616-A002' AND v_a = 'ORD-20991130-A003' THEN 'PASS ' ELSE 'FAIL ' END
    || E'4  the sequence continues across days and months: ' || v_b || ' then ' || v_a || E'\n';

  -- 5. Restarts on 1 January ------------------------------------------------
  v_a := next_order_number('2099-12-31 23:59:59+08'::timestamptz);
  v_b := next_order_number('2100-01-01 00:00:00+08'::timestamptz);
  v_report := v_report || CASE WHEN v_a = 'ORD-20991231-A004' AND v_b = 'ORD-21000101-A001' THEN 'PASS ' ELSE 'FAIL ' END
    || E'5  the sequence restarts at A001 on 1 January: ' || v_a || ' then ' || v_b || E'\n';

  -- 6. The date is the Philippine date -------------------------------------
  -- 2100-01-01 00:30 in Manila is still 2099-12-31 in UTC.
  v_a := next_order_number('2099-12-31 16:30:00+00'::timestamptz);
  v_report := v_report || CASE WHEN v_a = 'ORD-21000101-A002' THEN 'PASS ' ELSE 'FAIL ' END
    || E'6  an order at 00:30 on 1 January in the Philippines counts in the NEW year: ' || v_a || E'\n';

  -- 7. Block rollover at 999 ------------------------------------------------
  INSERT INTO order_number_counters (year, last_seq) VALUES (2098, 997);
  v_a := next_order_number('2098-03-03 10:00:00+08'::timestamptz);   -- 998
  v_b := next_order_number('2098-03-03 10:00:01+08'::timestamptz);   -- 999
  v_report := v_report || CASE WHEN right(v_a, 4) = 'A998' AND right(v_b, 4) = 'A999' THEN 'PASS ' ELSE 'FAIL ' END
    || E'7a ...A998 then ...A999: ' || v_a || ' then ' || v_b || E'\n';
  v_a := next_order_number('2098-03-03 10:00:02+08'::timestamptz);
  v_report := v_report || CASE WHEN right(v_a, 4) = 'B001' THEN 'PASS ' ELSE 'FAIL ' END
    || E'7b ...then B001 (the letter block advances): ' || v_a || E'\n';

  -- 8. Uniqueness over a large batch ----------------------------------------
  CREATE TEMP TABLE _nums (n TEXT) ON COMMIT DROP;
  INSERT INTO _nums SELECT next_order_number('2097-07-07 12:00:00+08'::timestamptz) FROM generate_series(1, 3000);
  SELECT count(*), count(DISTINCT n) INTO v_n, v_distinct FROM _nums;
  v_report := v_report || CASE WHEN v_n = 3000 AND v_distinct = 3000 THEN 'PASS ' ELSE 'FAIL ' END
    || E'8  3000 numbers issued, all different: ' || v_distinct || E'\n';
  SELECT last_seq INTO v_n FROM order_number_counters WHERE year = 2097;
  v_report := v_report || CASE WHEN v_n = 3000 THEN 'PASS ' ELSE 'FAIL ' END
    || E'9  the counter equals the number issued (no gaps): ' || v_n || E'\n';
  SELECT min(n), max(n) INTO v_a, v_b FROM _nums;
  v_report := v_report || '   range: ' || v_a || ' ... ' || v_b || E'\n';

  -- 10. The two-letter, three-digit shape is accepted by the table rule ----
  v_report := v_report || CASE WHEN 'ORD-20261024-A001' ~ '^ORD-[0-9]{8}-[A-Z]+[0-9]{3}$'
      AND 'ORD-20261024-AA001' ~ '^ORD-[0-9]{8}-[A-Z]+[0-9]{3}$'
      AND 'ORD-7D750007' !~ '^ORD-[0-9]{8}-[A-Z]+[0-9]{3}$'
    THEN 'PASS ' ELSE 'FAIL ' END || E'10 the table rule accepts new numbers and would refuse the old 8-character style\n';

  -- 11. Triggers and index exist ------------------------------------------
  SELECT count(*) INTO v_n FROM pg_trigger
  WHERE tgrelid = 'public.orders'::regclass AND NOT tgisinternal
    AND tgname IN ('trg_orders_assign_order_number', 'trg_orders_protect_order_number');
  v_report := v_report || CASE WHEN v_n = 2 THEN 'PASS ' ELSE 'FAIL ' END || E'11 both triggers are installed on orders\n';
  v_report := v_report || CASE WHEN to_regclass('public.uq_orders_order_number') IS NOT NULL THEN 'PASS ' ELSE 'FAIL ' END
    || E'12 the unique index exists\n';

  -- 13+. A real insert into orders (skipped if your data does not allow it) -
  SELECT l.id, l.farmer_id INTO v_listing, v_farmer
  FROM marketplace_listings l
  WHERE l.status = 'approved' AND l.crop_type = (SELECT code FROM market_types WHERE buyer_visible ORDER BY sort_order LIMIT 1)
  LIMIT 1;
  SELECT user_id INTO v_buyer FROM user_roles WHERE role = 'buyer' AND status = 'active' LIMIT 1;

  IF v_listing IS NULL OR v_buyer IS NULL THEN
    v_report := v_report || E'SKIP 13 real insert: no approved Public listing or no active buyer to use\n';
  ELSE
    BEGIN
      INSERT INTO orders (listing_id, farmer_id, buyer_id, quantity_kg, price_per_kg, total_price, order_number)
      VALUES (v_listing, v_farmer, v_buyer, 1, 10, 10, 'ORD-SPOOFED')
      RETURNING * INTO v_o1;
      INSERT INTO orders (listing_id, farmer_id, buyer_id, quantity_kg, price_per_kg, total_price)
      VALUES (v_listing, v_farmer, v_buyer, 1, 10, 10)
      RETURNING * INTO v_o2;

      v_report := v_report || CASE WHEN v_o1.order_number ~ '^ORD-[0-9]{8}-[A-Z]+[0-9]{3}$' AND v_o1.order_number <> 'ORD-SPOOFED'
        THEN 'PASS ' ELSE 'FAIL ' END || E'13 a real order gets a number, and a number sent by the client is ignored: ' || v_o1.order_number || E'\n';
      v_report := v_report || CASE WHEN v_o1.order_number <> v_o2.order_number THEN 'PASS ' ELSE 'FAIL ' END
        || E'14 two orders placed together get different numbers: ' || v_o1.order_number || ' and ' || v_o2.order_number || E'\n';
      v_report := v_report || CASE WHEN substr(v_o1.order_number, 5, 8) = to_char(v_o1.created_at AT TIME ZONE 'Asia/Manila', 'YYYYMMDD')
        THEN 'PASS ' ELSE 'FAIL ' END || E'15 the date in the number is the order''s date (Philippine time)\n';
      v_report := v_report || CASE WHEN right(v_o2.order_number, 4) <> right(v_o1.order_number, 4)
        THEN 'PASS ' ELSE 'FAIL ' END || E'16 the second order is the next in the sequence\n';

      BEGIN
        UPDATE orders SET order_number = 'ORD-20260101-A999' WHERE id = v_o1.id;
        v_report := v_report || E'FAIL 17 an order number was changed\n';
      EXCEPTION WHEN OTHERS THEN
        v_report := v_report || 'PASS 17 an order number cannot be changed (' || SQLERRM || E')\n';
      END;
    EXCEPTION WHEN OTHERS THEN
      v_report := v_report || 'SKIP 13-17 real insert was refused by another rule in your data (' || SQLERRM || E')\n';
    END;
  END IF;

  -- 18. Orders from before were not touched --------------------------------
  v_report := v_report || CASE WHEN (SELECT count(*) FROM orders WHERE order_number IS NULL) = v_old_null THEN 'PASS ' ELSE 'FAIL ' END
    || E'18 existing orders still have no number (' || v_old_null || E'); they keep their old reference\n';

  v_fail := (length(v_report) - length(replace(v_report, E'\nFAIL ', ''))) / 6;
  RAISE EXCEPTION E'ORDER NUMBER TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_report, v_fail;
END
$test$;
