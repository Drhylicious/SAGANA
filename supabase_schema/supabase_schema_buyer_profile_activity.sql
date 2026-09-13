-- ─────────────────────────────────────────────────────────────────────────────
-- supabase_schema_buyer_profile_activity.sql
--
-- Buyer Recent Activity — the one genuinely new piece of storage this
-- feature requires. Order-related activity is derived at read time
-- directly from `orders` (no new table — same convention as Farmer's
-- DashboardRepository.fetchAllActivity()). Profile changes have no
-- equivalent derivable history: user_information only carries the row's
-- current state, so there's no way to know after the fact whether a name,
-- phone, or photo changed. This table exists solely to record that one
-- fact, at the moment BuyerProfileRepository.updateProfile() actually
-- changes something — not a general-purpose activity-log system.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.buyer_profile_activity (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  buyer_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  description TEXT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS buyer_profile_activity_buyer_id_idx
  ON public.buyer_profile_activity (buyer_id, created_at DESC);

ALTER TABLE public.buyer_profile_activity ENABLE ROW LEVEL SECURITY;

-- Single FOR ALL policy, scoped to own rows — the buyer's own client
-- inserts (from updateProfile()) and reads (Recent Activity screen) both
-- need exactly this, nothing broader. No admin policy — not required by
-- this feature's scope.
CREATE POLICY "Buyers manage own profile activity"
  ON public.buyer_profile_activity
  FOR ALL
  USING (auth.uid() = buyer_id)
  WITH CHECK (auth.uid() = buyer_id);

NOTIFY pgrst, 'reload schema';
