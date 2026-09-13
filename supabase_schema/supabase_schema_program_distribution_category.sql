-- ============================================================
-- SAGANA — Program Management: database-driven distribution category
-- (Admin Dashboard investigation, Issue 3 / Phase 4)
--
-- Problem: the "Distribute Benefit" dropdown in Program Management showed
-- every active cooperative_inventory item regardless of the program's
-- purpose (e.g. a "Peanut Seed Distribution" program's Distribute dialog
-- would also offer fertilizer, pesticide, tools, etc.). program_type is a
-- free-text label (e.g. "Peanut", "Livestock") and doesn't reliably match
-- cooperative_inventory.category's fixed vocabulary, so filtering couldn't
-- be based on it without hardcoding a name-matching table.
--
-- Fix: add a nullable distribution_category column to cooperative_programs,
-- constrained to the SAME category vocabulary already enforced on
-- cooperative_inventory.category (see supabase_schema_programs.sql). This
-- is the single source of truth both screens now read from — no separate
-- mapping table, no hardcoded category lists in application code. Nullable
-- so existing programs are unaffected (a null category means "no filter,
-- show all items", matching current behavior) until an admin explicitly
-- sets one via the program's "Distributes From" field.
-- ============================================================

ALTER TABLE public.cooperative_programs
  ADD COLUMN IF NOT EXISTS distribution_category TEXT
  CHECK (distribution_category IN (
    'Fertilizer', 'Seeds', 'Animal Feeds',
    'Pesticide', 'Tools & Equipment', 'Agricultural Supplies', 'Harvest Stock'
  ));

COMMENT ON COLUMN public.cooperative_programs.distribution_category IS
  'Optional cooperative_inventory.category filter for this program''s '
  'Distribute Benefit picker. Null = no filter (all active items shown).';
