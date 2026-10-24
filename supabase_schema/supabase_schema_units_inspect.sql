-- ============================================================
-- SAGANA — Units: inspect the EXISTING public.units table (read-only)
-- The preflight found that public.units already exists. Run this and send back
-- all five result sets BEFORE running supabase_schema_units.sql.
-- ============================================================

-- 1. Its columns.
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'units'
ORDER BY ordinal_position;

-- 2. Its rows.
SELECT * FROM public.units LIMIT 50;

-- 3. Constraints and indexes on it.
SELECT 'constraint' AS kind, conname AS name, pg_get_constraintdef(oid) AS definition
FROM pg_constraint WHERE conrelid = 'public.units'::regclass
UNION ALL
SELECT 'index', indexname, indexdef
FROM pg_indexes WHERE schemaname = 'public' AND tablename = 'units';

-- 4. Row-level-security policies and triggers on it.
SELECT 'policy' AS kind, policyname AS name, cmd || ' / ' || COALESCE(qual, '') AS detail
FROM pg_policies WHERE schemaname = 'public' AND tablename = 'units'
UNION ALL
SELECT 'trigger', tgname, pg_get_triggerdef(oid)
FROM pg_trigger WHERE tgrelid = 'public.units'::regclass AND NOT tgisinternal;

-- 5. Do the guard triggers from the migration already exist on the two tables?
SELECT tgrelid::regclass::text AS on_table, tgname
FROM pg_trigger
WHERE tgname IN ('trg_cooperative_inventory_known_unit', 'trg_price_records_known_unit');
