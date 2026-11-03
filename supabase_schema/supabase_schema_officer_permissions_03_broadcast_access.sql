-- ============================================================
-- SAGANA — Officer permissions, script 3 of 6: BROADCAST ACCESS
--
-- Requires script 01. Safe to run on its own.
--
-- GOAL: an Officer whose Dashboard access is Manage can create, schedule, edit,
-- delete and send broadcasts, exactly like the Manager. An Officer with
-- Dashboard = View Only can only read them. The View Only / Manage decision is
-- made by the request gate (script 02, broadcast_logs and send_broadcast are
-- mapped to the Dashboard module); this script only removes the Manager-only
-- blocks that sit underneath it.
--
-- WHAT WAS BLOCKING OFFICERS (found in the repository SQL)
--   * broadcast_logs INSERT / UPDATE / DELETE policies were
--       is_platform_admin() AND NOT <is an Officer>
--     so scheduling a broadcast (the app writes broadcast_logs directly), and
--     editing or deleting a broadcast log, failed for every Officer.
--   * the notifications INSERT policy exists in two versions in the repository:
--     supabase_schema_officer_notification_insert.sql (staff allowed) and
--     supabase_schema_role_based_staff_access.sql (Officers excluded again).
--     Which one is live depends on the order they were run.
--
-- ALREADY OPEN TO OFFICERS (no change needed; verified in the function bodies)
--   send_broadcast(), preview_broadcast_recipients(), notify_price_update(),
--   record_program_thriving_outcome(), process_scheduled_broadcasts().
--
-- NOTE: the app has no screen to edit or delete a broadcast, for the Manager
-- either. After this script the database permits an Officer with Manage to do
-- both, the same as the Manager; no screen is added here.
--
-- NOT TOUCHED: Balik-Tangkilik. cooperative_annual_totals and member_contributions
-- keep their Manager-only write policies, and the payout RPCs keep their
-- Manager-only checks.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor.
-- ============================================================

-- ─── PRE-FLIGHT (read-only; run by itself) ───────────────────────────────
--   SELECT tablename, policyname, cmd, qual, with_check FROM pg_policies
--   WHERE tablename IN ('broadcast_logs', 'notifications') ORDER BY 1, 3, 2;
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

-- ─── broadcast_logs: staff may write (the gate decides View Only vs Manage) ──
DROP POLICY IF EXISTS "Admin full access to broadcast_logs (insert)" ON public.broadcast_logs;
DROP POLICY IF EXISTS "Admin full access to broadcast_logs (update)" ON public.broadcast_logs;
DROP POLICY IF EXISTS "Admin full access to broadcast_logs (delete)" ON public.broadcast_logs;
DROP POLICY IF EXISTS "broadcast_logs: staff insert" ON public.broadcast_logs;
DROP POLICY IF EXISTS "broadcast_logs: staff update" ON public.broadcast_logs;
DROP POLICY IF EXISTS "broadcast_logs: staff delete" ON public.broadcast_logs;

CREATE POLICY "broadcast_logs: staff insert"
  ON public.broadcast_logs FOR INSERT TO public
  WITH CHECK (public.is_staff());
CREATE POLICY "broadcast_logs: staff update"
  ON public.broadcast_logs FOR UPDATE TO public
  USING (public.is_staff()) WITH CHECK (public.is_staff());
CREATE POLICY "broadcast_logs: staff delete"
  ON public.broadcast_logs FOR DELETE TO public
  USING (public.is_staff());
-- (the read policy "Admin full access to broadcast_logs (read)" is already is_staff())

-- ─── notifications: staff may insert notices for any recipient ───────────────
DROP POLICY IF EXISTS "Admin insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "Staff insert notifications" ON public.notifications;
CREATE POLICY "Staff insert notifications"
  ON public.notifications FOR INSERT TO public
  WITH CHECK (public.is_staff());

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION (run each by itself)
-- ============================================================
-- 1) Exactly these write policies remain on broadcast_logs and one insert
--    policy on notifications for staff:
--    SELECT tablename, policyname, cmd FROM pg_policies
--    WHERE tablename IN ('broadcast_logs', 'notifications') AND cmd IN ('INSERT','UPDATE','DELETE')
--    ORDER BY 1, 3, 2;
-- 2) After script 06, in the app:
--    * Officer with Dashboard = Manage: send a broadcast now AND schedule one -> both work.
--    * Officer with Dashboard = View Only: both are refused with the view-only message.
-- ============================================================
