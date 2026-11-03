-- ============================================================
-- SAGANA — Officer permissions, script 22: STAFF ACCOUNTABILITY COVERS EVERY TAB
--
-- WHY
--   Staff Accountability (Manager only) is built from rows the database writes when a
--   Manager or Officer changes an audited table (script 05, 12). Checking it against
--   the request gate (script 02) showed what was NOT recorded yet:
--     * Marketplace: listings, listing edit requests, orders, cooperative offers,
--       member sales, market linking and DA-AMAD enrollments;
--     * Reports: the Balik-Tangkilik yearly settings and the payout result per member;
--     * the monthly BOD meeting reminder (sent by a scheduled job, so no person is
--       behind it).
--   Dashboard, Members and Loans were already covered (script 05 and 12), and the
--   Reports exports are already written by the app.
--
-- WHAT THIS DOES
--   1. Attaches the existing audit trigger (audit_staff_change) to the tables above.
--      It records ONLY a signed-in Manager or Officer: a Farmer's or Buyer's own
--      changes to the same tables (a Farmer's listing, a Buyer's order) are not
--      recorded, and neither are changes with no signed-in user.
--        Marketplace -> module 'marketplace'      Reports -> module 'reports'
--   2. member_contributions is audited on UPDATE only, and only when the payout result
--      changes (status, payout decision, actual Balik-Tangkilik / interest / purchase
--      patronage). Refreshing a member's estimate is routine and is not recorded.
--   3. The BOD reminder job (notify_bod_meeting_upcoming) is replaced by the SAME function
--      plus one log line per run: "BOD meeting reminder sent for <date> to N Farmers and
--      M staff", module 'system', actor "System". The notices themselves are unchanged.
--      Nothing is changed if the live function is not the one from batch10_01.
--
-- WHO SEES IT
--   Only the Manager (admin_activity_log already shows 'db' rows to the Manager alone).
--
-- LOCKS (a first version of this script hit "deadlock detected"):
--   Changing a trigger locks its table. The first version changed ten tables inside ONE
--   transaction, so the locks piled up while the live app was using the same tables in
--   another order. Now each table is its own short transaction (BEGIN ... COMMIT), a lock
--   is never waited for more than a few seconds, and a lock failure is retried after a
--   short pause. CREATE OR REPLACE TRIGGER (PostgreSQL 14+) is used where available, so
--   there is no moment without the audit trigger. Anything already done stays done: if a
--   step still fails, just run the script again.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor. Re-runnable.
-- To undo: DROP TRIGGER trg_audit_staff_change ON <table>; for the tables below, and run
-- batch10_01_bod_and_failed_outcome.sql's notify_bod_meeting_upcoming() again.
-- ============================================================

DO $$
DECLARE
  v_col text;
BEGIN
  IF to_regprocedure('public.audit_staff_change()') IS NULL THEN
    RAISE EXCEPTION 'audit_staff_change() is missing. Run officer_permissions_05 first.';
  END IF;
  IF to_regclass('public.admin_activity_log') IS NULL THEN
    RAISE EXCEPTION 'admin_activity_log is missing.';
  END IF;
  -- The payout result columns the member_contributions audit looks at.
  IF to_regclass('public.member_contributions') IS NOT NULL THEN
    FOREACH v_col IN ARRAY ARRAY['status', 'payout_decision', 'actual_balik_tangkilik',
                                 'actual_interest_on_capital', 'actual_purchase_patronage'] LOOP
      IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                     WHERE table_schema = 'public' AND table_name = 'member_contributions' AND column_name = v_col) THEN
        RAISE EXCEPTION 'member_contributions.% is missing.', v_col;
      END IF;
    END LOOP;
  END IF;
  -- The BOD function is replaced only if it is the one we know.
  IF to_regprocedure('public.notify_bod_meeting_upcoming(date)') IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM pg_proc
                   WHERE oid = 'public.notify_bod_meeting_upcoming(date)'::regprocedure
                     AND (prosrc LIKE '%BOD Meeting in 3 Days%' OR prosrc LIKE '%bod_system_log%')) THEN
      RAISE EXCEPTION 'notify_bod_meeting_upcoming() is not the batch10_01 version; check it before running this script.';
    END IF;
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════
-- Helper (lives only for this session): set the audit trigger on one table, retrying
-- when the table is busy. A table that does not exist is skipped with a notice.
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
      PERFORM set_config('lock_timeout', '4s', true);   -- never wait long for a busy table
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

-- ════════════════════════════════════════════════════════════
-- 1. Marketplace and Balik-Tangkilik tables (one short transaction each)
-- ════════════════════════════════════════════════════════════
BEGIN;
SELECT pg_temp.sagana_set_audit('marketplace_listings',
  'CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.marketplace_listings FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(''marketplace'', '''')');
COMMIT;
BEGIN;
SELECT pg_temp.sagana_set_audit('listing_edit_requests',
  'CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.listing_edit_requests FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(''marketplace'', '''')');
COMMIT;
BEGIN;
SELECT pg_temp.sagana_set_audit('orders',
  'CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.orders FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(''marketplace'', '''')');
COMMIT;
BEGIN;
SELECT pg_temp.sagana_set_audit('cooperative_purchase_offers',
  'CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.cooperative_purchase_offers FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(''marketplace'', '''')');
