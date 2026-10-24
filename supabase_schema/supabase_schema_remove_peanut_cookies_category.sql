-- ============================================================
-- SAGANA — Remove the "Peanut Cookies" inventory CATEGORY
--
-- Live check results: "Peanut Cookies" exists twice.
--   * an inventory CATEGORY row (inventory_categories, created 2026-09-17), and
--   * an inventory ITEM named Peanut Cookies in the category "Product Sales"
--     (90 sacks), which has a Product Sales listing and a purchase.
-- The item has purchase history, so it cannot be deleted without destroying a
-- purchase record. This script removes only the category row, and only if
-- nothing uses it. It touches no other category and no inventory item.
--
-- Categories are stored as plain text on the consuming tables (not foreign
-- keys), so "nothing uses it" is checked by name against every table that
-- stores an inventory category.
-- ============================================================

-- 1. READ-ONLY: who uses the category name today? (expect all zeros)
SELECT 'cooperative_inventory.category' AS used_by, count(*) AS rows
FROM public.cooperative_inventory WHERE lower(category) = 'peanut cookies'
UNION ALL
SELECT 'cooperative_programs.distribution_category', count(*)
FROM public.cooperative_programs WHERE lower(distribution_category) = 'peanut cookies';
-- (loan_items_master has no category column of its own; a loan-catalog item
--  takes its category from its cooperative_inventory row, checked above.)

-- 2. REMOVE — deletes the category only if step 1 is all zeros; otherwise it
--    deletes nothing. Returns the row it removed (zero rows = nothing removed).
DELETE FROM public.inventory_categories ic
WHERE lower(ic.name) = 'peanut cookies'
  AND NOT EXISTS (SELECT 1 FROM public.cooperative_inventory  WHERE lower(category) = lower(ic.name))
  AND NOT EXISTS (SELECT 1 FROM public.cooperative_programs   WHERE lower(distribution_category) = lower(ic.name))
RETURNING ic.id, ic.name;

-- 3. READ-ONLY: confirm the category is gone and the item is untouched
--    (expect 0 rows, then 1 row).
SELECT * FROM public.inventory_categories WHERE lower(name) = 'peanut cookies';
SELECT id, item_name, category, is_active FROM public.cooperative_inventory
WHERE item_name ILIKE '%peanut%cookie%';
