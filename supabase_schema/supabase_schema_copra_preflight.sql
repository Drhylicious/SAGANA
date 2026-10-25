-- ============================================================
-- SAGANA — Copra removal: read-only preflight (changes nothing)
-- Run in the Supabase SQL editor and send back all four result sets.
-- ============================================================

-- 1. The Copra row(s) in the crop catalog.
SELECT id, crop_name, category, crop_type, is_active, exclusive_channel, sort_order, created_at
FROM public.crop_master
WHERE crop_name ILIKE '%copra%';

-- 2. Every foreign key that points at crop_master (what could be affected by
--    archiving or deleting a catalog row), with its delete rule.
SELECT c.conrelid::regclass::text AS referencing_table,
       a.attname                  AS column_name,
       CASE c.confdeltype WHEN 'a' THEN 'NO ACTION' WHEN 'r' THEN 'RESTRICT'
         WHEN 'c' THEN 'CASCADE' WHEN 'n' THEN 'SET NULL' WHEN 'd' THEN 'SET DEFAULT' END AS on_delete
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
WHERE c.contype = 'f' AND c.confrelid = 'public.crop_master'::regclass
ORDER BY 1, 2;

-- 3. Every text column in the public schema that mentions "copra", with how many
--    rows do. This finds farmer crops, price records, harvests, inventory
--    batches, listings, offers, orders and anything else, without guessing
--    table names.
SELECT table_name, column_name, matches
FROM (
  SELECT c.table_name, c.column_name,
         (xpath('/row/n/text()', query_to_xml(
            format('SELECT count(*) AS n FROM %I.%I WHERE %I::text ILIKE %L',
                   c.table_schema, c.table_name, c.column_name, '%copra%'),
            false, true, '')))[1]::text::int AS matches
  FROM information_schema.columns c
  JOIN information_schema.tables t
    ON t.table_schema = c.table_schema AND t.table_name = c.table_name
   AND t.table_type = 'BASE TABLE'
  WHERE c.table_schema = 'public'
    AND c.data_type IN ('text', 'character varying')
) s
WHERE matches > 0
ORDER BY table_name, column_name;

-- 4. Whether any record of a real transaction mentions Copra: price records
--    (shown to Farmers and Buyers as market rates) and the farmers who list it
--    as a crop they grow.
SELECT 'price_records' AS source, COUNT(*) AS rows_found
FROM public.price_records WHERE crop_name ILIKE '%copra%'
UNION ALL
SELECT 'farmer_crops', COUNT(*)
FROM public.farmer_crops WHERE crop_name ILIKE '%copra%';
