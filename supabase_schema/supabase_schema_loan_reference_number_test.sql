-- ============================================================
-- SAGANA — Loan reference numbers: scenario test
--
-- Checks the number format, the yearly restart, uniqueness, the Philippine-time
-- date boundary, and (if a loan can be created in your data) the trigger on the
-- real farmer_loans table. It changes nothing: it ends by raising an error on
-- purpose, which rolls everything back, and the error text IS the report.
--
-- Run supabase_schema_loan_reference_number.sql first. Then run this whole file.
-- ============================================================

DO $test$
DECLARE
  v_report   TEXT := E'\n';
  v_fail     INT;
  v_a        TEXT;
  v_b        TEXT;
  v_n        INT;
  v_distinct INT;
  v_farmer   UUID;
  v_l1       public.farmer_loans%ROWTYPE;
  v_l2       public.farmer_loans%ROWTYPE;
  v_old      INT;
  v_def      TEXT;
BEGIN
  SELECT count(*) INTO v_old FROM farmer_loans WHERE reference_no NOT LIKE 'LRN-%';

  -- 1. The shared sequence layout (same function Orders use) -----------------
  v_report := v_report || CASE WHEN format_order_sequence(1) = 'A001' AND format_order_sequence(999) = 'A999'
      AND format_order_sequence(1000) = 'B001' AND format_order_sequence(25975) = 'AA001'
    THEN 'PASS ' ELSE 'FAIL ' END || E'1  sequence 1 = A001, 999 = A999, 1000 = B001, 25975 = AA001\n';

  -- 2. The format of an issued number ---------------------------------------
  DELETE FROM loan_reference_counters WHERE year IN (2097, 2098, 2099, 2100);
  v_a := next_loan_reference('2099-06-15 10:00:00+08'::timestamptz);
  v_report := v_report || CASE WHEN v_a = 'LRN-20990615-A001' THEN 'PASS ' ELSE 'FAIL ' END
    || E'2  first loan of a year is LRN-YYYYMMDD-A001: ' || v_a || E'\n';

  -- 3. Continues through the year, across days and months -------------------
  v_b := next_loan_reference('2099-06-16 09:00:00+08'::timestamptz);
  v_a := next_loan_reference('2099-11-30 09:00:00+08'::timestamptz);
  v_report := v_report || CASE WHEN v_b = 'LRN-20990616-A002' AND v_a = 'LRN-20991130-A003' THEN 'PASS ' ELSE 'FAIL ' END
    || E'3  the sequence continues across days and months: ' || v_b || ' then ' || v_a || E'\n';

  -- 4. Restarts on 1 January ------------------------------------------------
  v_a := next_loan_reference('2099-12-31 23:59:59+08'::timestamptz);
  v_b := next_loan_reference('2100-01-01 00:00:00+08'::timestamptz);
  v_report := v_report || CASE WHEN v_a = 'LRN-20991231-A004' AND v_b = 'LRN-21000101-A001' THEN 'PASS ' ELSE 'FAIL ' END
    || E'4  the sequence restarts at A001 on 1 January: ' || v_a || ' then ' || v_b || E'\n';

  -- 5. The date is the Philippine date -------------------------------------
  v_a := next_loan_reference('2099-12-31 16:30:00+00'::timestamptz);
  v_report := v_report || CASE WHEN v_a = 'LRN-21000101-A002' THEN 'PASS ' ELSE 'FAIL ' END
    || E'5  a loan at 00:30 on 1 January in the Philippines counts in the NEW year: ' || v_a || E'\n';

  -- 6. Block rollover at 999 ------------------------------------------------
  INSERT INTO loan_reference_counters (year, last_seq) VALUES (2098, 997);
  v_a := next_loan_reference('2098-03-03 10:00:00+08'::timestamptz);   -- 998
  v_b := next_loan_reference('2098-03-03 10:00:01+08'::timestamptz);   -- 999
  v_report := v_report || CASE WHEN right(v_a, 4) = 'A998' AND right(v_b, 4) = 'A999' THEN 'PASS ' ELSE 'FAIL ' END
    || E'6a ...A998 then ...A999: ' || v_a || ' then ' || v_b || E'\n';
  v_a := next_loan_reference('2098-03-03 10:00:02+08'::timestamptz);
  v_report := v_report || CASE WHEN right(v_a, 4) = 'B001' THEN 'PASS ' ELSE 'FAIL ' END
    || E'6b ...then B001 (the letter block advances): ' || v_a || E'\n';

  -- 7. Uniqueness over a large batch ----------------------------------------
  CREATE TEMP TABLE _loan_refs (n TEXT) ON COMMIT DROP;
  INSERT INTO _loan_refs SELECT next_loan_reference('2097-07-07 12:00:00+08'::timestamptz) FROM generate_series(1, 3000);
  SELECT count(*), count(DISTINCT n) INTO v_n, v_distinct FROM _loan_refs;
  v_report := v_report || CASE WHEN v_n = 3000 AND v_distinct = 3000 THEN 'PASS ' ELSE 'FAIL ' END
    || E'7  3000 numbers issued, all different: ' || v_distinct || E'\n';
  SELECT last_seq INTO v_n FROM loan_reference_counters WHERE year = 2097;
  v_report := v_report || CASE WHEN v_n = 3000 THEN 'PASS ' ELSE 'FAIL ' END
    || E'8  the counter equals the number issued (no gaps): ' || v_n || E'\n';

  -- 9. The shape ------------------------------------------------------------
  v_report := v_report || CASE WHEN 'LRN-20261024-A001' ~ '^LRN-[0-9]{8}-[A-Z]+[0-9]{3}$'
      AND 'LRN-20261024-AA001' ~ '^LRN-[0-9]{8}-[A-Z]+[0-9]{3}$'
      AND 'LN-2026-001' !~ '^LRN-[0-9]{8}-[A-Z]+[0-9]{3}$'
    THEN 'PASS ' ELSE 'FAIL ' END || E'9  the new shape matches new numbers and not the old LN-YYYY-### style\n';

  -- 10. Triggers exist ------------------------------------------------------
  SELECT count(*) INTO v_n FROM pg_trigger
  WHERE tgrelid = 'public.farmer_loans'::regclass AND NOT tgisinternal
    AND tgname IN ('trg_farmer_loans_assign_reference', 'trg_farmer_loans_protect_reference');
  v_report := v_report || CASE WHEN v_n = 2 THEN 'PASS ' ELSE 'FAIL ' END || E'10 both triggers are installed on farmer_loans\n';

  -- 11. issue_loan() lets the trigger issue the number ----------------------
  v_def := pg_get_functiondef('public.issue_loan(uuid,jsonb,date,numeric,date,text,uuid,text)'::regprocedure);
  v_report := v_report || CASE WHEN v_def NOT LIKE '%''LN-''%' AND v_def ILIKE '%RETURNING fl.id, fl.reference_no%'
    THEN 'PASS ' ELSE 'FAIL ' END || E'11 issue_loan() no longer builds LN- numbers; it reads the issued one back\n';

  -- 12+. A real insert into farmer_loans (skipped if your data does not allow it)
  SELECT user_id INTO v_farmer FROM user_roles WHERE role = 'farmer' AND status = 'active' LIMIT 1;
  IF v_farmer IS NULL THEN
    v_report := v_report || E'SKIP 12 real insert: no active farmer to use\n';
  ELSE
    BEGIN
      INSERT INTO farmer_loans (farmer_id, reference_no, issued_date, total_value, amount_paid, status)
      VALUES (v_farmer, 'LN-SPOOFED', CURRENT_DATE, 100, 0, 'active')
      RETURNING * INTO v_l1;
      INSERT INTO farmer_loans (farmer_id, reference_no, issued_date, total_value, amount_paid, status)
      VALUES (v_farmer, 'LN-SPOOFED-2', CURRENT_DATE, 100, 0, 'active')
      RETURNING * INTO v_l2;

      v_report := v_report || CASE WHEN v_l1.reference_no ~ '^LRN-[0-9]{8}-[A-Z]+[0-9]{3}$' AND v_l1.reference_no NOT LIKE '%SPOOFED%'
        THEN 'PASS ' ELSE 'FAIL ' END || E'12 a real loan gets a number, and a number sent by the caller is ignored: ' || v_l1.reference_no || E'\n';
      v_report := v_report || CASE WHEN v_l1.reference_no <> v_l2.reference_no THEN 'PASS ' ELSE 'FAIL ' END
        || E'13 two loans created together get different numbers: ' || v_l1.reference_no || ' and ' || v_l2.reference_no || E'\n';
      v_report := v_report || CASE WHEN substr(v_l1.reference_no, 5, 8) = to_char(v_l1.created_at AT TIME ZONE 'Asia/Manila', 'YYYYMMDD')
        THEN 'PASS ' ELSE 'FAIL ' END || E'14 the date in the number is the loan''s creation date (Philippine time)\n';
      v_report := v_report || CASE WHEN right(v_l2.reference_no, 4) <> right(v_l1.reference_no, 4)
        THEN 'PASS ' ELSE 'FAIL ' END || E'15 the second loan is the next in the sequence\n';

      BEGIN
        UPDATE farmer_loans SET reference_no = 'LRN-20260101-A999' WHERE id = v_l1.id;
        v_report := v_report || E'FAIL 16 a loan reference was changed\n';
      EXCEPTION WHEN OTHERS THEN
        v_report := v_report || 'PASS 16 a loan reference cannot be changed (' || SQLERRM || E')\n';
      END;
    EXCEPTION WHEN OTHERS THEN
      v_report := v_report || 'SKIP 12-16 real insert was refused by another rule in your data (' || SQLERRM || E')\n';
    END;
  END IF;

  -- 17. Loans from before were not touched ---------------------------------
  v_report := v_report || CASE WHEN (SELECT count(*) FROM farmer_loans WHERE reference_no NOT LIKE 'LRN-%') = v_old THEN 'PASS ' ELSE 'FAIL ' END
    || E'17 existing loans still carry their old reference (' || v_old || E' of them)\n';

  v_fail := (length(v_report) - length(replace(v_report, E'\nFAIL ', ''))) / 6;
  RAISE EXCEPTION E'LOAN REFERENCE TEST REPORT (nothing was saved)\n% \nFAILED CHECKS: %', v_report, v_fail;
END
$test$;
