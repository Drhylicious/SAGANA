-- ============================================================
-- SAGANA — Input Loans Schema
-- Covers: My Input Loans Screen
--
-- IMPORTANT: These are NOT cash loans.
-- Loans represent agricultural inputs distributed to farmers
-- by the SP3 Cooperative (seeds, fertilizers, tools, etc.).
-- Farmers repay by surrendering harvest value, not cash.
--
-- Tables:
--   farmer_loans        — one loan per issuance event
--   farmer_loan_items   — itemized inputs per loan
--   farmer_loan_payments — payment/repayment history per loan
-- ============================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: farmer_loans
-- status:
--   active   — outstanding balance, within payment schedule
--   overdue  — missed at least one BOD Saturday payment cycle
--   paid     — fully repaid
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.farmer_loans (
  id              UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  farmer_id       UUID        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reference_no    TEXT        NOT NULL UNIQUE,
  issued_date     DATE        NOT NULL,
  total_value     DECIMAL(12,2) NOT NULL CHECK (total_value > 0),
  amount_paid     DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (amount_paid >= 0),
  status          TEXT        NOT NULL DEFAULT 'active'
                  CHECK (status IN ('active', 'overdue', 'paid')),
  notes           TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_farmer_loans_updated_at
  BEFORE UPDATE ON public.farmer_loans
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE INDEX IF NOT EXISTS idx_farmer_loans_farmer
  ON public.farmer_loans (farmer_id, status, issued_date DESC);

ALTER TABLE public.farmer_loans ENABLE ROW LEVEL SECURITY;

CREATE POLICY "farmer_loans: farmer reads own"
  ON public.farmer_loans FOR SELECT
  USING (auth.uid() = farmer_id);

CREATE POLICY "farmer_loans: admin manages all"
  ON public.farmer_loans FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid())
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: farmer_loan_items
-- Itemized agricultural inputs per loan.
-- unit_price × quantity = line_total (enforced by app, not DB)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.farmer_loan_items (
  id          UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id     UUID          NOT NULL REFERENCES public.farmer_loans(id) ON DELETE CASCADE,
  item_name   TEXT          NOT NULL,
  quantity    DECIMAL(10,2) NOT NULL CHECK (quantity > 0),
  unit        TEXT          NOT NULL DEFAULT 'bag',
  unit_price  DECIMAL(10,2) NOT NULL CHECK (unit_price >= 0),
  line_total  DECIMAL(12,2) NOT NULL CHECK (line_total >= 0),
  created_at  TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_farmer_loan_items_loan
  ON public.farmer_loan_items (loan_id);

ALTER TABLE public.farmer_loan_items ENABLE ROW LEVEL SECURITY;

CREATE POLICY "farmer_loan_items: farmer reads own via loan"
  ON public.farmer_loan_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.farmer_loans fl
      WHERE fl.id = loan_id AND fl.farmer_id = auth.uid()
    )
  );

CREATE POLICY "farmer_loan_items: admin manages all"
  ON public.farmer_loan_items FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid())
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: farmer_loan_payments
-- Each row is a repayment event on a BOD Saturday.
-- running_balance = loan.total_value - sum(all payments up to this date)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.farmer_loan_payments (
  id               UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  loan_id          UUID          NOT NULL REFERENCES public.farmer_loans(id) ON DELETE CASCADE,
  payment_date     DATE          NOT NULL,
  amount_paid      DECIMAL(12,2) NOT NULL CHECK (amount_paid > 0),
  running_balance  DECIMAL(12,2) NOT NULL CHECK (running_balance >= 0),
  notes            TEXT,
  recorded_by      UUID          REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at       TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_farmer_loan_payments_loan
  ON public.farmer_loan_payments (loan_id, payment_date DESC);

ALTER TABLE public.farmer_loan_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "farmer_loan_payments: farmer reads own via loan"
  ON public.farmer_loan_payments FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.farmer_loans fl
      WHERE fl.id = loan_id AND fl.farmer_id = auth.uid()
    )
  );

CREATE POLICY "farmer_loan_payments: admin manages all"
  ON public.farmer_loan_payments FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid())
  );
