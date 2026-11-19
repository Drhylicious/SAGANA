-- ============================================================
-- SAGANA — The Accountability Log is MANAGER-ONLY in the database
--
-- WHY
--   Only the Manager may view the Staff Accountability log. The screen is already closed to
--   Officers, but the table behind it (admin_activity_log) still let ANY staff member read every
--   row the app writes (policy from officer_permissions_05), including other staff members' rows
--   and the report-export rows that the Accountability screen lists. An Officer who called the
--   data API directly could therefore read part of the log.
--
-- WHAT THIS DOES
--   Replaces the read policy on public.admin_activity_log:
--     * The Manager reads every row (unchanged).
--     * Any other staff member (Officer) can read ONLY their own app-written rows, which is exactly
--       what their Dashboard "Recent Activity" feed shows (the app already filters that feed to
--       admin_id = the signed-in user and source = 'app'), and NOT the report-export rows.
--     * An Officer can no longer read: the database-side audit trail (source 'db'), any other staff
--       member's rows, the Manager's rows, or the report-export rows.
--   Nothing else changes: inserts stay as they are, nothing can be updated or deleted, and the
--   Manager's Staff Accountability screen is unaffected.
--
-- WHAT STAYS THE SAME ON PURPOSE
--   The per-program History sheet and the member Status History are separate staff features built on
--   the audit trail through their own functions. They are not changed here.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Safe to re-run.
-- TO UNDO: re-run the policy from supabase_schema_officer_permissions_05_accountability.sql (line 117).
-- ============================================================

DO $$
BEGIN
  IF to_regclass('public.admin_activity_log') IS NULL THEN
    RAISE EXCEPTION 'public.admin_activity_log is missing.';
  END IF;
  -- is_manager takes one optional argument (p_uid uuid DEFAULT auth.uid()), so it is looked up by that signature.
  IF to_regprocedure('public.is_manager(uuid)') IS NULL OR to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_manager(uuid) / is_staff() are missing.';
  END IF;
END $$;

BEGIN;

DROP POLICY IF EXISTS "admin_activity_log: admin reads all" ON public.admin_activity_log;
DROP POLICY IF EXISTS "admin_activity_log: staff read app rows, manager reads all" ON public.admin_activity_log;
DROP POLICY IF EXISTS "admin_activity_log: manager reads all, staff read own recent activity" ON public.admin_activity_log;

CREATE POLICY "admin_activity_log: manager reads all, staff read own recent activity"
  ON public.admin_activity_log FOR SELECT TO public
  USING (
    public.is_manager()
    OR (
      public.is_staff()
      AND source = 'app'
      AND admin_id = auth.uid()
      AND NOT (module = 'reports' AND action_type = 'exported')
    )
  );

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only; run each by itself) ────────────────────────
--   -- 1. Exactly one read policy, with the new name:  expect 1 row
--   SELECT policyname, cmd FROM pg_policies
--   WHERE tablename = 'admin_activity_log' AND cmd = 'SELECT';
--   -- 2. The old policy is gone:  expect 0 rows
--   SELECT policyname FROM pg_policies
--   WHERE tablename = 'admin_activity_log' AND policyname LIKE 'admin_activity_log: staff read app rows%';
-- In the app: as the Manager, Staff Accountability still lists everything. As an Officer, the Dashboard
-- Recent Activity still shows that Officer's own actions, and a direct request for the log returns only
-- those rows (never the database audit trail, other staff, or exports).
-- ────────────────────────────────────────────────────────────────────────
