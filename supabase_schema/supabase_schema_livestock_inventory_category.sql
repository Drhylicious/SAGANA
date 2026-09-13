-- ============================================================
-- SAGANA — Add "Livestock" as an Inventory Management category
-- (Admin Dashboard investigation, Program Management dropdown review)
--
-- The Livestock Dispersal program distributes actual animals (piglets,
-- etc.) to members, not feed for animals — a genuinely different concept
-- from the existing "Animal Feeds" category (which covers feed/nutrition
-- inputs). Without this, a livestock item had no correct category to be
-- filed under in Inventory Management, and no way for a Livestock program
-- to filter its Distribute dropdown correctly via distribution_category.
--
-- This demonstrates the category set is extendable via migration + a
-- matching update to AppConstants.inventoryCategories (see the Dart
-- constant) — see the accompanying investigation notes on whether this
-- should eventually become a true admin-managed lookup table instead of a
-- CHECK constraint enum.
-- ============================================================

ALTER TABLE public.cooperative_inventory
  DROP CONSTRAINT IF EXISTS cooperative_inventory_category_check;
ALTER TABLE public.cooperative_inventory
  ADD CONSTRAINT cooperative_inventory_category_check2
  CHECK (category IN (
    'Fertilizer', 'Seeds', 'Animal Feeds', 'Pesticide',
    'Tools & Equipment', 'Agricultural Supplies', 'Harvest Stock', 'Livestock'
  ));

-- cooperative_programs.distribution_category shares the same vocabulary
-- (see supabase_schema_program_distribution_category.sql) so a Livestock
-- program can filter its Distribute dropdown to this category too.
ALTER TABLE public.cooperative_programs
  DROP CONSTRAINT IF EXISTS cooperative_programs_distribution_category_check2;
ALTER TABLE public.cooperative_programs
  ADD CONSTRAINT cooperative_programs_distribution_category_check3
  CHECK (distribution_category IN (
    'Fertilizer', 'Seeds', 'Animal Feeds', 'Pesticide',
    'Tools & Equipment', 'Agricultural Supplies', 'Harvest Stock', 'Livestock'
  ));

NOTIFY pgrst, 'reload schema';
