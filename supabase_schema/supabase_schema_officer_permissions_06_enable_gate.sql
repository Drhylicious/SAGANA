-- ============================================================
-- SAGANA — Officer permissions, script 6 of 6: TURN THE GATE ON
--
-- Requires scripts 01 and 02 (and the rest of 03-05). This is the switch that makes
-- View Only real: it registers staff_permission_gate() as PostgREST's
-- pre-request function. Run it LAST, after the matching app build is released
-- (the new Create/Edit Officer screens call the new RPC signatures).
--
-- ─── PRE-FLIGHT (run first, by itself) ──────────────────────────────────
-- Is another pre-request function already configured? If this returns a row,
-- STOP: that function must be chained into staff_permission_gate() instead of
-- being replaced.
--    SELECT rolname, rolconfig FROM pg_roles
--    WHERE rolname = 'authenticator' AND rolconfig::text ILIKE '%pre_request%';
-- ────────────────────────────────────────────────────────────────────────
--
-- ROLLBACK (turns enforcement off again; Officers return to today's behavior):
--    ALTER ROLE authenticator RESET pgrst.db_pre_request;
--    NOTIFY pgrst, 'reload config';
-- ============================================================

ALTER ROLE authenticator SET pgrst.db_pre_request = 'public.staff_permission_gate';
NOTIFY pgrst, 'reload config';
NOTIFY pgrst, 'reload schema';

-- ─── VERIFY (run each by itself) ────────────────────────────────────────
-- 1) The setting is stored:
--    SELECT rolconfig FROM pg_roles WHERE rolname = 'authenticator';
--    -- contains pgrst.db_pre_request=public.staff_permission_gate
-- 2) The gate is live — in the app, signed in as an Officer whose Dashboard is
--    View Only, edit a crop price: expect "Your Officer account has view-only
--    access to the dashboard module ...". Signed in as the Manager: it saves.
-- ============================================================
