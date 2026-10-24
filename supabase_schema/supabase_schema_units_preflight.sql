-- ============================================================
-- SAGANA — Units: read-only preflight (changes nothing)
-- Run in the Supabase SQL editor BEFORE supabase_schema_units.sql and send the
-- three result sets back.
-- ============================================================

-- 1. Every CHECK constraint on a column named "unit". The loan catalog
--    historically limited unit to 7 fixed values; this shows whether that (or
--    any other) constraint is still on a table.
SELECT c.conrelid::regclass::text AS table_name,
       c.conname                  AS constraint_name,
       pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
WHERE c.contype = 'c'
  AND a.attname = 'unit'
  AND c.connamespace = 'public'::regnamespace
ORDER BY 1, 2;

-- 2. Which units are in use today, per table.
SELECT 'cooperative_inventory' AS source, unit, COUNT(*) AS rows_using
FROM public.cooperative_inventory GROUP BY unit
UNION ALL
SELECT 'price_records', unit, COUNT(*) FROM public.price_records GROUP BY unit
ORDER BY source, rows_using DESC;

-- 3. Whether a units table already exists, and whether the helper functions
--    the migration relies on are present.
SELECT to_regclass('public.units')                   AS units_table,
       to_regprocedure('public.is_staff()')          AS is_staff_fn,
       to_regprocedure('public.handle_updated_at()') AS updated_at_fn;
