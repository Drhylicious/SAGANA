-- ============================================================
-- SAGANA — Officer permissions: VERIFICATION SCRIPT
--
-- Run AFTER scripts 01 to 05. Everything between BEGIN and ROLLBACK is undone,
-- so it changes nothing permanently. Run the whole block at once in the
-- Supabase SQL editor and read the NOTICE lines: every line must say PASS.
--
-- It exercises the gate function directly with the request settings PostgREST
-- would set (request.method, request.path, the JWT subject), so it proves the
-- gate's DECISIONS. That PostgREST really calls the gate on every request is
-- proven separately by script 06's live check.
--
-- Needs at least: 1 Manager (role admin), 1 Officer, 1 Farmer.
-- ============================================================

BEGIN;

SELECT set_config('test.officer', (SELECT user_id::text FROM user_roles WHERE role = 'officer' ORDER BY created_at LIMIT 1), true);
SELECT set_config('test.manager', (SELECT user_id::text FROM user_roles WHERE role = 'admin'   ORDER BY created_at LIMIT 1), true);
SELECT set_config('test.farmer',  (SELECT user_id::text FROM user_roles WHERE role = 'farmer'  ORDER BY created_at LIMIT 1), true);

-- Pretend to be <uid> making an HTTP <method> to <path>.
CREATE OR REPLACE FUNCTION pg_temp.as_request(p_uid uuid, p_method text, p_path text)
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', p_uid, 'role', 'authenticated')::text, true);
  PERFORM set_config('request.method', p_method, true);
  PERFORM set_config('request.path', p_path, true);
  PERFORM set_config('sagana.members_manage', '', true);
END $$;

-- Does the gate let this request through?
CREATE OR REPLACE FUNCTION pg_temp.gate_allows(p_uid uuid, p_method text, p_path text)
RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.as_request(p_uid, p_method, p_path);
  PERFORM public.staff_permission_gate();
  RETURN true;
EXCEPTION WHEN insufficient_privilege THEN
  RETURN false;
END $$;

DO $$
DECLARE
  o uuid := current_setting('test.officer')::uuid;
  m uuid := current_setting('test.manager')::uuid;
  f uuid := current_setting('test.farmer')::uuid;
  r boolean;
  n int;
  logs_before int;
  logs_after  int;
  new_id uuid := gen_random_uuid();
  req_id uuid;
  banned timestamptz;
