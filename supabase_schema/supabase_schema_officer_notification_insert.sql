-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_officer_notification_insert.sql
-- Phase 1 — Officer notification permission.
--
-- The previous insert policy ("Admin insert notifications") allowed platform
-- admins to insert notifications for any user, but explicitly excluded
-- officers. This blocked officer-initiated notices (broadcasts, reference
-- price changes, and other client-side notification writes).
--
-- This replaces that policy so that officers can also insert notifications,
-- for any recipient, exactly as admins can. Nothing else about officer access
-- changes: this policy only governs the notifications table.
--
-- Safe to re-run.
-- ─────────────────────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Admin insert notifications" ON public.notifications;
DROP POLICY IF EXISTS "Staff insert notifications" ON public.notifications;

CREATE POLICY "Staff insert notifications"
  ON public.notifications
  FOR INSERT
  TO public
  WITH CHECK (
    public.is_platform_admin(auth.uid())
    OR EXISTS (
      SELECT 1 FROM public.officer_profiles o
      WHERE o.user_id = auth.uid()
    )
  );

-- Verification (run in Supabase after applying):
--   select policyname, cmd, with_check from pg_policies where tablename = 'notifications';
--   Expected: one INSERT policy "Staff insert notifications" that allows
--   platform admins and officer_profiles users.
