-- ============================================================
-- SAGANA — Officer permissions, script 10: STATUS HISTORY IS MANAGER-ONLY
--
-- WHY
--   member_status_events holds the audit trail of a member's status changes,
--   including WHO decided (actor_name, actor_role) and the reason. The live policy
--   "mse: member reads own" lets a Farmer read their own rows, so a Farmer could
--   read the name of the Manager or Officer who decided their application.
--
-- DECISION (yours): a Farmer still sees their own outcome (approved, or
--   disapproved with the reason) but never the staff member's name or the Status
--   History. Only the Manager sees the full history.
--
-- WHAT STILL WORKS (checked)
--   * The Farmer's Pending screen reads user_roles (status, rejection_reason), not
--     this table; the approved / disapproved notices come from notifications.
--   * Nothing in the Farmer or Buyer app reads member_status_events (searched lib/);
--     only the Manager's Members and Farmer Details screens do.
--   * The Manager keeps the policy "mse: admin manages all". Officers cannot read
--     the table (they are not platform admins outside a Members write).
--
-- WHAT THIS DOES: drops the one policy. Re-runnable.
--
-- ROLLBACK: CREATE POLICY "mse: member reads own" ON public.member_status_events
--             FOR SELECT USING (auth.uid() = member_id);
-- ============================================================

BEGIN;

DROP POLICY IF EXISTS "mse: member reads own" ON public.member_status_events;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
--   SELECT policyname, cmd FROM pg_policies
--   WHERE schemaname = 'public' AND tablename = 'member_status_events';
--   -- expect only "mse: admin manages all"
-- As a Farmer, an application's approved / disapproved notice and the reason on the
-- Pending screen still appear; the Manager's Farmer Details still shows Status History.
-- ─────────────────────────────────────────────────────────────────────────