BEGIN
  IF o IS NULL OR m IS NULL THEN
    RAISE EXCEPTION 'Need at least one Officer and one Manager to run this test.';
  END IF;

  -- The Officer starts with every module at View Only (rows created if missing).
  PERFORM set_config('request.jwt.claims', '', true);
  INSERT INTO officer_permissions (user_id, module, access_level)
  SELECT o, mod, 'view' FROM unnest(public.staff_module_list()) mod
  ON CONFLICT (user_id, module) DO UPDATE SET access_level = 'view';

  -- 1. View Only: management writes are refused (RPC and table write).
  r := pg_temp.gate_allows(o, 'POST', '/rpc/issue_loan');
  RAISE NOTICE '% 1a View Only Officer cannot call issue_loan', CASE WHEN r THEN 'FAIL' ELSE 'PASS' END;
  r := pg_temp.gate_allows(o, 'PATCH', '/crop_master');
  RAISE NOTICE '% 1b View Only Officer cannot update crop_master', CASE WHEN r THEN 'FAIL' ELSE 'PASS' END;
  r := pg_temp.gate_allows(o, 'POST', '/rpc/approve_listing');
  RAISE NOTICE '% 1c View Only Officer cannot approve a listing', CASE WHEN r THEN 'FAIL' ELSE 'PASS' END;
  r := pg_temp.gate_allows(o, 'DELETE', '/price_records');
  RAISE NOTICE '% 1d View Only Officer cannot delete a price record', CASE WHEN r THEN 'FAIL' ELSE 'PASS' END;

  -- 2. View Only: reading is allowed.
  r := pg_temp.gate_allows(o, 'GET', '/farmer_loans');
  RAISE NOTICE '% 2a View Only Officer can read loans', CASE WHEN r THEN 'PASS' ELSE 'FAIL' END;
  r := pg_temp.gate_allows(o, 'GET', '/crop_master');
  RAISE NOTICE '% 2b View Only Officer can read crops', CASE WHEN r THEN 'PASS' ELSE 'FAIL' END;

  -- 3. A module the Officer manages is allowed; the others stay refused.
  UPDATE officer_permissions SET access_level = 'manage' WHERE user_id = o AND module = 'loans';
  r := pg_temp.gate_allows(o, 'POST', '/rpc/issue_loan');
  RAISE NOTICE '% 3a Loans = manage: issue_loan allowed', CASE WHEN r THEN 'PASS' ELSE 'FAIL' END;
  r := pg_temp.gate_allows(o, 'POST', '/rpc/approve_listing');
  RAISE NOTICE '% 3b ... but approve_listing still refused (Marketplace = view)', CASE WHEN r THEN 'FAIL' ELSE 'PASS' END;

  -- 4. Calls the gate does not govern are unaffected.
  r := pg_temp.gate_allows(o, 'POST', '/rpc/touch_last_active');
  RAISE NOTICE '% 4  ungoverned RPC (touch_last_active) works', CASE WHEN r THEN 'PASS' ELSE 'FAIL' END;

  -- 5. Broadcast follows the Dashboard permission, for sending AND scheduling.
  r := pg_temp.gate_allows(o, 'POST', '/rpc/send_broadcast');
  RAISE NOTICE '% 5a Dashboard = view: send_broadcast refused', CASE WHEN r THEN 'FAIL' ELSE 'PASS' END;
  r := pg_temp.gate_allows(o, 'POST', '/broadcast_logs');
  RAISE NOTICE '% 5b Dashboard = view: scheduling (broadcast_logs) refused', CASE WHEN r THEN 'FAIL' ELSE 'PASS' END;
  UPDATE officer_permissions SET access_level = 'manage' WHERE user_id = o AND module = 'dashboard';
  r := pg_temp.gate_allows(o, 'POST', '/rpc/send_broadcast');
  RAISE NOTICE '% 5c Dashboard = manage: send_broadcast allowed', CASE WHEN r THEN 'PASS' ELSE 'FAIL' END;
  r := pg_temp.gate_allows(o, 'DELETE', '/broadcast_logs');
  RAISE NOTICE '% 5d Dashboard = manage: broadcast_logs delete allowed by the gate', CASE WHEN r THEN 'PASS' ELSE 'FAIL' END;

  -- 6. Members: is_platform_admin() is false for a Members-View Officer, and true
  --    for a Members-Manage Officer only inside a gated Members request.
  PERFORM pg_temp.as_request(o, 'POST', '/rpc/approve_member');
  RAISE NOTICE '% 6a Members = view: is_platform_admin() false', CASE WHEN public.is_platform_admin() THEN 'FAIL' ELSE 'PASS' END;
  r := pg_temp.gate_allows(o, 'POST', '/rpc/approve_member');
  RAISE NOTICE '% 6b Members = view: approve_member refused by the gate', CASE WHEN r THEN 'FAIL' ELSE 'PASS' END;
  UPDATE officer_permissions SET access_level = 'manage' WHERE user_id = o AND module = 'members';
  r := pg_temp.gate_allows(o, 'POST', '/rpc/approve_member');
  RAISE NOTICE '% 6c Members = manage: gate allows approve_member', CASE WHEN r THEN 'PASS' ELSE 'FAIL' END;
  RAISE NOTICE '% 6d ... and is_platform_admin() is true during that request', CASE WHEN public.is_platform_admin() THEN 'PASS' ELSE 'FAIL' END;
  PERFORM pg_temp.as_request(o, 'POST', '/rpc/issue_loan');
  RAISE NOTICE '% 6e ... and false again in the next request', CASE WHEN public.is_platform_admin() THEN 'FAIL' ELSE 'PASS' END;

  -- 7. Manager and Farmer are never gated.
  r := pg_temp.gate_allows(m, 'POST', '/rpc/issue_loan');
  RAISE NOTICE '% 7a Manager is not gated', CASE WHEN r THEN 'PASS' ELSE 'FAIL' END;
  IF f IS NOT NULL THEN
    r := pg_temp.gate_allows(f, 'POST', '/rpc/issue_loan');
    RAISE NOTICE '% 7b Farmer is not gated (the RPC has its own checks)', CASE WHEN r THEN 'PASS' ELSE 'FAIL' END;
  END IF;

  -- 8. The only rules kept on accounts: nobody changes a role from the app, and
  --    nobody edits their own access. Nothing stops an Officer managing others.
  PERFORM pg_temp.as_request(o, 'POST', '/rpc/suspend_member');
  PERFORM set_config('sagana.members_manage', 'on', true);
  IF f IS NOT NULL THEN
    BEGIN
      UPDATE user_roles SET role = 'admin' WHERE user_id = f;
      RAISE NOTICE 'FAIL 8a a role was changed from the app';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'PASS 8a role change refused (%)', SQLERRM;
    END;
    BEGIN
      UPDATE user_roles SET status = status WHERE user_id = f;   -- an ordinary update is allowed
      RAISE NOTICE 'PASS 8b an Officer with Members = manage can update another account (no extra guard)';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'FAIL 8b ordinary account update refused (%)', SQLERRM;
    END;
  END IF;
  PERFORM pg_temp.as_request(o, 'POST', '/rpc/set_officer_permissions');
  BEGIN
    PERFORM public.set_officer_permissions(o, '{"dashboard":"view"}'::jsonb);
    RAISE NOTICE 'FAIL 8c Officer edited their own access';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS 8c Officer cannot edit their own access (%)', SQLERRM;
  END;

  -- 9. The Manager can set permissions and the change is recorded with who did it.
  SELECT count(*) INTO logs_before FROM admin_activity_log WHERE source = 'db' AND table_name = 'officer_permissions';
  PERFORM pg_temp.as_request(m, 'POST', '/rpc/set_officer_permissions');
  PERFORM public.set_officer_permissions(o, '{"reports":"manage"}'::jsonb);
  SELECT count(*) INTO logs_after FROM admin_activity_log WHERE source = 'db' AND table_name = 'officer_permissions';
  RAISE NOTICE '% 9a Manager changed Reports access; the database logged it (% -> % rows)',
    CASE WHEN logs_after > logs_before THEN 'PASS' ELSE 'FAIL' END, logs_before, logs_after;
  RAISE NOTICE '% 9b the log row names the Manager as the actor',
    CASE WHEN EXISTS (SELECT 1 FROM admin_activity_log
                      WHERE source = 'db' AND table_name = 'officer_permissions'
                        AND admin_id = m AND actor_role = 'admin' AND actor_name IS NOT NULL
                        AND old_values ? 'access_level' AND new_values ? 'access_level')
         THEN 'PASS' ELSE 'FAIL' END;

  -- 10. Officer-created accounts wait for the Manager.
  --     A throw-away login row stands in for what create_*_account inserts.
  INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000', new_id, 'authenticated', 'authenticated',
          'approval-test-' || new_id || '@sagana.local', now(), now());
  PERFORM pg_temp.as_request(o, 'POST', '/rpc/create_farmer_account');
  INSERT INTO user_roles (user_id, role, status) VALUES (new_id, 'farmer', 'active');
  SELECT id INTO req_id FROM account_creation_requests WHERE user_id = new_id AND status = 'pending';
  SELECT banned_until INTO banned FROM auth.users WHERE id = new_id;
  RAISE NOTICE '% 10a Officer-created account is recorded as pending', CASE WHEN req_id IS NOT NULL THEN 'PASS' ELSE 'FAIL' END;
  RAISE NOTICE '% 10b ... and cannot sign in (banned_until %)', CASE WHEN banned > now() + interval '50 years' THEN 'PASS' ELSE 'FAIL' END, banned;

  -- Even with Members = manage (is_platform_admin true) the Officer cannot approve.
  PERFORM set_config('sagana.members_manage', 'on', true);
  BEGIN
    PERFORM public.approve_account_creation(req_id);
    RAISE NOTICE 'FAIL 10c an Officer approved an account';
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'PASS 10c Officer cannot approve (%)', SQLERRM;
  END;

  PERFORM pg_temp.as_request(m, 'POST', '/rpc/approve_account_creation');
  PERFORM public.approve_account_creation(req_id);
  SELECT banned_until INTO banned FROM auth.users WHERE id = new_id;
  RAISE NOTICE '% 10d Manager approval lifts the block', CASE WHEN banned IS NULL THEN 'PASS' ELSE 'FAIL' END;

  -- A Manager-created account is never held.
  new_id := gen_random_uuid();
  INSERT INTO auth.users (instance_id, id, aud, role, email, created_at, updated_at)
  VALUES ('00000000-0000-0000-0000-000000000000', new_id, 'authenticated', 'authenticated',
          'approval-test-' || new_id || '@sagana.local', now(), now());
  PERFORM pg_temp.as_request(m, 'POST', '/rpc/create_farmer_account');
  INSERT INTO user_roles (user_id, role, status) VALUES (new_id, 'farmer', 'active');
  SELECT count(*) INTO n FROM account_creation_requests WHERE user_id = new_id;
  SELECT banned_until INTO banned FROM auth.users WHERE id = new_id;
  RAISE NOTICE '% 10e Manager-created account: no request, not blocked', CASE WHEN n = 0 AND banned IS NULL THEN 'PASS' ELSE 'FAIL' END;

  -- 11. Who can read the accountability trail (row level security, as the app sees it).
  PERFORM set_config('request.jwt.claims', '', true);
  INSERT INTO admin_activity_log (admin_id, module, action_type, description, source)
  VALUES (m, 'test', 'created', 'verification row', 'db');
  PERFORM pg_temp.as_request(o, 'GET', '/admin_activity_log');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.admin_activity_log WHERE source = 'db';
  RESET ROLE;
  RAISE NOTICE '% 11a Officer sees 0 database-written accountability rows (saw %)', CASE WHEN n = 0 THEN 'PASS' ELSE 'FAIL' END, n;
  PERFORM pg_temp.as_request(m, 'GET', '/admin_activity_log');
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO n FROM public.admin_activity_log WHERE source = 'db';
  RESET ROLE;
  RAISE NOTICE '% 11b Manager sees them (saw %)', CASE WHEN n >= 1 THEN 'PASS' ELSE 'FAIL' END, n;
