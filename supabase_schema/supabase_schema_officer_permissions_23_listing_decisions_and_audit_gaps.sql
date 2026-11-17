-- ============================================================
-- SAGANA — Officer permissions, script 23:
--   LISTING DECISIONS FOR EVERY OFFICER + TWO MISSING AUDIT TRIGGERS
--
-- WHAT YOUR CHECKS SHOWED (Nov 15 2026)
--   * Officer "Arisu Yamabuki" has no admin_profiles row. The current Officer-creation
--     function no longer creates one (Officers made by the older script got it from the
--     backfill in phase_d2).
--   * Exactly four functions still test that row and nothing else:
--         approve_listing(uuid)               reject_listing(uuid, text)
--         admin_update_listing_price(uuid, numeric)   request_listing_changes(uuid, text)
--     So an Officer with Marketplace = Manage, created after that change, is refused with
--     "only Managers can ..." while an older Officer is not. No policy depends on the row.
--   * request_listing_changes() was not in the Officer gate, so a View Only Officer could
--     call it directly.
--   * program_types and shelf_life_settings (the expiry-day discount) are changed by staff
--     but were not in the accountability trail.
--
-- WHAT THIS DOES
--   1. Changes ONLY the permission test inside those four functions, from "has an
--      admin_profiles row" to public.is_staff(). The function bodies are read from YOUR
--      LIVE database (pg_get_functiondef) and changed in place, so nothing newer is
--      overwritten. If a function does not look as expected, nothing is changed and the
--      script stops with a message.
--      View Only versus Manage is still decided by the Officer gate (staff_permission_targets,
--      module marketplace), exactly as for every other Marketplace action.
--   2. Registers request_listing_changes under Marketplace in that gate.
--   3. Adds the audit trigger to program_types (module programs) and shelf_life_settings
--      (module crops), one short transaction each, with the same lock-safe retry as script 22.
--
-- NOT CHANGED: the wording of the refusal messages, any policy, any table, any other function.
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Re-runnable.
-- ============================================================

DO $$
DECLARE
  v_sig text;
BEGIN
  IF to_regprocedure('public.is_staff()') IS NULL THEN
    RAISE EXCEPTION 'is_staff() is missing.';
  END IF;
  IF to_regclass('public.staff_permission_targets') IS NULL THEN
    RAISE EXCEPTION 'staff_permission_targets is missing. Run officer_permissions_02 first.';
  END IF;
  IF to_regprocedure('public.audit_staff_change()') IS NULL THEN
    RAISE EXCEPTION 'audit_staff_change() is missing. Run officer_permissions_05 first.';
  END IF;
  FOREACH v_sig IN ARRAY ARRAY[
    'public.approve_listing(uuid)',
    'public.reject_listing(uuid,text)',
    'public.admin_update_listing_price(uuid,numeric)',
    'public.request_listing_changes(uuid,text)'
  ] LOOP
    IF to_regprocedure(v_sig) IS NULL THEN
      RAISE EXCEPTION '% is missing.', v_sig;
    END IF;
  END LOOP;
END $$;

-- ════════════════════════════════════════════════════════════
-- 1 + 2. The four listing functions, and the gate
-- ════════════════════════════════════════════════════════════
BEGIN;
SELECT set_config('lock_timeout', '5s', true);

DO $$
DECLARE
  v_sig text;
  v_def text;
  v_new text;
BEGIN
  FOREACH v_sig IN ARRAY ARRAY[
    'public.approve_listing(uuid)',
    'public.reject_listing(uuid,text)',
    'public.admin_update_listing_price(uuid,numeric)',
    'public.request_listing_changes(uuid,text)'
  ] LOOP
    v_def := pg_get_functiondef(v_sig::regprocedure);
    IF v_def NOT ILIKE '%admin_profiles%' THEN
      RAISE NOTICE '% already has no admin_profiles test; left as it is.', v_sig;
      CONTINUE;
    END IF;
    v_new := regexp_replace(
      v_def,
      'NOT\s+EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+(?:public\.)?admin_profiles\s+WHERE\s+user_id\s*=\s*auth\.uid\(\)\s*\)',
      'NOT public.is_staff()',
      'gi'
    );
    IF v_new = v_def OR v_new ILIKE '%admin_profiles%' THEN
      RAISE EXCEPTION '% does not have the expected permission test; nothing was changed. Send me its definition.', v_sig;
    END IF;
    EXECUTE v_new;
    RAISE NOTICE '% now uses is_staff().', v_sig;
  END LOOP;
END $$;

INSERT INTO public.staff_permission_targets (kind, name, module)
VALUES ('rpc', 'request_listing_changes', 'marketplace')
ON CONFLICT (kind, name) DO NOTHING;

COMMIT;

-- ════════════════════════════════════════════════════════════
-- 3. Audit triggers (one short transaction per table)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION pg_temp.sagana_set_audit(p_tbl text, p_def text)
RETURNS void
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_try int;
BEGIN
  IF to_regclass('public.' || p_tbl) IS NULL THEN
    RAISE NOTICE 'audit trigger skipped, table not found: %', p_tbl;
    RETURN;
  END IF;
  FOR v_try IN 1..8 LOOP
    BEGIN
      PERFORM set_config('lock_timeout', '4s', true);
      IF current_setting('server_version_num')::int >= 140000 THEN
        EXECUTE regexp_replace(p_def, '^CREATE TRIGGER', 'CREATE OR REPLACE TRIGGER');
      ELSE
        EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.%I', p_tbl);
        EXECUTE p_def;
      END IF;
      RETURN;
    EXCEPTION WHEN deadlock_detected OR lock_not_available THEN
      IF v_try = 8 THEN
        RAISE;
      END IF;
      RAISE NOTICE 'table % is busy, trying again (%/8)', p_tbl, v_try;
      PERFORM pg_sleep(1 + random() * 2);
    END;
  END LOOP;
END
$fn$;

BEGIN;
SELECT pg_temp.sagana_set_audit('program_types',
  'CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.program_types FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(''programs'', '''')');
COMMIT;

BEGIN;
SELECT pg_temp.sagana_set_audit('shelf_life_settings',
  'CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.shelf_life_settings FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(''crops'', '''')');
COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only; run each by itself) ────────────────────────
--   SELECT p.oid::regprocedure FROM pg_proc p
--   WHERE p.pronamespace = 'public'::regnamespace AND p.prosrc ILIKE '%admin_profiles%'
--     AND p.prosrc NOT ILIKE '%insert into%admin_profiles%';            -- expect no rows
--   SELECT name, module FROM staff_permission_targets WHERE name = 'request_listing_changes';   -- marketplace
--   SELECT event_object_table FROM information_schema.triggers
--   WHERE trigger_name = 'trg_audit_staff_change' AND event_object_table IN ('program_types','shelf_life_settings')
--   GROUP BY 1;                                                         -- both tables
-- In the app: sign in as Arisu (Marketplace = Manage) and approve a pending listing: it works;
-- with Marketplace = View Only the same action is refused with the view-only message.
-- ─────────────────────────────────────────────────────────────────────────
