-- ============================================================
-- SAGANA — Officer permissions, script 12: MEMBER ACTIVITY LOGBOOK
--
-- APPROVED by you (N5). Goal: every action a Manager or Officer performs in the
-- Members tab is recorded — what was done, to which member, by whom, when, and
-- the reason or details — the Manager can read all of it, and no Officer can
-- change or delete a record.
--
-- THE LOGBOOK is the staff audit trail (admin_activity_log, rows with
-- source = 'db', written by a database trigger in the same transaction as the
-- change, so an action cannot happen without its record). The Manager reads it
-- in Staff Accountability (Profile). Status changes are also kept, with the
-- staff name, in member_status_events (shown in Farmer Details).
--
-- WHAT IS RECORDED TODAY (checked against the code and scripts 05, 08, 09)
--   Members-tab action                         recorded as
--   ------------------------------------------ ---------------------------------
--   Create a Farmer account (Manager/Officer)  user_roles created (+ capital row)
--   Create an Officer account (Manager)        user_roles created
--   Approve an applicant                       user_roles status pending -> active,
--                                              member_status_events (name, role)
--   Disapprove an applicant (with reason)      user_roles status + rejection_reason,
--                                              member_status_events
--   Suspend / Reactivate (reason, end date)    user_roles status + suspension_reason,
--                                              member_status_events
--   Add a contribution (Farmer Details)        capital_contribution_events created
--                                              (amount, source, note) + the member's
--                                              capital total change
--   Reset a member's password                  user_roles must_change_password
--   Handle a password help request             password_reset_requests updated
--   Change an Officer's module access          officer_permissions (see gap 2)
--   Decision on an Officer-created Farmer      account_creation_requests
--   Delete a disapproved account               entry written by script 09
--   Broadcast / loans from the Members menu    broadcast_logs / loans tables
--
-- THE GAP THIS SCRIPT CLOSES
--   1. EDITING MEMBER INFORMATION. No screen edits another member's information
--      today, but an API call could (user_information: name, phone, e-mail;
--      farmer_profiles: date of birth, gender, farm details, verified flag). Those
--      two tables had no audit trigger. They get one for UPDATES by staff (a
--      member editing their own details is not staff activity and is not logged;
--      neither is a staff member editing their own profile).
--      Creation is not logged again here: the new account is already recorded
--      once through user_roles.
--
--   2. OFFICER ACCESS CHANGES DID NOT SAY WHICH MODULE. An update row stores only
--      the columns that changed, and for officer_permissions that is just the level
--      (the module name never changes, so it was left out). The log showed "Loans
--      or Reports?" nowhere. Officer access gets its own small audit function that
--      always records the module together with the old and new level.
--
-- THE PROTECTION THIS SCRIPT ADDS (Officers cannot alter or delete the records)
--   3. member_status_events (the approval / suspension history):
--        * Today the policy "mse: admin manages all" lets an Officer with
--          Members = Manage insert, change or delete its rows through the API
--          (the table is in the gate's Members list). That is removed.
--        * Only the Manager can read it. Nobody writes it through the API: the
--          approve / disapprove / suspend / reactivate / delete functions write
--          it (they run with the database owner's rights and are unaffected).
--   4. admin_activity_log (the logbook itself): explicit REVOKE of UPDATE and
--      DELETE from every API role. It already had no UPDATE / DELETE policy; this
--      makes it impossible even if a policy were added by mistake.
--
-- WHAT DOES NOT CHANGE
--   Officers keep every action their permissions allow, in the app. The app never
--   writes member_status_events or admin_activity_log updates / deletes directly.
--   Deleting an Officer account still removes their access rows silently; that
--   removal is already recorded once through the account's own deletion.
--
-- OBSERVATION (not changed here, tell me if you want it): an Officer with Members
--   = Manage can still correct or remove a row of the contribution ledger
--   (capital_contribution_events) through the API, because the Members module
--   covers contributions. It is logged (old and new values), so it can be seen,
--   but not prevented. The app only ever ADDS contribution rows.
--
-- REQUIRES scripts 01, 02, 05 (audit_staff_change, is_manager, the gate mapping).
-- Not applied automatically. Run in the Supabase SQL editor. Re-runnable.
--
-- ROLLBACK (only if something unexpected breaks):
--   CREATE POLICY "mse: admin manages all" ON public.member_status_events
--     FOR ALL USING (public.is_platform_admin());
--   INSERT INTO staff_permission_targets VALUES ('table','member_status_events','members')
--     ON CONFLICT DO NOTHING;
--   GRANT INSERT, UPDATE, DELETE ON public.member_status_events TO authenticated;
-- ============================================================

-- ─── PRE-FLIGHT (the script stops with a message if one fails) ───────────────
DO $$
BEGIN
  IF to_regprocedure('public.audit_staff_change()') IS NULL THEN
    RAISE EXCEPTION 'audit_staff_change() is missing. Run officer_permissions_05 first.';
  END IF;
  IF to_regprocedure('public.is_manager(uuid)') IS NULL THEN
    RAISE EXCEPTION 'is_manager() is missing. Run officer_permissions_01 first.';
  END IF;
  IF to_regclass('public.member_status_events') IS NULL OR to_regclass('public.admin_activity_log') IS NULL THEN
    RAISE EXCEPTION 'member_status_events or admin_activity_log is missing.';
  END IF;
END $$;

BEGIN;

-- ════════════════════════════════════════════════════════════
-- 1. Audit staff edits of member information
--    (UPDATE only; same function and flags as the other Members tables)
-- ════════════════════════════════════════════════════════════
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['user_information', 'farmer_profiles']
  LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.%I', t);
      EXECUTE format(
        'CREATE TRIGGER trg_audit_staff_change AFTER UPDATE ON public.%I '
        'FOR EACH ROW EXECUTE FUNCTION public.audit_staff_change(%L, %L)',
        t, 'members', 'skip_self');
    ELSE
      RAISE NOTICE 'audit trigger skipped, table not found: %', t;
    END IF;
  END LOOP;
END
$$;

-- ════════════════════════════════════════════════════════════
-- 1b. Officer access: always say WHICH module
--     (replaces the generic trigger on this one table; the other audit triggers
--      and audit_staff_change() itself are not touched)
-- ════════════════════════════════════════════════════════════
CREATE OR REPLACE FUNCTION public.audit_officer_permission_change()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_role  text;
  v_name  text;
  v_row   jsonb;
  v_label text;
  v_action text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  SELECT role INTO v_role FROM user_roles WHERE user_id = v_uid;
  IF v_role IS NULL OR v_role NOT IN ('admin', 'officer') THEN
    RETURN COALESCE(NEW, OLD);
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.access_level IS NOT DISTINCT FROM OLD.access_level THEN
    RETURN NEW;                                   -- nothing meaningful changed
  END IF;

  v_row := to_jsonb(COALESCE(NEW, OLD));
  SELECT full_name INTO v_label FROM user_information WHERE user_id = (v_row ->> 'user_id')::uuid;
  SELECT full_name INTO v_name  FROM user_information WHERE user_id = v_uid;
  v_action := CASE TG_OP WHEN 'INSERT' THEN 'created' ELSE 'updated' END;

  INSERT INTO admin_activity_log (
    admin_id, module, action_type, description, reference_id,
    actor_role, actor_name, table_name, operation, record_id, reference_label,
    old_values, new_values, source
  ) VALUES (
    v_uid, 'members', v_action,
    'Changed module access: ' || COALESCE(v_label, '') || ' (' || (v_row ->> 'module') || ')',
    (v_row ->> 'user_id')::uuid,
    v_role, v_name, 'officer_permissions', v_action, v_row ->> 'user_id', v_label,
    CASE WHEN TG_OP = 'UPDATE'
         THEN jsonb_build_object('module', v_row ->> 'module', 'access_level', to_jsonb(OLD) ->> 'access_level') END,
    jsonb_build_object('module', v_row ->> 'module', 'access_level', to_jsonb(NEW) ->> 'access_level'),
    'db'
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'audit_officer_permission_change failed: %', SQLERRM;
  RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE ALL ON FUNCTION public.audit_officer_permission_change() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_audit_staff_change ON public.officer_permissions;
DROP TRIGGER IF EXISTS trg_audit_officer_permissions ON public.officer_permissions;
CREATE TRIGGER trg_audit_officer_permissions
  AFTER INSERT OR UPDATE ON public.officer_permissions
  FOR EACH ROW EXECUTE FUNCTION public.audit_officer_permission_change();

-- ════════════════════════════════════════════════════════════
-- 2. The approval / suspension history cannot be written through the API
-- ════════════════════════════════════════════════════════════
-- No longer a Members-gated table: nobody writes it through the API at all.
DELETE FROM public.staff_permission_targets
WHERE kind = 'table' AND name = 'member_status_events';

DROP POLICY IF EXISTS "mse: admin manages all" ON public.member_status_events;
DROP POLICY IF EXISTS "mse: manager reads" ON public.member_status_events;
CREATE POLICY "mse: manager reads"
  ON public.member_status_events FOR SELECT
  USING (public.is_manager());

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.member_status_events FROM anon, authenticated;

-- ════════════════════════════════════════════════════════════
-- 3. The logbook itself cannot be changed or deleted through the API
-- ════════════════════════════════════════════════════════════
REVOKE UPDATE, DELETE, TRUNCATE ON public.admin_activity_log FROM anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

-- ─── VERIFICATION (read-only; run each by itself) ────────────────────────
-- 1. The new triggers:
--    SELECT tgrelid::regclass AS tbl, tgname FROM pg_trigger
--    WHERE tgrelid::regclass::text IN ('user_information','farmer_profiles','officer_permissions')
--      AND tgname IN ('trg_audit_staff_change','trg_audit_officer_permissions');
--    -- expect 3 rows: user_information and farmer_profiles (trg_audit_staff_change),
--    -- officer_permissions (trg_audit_officer_permissions)
-- 2. The history is Manager-read-only:
--    SELECT policyname, cmd FROM pg_policies WHERE tablename = 'member_status_events';
--    -- expect one row: "mse: manager reads" / SELECT
--    SELECT * FROM staff_permission_targets WHERE name = 'member_status_events';   -- expect 0 rows
-- 3. Nobody can change the logbook:
--    SELECT grantee, privilege_type FROM information_schema.role_table_grants
--    WHERE table_name IN ('admin_activity_log','member_status_events')
--      AND grantee IN ('anon','authenticated') AND privilege_type IN ('UPDATE','DELETE','TRUNCATE');
--    -- expect no rows
-- 4. In the app: as an Officer (Members = Manage) suspend a test Farmer, add a
--    contribution, then as the Manager open Profile > Staff Accountability, filter
--    "Members": each shows as a sentence with the Officer's name and the time.
-- ─────────────────────────────────────────────────────────────────────────