END $$;

ROLLBACK;

-- ============================================================
-- READ-ONLY CHECKS ON REAL DATA (run each by itself, after real use)
-- ============================================================

-- A. Who changed what, newest first (the Staff Accountability screen's source):
--    SELECT created_at, actor_name, actor_role, module, operation, table_name,
--           reference_label, old_values, new_values
--    FROM admin_activity_log WHERE source = 'db' ORDER BY created_at DESC LIMIT 50;

-- B. Every audited table has the trigger (expect ~26 rows):
--    SELECT event_object_table FROM information_schema.triggers
--    WHERE trigger_name = 'trg_audit_staff_change' GROUP BY 1 ORDER BY 1;

-- C. Marketplace accountability (workflow_events names the staff member's role):
--    SELECT actor_role, entity_type, action, count(*) FROM workflow_events
--    WHERE actor_role IN ('admin','officer') GROUP BY 1,2,3 ORDER BY 1,2,3;
--    SELECT count(*) FROM workflow_events WHERE actor_id IS NULL AND actor_role IN ('admin','officer');  -- 0

-- D. Loan accountability (who recorded each payment):
--    SELECT ur.role, count(*) FROM farmer_loan_payments p
--    JOIN user_roles ur ON ur.user_id = p.recorded_by GROUP BY 1;

-- E. Approval history now carries the staff name:
--    SELECT created_at, to_status, actor_name, actor_role, reason
--    FROM member_status_events ORDER BY created_at DESC LIMIT 20;

-- F. Accounts waiting for or refused by the Manager:
--    SELECT status, account_role, requested_by_name, requested_at, decided_by_name, decided_at, decision_reason
--    FROM account_creation_requests ORDER BY requested_at DESC;

-- G. Each Officer's access:
--    SELECT ui.full_name, op.module, op.access_level, op.updated_at
--    FROM officer_permissions op JOIN user_information ui USING (user_id)
--    ORDER BY ui.full_name, op.module;
-- ============================================================
