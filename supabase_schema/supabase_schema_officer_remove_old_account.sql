-- ============================================================
-- SAGANA — Permanently delete ONE old Officer account
--
--   Auth UID: 32dbca85-d93e-49bc-a468-06d08e70a6ed        (and nothing else)
--
-- NOT EXECUTED. Run each BLOCK on its own (select it, press Run), in order.
-- Block 2 DELETES A LOGIN AND CANNOT BE UNDONE. Read the results of Block 1
-- first, then fill in the one placeholder in Block 2.
--
-- This is a permanent delete of the single row in auth.users. It is not an
-- archive and not a soft delete. No broad query is used: every statement names
-- this one UID.
--
-- WHAT DELETING auth.users DOES (decided by each table's foreign key)
--
--   DELETED together with the account (ON DELETE CASCADE)
--     * the sign-in itself: auth.users, auth.identities, sessions, refresh tokens
--     * user_roles, user_information, officer_profiles (and admin_profiles /
--       staff_profiles if the old account has one)
--     * member_identifiers + member_identifier_history (its OFF-YYYY-NNN number;
--       the number is NOT re-issued, the counter is not touched)
--     * officer_permissions (if script 01 was run), notifications addressed to it,
--       contact_email_codes, password_reset_requests it opened
--     * rows where it is the FARMER/BUYER side (farmer_loans, orders, harvests...).
--       An Officer should have none; Block 1B shows the real counts.
--
--   KEPT, with only the link to this account cleared (ON DELETE SET NULL)
--     * everything it created or decided: listings/offers/loans/payments it
--       reviewed or recorded, crops, inventory, programs, prices, units,
--       categories, loan items, broadcasts, orders it fulfilled, status events,
--       workflow_events, admin_activity_log rows
--     * the record stays; its "done by" field becomes empty. Names are NOT lost
--       from admin_activity_log rows written after officer-permissions script 05
--       (they carry actor_name and actor_role as a copy). OLDER rows lose the
--       name. Run script 05 BEFORE this script so its backfill copies the name
--       onto the existing rows first.
--     * officer_registry / sp3_member_registry rows: kept, link cleared.
--
--   WOULD BLOCK the delete (NO ACTION foreign keys, no ON DELETE rule):
--     crop_requests.reviewed_by, da_amad_enrollments.reviewed_by,
--     program_enrollment_requests.reviewed_by, cooperative_purchase_offers.
--     confirmed_by, password_reset_requests.resolved_by
--     Block 2 clears ONLY these columns, ONLY on rows that name this UID, so the
--     records are kept and only "reviewed by" becomes empty. Block 1B shows how
--     many rows that is.
--
--   NOT touched by SQL (stay as they are)
--     * files in Storage (a profile photo): listed by Block 1D; remove them in
--       the Supabase dashboard if you want them gone.
--     * columns that hold this UID WITHOUT a foreign key: listed by Block 1C.
--       They keep the old UID as a harmless label.
-- ============================================================


-- ─── BLOCK 1A — WHO THIS UID IS (read-only). Run first. ────────────────────
-- Confirm the name, username, role and Officer ID are the old account you mean.
-- Exactly ONE row is expected; zero rows means the UID does not exist.

SELECT u.id                         AS auth_uid,
       u.email                      AS auth_email,
       u.created_at                 AS created,
       u.last_sign_in_at            AS last_sign_in,
       u.banned_until,
       (SELECT string_agg(r.role || ' (' || r.status || ')', ', ')
          FROM public.user_roles r WHERE r.user_id = u.id)      AS roles,
       ui.full_name, ui.username, ui.contact_email, ui.phone_number,
       ui.last_active_at,
       (SELECT to_jsonb(op) FROM public.officer_profiles op WHERE op.user_id = u.id) AS officer_profile,
       (SELECT jsonb_agg(to_jsonb(mi)) FROM public.member_identifiers mi WHERE mi.user_id = u.id) AS identifiers
FROM auth.users u
LEFT JOIN public.user_information ui ON ui.user_id = u.id
WHERE u.id = '32dbca85-d93e-49bc-a468-06d08e70a6ed';

-- For comparison: every Officer account that exists (so you can see this is the
-- old one and which is the new one you created).
SELECT u.id, ui.username, ui.full_name, r.status, u.created_at, u.last_sign_in_at
FROM public.user_roles r
JOIN auth.users u ON u.id = r.user_id
LEFT JOIN public.user_information ui ON ui.user_id = r.user_id
WHERE r.role = 'officer'
ORDER BY u.created_at;


-- ─── BLOCK 1B — EVERY TABLE THAT POINTS AT THIS LOGIN (read-only). ─────────
-- Only tables that actually have rows for this UID are shown.
--   CASCADE   = the row is deleted with the account
--   SET NULL  = the row is kept, the link is cleared
--   NO ACTION / RESTRICT = would block the delete; Block 2 clears those links first

CREATE OR REPLACE FUNCTION pg_temp.impact(p_id uuid)
RETURNS TABLE(table_name text, column_name text, on_delete text, rows_for_user bigint)
LANGUAGE plpgsql AS $$
DECLARE
  r record;
  n bigint;
BEGIN
  FOR r IN
    SELECT k.conrelid::regclass::text AS tbl, a.attname::text AS col, k.confdeltype AS dt
    FROM pg_constraint k
    JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
    WHERE k.contype = 'f'
      AND k.confrelid = 'auth.users'::regclass
      AND cardinality(k.conkey) = 1
      AND k.conrelid::regclass::text NOT LIKE 'auth.%'
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

SELECT * FROM pg_temp.impact('32dbca85-d93e-49bc-a468-06d08e70a6ed')
WHERE rows_for_user > 0
ORDER BY on_delete, table_name, column_name;


-- ─── BLOCK 1C — OTHER COLUMNS THAT HOLD THIS UID (read-only). ──────────────
-- uuid columns in the public schema with NO foreign key to auth.users. They
-- are not changed by the delete; the UID just stays in them as a label.
-- (Skip any table you cannot read; none are expected to error.)

CREATE OR REPLACE FUNCTION pg_temp.loose_refs(p_id uuid)
RETURNS TABLE(table_name text, column_name text, rows_for_user bigint)
LANGUAGE plpgsql AS $$
DECLARE
  r record;
  n bigint;
BEGIN
  FOR r IN
    SELECT c.table_name::text AS tbl, c.column_name::text AS col
    FROM information_schema.columns c
    JOIN information_schema.tables t
      ON t.table_schema = c.table_schema AND t.table_name = c.table_name
    WHERE c.table_schema = 'public' AND c.data_type = 'uuid' AND t.table_type = 'BASE TABLE'
      AND NOT EXISTS (
        SELECT 1 FROM pg_constraint k
        JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
        WHERE k.contype = 'f' AND k.confrelid = 'auth.users'::regclass
          AND k.conrelid = format('public.%I', c.table_name)::regclass
          AND a.attname = c.column_name)
  LOOP
    EXECUTE format('SELECT count(*) FROM public.%I WHERE %I = $1', r.tbl, r.col) INTO n USING p_id;
    IF n > 0 THEN
      table_name := r.tbl; column_name := r.col; rows_for_user := n;
      RETURN NEXT;
    END IF;
  END LOOP;
END
$$;

SELECT * FROM pg_temp.loose_refs('32dbca85-d93e-49bc-a468-06d08e70a6ed')
ORDER BY table_name, column_name;
-- Expect this account's own profile ids (for example id columns that equal the
-- user id) and nothing that points at other people's records.


