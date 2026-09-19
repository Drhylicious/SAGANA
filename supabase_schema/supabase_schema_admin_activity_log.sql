-- ============================================================
-- SAGANA — Admin Activity Log
-- (Admin Dashboard — Recent Activity, dashboard.md section 13)
--
-- Problem: Recent Activity previously had no log table at all — it was
-- reconstructed live by polling a fixed set of domain tables
-- (harvest_records, marketplace_listings, orders, price_records,
-- user_roles, crop_requests) and inferring "a row with a recent
-- created_at is an activity". That structurally can only capture row
-- creation on those specific tables — never an update, never a
-- non-row-creating action (broadcasting, exporting, editing one's own
-- profile), and critically never captures WHICH ADMIN performed the
-- action, since none of those tables record an acting admin at all.
--
-- Fix: a real, generic activity log that any admin-mutating action can
-- write one row to, at the moment it happens. Recent Activity now reads
-- from this table *in addition to* the original 6 polled sources (which
-- are left as-is — they already work and are fully localized), merged
-- and sorted together by timestamp.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.admin_activity_log (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  admin_id    UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  module      TEXT        NOT NULL,
  action_type TEXT        NOT NULL,
  description TEXT        NOT NULL,
  reference_id UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_admin_activity_log_created_at
  ON public.admin_activity_log (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_activity_log_module
  ON public.admin_activity_log (module);

ALTER TABLE public.admin_activity_log ENABLE ROW LEVEL SECURITY;

-- Any admin/officer can read the full log (it's an operational feed, not
-- scoped to one admin) — mirrors the "admin manages all" read pattern
-- used everywhere else in this schema.
CREATE POLICY "admin_activity_log: admin reads all"
  ON public.admin_activity_log FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

-- An admin may only insert a row attributed to themselves — prevents one
-- admin's actions from being logged under another admin's name.
CREATE POLICY "admin_activity_log: admin inserts own"
  ON public.admin_activity_log FOR INSERT
  WITH CHECK (
    admin_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid())
  );

NOTIFY pgrst, 'reload schema';
