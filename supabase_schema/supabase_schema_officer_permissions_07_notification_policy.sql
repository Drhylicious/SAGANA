-- ============================================================
-- SAGANA — Officer permissions, script 7: NOTIFICATION INSERT POLICY
--
-- WHY
--   The live policy "Staff insert notifications" (INSERT, WITH CHECK is_staff())
--   lets ANY staff member, including an Officer who is View Only, post a
--   notification to any user straight through the REST API. That bypasses the
--   Broadcast permission (Dashboard = Manage).
--
-- WHAT THE CHECKS FOUND (database_checks, 2026-11)
--   * No function that inserts into notifications runs with the caller's rights
--     (every one is SECURITY DEFINER), so none relies on this policy.
--   * The app never inserts into notifications directly (searched lib/).
--   * The Edge function process-scheduled-broadcasts uses the service-role key,
--     which bypasses row level security.
--   So nothing depends on the policy.
--
-- WHAT THIS DOES
--   Drops the policy. After this, no signed-in user can insert a notification
--   directly. Notifications are still created by the database functions
--   (send_broadcast, the approval, order, loan ... functions), which are
--   SECURITY DEFINER and unaffected. Reading and deleting your own
--   notifications, and the staff read policy, are untouched.
--
-- RE-RUNNABLE. Not applied automatically. Run in the Supabase SQL editor.
--
-- RE-CHECK (read-only, run before):
--   SELECT p.proname FROM pg_proc p
--   WHERE p.pronamespace = 'public'::regnamespace AND p.prokind = 'f'
--     AND p.prosrc ILIKE '%insert into%notifications%' AND NOT p.prosecdef;
--   -- expect no rows
--
-- ROLLBACK (only if something unexpected breaks):
--   CREATE POLICY "Staff insert notifications" ON public.notifications
--     FOR INSERT TO public WITH CHECK (public.is_staff());
-- ============================================================

BEGIN;

DROP POLICY IF EXISTS "Staff insert notifications" ON public.notifications;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
-- The INSERT policy must be gone (expect no INSERT row):
--   SELECT policyname, cmd FROM pg_policies
--   WHERE schemaname = 'public' AND tablename = 'notifications' ORDER BY cmd, policyname;
-- A broadcast still works: send one from the app as the Manager and as an
-- Officer with Dashboard = Manage; both reach the recipients.
-- ─────────────────────────────────────────────────────────────────────────
