-- ============================================================
-- SAGANA — Loan Items Master List
-- Admin-managed catalog of loanable agricultural inputs.
-- Replaces hardcoded loanInputCategories in app_constants.dart.
-- When issuing a loan, admin selects from this list.
-- unit_price here is the cooperative's standard issue price.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.loan_items_master (
  id           UUID          PRIMARY KEY DEFAULT uuid_generate_v4(),
  item_name    TEXT          NOT NULL UNIQUE,
  category     TEXT          NOT NULL DEFAULT 'Agricultural Supplies'
               CHECK (category IN (
                 'Fertilizer', 'Seeds', 'Animal Feeds',
                 'Pesticide', 'Tools & Equipment', 'Agricultural Supplies'
               )),
  unit         TEXT          NOT NULL DEFAULT 'bag'
               CHECK (unit IN ('bag', 'kg', 'sack', 'piece', 'liter', 'set', 'bottle')),
  unit_price   DECIMAL(10,2) NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
  description  TEXT,
  is_active    BOOLEAN       NOT NULL DEFAULT TRUE,
  sort_order   INT           NOT NULL DEFAULT 0,
  created_by   UUID          REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ   NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_loan_items_master_updated_at
  BEFORE UPDATE ON public.loan_items_master
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.loan_items_master ENABLE ROW LEVEL SECURITY;

CREATE POLICY "loan_items_master: admin manages all"
  ON public.loan_items_master FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

CREATE POLICY "loan_items_master: farmer reads active"
  ON public.loan_items_master FOR SELECT
  USING (is_active = TRUE AND auth.role() = 'authenticated');

-- Seed common SP3 inputs
INSERT INTO public.loan_items_master (item_name, category, unit, unit_price, description, sort_order) VALUES
  ('Urea Fertilizer',        'Fertilizer',          'bag',    950.00, '50kg bag. For Palay and Peanut.', 1),
  ('Complete Fertilizer',    'Fertilizer',          'bag',    1100.00,'14-14-14 NPK, 50kg bag.', 2),
  ('Palay Seeds',            'Seeds',               'kg',     55.00,  'Certified rice seeds. MAO subsidy applies.', 3),
  ('Peanut Seeds',           'Seeds',               'kg',     120.00, 'SP3 subsidy applies.', 4),
  ('Ginger Seed Rhizomes',   'Seeds',               'kg',     80.00,  'For DA-AMAD program participants.', 5),
  ('Banana Suckers',         'Seeds',               'piece',  25.00,  'Tissue-cultured banana planting material.', 6),
  ('Pesticide (Insecticide)','Pesticide',           'liter',  350.00, 'General purpose, 1L bottle.', 7),
  ('Herbicide',              'Pesticide',           'liter',  280.00, 'Pre-emergent, 1L bottle.', 8),
  ('Hog Feeds',              'Animal Feeds',        'bag',    1400.00,'50kg sack, grower formula.', 9),
  ('Chicken Feeds',          'Animal Feeds',        'bag',    1250.00,'50kg sack, broiler formula.', 10),
  ('Hand Trowel Set',        'Tools & Equipment',   'set',    450.00, 'Basic garden tool set.', 11),
  ('Irrigation Hose',        'Agricultural Supplies','piece', 850.00, '50m agricultural hose.', 12)
ON CONFLICT (item_name) DO NOTHING;