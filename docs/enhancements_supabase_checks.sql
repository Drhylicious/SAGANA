-- SAGANA enhancements: read-only compatibility checks.
-- No migration or data change is performed by this file.
-- These queries have NOT been executed against the live Supabase database.
-- Review missing prerequisites against the current deployed schema; do not
-- blindly reapply old migrations, which may replace newer business logic.

-- 1. Required transaction tables. Every table_exists should be true.
WITH required(table_name) AS (
  VALUES ('harvest_records'), ('inventory_batches'), ('farmer_expenses'),
         ('farmer_loans'), ('farmer_loan_payments'),
         ('capital_contribution_events'), ('member_capital_shares'),
         ('user_roles'), ('officer_permissions')
)
SELECT table_name, to_regclass('public.' || table_name) IS NOT NULL AS table_exists
FROM required ORDER BY table_name;

-- 2. Existing loan RPC signatures and authenticated execute privileges.
-- issue_loan and record_loan_payment must include p_idempotency_key text.
-- ping is optional: an HTTP error response also proves reachability.
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS arguments,
       pg_get_function_result(p.oid) AS returns,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('issue_loan', 'record_loan_payment', 'ping')
ORDER BY p.proname, arguments;

-- 3. Inspect the CURRENT loan definitions: preserve authorization, active-member
-- checks, stock checks, balance/overpayment checks, row locks, and replay lookup.
SELECT p.proname, pg_get_functiondef(p.oid) AS current_definition
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('issue_loan', 'record_loan_payment')
ORDER BY p.proname, p.oid;

-- 4. Primary/unique constraints. Expect id primary keys on harvest_records,
-- farmer_expenses, inventory_batches and capital_contribution_events, plus
-- unique idempotency_key on farmer_loans and farmer_loan_payments and a unique
-- inventory batch number. Equivalent unique indexes are listed in query 5.
SELECT c.conrelid::regclass AS table_name, c.conname, c.contype,
       pg_get_constraintdef(c.oid) AS definition
FROM pg_constraint c JOIN pg_namespace n ON n.oid = c.connamespace
WHERE n.nspname = 'public' AND c.contype IN ('p', 'u')
  AND c.conrelid IN (
    to_regclass('public.harvest_records'), to_regclass('public.inventory_batches'),
    to_regclass('public.farmer_expenses'), to_regclass('public.farmer_loans'),
    to_regclass('public.farmer_loan_payments'),
    to_regclass('public.capital_contribution_events'))
ORDER BY table_name, c.conname;

-- 5. Unique indexes also enforce replay identity and stock-batch uniqueness.
SELECT tablename, indexname, indexdef FROM pg_indexes
WHERE schemaname = 'public' AND indexdef ILIKE '%UNIQUE%'
  AND tablename IN ('harvest_records', 'inventory_batches', 'farmer_expenses',
                    'farmer_loans', 'farmer_loan_payments', 'capital_contribution_events')
ORDER BY tablename, indexname;

-- 6. RLS must remain enabled. Policies must preserve role/module permissions
-- and farmer ownership; the client cache never replaces server authorization.
SELECT c.relname AS table_name, c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS force_rls
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('harvest_records', 'inventory_batches', 'farmer_expenses',
                    'farmer_loans', 'farmer_loan_payments', 'capital_contribution_events',
                    'member_capital_shares', 'user_roles', 'officer_permissions')
ORDER BY c.relname;

SELECT tablename, policyname, roles, cmd, qual, with_check FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('harvest_records', 'inventory_batches', 'farmer_expenses',
                    'farmer_loans', 'farmer_loan_payments', 'capital_contribution_events',
                    'member_capital_shares', 'user_roles', 'officer_permissions')
ORDER BY tablename, policyname;

-- 7. Existing trigger definitions: harvest numbering/units, stock inheritance,
-- and capital-total maintenance must remain enabled and intact.
SELECT t.tgrelid::regclass AS table_name, t.tgname, t.tgenabled,
       pg_get_triggerdef(t.oid) AS definition
FROM pg_trigger t
WHERE NOT t.tgisinternal AND t.tgrelid IN (
  to_regclass('public.harvest_records'), to_regclass('public.inventory_batches'),
  to_regclass('public.capital_contribution_events'))
ORDER BY table_name, t.tgname;

-- 8. Read-only RPC snapshot coverage. Every rpc_exists should be true on a
-- fully deployed schema. Only these explicit functions can be cached.
-- get_my_staff_permissions and user_roles account-status reads are deliberately
-- excluded from transport snapshots: authorization/status checks stay live.
WITH required(rpc_name) AS (
  VALUES ('get_cooperative_details'), ('get_delivery_status'), ('get_delivery_quote'),
         ('get_supply_chain_records'), ('get_supply_chain_totals'),
         ('get_programs_completion_status'), ('get_program_returns'),
         ('get_failed_resolutions'), ('get_my_assistance_options'),
         ('get_my_assistance_requests'), ('get_assistance_requests'),
         ('list_loanable_items'), ('get_my_loan_requests'),
         ('get_program_product_stats'), ('get_my_program_returns'),
         ('get_my_outcome_reports'), ('get_my_marketplace_buyer_names'),
         ('get_program_outcome_reports'), ('get_program_history'),
         ('get_my_activity_share'), ('get_manager_sign_in_emails'),
         ('get_my_listing_edit_requests'), ('get_my_listing_history'),
         ('get_officer_permissions')
)
SELECT r.rpc_name, p.oid IS NOT NULL AS rpc_exists,
       pg_get_function_identity_arguments(p.oid) AS arguments,
       p.provolatile, -- 's' = stable, 'i' = immutable; inspect any 'v' definition.
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute
FROM required r
LEFT JOIN pg_namespace n ON n.nspname = 'public'
LEFT JOIN pg_proc p ON p.pronamespace = n.oid AND p.proname = r.rpc_name
ORDER BY r.rpc_name, arguments;

-- 9. Data integrity diagnostics. The first two queries should return no rows.
-- The harvest/batch query reports existing incomplete or duplicate links for
-- review; it does NOT delete, combine, or repair stock or financial records.
SELECT idempotency_key, count(*) FROM public.farmer_loans
WHERE idempotency_key IS NOT NULL
GROUP BY idempotency_key HAVING count(*) > 1;

SELECT idempotency_key, count(*) FROM public.farmer_loan_payments
WHERE idempotency_key IS NOT NULL
GROUP BY idempotency_key HAVING count(*) > 1;

SELECT h.id AS harvest_id, count(b.id) AS batch_count
FROM public.harvest_records h
LEFT JOIN public.inventory_batches b ON b.harvest_record_id = h.id
GROUP BY h.id HAVING count(b.id) <> 1
ORDER BY h.id;
