-- ============================================================
-- SAGANA — Farmer Expenses Schema
-- Covers: My Expenses Screen
--
-- Tracks farming-related cash expenses per farmer.
-- Subsidy items (MAO/SP3-covered) are recorded at ₱0.00
-- and excluded from monetary totals via is_subsidy flag.
--
-- Subsidy sources:
--   MAO: Palay seeds, Palay fertilizer
--   SP3: Peanut seeds
--
-- Categories: Fertilizer, Labor, Seeds, Tools,
--             Irrigation, Transport, Other
-- ============================================================

CREATE TABLE IF NOT EXISTS public.farmer_expenses (
  id           UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id    UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  category     TEXT          NOT NULL DEFAULT 'Other'
               CHECK (category IN (
                 'Fertilizer', 'Labor', 'Seeds', 'Tools',
                 'Irrigation', 'Transport', 'Other'
               )),
  description  TEXT          NOT NULL,
  amount       DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  expense_date DATE          NOT NULL,
  is_subsidy   BOOLEAN       NOT NULL DEFAULT FALSE,
  notes        TEXT,
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_farmer_expenses_updated_at
  BEFORE UPDATE ON public.farmer_expenses
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE INDEX IF NOT EXISTS idx_farmer_expenses_farmer_date
  ON public.farmer_expenses (farmer_id, expense_date DESC);

CREATE INDEX IF NOT EXISTS idx_farmer_expenses_category
  ON public.farmer_expenses (farmer_id, category, expense_date DESC);

ALTER TABLE public.farmer_expenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "farmer_expenses: farmer manages own"
  ON public.farmer_expenses FOR ALL
  USING (auth.uid() = farmer_id)
  WITH CHECK (auth.uid() = farmer_id);

CREATE POLICY "farmer_expenses: admin reads all"
  ON public.farmer_expenses FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid())
  );
