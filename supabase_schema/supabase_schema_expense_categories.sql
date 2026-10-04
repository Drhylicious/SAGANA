-- ============================================================
-- SAGANA — Expense Category Lookup Table
-- (Farmer Profile tab investigation — My Expenses revision)
--
-- Problem: farmer_expenses.category was a hardcoded Dart list
-- (expenseCategories in expense_model.dart) backed by a DB CHECK
-- constraint enum. Adding a category required a code change + a
-- migration + an app release — the same problem
-- supabase_schema_category_lookup_tables.sql already fixed for
-- inventory/crop categories.
--
-- Fix: one more admin-managed lookup table, mirroring that exact same
-- pattern (id/name/is_active/sort_order/created_by + "admin manages all"
-- / "authenticated reads active" RLS), so a farmer adding a new expense
-- category from the dropdown persists it for everyone, the same way
-- Admin Inventory's category dropdown already works.
--
-- farmer_expenses.category keeps storing plain TEXT exactly as before.
-- ============================================================

CREATE TABLE IF NOT EXISTS public.expense_categories (
  id          UUID        PRIMARY KEY DEFAULT uuid_generate_v4(),
  name        TEXT        NOT NULL UNIQUE,
  is_active   BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order  INT         NOT NULL DEFAULT 0,
  created_by  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TRIGGER trg_expense_categories_updated_at
  BEFORE UPDATE ON public.expense_categories
  FOR EACH ROW EXECUTE FUNCTION handle_updated_at();

ALTER TABLE public.expense_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "expense_categories: admin manages all"
  ON public.expense_categories FOR ALL
  USING (EXISTS (SELECT 1 FROM public.admin_profiles WHERE user_id = auth.uid()));

CREATE POLICY "expense_categories: authenticated reads active"
  ON public.expense_categories FOR SELECT
  USING (is_active = TRUE AND auth.role() = 'authenticated');

-- Farmers may add a new category inline from the Add Expense dropdown
-- (unlike farm_ownership_types, expense categories are the farmer's own
-- descriptive labels for their spending, not a fixed taxonomy) — mirrors
-- inventory_categories, which admin manages inline the same way.
CREATE POLICY "expense_categories: authenticated inserts"
  ON public.expense_categories FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

-- Seed with the categories already hardcoded in expenseCategories
INSERT INTO public.expense_categories (name, sort_order) VALUES
  ('Fertilizer', 1),
  ('Labor', 2),
  ('Seeds', 3),
  ('Tools', 4),
  ('Irrigation', 5),
  ('Transport', 6),
  ('Other', 7)
ON CONFLICT (name) DO NOTHING;

-- Drop the old hardcoded CHECK constraint so a category added at runtime
-- to expense_categories isn't rejected by a stale enum. Found dynamically
-- by column rather than by guessed constraint name, matching the same
-- pattern used in supabase_schema_category_lookup_tables.sql.
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT con.conname, con.conrelid::regclass::text AS tbl
    FROM pg_constraint con
    JOIN pg_attribute att
      ON att.attrelid = con.conrelid AND att.attnum = ANY(con.conkey)
    WHERE con.contype = 'c'
      AND con.conrelid = 'public.farmer_expenses'::regclass
      AND att.attname = 'category'
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I', r.tbl, r.conname);
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
