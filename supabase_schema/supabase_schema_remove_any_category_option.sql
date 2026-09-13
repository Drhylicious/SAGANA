-- ============================================================
-- SAGANA — Remove "Any category" placeholder option
-- (Program Management — "Distributes From" dropdown)
--
-- "Any category" was never a real category — it was a UI-only sentinel
-- ('__any__' in program_management_screen.dart) meaning "no category
-- filter", always converted to NULL before being saved to
-- cooperative_programs.distribution_category. The app itself never wrote
-- the literal text "Any category" anywhere. The only way it could exist
-- as a real row in inventory_categories is if someone used the new
-- inline "Add new category" prompt and typed "Any category" as if it
-- were a real category name.
--
-- This removes only that one specific name, wherever it may have landed
-- — every other category, and every program's actual chosen category,
-- is left untouched.
-- ============================================================

-- Remove it as a selectable inventory category, if it was ever added
-- this way. No-op if it was never added (the app-defined sentinel is
-- never persisted here on its own).
DELETE FROM public.inventory_categories WHERE name = 'Any category';

-- Defensive guard: null out distribution_category on any program where
-- it was somehow literally set to 'Any category' rather than NULL. Not
-- expected from normal app usage (the app always converts the sentinel
-- to NULL before saving) — this only protects against a stray manual
-- edit or an inconsistent state from before this fix.
UPDATE public.cooperative_programs
SET distribution_category = NULL
WHERE distribution_category = 'Any category';

NOTIFY pgrst, 'reload schema';
