-- ============================================================
-- SAGANA — Cooperative Inventory Management
-- Admin-managed cooperative-level stock ledger.
-- Distinct from farmer inventory_batches.
-- This is the source of truth for cooperative-owned stock:
-- inputs purchased for distribution, harvests received from
-- farmers, and items allocated to loans or sold.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.cooperative_inventory (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  item_name       TEXT          NOT NULL,
  category        TEXT          NOT NULL DEFAULT 'Agricultural Supplies'
                  CHECK (category IN (
                    'Fertilizer', 'Seeds', 'Animal Feeds', 'Pesticide',
                    'Tools & Equipment', 'Agricultural Supplies', 'Harvest Stock'
                  )),
  unit            TEXT          NOT NULL DEFAULT 'kg',
  quantity_on_hand DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (quantity_on_hand >= 0),
  quantity_reserved DECIMAL(12,2) NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
  reorder_level   DECIMAL(12,2) NOT NULL DEFAULT 0,
  unit_cost       DECIMAL(10,2),
  notes           TEXT,
  is_active       BOOLEAN       NOT NULL DEFAULT TRUE,
  last_restocked_at TIMESTAMPTZ,
  created_by      UUID          REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_cooperative_inventory_updated_at
  BEFORE UPDATE ON public.cooperative_inventory
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

CREATE INDEX IF NOT EXISTS idx_cooperative_inventory_category
  ON public.cooperative_inventory (category, is_active);

ALTER TABLE public.cooperative_inventory ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cooperative_inventory: admin manages all"
  ON public.cooperative_inventory FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

-- Inventory transaction log — every stock movement is recorded
CREATE TABLE IF NOT EXISTS public.inventory_transactions (
  id              UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  inventory_id    UUID          NOT NULL REFERENCES public.cooperative_inventory(id) ON DELETE CASCADE,
  transaction_type TEXT         NOT NULL
                  CHECK (transaction_type IN (
                    'restock', 'loan_issued', 'adjustment', 'harvest_received',
                    'sold', 'returned', 'written_off'
                  )),
  quantity        DECIMAL(12,2) NOT NULL, -- positive = in, negative = out
  reference_id    UUID,         -- FK to loan_id, harvest_record_id, etc.
  reference_type  TEXT,         -- 'loan' | 'harvest' | 'sale' | 'manual'
  notes           TEXT,
  recorded_by     UUID          REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

ALTER TABLE public.inventory_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "inventory_transactions: admin manages all"
  ON public.inventory_transactions FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));