-- ─── BLOCK 1D — FILES IN STORAGE OWNED BY THIS UID (read-only). ────────────
SELECT o.bucket_id, o.name, o.created_at
FROM storage.objects o
WHERE to_jsonb(o) ->> 'owner_id' = '32dbca85-d93e-49bc-a468-06d08e70a6ed'
   OR to_jsonb(o) ->> 'owner'    = '32dbca85-d93e-49bc-a468-06d08e70a6ed'
   OR o.name LIKE '32dbca85-d93e-49bc-a468-06d08e70a6ed%';
-- These files are NOT deleted by Block 2.


-- ─── BLOCK 2 — DELETE the account (guarded, all-or-nothing). ───────────────
-- BEFORE RUNNING: replace REPLACE_WITH_USERNAME_FROM_BLOCK_1A below with the
-- exact username Block 1A showed. The block refuses to run until you do.
--
-- It refuses (and removes NOTHING) when:
--   * the UID is not found, or its username differs from the one you typed
--   * the account has any role other than a single "officer"
--   * after the delete, any row count is not exactly what Block 1B predicted
--     (auth.users, user_roles, user_information must each drop by exactly 1; every
--     CASCADE table must drop by exactly its Block 1B count) — then the whole
--     block is rolled back.
-- Success shows "Success. No rows returned".

DO $$
DECLARE
  v_id        constant uuid := '32dbca85-d93e-49bc-a468-06d08e70a6ed';
  v_expected  constant text := 'REPLACE_WITH_USERNAME_FROM_BLOCK_1A';
  v_username  text;
  v_roles     text;
  r           record;
  n           bigint;
  v_before    bigint;
  v_after     bigint;
  v_users_b   bigint;
  v_roles_b   bigint;
  v_info_b    bigint;
  v_cascade   jsonb := '[]'::jsonb;   -- [{tbl, expected_drop, before}]
  item        jsonb;
