-- ============================================================
-- supabase_schema_registration_17_remove_test_account.sql
--
-- Removes ONE test account: the farmer "testing test"
--   user_id 2597cfa0-9889-421b-9dbe-86be2b5bc59d
-- and nothing else.
--
-- Run each BLOCK on its own (select it, press Run), in order. THIS DELETES A
-- LOGIN AND CANNOT BE UNDONE. Read Block 1 before running Block 2.
--
-- WHY NOT THE APP'S DELETE BUTTON
--   The Members screen can only delete a Disapproved farmer applicant. If this
--   account is Disapproved (script 16, Block 1 shows its status) use that button
--   instead: it is the same check. Otherwise use Block 2 below.
--
-- WHAT BLOCK 2 REFUSES TO DO (the whole block is cancelled, nothing is deleted)
--   * the id is not found, or the stored name is not exactly "testing test"
--   * the account has any role other than a single "farmer" role
--   * the account has ANY harvest, order, loan, capital or contribution record
-- So it cannot remove a real member, a Manager/Officer, a buyer, or an account
-- with money or harvests on it.
-- ============================================================


-- ─── BLOCK 1 — WHAT WOULD BE REMOVED (read-only). Run first. ───────────────
-- Lists every table that points at this login and has rows for it:
--   CASCADE   = the row is deleted together with the account
--   SET NULL  = the row is kept, only its link to this account is cleared
--   NO ACTION / RESTRICT = this row would BLOCK the delete (Block 2 then fails
--                          with an error and removes nothing)
-- An empty result means nothing else is attached to the account.

CREATE OR REPLACE FUNCTION pg_temp.impact(p_id uuid)
RETURNS TABLE(table_name text, column_name text, on_delete text, rows_for_user bigint)
LANGUAGE plpgsql AS $$
DECLARE
  r record;
  n bigint;
BEGIN
  FOR r IN
    SELECT c.conrelid::regclass::text AS tbl, a.attname::text AS col, c.confdeltype AS dt
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'f'
      AND c.confrelid = 'auth.users'::regclass
      AND cardinality(c.conkey) = 1
  LOOP
    EXECUTE format('SELECT count(*) FROM %s WHERE %I = $1', r.tbl, r.col) INTO n USING p_id;
    table_name := r.tbl;
    column_name := r.col;
    on_delete := CASE r.dt
      WHEN 'c' THEN 'CASCADE (row is deleted)'
      WHEN 'n' THEN 'SET NULL (row kept)'
      WHEN 'a' THEN 'NO ACTION (blocks the delete)'
      WHEN 'r' THEN 'RESTRICT (blocks the delete)'
      ELSE 'SET DEFAULT (row kept)' END;
    rows_for_user := n;
    RETURN NEXT;
  END LOOP;
END
$$;

SELECT * FROM pg_temp.impact('2597cfa0-9889-421b-9dbe-86be2b5bc59d')
WHERE rows_for_user > 0
ORDER BY on_delete, table_name;


-- ─── BLOCK 2 — DELETE the test account (guarded). ──────────────────────────
-- Success shows "Success. No rows returned". Any refusal is an error that starts
-- with "NOT DELETED" and means nothing was removed.

DO $$
DECLARE
  v_id      constant uuid := '2597cfa0-9889-421b-9dbe-86be2b5bc59d';
  v_name    text;
  v_roles   text;
  v_records bigint;
BEGIN
  SELECT full_name INTO v_name FROM public.user_information WHERE user_id = v_id;
  IF v_name IS NULL THEN
    RAISE EXCEPTION 'NOT DELETED: no account with this id (already removed?)';
  END IF;
  IF v_name <> 'testing test' THEN
    RAISE EXCEPTION 'NOT DELETED: the account is named "%", not "testing test"', v_name;
  END IF;

  SELECT string_agg(role, ',' ORDER BY role) INTO v_roles
  FROM public.user_roles WHERE user_id = v_id;
  IF v_roles IS DISTINCT FROM 'farmer' THEN
    RAISE EXCEPTION 'NOT DELETED: expected a single farmer role, found "%"', coalesce(v_roles, 'none');
  END IF;

  SELECT (SELECT count(*) FROM public.harvest_records           WHERE farmer_id = v_id)
       + (SELECT count(*) FROM public.orders                    WHERE farmer_id = v_id OR buyer_id = v_id)
       + (SELECT count(*) FROM public.farmer_loans              WHERE farmer_id = v_id)
       + (SELECT count(*) FROM public.member_capital_shares     WHERE farmer_id = v_id)
       + (SELECT count(*) FROM public.member_contributions      WHERE farmer_id = v_id)
       + (SELECT count(*) FROM public.capital_contribution_events WHERE farmer_id = v_id)
    INTO v_records;
  IF v_records > 0 THEN
    RAISE EXCEPTION 'NOT DELETED: the account has % harvest/order/loan/capital record(s)', v_records;
  END IF;

  DELETE FROM auth.users WHERE id = v_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT DELETED: the login row was not found in auth.users';
  END IF;
END
$$;


-- ─── BLOCK 3 — CONFIRM it is gone and nothing else was touched. ────────────
-- Expect: the first four rows 0 and PASS. The last row is INFO: the number of
-- accounts left, which should be exactly one fewer than before.

SELECT 'auth login'       AS check_name,
       (SELECT count(*) FROM auth.users             WHERE id      = '2597cfa0-9889-421b-9dbe-86be2b5bc59d')::text AS remaining,
       CASE WHEN (SELECT count(*) FROM auth.users             WHERE id      = '2597cfa0-9889-421b-9dbe-86be2b5bc59d') = 0 THEN 'PASS' ELSE 'STILL THERE' END AS result
UNION ALL
SELECT 'user_information',
       (SELECT count(*) FROM public.user_information WHERE user_id = '2597cfa0-9889-421b-9dbe-86be2b5bc59d')::text,
       CASE WHEN (SELECT count(*) FROM public.user_information WHERE user_id = '2597cfa0-9889-421b-9dbe-86be2b5bc59d') = 0 THEN 'PASS' ELSE 'STILL THERE' END
UNION ALL
SELECT 'user_roles',
       (SELECT count(*) FROM public.user_roles       WHERE user_id = '2597cfa0-9889-421b-9dbe-86be2b5bc59d')::text,
       CASE WHEN (SELECT count(*) FROM public.user_roles       WHERE user_id = '2597cfa0-9889-421b-9dbe-86be2b5bc59d') = 0 THEN 'PASS' ELSE 'STILL THERE' END
UNION ALL
SELECT 'farmer_profiles',
       (SELECT count(*) FROM public.farmer_profiles  WHERE user_id = '2597cfa0-9889-421b-9dbe-86be2b5bc59d')::text,
       CASE WHEN (SELECT count(*) FROM public.farmer_profiles  WHERE user_id = '2597cfa0-9889-421b-9dbe-86be2b5bc59d') = 0 THEN 'PASS' ELSE 'STILL THERE' END
UNION ALL
SELECT 'accounts left (user_information)',
       (SELECT count(*) FROM public.user_information)::text,
       'INFO';
