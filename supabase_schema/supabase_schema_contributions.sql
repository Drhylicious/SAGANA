-- ============================================================
-- SAGANA — Cooperative Contribution Schema
-- Covers: My Cooperative Contribution (Balik-Tangkilik) Screen
--
-- Balik-Tangkilik is SP3's profit-sharing mechanism.
-- Only Palay and Peanut sold DIRECTLY to SP3 count toward
-- a farmer's contribution share. Ginger sales via DA-AMAD
-- market linking are excluded (free coop service, not purchase).
--
-- Tables:
--   member_contributions      — annual summary per farmer
--   member_sales_transactions — individual sales to SP3
--   member_capital_shares     — share count + value per farmer
--   cooperative_annual_totals — coop-wide totals for share %
-- ============================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: member_capital_shares
-- Tracks each farmer's share investment in the cooperative.
-- share_value_per_unit is fixed by BOD (currently ₱100/share).
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.member_capital_shares (
  id                 UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id          UUID          NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  total_shares       INT           NOT NULL DEFAULT 0 CHECK (total_shares >= 0),
  share_value_per_unit DECIMAL(10,2) NOT NULL DEFAULT 100.00,
  updated_at         TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

ALTER TABLE public.member_capital_shares ENABLE ROW LEVEL SECURITY;

CREATE POLICY "member_capital_shares: farmer reads own"
  ON public.member_capital_shares FOR SELECT
  USING (auth.uid() = farmer_id);

CREATE POLICY "member_capital_shares: admin manages all"
  ON public.member_capital_shares FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: member_contributions
-- One row per farmer per year.
-- Tracks sales totals, estimated distribution, and actual payout.
-- status: pending | paid | not_yet_computed
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.member_contributions (
  id                           UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id                    UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  year                         INT           NOT NULL,
  total_sales_amount           DECIMAL(12,2) NOT NULL DEFAULT 0,
  palay_sales_kg               DECIMAL(10,2) NOT NULL DEFAULT 0,
  palay_sales_amount           DECIMAL(12,2) NOT NULL DEFAULT 0,
  peanut_sales_kg              DECIMAL(10,2) NOT NULL DEFAULT 0,
  peanut_sales_amount          DECIMAL(12,2) NOT NULL DEFAULT 0,
  estimated_balik_tangkilik    DECIMAL(12,2) NOT NULL DEFAULT 0,
  estimated_interest_on_capital DECIMAL(12,2) NOT NULL DEFAULT 0,
  actual_balik_tangkilik       DECIMAL(12,2),
  actual_interest_on_capital   DECIMAL(12,2),
  actual_payout_date           DATE,
  status                       TEXT          NOT NULL DEFAULT 'pending'
                               CHECK (status IN ('pending', 'paid', 'not_yet_computed')),
  notes                        TEXT,
  created_at                   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at                   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  UNIQUE (farmer_id, year)
);

CREATE TRIGGER trg_member_contributions_updated_at
  BEFORE UPDATE ON public.member_contributions
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE INDEX IF NOT EXISTS idx_member_contributions_farmer
  ON public.member_contributions (farmer_id, year DESC);

ALTER TABLE public.member_contributions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "member_contributions: farmer reads own"
  ON public.member_contributions FOR SELECT
  USING (auth.uid() = farmer_id);

CREATE POLICY "member_contributions: admin manages all"
  ON public.member_contributions FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: member_sales_transactions
-- Individual crop sales submitted to SP3.
-- crop_type: 'palay' | 'peanut' (only these count toward Balik-Tangkilik)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.member_sales_transactions (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id       UUID          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  contribution_id UUID          REFERENCES public.member_contributions(id) ON DELETE SET NULL,
  crop_name       TEXT          NOT NULL,
  crop_type       TEXT          NOT NULL DEFAULT 'palay'
                  CHECK (crop_type IN ('palay', 'peanut')),
  quantity_kg     DECIMAL(10,2) NOT NULL CHECK (quantity_kg > 0),
  amount          DECIMAL(12,2) NOT NULL CHECK (amount >= 0),
  sale_date       DATE          NOT NULL,
  reference_no    TEXT,
  recorded_by     UUID          REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_member_sales_farmer_date
  ON public.member_sales_transactions (farmer_id, sale_date DESC);

ALTER TABLE public.member_sales_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "member_sales_transactions: farmer reads own"
  ON public.member_sales_transactions FOR SELECT
  USING (auth.uid() = farmer_id);

CREATE POLICY "member_sales_transactions: admin manages all"
  ON public.member_sales_transactions FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: cooperative_annual_totals
-- Admin-entered coop-wide totals for share % calculation.
-- distributable_surplus is the pool from which Balik-Tangkilik is drawn.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cooperative_annual_totals (
  id                     UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  year                   INT           NOT NULL UNIQUE,
  total_coop_sales       DECIMAL(14,2) NOT NULL DEFAULT 0,
  distributable_surplus  DECIMAL(14,2) NOT NULL DEFAULT 0,
  interest_rate_percent  DECIMAL(5,2)  NOT NULL DEFAULT 7.00,
  created_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_cooperative_annual_totals_updated_at
  BEFORE UPDATE ON public.cooperative_annual_totals
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

-- All authenticated users can read (needed for share % display)
ALTER TABLE public.cooperative_annual_totals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cooperative_annual_totals: authenticated reads"
  ON public.cooperative_annual_totals FOR SELECT
  USING (auth.role() = 'authenticated');

CREATE POLICY "cooperative_annual_totals: admin manages all"
  ON public.cooperative_annual_totals FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));
