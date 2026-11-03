-- ============================================================
-- SAGANA — Officer permissions, script 5 of 6: STAFF ACCOUNTABILITY
--
-- Requires script 01 (and 04 for the account_creation_requests audit). RUN THIS BEFORE
-- deleting the old Officer account: the name backfill below copies each staff
-- member's name onto the existing log rows, so it survives their deletion.
--
-- REUSES the existing audit table, admin_activity_log (it already carries the
-- acting staff member in admin_id, the module, the action and the record). No
-- second audit system is created. The table gains structured columns and a
-- database-side writer:
--
--   source = 'app'  the existing human-readable rows the app writes after an
--                   action (Recent Activity feed). Unchanged. Written by the
--                   client, so they are best-effort.
--   source = 'db'   NEW. Written by a trigger inside the same transaction as the
--                   change, so a Manager/Officer change to an audited table is
--                   ALWAYS recorded, whichever screen, RPC or script made it.
--                   Carries who (id, name, role), what (table, operation,
--                   record id + reference), before/after values and when.
--
-- 'db' rows can only be written by the trigger: the insert policy now refuses
-- any client row that is not source = 'app'. Nobody can update or delete log
-- rows (no policy exists), so the trail cannot be edited.
--
-- WHO CAN READ THE TRAIL: 'db' rows (who did what, with before/after values)
-- are readable by the MANAGER ONLY. 'app' rows keep their current visibility
-- (they feed each person's own Recent Activity).
--
-- APPROVAL HISTORY: member_status_events (approve / disapprove / suspend of a
-- member, including outsider applications) gains actor_name and actor_role,
-- copied from the staff member at the time, so the Manager's history in Farmer
-- Details names the person even after that account is removed. That table is
-- not readable by Officers.
--
-- AUDITED TABLES (module key in brackets — the keys the app already uses)
--   crop_master, crop_categories, crop_requests ........ [crops]
--   cooperative_inventory, inventory_transactions,
--     inventory_categories, units ...................... [inventory]
--   cooperative_programs, program_activities,
--     program_members, program_products,
--     program_product_purchases,
--     program_enrollment_requests ...................... [programs]
--   loan_items_master, farmer_loans, farmer_loan_payments,
--     loan_requests, loan_policy_settings .............. [loans]
--   price_records ...................................... [prices]
--   broadcast_logs ..................................... [broadcast]
--   user_roles (staff changes only), member_capital_shares,
--     capital_contribution_events, password_reset_requests,
--     officer_permissions .............................. [members]
--
-- Marketplace (listings, orders, offers, market linking) is NOT added here: it
-- already has its own server-side trail, workflow_events (actor id + role,
-- from/to status), written by the SECURITY DEFINER code. Duplicating it would
-- create two competing trails for the same events.
--
-- Only changes made by a signed-in Manager or Officer are recorded; Farmer and
-- Buyer activity on the same tables is not.
--
-- NOT APPLIED AUTOMATICALLY. Run in the Supabase SQL editor.
-- ============================================================

-- ─── PRE-FLIGHT (read-only; run by itself) ───────────────────────────────
-- A. Current admin_activity_log columns and policies:
--    SELECT column_name, data_type FROM information_schema.columns
--    WHERE table_schema = 'public' AND table_name = 'admin_activity_log' ORDER BY ordinal_position;
--    SELECT policyname, cmd, with_check FROM pg_policies WHERE tablename = 'admin_activity_log';
-- ─────────────────────────────────────────────────────────────────────────

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. Structured columns on the existing table
-- ════════════════════════════════════════════════════════════
ALTER TABLE public.admin_activity_log
  ADD COLUMN IF NOT EXISTS actor_role      TEXT,
  ADD COLUMN IF NOT EXISTS actor_name      TEXT,
  ADD COLUMN IF NOT EXISTS table_name      TEXT,
  ADD COLUMN IF NOT EXISTS operation       TEXT,
  ADD COLUMN IF NOT EXISTS record_id       TEXT,
  ADD COLUMN IF NOT EXISTS reference_label TEXT,
  ADD COLUMN IF NOT EXISTS old_values      JSONB,
  ADD COLUMN IF NOT EXISTS new_values      JSONB,
  ADD COLUMN IF NOT EXISTS source          TEXT NOT NULL DEFAULT 'app';

ALTER TABLE public.admin_activity_log
  DROP CONSTRAINT IF EXISTS admin_activity_log_source_check;
ALTER TABLE public.admin_activity_log
  ADD CONSTRAINT admin_activity_log_source_check CHECK (source IN ('app', 'db'));

CREATE INDEX IF NOT EXISTS idx_admin_activity_log_source_created
  ON public.admin_activity_log (source, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_admin_activity_log_admin_created
  ON public.admin_activity_log (admin_id, created_at DESC);

-- Existing rows were all written by the app and record who did it.
UPDATE public.admin_activity_log l
SET actor_role = COALESCE(l.actor_role, r.role),
    actor_name = COALESCE(l.actor_name, ui.full_name)
FROM public.user_roles r
LEFT JOIN public.user_information ui ON ui.user_id = r.user_id
WHERE r.user_id = l.admin_id
  AND (l.actor_role IS NULL OR l.actor_name IS NULL);

-- ════════════════════════════════════════════════════════════
-- 2. Only the trigger may write 'db' rows
-- ════════════════════════════════════════════════════════════
DROP POLICY IF EXISTS "admin_activity_log: admin inserts own" ON public.admin_activity_log;
CREATE POLICY "admin_activity_log: admin inserts own"
  ON public.admin_activity_log FOR INSERT TO public
  WITH CHECK (admin_id = auth.uid() AND public.is_staff() AND source = 'app');

-- Reading: the Manager reads everything; any other staff member reads only the
-- app-written rows (their own feed filters to their own actions in the app).
DROP POLICY IF EXISTS "admin_activity_log: admin reads all" ON public.admin_activity_log;
DROP POLICY IF EXISTS "admin_activity_log: staff read app rows, manager reads all" ON public.admin_activity_log;
CREATE POLICY "admin_activity_log: staff read app rows, manager reads all"
  ON public.admin_activity_log FOR SELECT TO public
  USING (public.is_manager() OR (public.is_staff() AND source = 'app'));

-- The app's own rows now also carry the actor's role and name, filled in by the
-- database so a client cannot misstate who it is.
CREATE OR REPLACE FUNCTION public.admin_activity_log_fill_actor()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.source = 'app' AND NEW.admin_id IS NOT NULL THEN
    SELECT r.role, ui.full_name INTO NEW.actor_role, NEW.actor_name
    FROM user_roles r
    LEFT JOIN user_information ui ON ui.user_id = r.user_id
    WHERE r.user_id = NEW.admin_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_admin_activity_log_fill_actor ON public.admin_activity_log;
CREATE TRIGGER trg_admin_activity_log_fill_actor
  BEFORE INSERT ON public.admin_activity_log
  FOR EACH ROW EXECUTE FUNCTION public.admin_activity_log_fill_actor();

-- ════════════════════════════════════════════════════════════
-- 3. The database-side writer
-- ════════════════════════════════════════════════════════════
-- TG_ARGV[0] = the module key stored in admin_activity_log.module
-- TG_ARGV[1] = 'skip_self' to ignore a row that belongs to the actor
--              (an Officer clearing their own flags is not a management action)
--
-- UPDATE rows store only the columns that changed (old and new side by side).
-- A failure to log raises a WARNING and lets the change proceed: losing a
-- business operation because the log write failed would be worse than the gap,
-- and the warning surfaces in the Postgres logs.
CREATE OR REPLACE FUNCTION public.audit_staff_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid       uuid := auth.uid();
  v_role      text;
  v_name      text;
  v_module    text := COALESCE(TG_ARGV[0], TG_TABLE_NAME);
  v_skip_self boolean := COALESCE(TG_ARGV[1], '') = 'skip_self';
  v_old       jsonb;
  v_new       jsonb;
  v_row       jsonb;
  v_key       text;
  v_label_key text;
  v_label     text;
  v_rec       text;
  v_ref       uuid;
  v_action    text;
  v_verb      text;
  v_secret    text[] := ARRAY['password', 'encrypted_password', 'token'];
BEGIN
  IF v_uid IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  SELECT role INTO v_role FROM user_roles WHERE user_id = v_uid;
  IF v_role IS NULL OR v_role NOT IN ('admin', 'officer') THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP <> 'INSERT' THEN v_old := to_jsonb(OLD); END IF;
  IF TG_OP <> 'DELETE' THEN v_new := to_jsonb(NEW); END IF;
  v_row := COALESCE(v_new, v_old);

  IF v_skip_self AND (v_row ->> 'user_id') = v_uid::text THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  IF TG_OP = 'UPDATE' THEN
    DECLARE
      d_old jsonb := '{}'::jsonb;
      d_new jsonb := '{}'::jsonb;
    BEGIN
      FOR v_key IN SELECT jsonb_object_keys(v_new) LOOP
        IF v_key IN ('updated_at', 'last_active_at') THEN CONTINUE; END IF;
        IF (v_new -> v_key) IS DISTINCT FROM (v_old -> v_key) THEN
          d_old := d_old || jsonb_build_object(v_key, v_old -> v_key);
          d_new := d_new || jsonb_build_object(v_key, v_new -> v_key);
        END IF;
      END LOOP;
      IF d_new = '{}'::jsonb THEN
        RETURN NEW;                       -- nothing meaningful changed
      END IF;
      v_old := d_old;
      v_new := d_new;
    END;
  END IF;

  -- Never copy secrets into the log.
  FOREACH v_key IN ARRAY v_secret LOOP
    IF v_old IS NOT NULL THEN v_old := v_old - v_key; END IF;
    IF v_new IS NOT NULL THEN v_new := v_new - v_key; END IF;
  END LOOP;

  v_rec := COALESCE(v_row ->> 'id', v_row ->> 'user_id', v_row ->> 'code');
  BEGIN
    v_ref := v_rec::uuid;
  EXCEPTION WHEN OTHERS THEN
    v_ref := NULL;
  END;

  -- A human reference for the record: the first of these columns that has a
  -- value, else the name of the member the row belongs to.
  FOREACH v_label_key IN ARRAY ARRAY[
    'reference_no', 'loan_reference', 'order_number', 'item_name', 'crop_name',
    'program_name', 'product_name', 'name', 'title', 'category_name', 'full_name'
  ] LOOP
    IF NULLIF(v_row ->> v_label_key, '') IS NOT NULL THEN
      v_label := v_row ->> v_label_key;
      EXIT;
    END IF;
  END LOOP;
  IF v_label IS NULL THEN
    SELECT ui.full_name INTO v_label
    FROM user_information ui
    WHERE ui.user_id::text = COALESCE(v_row ->> 'farmer_id', v_row ->> 'user_id', v_row ->> 'member_id');
  END IF;

  SELECT full_name INTO v_name FROM user_information WHERE user_id = v_uid;

  v_action := CASE TG_OP WHEN 'INSERT' THEN 'created' WHEN 'UPDATE' THEN 'updated' ELSE 'deleted' END;
  v_verb   := CASE TG_OP WHEN 'INSERT' THEN 'Created' WHEN 'UPDATE' THEN 'Updated' ELSE 'Deleted' END;

  INSERT INTO admin_activity_log (
    admin_id, module, action_type, description, reference_id,
    actor_role, actor_name, table_name, operation, record_id, reference_label,
    old_values, new_values, source
  ) VALUES (
    v_uid, v_module, v_action,
    v_verb || ' ' || replace(TG_TABLE_NAME, '_', ' ')
      || CASE WHEN v_label IS NOT NULL THEN ': ' || v_label ELSE '' END,
    v_ref,
    v_role, v_name, TG_TABLE_NAME, v_action, v_rec, v_label,
    v_old, v_new, 'db'
  );

  RETURN COALESCE(NEW, OLD);
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'audit_staff_change failed on %: %', TG_TABLE_NAME, SQLERRM;
  RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE ALL ON FUNCTION public.audit_staff_change() FROM PUBLIC, anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 4. Attach it to the audited tables (skips any table that does not exist)
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('crop_master',                 'crops',     ''),
      ('crop_categories',             'crops',     ''),
      ('crop_requests',               'crops',     ''),
      ('cooperative_inventory',       'inventory', ''),
      ('inventory_transactions',      'inventory', ''),
      ('inventory_categories',        'inventory', ''),
      ('units',                       'inventory', ''),
      ('cooperative_programs',        'programs',  ''),
      ('program_activities',          'programs',  ''),
      ('program_members',             'programs',  ''),
      ('program_products',            'programs',  ''),
      ('program_product_purchases',   'programs',  ''),
      ('program_enrollment_requests', 'programs',  ''),
      ('loan_items_master',           'loans',     ''),
      ('farmer_loans',                'loans',     ''),
      ('farmer_loan_payments',        'loans',     ''),
      ('loan_requests',               'loans',     ''),
      ('loan_policy_settings',        'loans',     ''),
      ('price_records',               'prices',    ''),
      ('broadcast_logs',              'broadcast', ''),
      ('user_roles',                  'members',   'skip_self'),
      ('member_capital_shares',       'members',   ''),
      ('capital_contribution_events', 'members',   ''),
      ('password_reset_requests',     'members',   ''),
      ('officer_permissions',         'members',   ''),
      ('account_creation_requests',   'members',   '')
    ) AS t(tbl, module_key, flag)
  LOOP
    IF to_regclass('public.' || r.tbl) IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.%I', r.tbl);
      EXECUTE format(
        'CREATE TRIGGER trg_audit_staff_change AFTER INSERT OR UPDATE OR DELETE ON public.%I '
        'FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(%L, %L)',
        r.tbl, r.module_key, r.flag);
    ELSE
      RAISE NOTICE 'audit trigger skipped, table not found: %', r.tbl;
    END IF;
  END LOOP;
END
$$;

-- ════════════════════════════════════════════════════════════
-- 5. Approval history names the staff member (member_status_events)
-- ════════════════════════════════════════════════════════════
-- approve_member / reject_member / suspend_member / reactivate_member already
-- write actor_id. This adds a copy of the actor's name and role at that moment,
-- filled by a trigger so none of those functions has to change. If the staff
-- account is ever removed, actor_id becomes empty but the name stays.
ALTER TABLE public.member_status_events
  ADD COLUMN IF NOT EXISTS actor_name TEXT,
  ADD COLUMN IF NOT EXISTS actor_role TEXT;

CREATE OR REPLACE FUNCTION public.member_status_events_fill_actor()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.actor_id IS NOT NULL AND (NEW.actor_name IS NULL OR NEW.actor_role IS NULL) THEN
    SELECT COALESCE(NEW.actor_name, ui.full_name), COALESCE(NEW.actor_role, r.role)
    INTO NEW.actor_name, NEW.actor_role
    FROM user_roles r
    LEFT JOIN user_information ui ON ui.user_id = r.user_id
    WHERE r.user_id = NEW.actor_id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_member_status_events_fill_actor ON public.member_status_events;
CREATE TRIGGER trg_member_status_events_fill_actor
  BEFORE INSERT ON public.member_status_events
  FOR EACH ROW EXECUTE FUNCTION public.member_status_events_fill_actor();

-- Existing history rows get their actor's name and role now.
UPDATE public.member_status_events e
SET actor_name = COALESCE(e.actor_name, ui.full_name),
    actor_role = COALESCE(e.actor_role, r.role)
FROM public.user_roles r
LEFT JOIN public.user_information ui ON ui.user_id = r.user_id
WHERE r.user_id = e.actor_id
  AND e.actor_id IS NOT NULL
  AND (e.actor_name IS NULL OR e.actor_role IS NULL);

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ============================================================
-- POST-DEPLOY VERIFICATION (run each by itself)
-- ============================================================
-- 1) Triggers attached (expect ~25 rows):
--    SELECT event_object_table, count(*) FROM information_schema.triggers
--    WHERE trigger_name = 'trg_audit_staff_change' GROUP BY 1 ORDER BY 1;
-- 2) Insert policy refuses 'db' rows from clients:
--    SELECT with_check FROM pg_policies
--    WHERE tablename = 'admin_activity_log' AND cmd = 'INSERT';   -- contains source = 'app'
-- 3) After any staff action in the app (e.g. edit a crop's price reference):
--    SELECT created_at, actor_name, actor_role, module, operation, table_name,
--           reference_label, old_values, new_values
--    FROM admin_activity_log WHERE source = 'db' ORDER BY created_at DESC LIMIT 20;
-- ============================================================
