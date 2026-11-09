-- ============================================================
-- SAGANA — Program Management rework: PRE-FLIGHT (read-only)
--
-- Nothing here changes data. Run each numbered query by itself in the Supabase
-- SQL editor and send me the result (for 3 and 8, "Export CSV" is easiest).
-- I will not write any SQL for the rework until these are answered, because
-- many of these functions were redefined several times across scripts and the
-- repository copy may not be the live one.
-- ============================================================


-- ─── 1. Which migrations are live? (expect no NULLs if all were applied) ─────
SELECT
  to_regclass('public.loan_requests')                                   AS loan_requests,
  to_regclass('public.workflow_events')                                 AS workflow_events,
  to_regclass('public.program_enrollment_requests')                      AS enrollment_requests,
  to_regclass('public.cooperative_harvest_batches')                     AS harvest_batches,
  to_regclass('public.staff_permission_targets')                        AS permission_targets,
  to_regprocedure('public.review_loan_request(uuid,text,text,numeric,date,date)') AS review_loan_request,
  to_regprocedure('public.list_loanable_items()')                       AS list_loanable_items,
  to_regprocedure('public.staff_permission_gate()')                     AS permission_gate,
  to_regprocedure('public.audit_staff_change()')                        AS audit_trigger_fn;


-- ─── 2. Live columns of every table the rework touches ───────────────────────
SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('cooperative_programs', 'program_members', 'program_enrollment_requests',
                     'program_activities', 'farmer_loans', 'loan_requests', 'cooperative_inventory',
                     'loan_items_master')
ORDER BY table_name, ordinal_position;


-- ─── 3. Live definitions of the program / loan functions ─────────────────────
-- (large output — export as CSV)
SELECT p.proname, pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.prokind = 'f'
  AND p.proname IN ('distribute_program_benefit', 'record_program_thriving_outcome',
                    'confirm_program_return', 'respond_to_program_enrollment_request',
                    'submit_program_enrollment_request', 'convert_program_distribution_to_loan',
                    'issue_loan', 'submit_loan_request', 'review_loan_request')
ORDER BY p.proname;


-- ─── 4. Constraints, triggers and policies on those tables ───────────────────
SELECT 'constraint' AS kind, conrelid::regclass::text AS tbl, conname AS name, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid IN ('public.cooperative_programs'::regclass, 'public.program_members'::regclass,
                   'public.program_activities'::regclass, 'public.farmer_loans'::regclass,
                   'public.loan_requests'::regclass)
UNION ALL
SELECT 'trigger', event_object_table, trigger_name, action_timing || ' ' || event_manipulation
FROM information_schema.triggers
WHERE trigger_schema = 'public'
  AND event_object_table IN ('cooperative_programs', 'program_members', 'program_activities',
                             'program_enrollment_requests', 'farmer_loans', 'loan_requests')
UNION ALL
SELECT 'policy', tablename, policyname, cmd || ' | ' || COALESCE(qual, '') || ' | ' || COALESCE(with_check, '')
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('cooperative_programs', 'program_members', 'program_activities',
                    'program_enrollment_requests', 'loan_requests')
ORDER BY 1, 2, 3;


-- ─── 5. Is the Officer permission gate live, and which program/loan RPCs does it know? ──
SELECT rolname, rolconfig FROM pg_roles WHERE rolname = 'authenticator';   -- expect db_pre_request = staff_permission_gate
SELECT kind, name, module FROM public.staff_permission_targets
WHERE name ILIKE '%program%' OR name ILIKE '%loan%' ORDER BY kind, name;


-- ─── 6. What is in the existing programs? (drives the "Incomplete" rule) ─────
SELECT cp.program_name, cp.program_purpose, cp.benefit_type, cp.status,
       cp.budget IS NULL                                    AS no_budget,
       (cp.description IS NULL OR btrim(cp.description) = '') AS no_description,
       (cp.image_url IS NULL OR btrim(cp.image_url) = '')     AS no_photo,
       cp.distribution_category,
       (SELECT count(*) FROM program_members pm WHERE pm.program_id = cp.id)                         AS members,
       (SELECT count(*) FROM program_members pm WHERE pm.program_id = cp.id AND pm.distributed_at IS NOT NULL) AS distributed,
       (SELECT count(*) FROM program_members pm WHERE pm.program_id = cp.id AND pm.distribution_outcome = 'failed') AS failed,
       (SELECT count(*) FROM program_members pm WHERE pm.program_id = cp.id AND pm.converted_loan_id IS NOT NULL) AS converted_to_loan,
       (SELECT count(DISTINCT pm.inventory_item_id) FROM program_members pm WHERE pm.program_id = cp.id AND pm.inventory_item_id IS NOT NULL) AS distinct_items_given,
       (SELECT count(*) FROM program_activities pa WHERE pa.program_id = cp.id)                       AS activities
FROM cooperative_programs cp
ORDER BY cp.created_at;


-- ─── 7. What history already exists for programs? (do the DB audit triggers fire?) ──
SELECT source, table_name, operation, count(*) AS rows, min(created_at) AS first_seen
FROM admin_activity_log
WHERE module = 'programs'
GROUP BY source, table_name, operation
ORDER BY source, table_name, operation;


-- ─── 8. Storage: buckets and who may write to them (photo evidence design) ───
SELECT id, name, public, file_size_limit, allowed_mime_types FROM storage.buckets ORDER BY name;
SELECT policyname, cmd, COALESCE(qual, '') AS using_expr, COALESCE(with_check, '') AS check_expr
FROM pg_policies
WHERE schemaname = 'storage' AND tablename = 'objects'
ORDER BY policyname;


-- ─── 9. Staff accounts and anything that reacts to loans on a schedule ───────
SELECT role, status, count(*) FROM user_roles WHERE role IN ('admin', 'officer') GROUP BY role, status;

SELECT jobname, schedule, command FROM cron.job ORDER BY jobname;

SELECT p.proname
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace AND p.prokind = 'f'
  AND pg_get_functiondef(p.oid) ILIKE '%farmer_loans%'
  AND (pg_get_functiondef(p.oid) ILIKE '%overdue%' OR pg_get_functiondef(p.oid) ILIKE '%next_payment_date%')
ORDER BY p.proname;
