-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_farmer_home_activity.sql
--
-- Farmer Recent Activity — Home category. Mirrors farmer_profile_activity
-- and farmer_crop_activity exactly. Home itself creates nothing in any
-- other table (see home_tab.md §1) except this one: a manual Sync Now tap
-- that actually had something queued to push. This table exists solely to
-- record that one fact, at the moment DashboardRepository's sync handler
-- confirms SyncService.syncPending() completed after a nonzero unsynced
-- count.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.farmer_home_activity (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  farmer_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS farmer_home_activity_farmer_id_idx
  ON public.farmer_home_activity (farmer_id, created_at DESC);

ALTER TABLE public.farmer_home_activity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Farmers manage own home activity"
  ON public.farmer_home_activity
  FOR ALL
  USING (auth.uid() = farmer_id)
  WITH CHECK (auth.uid() = farmer_id);

NOTIFY pgrst, 'reload schema';
