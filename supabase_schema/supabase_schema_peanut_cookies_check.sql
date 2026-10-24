-- ============================================================
-- SAGANA — "Peanut Cookies": find it and check what depends on it
--
-- READ-ONLY (steps 1-3). Nothing in the repository's SQL or Dart code creates
-- an item named "Peanut Cookies"; it only appears in a comment as an example of
-- a Product Sales product. So it is live data, and where it lives decides how
-- it can be removed. Run steps 1-3 and send the results back BEFORE running
-- step 4.
-- ============================================================

-- 1. Where does the name exist? (expect hits in cooperative_inventory and
--    possibly program_products / loan_items_master via their inventory link)
SELECT 'cooperative_inventory' AS source_table, id, item_name, category, unit,
       quantity_on_hand, is_active
FROM public.cooperative_inventory
WHERE item_name ILIKE '%peanut%cookie%';

SELECT 'crop_master' AS source_table, id, crop_name AS item_name
FROM public.crop_master WHERE crop_name ILIKE '%cookie%';

SELECT 'inventory_categories' AS source_table, *
FROM public.inventory_categories WHERE name ILIKE '%cookie%';

SELECT 'loan_items_master' AS source_table, lim.id, ci.item_name
FROM public.loan_items_master lim
JOIN public.cooperative_inventory ci ON ci.id = lim.inventory_item_id
WHERE ci.item_name ILIKE '%peanut%cookie%';

-- 2. Everything that points at it (one row per dependency; empty = none).
WITH item AS (
  SELECT id FROM public.cooperative_inventory WHERE item_name ILIKE '%peanut%cookie%'
)
SELECT 'inventory_transactions (deleted with the item)' AS dependency, count(*) AS rows
FROM public.inventory_transactions t JOIN item i ON i.id = t.inventory_id
UNION ALL
SELECT 'loan_items_master (loan catalog entry)', count(*)
FROM public.loan_items_master l JOIN item i ON i.id = l.inventory_item_id
UNION ALL
SELECT 'program_products (product-sales listing)', count(*)
FROM public.program_products p JOIN item i ON i.id = p.inventory_item_id
UNION ALL
SELECT 'program_product_purchases (BLOCKS deletion)', count(*)
FROM public.program_product_purchases ppp
JOIN public.program_products p ON p.id = ppp.product_id
JOIN item i ON i.id = p.inventory_item_id
UNION ALL
SELECT 'program_members distribution (kept; item link set to NULL)', count(*)
FROM public.program_members pm JOIN item i ON i.id = pm.inventory_item_id
UNION ALL
SELECT 'cooperative_programs.distribution link', count(*)
FROM public.cooperative_programs cp
WHERE cp.id IN (SELECT program_id FROM public.program_products p JOIN item i ON i.id = p.inventory_item_id);

-- 3. Farmer loans that already issued it (history is snapshotted in
--    farmer_loan_items, so these are NOT affected by deleting the item):
SELECT count(*) AS loan_lines_snapshotted
FROM public.farmer_loan_items WHERE item_name ILIKE '%peanut%cookie%';

-- ------------------------------------------------------------
-- 4. REMOVAL — only after steps 1-3 are reviewed.
--
--    Preferred: use the app (Admin > Inventory > item menu > Delete). It calls
--    delete_inventory_item(), which refuses with CANNOT_DELETE_HAS_PURCHASE_HISTORY
--    when any Product Sales purchase exists, and otherwise removes, in order:
--    its program_products rows, its loan_items_master row, then the item
--    (inventory_transactions go with it). Other items are not touched.
--
--    If the app route is blocked by purchase history, the item must be
--    DEACTIVATED instead (the app offers this); deleting it would destroy real
--    purchase records.
--
--    Equivalent SQL, scoped to exactly one row by id (replace the id). Run only
--    if step 2 shows 0 for 'program_product_purchases'.
--
--    BEGIN;
--      SELECT public.delete_inventory_item('00000000-0000-0000-0000-000000000000'::uuid);
--      -- confirm exactly one item disappeared, then:
--    COMMIT;   -- or ROLLBACK;
-- ------------------------------------------------------------
