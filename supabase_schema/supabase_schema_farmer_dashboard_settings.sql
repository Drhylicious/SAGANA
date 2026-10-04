-- ============================================================
-- SAGANA — Farmer Dashboard Settings
-- Replaces the hardcoded ₱60,000 monthly earnings goal on Farmer
-- Home with an Admin-configurable, database-driven value. Same
-- singleton-row + RLS pattern already established by
-- loan_policy_settings (see supabase_schema_loan_overdue_automation.sql),
-- kept as its own table rather than reusing loan_policy_settings —
-- per explicit decision, the ₱2,000 loan-eligibility threshold in
-- that table is a Capital Share rule and must stay unrelated to the
-- Home earnings goal.
--
-- CURRENT DEFAULT — ₱5,000/month, per explicit direction, to be
-- revisited once confirmed against real cooperative income data.
-- Change it any time via a plain UPDATE statement below — no code
-- or app redeploy needed:
--   UPDATE public.farmer_dashboard_settings SET monthly_earnings_goal = <new_value> WHERE id = 1;
-- ============================================================

CREATE TABLE IF NOT EXISTS public.farmer_dashboard_settings (
  id                     INT         PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  monthly_earnings_goal  NUMERIC     NOT NULL DEFAULT 5000,
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.farmer_dashboard_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.farmer_dashboard_settings ENABLE ROW LEVEL SECURITY;

-- Every authenticated user may read it — Farmer Home reads this value
-- directly from the client (unlike loan_policy_settings, which is only
-- ever read server-side by admin-facing screens/automation).
DROP POLICY IF EXISTS "farmer_dashboard_settings: authenticated read" ON public.farmer_dashboard_settings;
CREATE POLICY "farmer_dashboard_settings: authenticated read"
  ON public.farmer_dashboard_settings FOR SELECT
  USING (auth.role() = 'authenticated');

-- Only Admin may change it. No Admin UI screen exists yet to edit this
-- through the app — until one is built, use the UPDATE statement above
-- directly in the Supabase SQL editor.
DROP POLICY IF EXISTS "farmer_dashboard_settings: admin update" ON public.farmer_dashboard_settings;
CREATE POLICY "farmer_dashboard_settings: admin update"
  ON public.farmer_dashboard_settings FOR UPDATE
  USING (EXISTS (SELECT 1 FROM admin_profiles WHERE user_id = auth.uid()));

NOTIFY pgrst, 'reload schema';