COMMIT;
BEGIN;
SELECT pg_temp.sagana_set_audit('member_sales_transactions',
  'CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.member_sales_transactions FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(''marketplace'', '''')');
COMMIT;
BEGIN;
SELECT pg_temp.sagana_set_audit('market_linking_programs',
  'CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.market_linking_programs FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(''marketplace'', '''')');
COMMIT;
BEGIN;
SELECT pg_temp.sagana_set_audit('market_linking_sales',
  'CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.market_linking_sales FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(''marketplace'', '''')');
COMMIT;
BEGIN;
SELECT pg_temp.sagana_set_audit('da_amad_enrollments',
  'CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.da_amad_enrollments FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(''marketplace'', '''')');
COMMIT;
BEGIN;
SELECT pg_temp.sagana_set_audit('cooperative_annual_totals',
  'CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.cooperative_annual_totals FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(''reports'', '''')');
COMMIT;

-- ════════════════════════════════════════════════════════════
-- 2. The payout result (UPDATE only, and only when it changes)
-- ════════════════════════════════════════════════════════════
BEGIN;
SELECT pg_temp.sagana_set_audit('member_contributions',
  'CREATE TRIGGER trg_audit_staff_change AFTER UPDATE ON public.member_contributions FOR EACH ROW '
  'WHEN (OLD.status IS DISTINCT FROM NEW.status '
  'OR OLD.payout_decision IS DISTINCT FROM NEW.payout_decision '
  'OR OLD.actual_balik_tangkilik IS DISTINCT FROM NEW.actual_balik_tangkilik '
  'OR OLD.actual_interest_on_capital IS DISTINCT FROM NEW.actual_interest_on_capital '
  'OR OLD.actual_purchase_patronage IS DISTINCT FROM NEW.actual_purchase_patronage) '
  'EXECUTE FUNCTION public.audit_staff_change(''reports'', '''')');
COMMIT;

-- ════════════════════════════════════════════════════════════
-- 3. The monthly BOD meeting reminder leaves one line per run
-- ════════════════════════════════════════════════════════════
-- Identical to batch10_01's function (same notices, same rules) plus the log line.
-- bod_system_log: marker so a later re-run recognises this version.
BEGIN;
SELECT set_config('lock_timeout', '4s', true);
DO $$
BEGIN
  IF to_regprocedure('public.notify_bod_meeting_upcoming(date)') IS NOT NULL THEN
    EXECUTE $fn$
CREATE OR REPLACE FUNCTION public.notify_bod_meeting_upcoming(p_today date DEFAULT CURRENT_DATE)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $body$
DECLARE
  v_meeting date := public.bod_next_meeting(p_today);
  v_count   integer := 0;
  v_staff   integer := 0;
  v_body    text;
BEGIN
  IF v_meeting - p_today <> 3 THEN
    RETURN 0;
  END IF;

  v_body := 'The BOD meeting is on ' || to_char(v_meeting, 'FMMonth DD, YYYY') || ' (in 3 days).';

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ur.user_id, 'loan', 'BOD Meeting in 3 Days', v_body, FALSE, NOW(), '/farmer/profile/loans'
  FROM user_roles ur
  WHERE ur.role = 'farmer' AND ur.status = 'active';
  GET DIAGNOSTICS v_count = ROW_COUNT;

  INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
  SELECT ur.user_id, 'system', 'BOD Meeting in 3 Days', v_body, FALSE, NOW(), '/admin/loans'
  FROM user_roles ur
  WHERE ur.role IN ('admin', 'officer');
  GET DIAGNOSTICS v_staff = ROW_COUNT;

  -- bod_system_log: one accountability line for this run. A failure here never
  -- stops the notices.
  BEGIN
    INSERT INTO admin_activity_log (
      admin_id, module, action_type, description, actor_role, actor_name,
      table_name, operation, reference_label, new_values, source
    ) VALUES (
      NULL, 'system', 'bod_reminder',
      'BOD meeting reminder sent for ' || to_char(v_meeting, 'FMMonth DD, YYYY')
        || ' to ' || v_count || ' Farmers and ' || v_staff || ' staff',
      'system', 'System', 'notifications', 'created', to_char(v_meeting, 'YYYY-MM-DD'),
      jsonb_build_object('meeting_date', v_meeting, 'farmers', v_count, 'staff', v_staff), 'db'
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'BOD reminder log failed: %', SQLERRM;
  END;

  RETURN v_count;
END;
$body$;
$fn$;
  ELSE
    RAISE NOTICE 'notify_bod_meeting_upcoming() not found; the BOD reminder line was not added.';
  END IF;
END
$$;
COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only; run each by itself) ────────────────────────
--   SELECT event_object_table, count(*) FROM information_schema.triggers
--   WHERE trigger_name = 'trg_audit_staff_change' GROUP BY 1 ORDER BY 1;
--   -- now also: cooperative_annual_totals, cooperative_purchase_offers, da_amad_enrollments,
--   --   listing_edit_requests, market_linking_programs, market_linking_sales, marketplace_listings,
--   --   member_contributions, member_sales_transactions, orders
--   SELECT prosrc LIKE '%bod_system_log%' FROM pg_proc WHERE proname = 'notify_bod_meeting_upcoming';  -- true
-- In the app (Manager): Staff Accountability > Marketplace shows listing, order and offer
-- actions by Managers and Officers; Reports shows Balik-Tangkilik changes and exports;
-- System shows the BOD reminder line. A Farmer listing or a Buyer order never appears.
-- ─────────────────────────────────────────────────────────────────────────