BEGIN
  IF v_expected = 'REPLACE_WITH_USERNAME_FROM_BLOCK_1A' THEN
    RAISE EXCEPTION 'NOT DELETED: type the username from Block 1A into v_expected first';
  END IF;

  SELECT username INTO v_username FROM public.user_information WHERE user_id = v_id;
  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE id = v_id) THEN
    RAISE EXCEPTION 'NOT DELETED: no login with this UID (already removed?)';
  END IF;
  IF v_username IS DISTINCT FROM v_expected THEN
    RAISE EXCEPTION 'NOT DELETED: the account username is "%", not "%"', v_username, v_expected;
  END IF;

  SELECT string_agg(role, ',' ORDER BY role) INTO v_roles FROM public.user_roles WHERE user_id = v_id;
  IF v_roles IS DISTINCT FROM 'officer' THEN
    RAISE EXCEPTION 'NOT DELETED: expected a single officer role, found "%"', coalesce(v_roles, 'none');
  END IF;

  -- Counts before.
  SELECT count(*) INTO v_users_b FROM auth.users;
  SELECT count(*) INTO v_roles_b FROM public.user_roles;
  SELECT count(*) INTO v_info_b  FROM public.user_information;

  FOR r IN
    SELECT k.conrelid::regclass::text AS tbl, a.attname::text AS col, k.confdeltype AS dt
    FROM pg_constraint k
    JOIN pg_attribute a ON a.attrelid = k.conrelid AND a.attnum = k.conkey[1]
    WHERE k.contype = 'f' AND k.confrelid = 'auth.users'::regclass
      AND cardinality(k.conkey) = 1
      AND k.conrelid::regclass::text NOT LIKE 'auth.%'
  LOOP
    EXECUTE format('SELECT count(*) FROM %s WHERE %I = $1', r.tbl, r.col) INTO n USING v_id;

    IF r.dt IN ('a', 'r') AND n > 0 THEN
      -- Keep the record, clear only the "done by" link on this UID's rows.
      EXECUTE format('UPDATE %s SET %I = NULL WHERE %I = $1', r.tbl, r.col, r.col) USING v_id;
      RAISE NOTICE 'cleared %.% on % row(s)', r.tbl, r.col, n;
    ELSIF r.dt = 'c' THEN
      EXECUTE format('SELECT count(*) FROM %s', r.tbl) INTO v_before;
      v_cascade := v_cascade || jsonb_build_object(
        'tbl', r.tbl, 'col', r.col, 'drop', n, 'before', v_before);
    END IF;
  END LOOP;

  -- The one and only delete.
  DELETE FROM auth.users WHERE id = v_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'NOT DELETED: the login row was not found in auth.users';
  END IF;

  -- Verify nothing but this account was removed.
  SELECT count(*) INTO v_after FROM auth.users;
  IF v_after <> v_users_b - 1 THEN
    RAISE EXCEPTION 'ROLLED BACK: auth.users dropped by % rows, expected 1', v_users_b - v_after;
  END IF;
  SELECT count(*) INTO v_after FROM public.user_roles;
  IF v_after <> v_roles_b - 1 THEN
    RAISE EXCEPTION 'ROLLED BACK: user_roles dropped by % rows, expected 1', v_roles_b - v_after;
  END IF;
  SELECT count(*) INTO v_after FROM public.user_information;
  IF v_after <> v_info_b - 1 THEN
    RAISE EXCEPTION 'ROLLED BACK: user_information dropped by % rows, expected 1', v_info_b - v_after;
  END IF;

  FOR item IN SELECT value FROM jsonb_array_elements(v_cascade) LOOP
    EXECUTE format('SELECT count(*) FROM %s', item ->> 'tbl') INTO v_after;
    IF v_after <> (item ->> 'before')::bigint - (item ->> 'drop')::bigint THEN
      RAISE EXCEPTION 'ROLLED BACK: % dropped by % rows, expected %',
        item ->> 'tbl', (item ->> 'before')::bigint - v_after, item ->> 'drop';
    END IF;
  END LOOP;
END
$$;


-- ─── BLOCK 3 — CONFIRM it is gone (read-only). ─────────────────────────────
-- Expect every count_left to be 0.

SELECT 'auth.users'        AS what, count(*) AS count_left FROM auth.users             WHERE id      = '32dbca85-d93e-49bc-a468-06d08e70a6ed'
UNION ALL SELECT 'auth.identities',  count(*) FROM auth.identities                    WHERE user_id = '32dbca85-d93e-49bc-a468-06d08e70a6ed'
UNION ALL SELECT 'user_roles',       count(*) FROM public.user_roles                  WHERE user_id = '32dbca85-d93e-49bc-a468-06d08e70a6ed'
UNION ALL SELECT 'user_information', count(*) FROM public.user_information           WHERE user_id = '32dbca85-d93e-49bc-a468-06d08e70a6ed'
UNION ALL SELECT 'officer_profiles', count(*) FROM public.officer_profiles           WHERE user_id = '32dbca85-d93e-49bc-a468-06d08e70a6ed';

-- Remaining Officer accounts (your new one must be listed):
SELECT ui.username, ui.full_name, r.status
FROM public.user_roles r LEFT JOIN public.user_information ui USING (user_id)
WHERE r.role = 'officer';
