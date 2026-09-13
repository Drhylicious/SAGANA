-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_farmer_profile_activity.sql
--
-- Farmer Recent Activity — Account category. Mirrors
-- buyer_profile_activity exactly (same reasoning: user_information and
-- farmer_profiles only carry current state, so there's no way to know
-- after the fact whether a name, phone, farm detail, password, or photo
-- changed). This table exists solely to record that one fact, at the
-- moment FarmerProfileRepository's update methods actually change
-- something, or ChangePasswordDialog succeeds.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.farmer_profile_activity (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  farmer_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS farmer_profile_activity_farmer_id_idx
  ON public.farmer_profile_activity (farmer_id, created_at DESC);

ALTER TABLE public.farmer_profile_activity ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Farmers manage own profile activity"
  ON public.farmer_profile_activity
  FOR ALL
  USING (auth.uid() = farmer_id)
  WITH CHECK (auth.uid() = farmer_id);

NOTIFY pgrst, 'reload schema';