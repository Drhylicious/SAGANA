-- ============================================================
-- SAGANA — Officer permissions, script 11: BROADCAST IS OPEN TO EVERY OFFICER
--
-- DECISION (yours): Broadcast sits in the top bar with the Navigation Drawer and
-- Profile. Those are primary screens, so an Officer can send, schedule and reach
-- Farmer Members and Buyers at any time, whatever module access they hold. What
-- protects the cooperative is accountability, not permission: every broadcast
-- records who made it.
--
-- WHAT THIS DOES
--   Removes the two Broadcast rows from staff_permission_targets (script 02 had
--   put them under the Dashboard module), so the request gate no longer refuses a
--   View Only Officer on them:
--     * rpc   send_broadcast   (the "Send now" call)
--     * table broadcast_logs   (a scheduled broadcast is a row in this table)
--   Nothing else changes. Everything else stays governed, including price
--   announcements (notify_price_update), which belong to Prices in Dashboard.
--
-- WHY THE DATABASE STILL ACCEPTS IT
--   send_broadcast() allows the Manager or any Officer, and the broadcast_logs
--   policies (script 03) allow any staff member to insert, update and delete.
--   Farmers and Buyers still cannot write broadcast_logs.
--
-- ACCOUNTABILITY (already in place, script 05)
--   broadcast_logs has the audit trigger (module 'broadcast'). Every broadcast, its
--   scheduling, any edit and any delete is written in the same transaction with the
--   staff member's name, role, the values, and the time. The Manager reads it in
--   Staff Accountability, filter "Broadcast". broadcast_logs.created_by also keeps
--   the sender.
--
-- BEFORE YOU RELY ON THIS (read-only; the answer is what the live gate holds now):
--   SELECT * FROM staff_permission_targets WHERE name IN ('send_broadcast','broadcast_logs');
--   -- expect 2 rows before this script, 0 after
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Re-runnable.
-- To undo (puts Broadcast back under Dashboard):
--   INSERT INTO staff_permission_targets (kind, name, module) VALUES
--     ('rpc','send_broadcast','dashboard'), ('table','broadcast_logs','dashboard')
--   ON CONFLICT DO NOTHING;
-- ============================================================

BEGIN;

DELETE FROM public.staff_permission_targets
WHERE (kind = 'rpc'   AND name = 'send_broadcast')
   OR (kind = 'table' AND name = 'broadcast_logs');

COMMIT;

-- ─── VERIFICATION (read-only) ────────────────────────────────────────────
--   SELECT * FROM staff_permission_targets WHERE name IN ('send_broadcast','broadcast_logs'); -- 0 rows
--   SELECT * FROM staff_permission_targets WHERE name = 'notify_price_update';               -- still 'dashboard'
-- As an Officer whose Dashboard is View Only, send a broadcast from the app: it is
-- delivered, and the Manager sees "Created broadcast logs: <title>" with the Officer's
-- name under Staff Accountability > Broadcast.
-- ─────────────────────────────────────────────────────────────────────────
