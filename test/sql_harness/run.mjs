import fs from 'node:fs';
import { db, ID, STUBS, runScript, check, as, q, createUser, setLevels, regrant, report } from './harness.mjs';

const M = ID.mgr, O1 = ID.off1, O2 = ID.off2, O3 = ID.off3, F1 = ID.far1, F2 = ID.far2, B1 = ID.buy1, B2 = ID.buy2;
const ALL_M = { dashboard: 'manage', members: 'manage', marketplace: 'manage', loans: 'manage', reports: 'manage' };
const ALL_V = { dashboard: 'view', members: 'view', marketplace: 'view', loans: 'view', reports: 'view' };

await db.exec(STUBS);
await runScript('supabase_schema_officer_permissions_01_foundation.sql');
await runScript('supabase_schema_officer_permissions_02_enforcement.sql');
await runScript('supabase_schema_officer_permissions_04_account_approval.sql');
await runScript('supabase_schema_officer_permissions_05_accountability.sql');
await regrant();

await createUser(M, 'admin', 'The Manager', 'manager');
await createUser(O1, 'officer', 'Olivia One', 'off-0002');
await createUser(O2, 'officer', 'Omar Two', 'off-0003');
await createUser(O3, 'officer', 'Oscar Three', 'off-0004');
await createUser(F1, 'farmer', 'Farah One', 'sp3-0001');
await createUser(F2, 'farmer', 'Farid Two', 'sp3-0002');
await createUser(B1, 'buyer', 'Bea One', 'buy-0001');
await createUser(B2, 'buyer', 'Bo Two', 'buy-0002');
await setLevels(O1, ALL_M);
await setLevels(O2, { ...ALL_M, members: 'view' });
await setLevels(O3, ALL_V);

const err = (r) => (r.ok ? 'no error' : r.error);
const VIEW_ONLY = /view-only access/;

// ───────────────────────── T1 · Create Officer (server side) ─────────────────────────
{
  const call = (perms, uname) => as(M, { path: '/rpc/create_officer_account' }, async (d) =>
    (await d.query(
      `SELECT public.create_officer_account($1,'Passw0rd!','Reyes','Ana',NULL,NULL,NULL,NULL,NULL,NULL,$2::jsonb,NULL) AS id`,
      [uname, perms === null ? null : JSON.stringify(perms)],
    )).rows[0].id);

  const sig = await q(`SELECT pg_get_function_identity_arguments(oid) AS a FROM pg_proc WHERE proname='create_officer_account'`);
  check('T1', 'exactly one create_officer_account, takes p_permissions, no p_position',
    sig.length === 1 && /p_permissions jsonb/.test(sig[0].a) && !/p_position/.test(sig[0].a), JSON.stringify(sig));

  const r1 = await call({ loans: 'view' }, 'newoff1');
  check('T1', 'Manager creates an Officer with Loans = view', r1.ok, err(r1));
  let rows = [];
  if (r1.ok) {
    const id = r1.value;
    await as(M, { path: '/rpc/create_officer_account', commit: true }, async (d) =>
      d.query(`SELECT public.create_officer_account('newoff1b','Passw0rd!','Reyes','Ana',NULL,NULL,NULL,NULL,NULL,NULL,'{"loans":"view"}'::jsonb,NULL)`));
    rows = await q(`SELECT ur.user_id, op.module, op.access_level FROM user_roles ur JOIN user_information ui USING(user_id)
                    JOIN officer_permissions op USING(user_id) WHERE ui.username='newoff1b' ORDER BY op.module`);
  }
  const map = Object.fromEntries(rows.map((x) => [x.module, x.access_level]));
  check('T1', 'stored: loans=view, the other four default to manage (5 rows)',
    rows.length === 5 && map.loans === 'view' && ['dashboard','members','marketplace','reports'].every((m) => map[m] === 'manage'), JSON.stringify(map));

  await as(M, { path: '/rpc/create_officer_account', commit: true }, async (d) =>
    d.query(`SELECT public.create_officer_account('newoff2','Passw0rd!','Reyes','Bo',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)`));
  const def = await q(`SELECT op.module, op.access_level FROM officer_permissions op JOIN user_information ui USING(user_id) WHERE ui.username='newoff2'`);
  check('T1', 'no permissions sent -> all five default to manage', def.length === 5 && def.every((x) => x.access_level === 'manage'), JSON.stringify(def));

  const acct = await q(`SELECT ur.status, ur.must_change_password, op.position FROM user_roles ur JOIN user_information ui USING(user_id)
                        JOIN officer_profiles op USING(user_id) WHERE ui.username='newoff2'`);
  check('T1', 'Manager-created Officer is active at once, must change password, position left empty',
    acct[0]?.status === 'active' && acct[0]?.must_change_password === true && acct[0]?.position === null, JSON.stringify(acct));
  const held = await q(`SELECT count(*)::int AS n FROM account_creation_requests r JOIN user_information ui USING(user_id) WHERE ui.username IN ('newoff1b','newoff2')`);
  const ban = await q(`SELECT count(*)::int AS n FROM auth.users u JOIN user_information ui ON ui.user_id=u.id WHERE ui.username IN ('newoff1b','newoff2') AND u.banned_until IS NOT NULL`);
  check('T10', 'Manager-created accounts: no approval request and not blocked', held[0].n === 0 && ban[0].n === 0, JSON.stringify({ held, ban }));

  const bad1 = await call({ nonsense: 'manage' }, 'bad1');
  check('T1', 'unknown module rejected', !bad1.ok && /Unknown module/.test(bad1.error), err(bad1));
  const bad2 = await call({ loans: 'admin' }, 'bad2');
  check('T1', 'invalid level rejected', !bad2.ok && /must be view or manage/.test(bad2.error), err(bad2));
  const bad3 = await as(M, { path: '/rpc/create_officer_account' }, async (d) =>
    d.query(`SELECT public.create_officer_account('bad3','Passw0rd!','Reyes','Cy',NULL,NULL,NULL,NULL,NULL,NULL,'["x"]'::jsonb,NULL)`));
  check('T1', 'non-object permissions rejected', !bad3.ok && /object of module/.test(bad3.error), err(bad3));

  const farmerTry = await as(F1, { path: '/rpc/create_officer_account' }, async (d) =>
    d.query(`SELECT public.create_officer_account('bad4','Passw0rd!','Reyes','Di',NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL)`));
  check('T1', 'a Farmer cannot create an Officer', !farmerTry.ok && /Unauthorized/.test(farmerTry.error), err(farmerTry));
}

// ───────────────────────── T2 / T4 / T14 · the gate ─────────────────────────
{
  const g = async (uid, method, path) => as(uid, { method, path });
  let r;
  r = await g(O3, 'POST', '/rpc/issue_loan');
  check('T2', 'View Only Officer: issue_loan refused with the view-only message', !r.ok && r.code === '42501' && VIEW_ONLY.test(r.error), err(r));
  r = await g(O3, 'POST', '/rpc/record_loan_payment');
  check('T2', 'View Only Officer: record_loan_payment refused', !r.ok && VIEW_ONLY.test(r.error), err(r));
  r = await g(O3, 'PATCH', '/farmer_loans');
  check('T2', 'View Only Officer: marking a loan paid (PATCH farmer_loans) refused', !r.ok && VIEW_ONLY.test(r.error), err(r));
  r = await g(O3, 'PATCH', '/crop_master');
  check('T2', 'Dashboard View Only: crop price edit (PATCH crop_master) refused', !r.ok && VIEW_ONLY.test(r.error), err(r));
  r = await g(O1, 'PATCH', '/crop_master');
  check('T2', 'Dashboard Manage: crop price edit passes the gate', r.ok, err(r));
  r = await g(O3, 'GET', '/crop_master');
  check('T2', 'View Only Officer can still READ', r.ok, err(r));
  r = await g(O3, 'POST', '/rpc/touch_last_active');
  check('T2', 'ungoverned call (touch_last_active) is unaffected', r.ok, err(r));
  r = await g(M, 'POST', '/rpc/issue_loan');
  check('T21', 'Manager is never gated', r.ok, err(r));
  r = await g(F1, 'POST', '/rpc/issue_loan');
  check('T21', 'Farmer is never gated by it', r.ok, err(r));
  r = await as(null, { method: 'POST', path: '/rpc/issue_loan', role: 'anon' });
  check('T21', 'anonymous caller passes through the gate untouched', r.ok, err(r));

  // T4: the exact REST call from the test plan.
  r = await g(O3, 'DELETE', '/price_records');
  check('T4', 'Dashboard View Only: DELETE /price_records refused (HTTP 403 = SQLSTATE 42501)', !r.ok && r.code === '42501' && VIEW_ONLY.test(r.error), err(r));
  r = await g(O1, 'DELETE', '/price_records');
  check('T4', 'Dashboard Manage: the same call passes the gate', r.ok, err(r));
  r = await as(O3, { method: '', path: '/crop_master' });
  check('T4', 'if PostgREST gave no request.method, a View Only write is still refused (fails closed)', !r.ok, err(r));

  // T14 Members
  r = await g(O2, 'POST', '/rpc/create_farmer_account');
  check('T14', 'Members View Only: create_farmer_account refused', !r.ok && VIEW_ONLY.test(r.error), err(r));
  r = await g(O2, 'POST', '/rpc/create_officer_account');
  check('T14', 'Members View Only: create_officer_account refused', !r.ok && VIEW_ONLY.test(r.error), err(r));
  r = await g(O2, 'POST', '/rpc/suspend_member');
  check('T14', 'Members View Only: suspend_member refused', !r.ok && VIEW_ONLY.test(r.error), err(r));
  r = await g(O2, 'POST', '/rpc/admin_reset_user_password');
  check('T14', 'Members View Only: reset password refused', !r.ok && VIEW_ONLY.test(r.error), err(r));
  r = await g(O1, 'POST', '/rpc/suspend_member');
  check('T14', 'Members Manage: suspend_member passes', r.ok, err(r));
}

// ───────────────────────── T3 · permission changes ─────────────────────────
{
  let r = await as(O3, { path: '/rpc/get_my_staff_permissions' }, async (d) => (await d.query('SELECT public.get_my_staff_permissions() AS p')).rows[0].p);
  check('T3', 'get_my_staff_permissions returns the Officer\'s five levels', r.ok && Object.keys(r.value).length === 5 && Object.values(r.value).every((v) => v === 'view'), JSON.stringify(r.value ?? r.error));
  r = await as(M, { path: '/rpc/get_my_staff_permissions' }, async (d) => (await d.query('SELECT public.get_my_staff_permissions() AS p')).rows[0].p);
  check('T3', 'Manager reads Manage for every module', r.ok && Object.values(r.value).every((v) => v === 'manage'), JSON.stringify(r.value ?? r.error));
  r = await as(F1, { path: '/rpc/get_my_staff_permissions', gate: false }, async (d) => (await d.query('SELECT public.get_my_staff_permissions() AS p')).rows[0].p);
  check('T3', 'a Farmer gets no staff permissions ({})', r.ok && Object.keys(r.value).length === 0, JSON.stringify(r.value ?? r.error));

  await as(M, { path: '/rpc/set_officer_permissions', commit: true }, async (d) =>
    d.query(`SELECT public.set_officer_permissions($1, '{"loans":"manage"}'::jsonb)`, [O3]));
  let lv = await q(`SELECT access_level FROM officer_permissions WHERE user_id=$1 AND module='loans'`, [O3]);
  check('T3', 'Manager sets Loans = manage; the stored level changes', lv[0]?.access_level === 'manage', JSON.stringify(lv));
  r = await as(O3, { method: 'POST', path: '/rpc/issue_loan' });
  check('T3', 'the same Officer\'s next issue_loan now passes the gate', r.ok, err(r));
  const log = await q(`SELECT actor_name, actor_role, old_values, new_values FROM admin_activity_log
                       WHERE source='db' AND table_name='officer_permissions' AND admin_id=$1 ORDER BY created_at DESC LIMIT 1`, [M]);
  check('T3', 'the change is logged with the Manager as actor, old and new level', log[0]?.actor_role === 'admin' && log[0]?.old_values?.access_level === 'view' && log[0]?.new_values?.access_level === 'manage', JSON.stringify(log));
  await setLevels(O3, ALL_V);

  r = await as(O1, { path: '/rpc/set_officer_permissions' }, async (d) =>
    d.query(`SELECT public.set_officer_permissions($1, '{"dashboard":"manage"}'::jsonb)`, [O1]));
  check('T13', 'nobody edits their own access', !r.ok && /cannot change your own access/.test(r.error), err(r));
  r = await as(O1, { path: '/rpc/set_officer_permissions' }, async (d) =>
    d.query(`SELECT public.set_officer_permissions($1, '{"loans":"manage","dashboard":"manage"}'::jsonb)`, [O3]));
  check('T13', 'an Officer with Members = Manage can raise another Officer (no ceiling)', r.ok, err(r));
  r = await as(O2, { path: '/rpc/set_officer_permissions' }, async (d) =>
    d.query(`SELECT public.set_officer_permissions($1, '{"loans":"manage"}'::jsonb)`, [O3]));
  check('T13', 'an Officer with Members = View cannot assign access (gate)', !r.ok && VIEW_ONLY.test(r.error), err(r));
  r = await as(O1, { path: '/rpc/set_officer_permissions' }, async (d) =>
    d.query(`SELECT public.set_officer_permissions($1, '{"loans":"manage"}'::jsonb)`, [F1]));
  check('T13', 'access can only be set on an Officer account', !r.ok && /only be set for an Officer/.test(r.error), err(r));
}

// ───────────────────────── T13 · account management by an Officer ─────────────────────────
{
  const upd = (target, set) => async (d) => (await d.query(`UPDATE user_roles SET ${set} WHERE user_id=$1 RETURNING user_id`, [target])).rows.length;
  let r = await as(O1, { path: '/rpc/suspend_member' }, upd(F1, "status='suspended'"));
  check('T13', 'Members Manage Officer suspends a Farmer (row updated)', r.ok && r.value === 1, err(r));
  r = await as(O1, { path: '/rpc/suspend_member' }, upd(O2, "status='suspended'"));
  check('T13', '... and another Officer (no automatic guard)', r.ok && r.value === 1, err(r));
  r = await as(O1, { path: '/rpc/suspend_member' }, upd(M, "status='suspended'"));
  check('T13', 'accepted risk: ... and the Manager account (Decision 3)', r.ok && r.value === 1, err(r));
  r = await as(O1, { path: '/rpc/suspend_member' }, upd(F1, "role='admin'"));
  check('T13', 'but no role can be changed from the app', !r.ok && /role cannot be changed/.test(r.error), err(r));
  r = await as(O1, { path: '/rpc/suspend_member', gate: false }, upd(F1, "status='suspended'"));
  check('T13', 'without the Members request marker (gate not run) row security updates nothing', r.ok && r.value === 0, err(r));
  r = await as(F2, { path: '/x', gate: false }, upd(F1, "status='suspended'"));
  check('T13', 'a Farmer cannot update another user\'s role row', r.ok && r.value === 0, err(r));
}

// ───────────────────────── T5–T10 · Officer-created Farmers and approval (script 08) ─────────────────────────
let OC, OC2, SR;   // used again by the deletion checks below
const O4 = '00000000-0000-0000-0000-0000000000a4';
{
  await runScript('supabase_schema_officer_permissions_08_farmer_creation_approval.sql');
  // the live database already has this trigger (it calls the function script 08 just replaced)
  await db.exec(`DROP TRIGGER IF EXISTS trg_notify_account_created ON user_roles;
    CREATE TRIGGER trg_notify_account_created AFTER INSERT ON user_roles
    FOR EACH ROW EXECUTE FUNCTION fn_notify_account_created();`);
  await regrant();
  await createUser(O4, 'officer', 'Olga Four', 'off-0005');
  await setLevels(O4, ALL_M);

  const create = (uid, username, name) => as(uid, { path: '/rpc/create_farmer_account', commit: true }, async (d) =>
    (await d.query(
      `SELECT public.create_farmer_account(p_username => $1, p_password => 'Passw0rd1', p_surname => 'Reyes',
         p_first_name => $2, p_date_of_birth => '1990-01-01', p_gender => 'female',
         p_street => 'Rizal St.', p_house_no => '12') AS id`, [username, name])).rows[0].id);

  // ── The Manager creates a Farmer: active at once ──
  const mc = await create(M, 'mgrfarm', 'Ana');
  const mrow = (await q(`SELECT ur.status, ur.must_change_password, fp.is_verified, u.banned_until
      FROM user_roles ur JOIN farmer_profiles fp ON fp.user_id = ur.user_id JOIN auth.users u ON u.id = ur.user_id
      WHERE ur.user_id = $1`, [mc.value]))[0];
  check('T10', 'Manager-created Farmer: active at once, verified, must change the password, not blocked', mc.ok && mrow.status === 'active' && mrow.must_change_password === true && mrow.is_verified === true && mrow.banned_until === null, JSON.stringify(mrow ?? mc));
  const mreq = await q(`SELECT count(*)::int AS n FROM account_creation_requests WHERE user_id = $1`, [mc.value]);
  check('T10', '... with no approval request', mreq[0].n === 0, JSON.stringify(mreq));
  const addr = (await q(`SELECT street, house_no, barangay_name, postal_code FROM buyer_addresses WHERE user_id = $1`, [mc.value]))[0];
  check('T5', 'the address is stored with the fixed service area (as registration does)', addr?.street === 'Rizal St.' && addr.house_no === '12' && addr.barangay_name === 'Payanas' && addr.postal_code === '4903', JSON.stringify(addr));
  const mnote = await q(`SELECT title FROM notifications WHERE user_id = $1`, [mc.value]);
  check('T10', 'the "Account Created" notice is sent for a Manager-created account', mnote.some((n) => n.title === 'Account Created'), JSON.stringify(mnote));

  // ── An Officer creates a Farmer: a pending applicant, NOT banned ──
  OC = await create(O1, 'offfarm1', 'Beth');
  const orow = (await q(`SELECT ur.status, ur.application_attempts, ur.must_change_password, fp.is_verified, u.banned_until,
        r.status AS req, r.requested_by_name, r.requested_by_role
      FROM user_roles ur JOIN farmer_profiles fp ON fp.user_id = ur.user_id JOIN auth.users u ON u.id = ur.user_id
      LEFT JOIN account_creation_requests r ON r.user_id = ur.user_id WHERE ur.user_id = $1`, [OC.value]))[0];
  check('T5', 'Officer-created Farmer is a PENDING applicant, unverified, and must change the password', OC.ok && orow.status === 'pending' && orow.application_attempts === 1 && orow.is_verified === false && orow.must_change_password === true, JSON.stringify(orow ?? OC));
  check('T5', '... it can sign in (no ban) and the request names who created it', orow.banned_until === null && orow.req === 'pending' && orow.requested_by_name === 'Olivia One' && orow.requested_by_role === 'officer', JSON.stringify(orow));
  const ev = await q(`SELECT to_status, actor_name, actor_role FROM member_status_events WHERE member_id = $1`, [OC.value]);
  check('T5', 'the status history records it as created by the Officer', ev.length === 1 && ev[0].to_status === 'pending' && ev[0].actor_name === 'Olivia One' && ev[0].actor_role === 'officer', JSON.stringify(ev));
  const mgrNote = await q(`SELECT body FROM notifications WHERE user_id = $1 AND type = 'member_pending'`, [M]);
  check('T5', 'the Manager is notified, naming the Officer', mgrNote.some((n) => /was created by Olivia One and needs your approval/.test(n.body)), JSON.stringify(mgrNote));
  const fnote = await q(`SELECT count(*)::int AS n FROM notifications WHERE user_id = $1 AND title = 'Account Created'`, [OC.value]);
  check('T5', 'no "created by the Manager" notice for an Officer-created account', fnote[0].n === 0, JSON.stringify(fnote));

  // ── Only the Manager creates Officers ──
  let r = await as(O1, { path: '/rpc/create_officer_account' }, async (d) =>
    d.query(`SELECT public.create_officer_account('offnew1','Passw0rd!','Cruz','Eli',NULL,NULL,NULL,NULL,NULL,NULL,'{"loans":"view"}'::jsonb,NULL)`));
  check('T9', 'an Officer (even with Members = Manage) cannot create an Officer account', !r.ok && /Only the Manager can create an Officer account/.test(r.error), err(r));
  r = await as(M, { path: '/rpc/create_officer_account', commit: true }, async (d) =>
    d.query(`SELECT public.create_officer_account('offnew2','Passw0rd!','Cruz','Fay',NULL,NULL,NULL,NULL,NULL,NULL,'{"loans":"view"}'::jsonb,NULL)`));
  const mo = await q(`SELECT (SELECT count(*)::int FROM account_creation_requests r JOIN auth.users u ON u.id = r.user_id WHERE u.email = 'offnew2@sagana.local') AS reqs,
      (SELECT status FROM user_roles ur JOIN auth.users u ON u.id = ur.user_id WHERE u.email = 'offnew2@sagana.local') AS status`);
  check('T10', 'the Manager creates an Officer: active at once, no request', r.ok && mo[0].reqs === 0 && mo[0].status === 'active', JSON.stringify(mo));

  // ── Who may decide ──
  r = await as(O1, { path: '/rpc/approve_member' }, async (d) => d.query(`SELECT public.approve_member($1)`, [OC.value]));
  check('T7', 'the Officer who created the account cannot approve it', !r.ok && /Only the Manager can approve an account created by an Officer/.test(r.error), err(r));
  r = await as(O4, { path: '/rpc/approve_member' }, async (d) => d.query(`SELECT public.approve_member($1)`, [OC.value]));
  check('T7', 'another Officer with Members = Manage cannot approve it either', !r.ok && /Only the Manager can approve/.test(r.error), err(r));
  r = await as(O4, { path: '/rpc/reject_member' }, async (d) => d.query(`SELECT public.reject_member($1, 'no')`, [OC.value]));
  check('T8', 'nor disapprove it', !r.ok && /Only the Manager can disapprove/.test(r.error), err(r));
  r = await as(O2, { path: '/rpc/approve_member' }, async (d) => d.query(`SELECT public.approve_member($1)`, [OC.value]));
  check('T7', 'an Officer with Members = View Only is stopped by the gate', !r.ok && VIEW_ONLY.test(r.error), err(r));

  // ── A self-registered applicant is still decided by an Officer ──
  SR = '00000000-0000-0000-0000-0000000000e2';
  await db.query(`INSERT INTO auth.users (id,email) VALUES ($1,'selfreg@sagana.local')`, [SR]);
  await as(SR, { path: '/rpc/register_account', gate: false, role: null, commit: true }, async (d) =>
    d.query(`INSERT INTO user_roles (user_id, role, status) VALUES ($1,'farmer','pending')`, [SR]));
  const sreq = await q(`SELECT count(*)::int AS n FROM account_creation_requests WHERE user_id = $1`, [SR]);
  check('T12', 'self-registration is untouched: pending, no request row, not blocked', sreq[0].n === 0 && (await q(`SELECT status FROM user_roles WHERE user_id=$1`, [SR]))[0].status === 'pending', JSON.stringify(sreq));
  r = await as(O4, { path: '/rpc/approve_member', commit: true }, async (d) => d.query(`SELECT public.approve_member($1)`, [SR]));
  const srow = (await q(`SELECT status, pending_acknowledgement FROM user_roles WHERE user_id = $1`, [SR]))[0];
  check('T12', 'an Officer with Members = Manage still approves a self-registered applicant', r.ok && srow.status === 'active' && srow.pending_acknowledgement === true, err(r));

  // ── The Manager approves the Officer-created Farmer ──
  r = await as(M, { path: '/rpc/approve_member', commit: true }, async (d) => d.query(`SELECT public.approve_member($1)`, [OC.value]));
  const arow = (await q(`SELECT ur.status, ur.pending_acknowledgement, fp.is_verified, r.status AS req, r.decided_by_name, r.decided_at
      FROM user_roles ur JOIN farmer_profiles fp ON fp.user_id = ur.user_id JOIN account_creation_requests r ON r.user_id = ur.user_id
      WHERE ur.user_id = $1`, [OC.value]))[0];
  check('T7', 'Manager approves: active, the Continue step is on, verified, request closed with who and when', r.ok && arow.status === 'active' && arow.pending_acknowledgement === true && arow.is_verified === true && arow.req === 'approved' && arow.decided_by_name === 'The Manager' && arow.decided_at, JSON.stringify(arow ?? r));
  const fn1 = await q(`SELECT title FROM notifications WHERE user_id = $1`, [OC.value]);
  check('T7', 'the Farmer is told the membership was approved', fn1.some((n) => n.title === 'Membership Approved'), JSON.stringify(fn1));
  const on1 = await q(`SELECT title FROM notifications WHERE user_id = $1`, [O1]);
  check('T7', 'the creating Officer is told it was approved', on1.some((n) => n.title === 'Account approved'), JSON.stringify(on1));
  r = await as(M, { path: '/rpc/approve_member' }, async (d) => d.query(`SELECT public.approve_member($1)`, [OC.value]));
  check('T7', 'approving again is refused (no duplicate decision)', !r.ok && /Only a pending application can be approved/.test(r.error), err(r));

  // ── The Manager disapproves another one ──
  OC2 = await create(O1, 'offfarm2', 'Cora');
  r = await as(M, { path: '/rpc/reject_member' }, async (d) => d.query(`SELECT public.reject_member($1, '   ')`, [OC2.value]));
  check('T8', 'a reason is required to disapprove', !r.ok && /reason for disapproval is required/.test(r.error), err(r));
  r = await as(M, { path: '/rpc/reject_member', commit: true }, async (d) => d.query(`SELECT public.reject_member($1, 'Duplicate member')`, [OC2.value]));
  const drow = (await q(`SELECT ur.status, ur.rejection_reason, u.banned_until, r.status AS req, r.decision_reason
      FROM user_roles ur JOIN auth.users u ON u.id = ur.user_id JOIN account_creation_requests r ON r.user_id = ur.user_id
      WHERE ur.user_id = $1`, [OC2.value]))[0];
  check('T8', 'disapproval: status rejected with the reason, request closed, still not banned (the Pending screen shows why)', r.ok && drow.status === 'rejected' && drow.rejection_reason === 'Duplicate member' && drow.req === 'disapproved' && drow.decision_reason === 'Duplicate member' && drow.banned_until === null, JSON.stringify(drow ?? r));
  const fn2 = await q(`SELECT title FROM notifications WHERE user_id = $1`, [OC2.value]);
  const on2 = await q(`SELECT title FROM notifications WHERE user_id = $1`, [O1]);
  check('T8', 'the Farmer sees the disapproval notice; the creating Officer is told too', fn2.some((n) => n.title === 'Application Disapproved') && on2.some((n) => n.title === 'Account not approved'), JSON.stringify({ fn2, on2 }));
  // The applicant resubmits (submit_application sets it pending again): still the Manager's decision.
  await db.query(`UPDATE user_roles SET status = 'pending' WHERE user_id = $1`, [OC2.value]);
  r = await as(O4, { path: '/rpc/approve_member' }, async (d) => d.query(`SELECT public.approve_member($1)`, [OC2.value]));
  check('T8', 'after a resubmission an Officer still cannot approve an Officer-created account', !r.ok && /Only the Manager can approve/.test(r.error), err(r));
  r = await as(M, { path: '/rpc/approve_member', commit: true }, async (d) => d.query(`SELECT public.approve_member($1)`, [OC2.value]));
  check('T8', '... the Manager can', r.ok && (await q(`SELECT status FROM account_creation_requests WHERE user_id=$1`, [OC2.value]))[0].status === 'approved', err(r));
  await db.query(`UPDATE user_roles SET status = 'pending' WHERE user_id = $1`, [OC2.value]);
  await as(M, { path: '/rpc/reject_member', commit: true }, async (d) => d.query(`SELECT public.reject_member($1, 'Not eligible')`, [OC2.value]));

  // ── Who can read what ──
  const cnt = async (uid, rel) => (await as(uid, { method: 'GET', path: '/' + rel, gate: false }, async (d) =>
    (await d.query(`SELECT count(*)::int AS n FROM ${rel}`)).rows[0].n)).value;
  const reqM = await cnt(M, 'account_creation_requests'), reqO1 = await cnt(O1, 'account_creation_requests'), reqO4 = await cnt(O4, 'account_creation_requests'), reqF = await cnt(F1, 'account_creation_requests');
  check('T7', 'decision details (the request table) are readable by the Manager only', reqM >= 2 && reqO1 === 0 && reqO4 === 0 && reqF === 0, JSON.stringify({ reqM, reqO1, reqO4, reqF }));
  const srcM = await cnt(M, 'account_creation_sources'), srcO1 = await cnt(O1, 'account_creation_sources'), srcO4 = await cnt(O4, 'account_creation_sources'), srcF = await cnt(F1, 'account_creation_sources');
  check('T5', 'staff read WHO CREATED an applicant (a narrow view); a Farmer reads nothing', srcM >= 2 && srcO1 === srcM && srcO4 === srcM && srcF === 0, JSON.stringify({ srcM, srcO1, srcO4, srcF }));
  const cols = (await q(`SELECT column_name FROM information_schema.columns WHERE table_name = 'account_creation_sources'`)).map((c) => c.column_name);
  check('T7', 'the view exposes no decision details', !cols.some((c) => /decid|decision|status/.test(c)), JSON.stringify(cols));

  // ── Clean-up checks ──
  const gone = await q(`SELECT count(*)::int AS n FROM pg_proc WHERE proname IN ('approve_account_creation','disapprove_account_creation')`);
  check('T7', 'the old approve/disapprove_account_creation functions are gone', gone[0].n === 0, JSON.stringify(gone));
  const banned = await q(`SELECT count(*)::int AS n FROM auth.users WHERE banned_until IS NOT NULL`);
  check('T6', 'nothing is banned any more: pending and disapproved Farmers can sign in to the Pending screen', banned[0].n === 0, JSON.stringify(banned));

  // ── The address is required; the old parameters still work ──
  r = await as(M, { path: '/rpc/create_farmer_account' }, async (d) => d.query(`SELECT public.create_farmer_account(p_username => 'nostreet', p_password => 'Passw0rd1', p_surname => 'A', p_first_name => 'B', p_house_no => '1')`));
  check('T5', 'a Farmer account needs a street', !r.ok && /Street is required/.test(r.error), err(r));
  r = await as(M, { path: '/rpc/create_farmer_account' }, async (d) => d.query(`SELECT public.create_farmer_account(p_username => 'nohouse', p_password => 'Passw0rd1', p_surname => 'A', p_first_name => 'B', p_street => 'S')`));
  check('T5', 'and a house number', !r.ok && /House number is required/.test(r.error), err(r));
  r = await as(M, { path: '/rpc/create_farmer_account', commit: true }, async (d) => (await d.query(
    `SELECT public.create_farmer_account(p_username => 'withcap', p_password => 'Passw0rd1', p_surname => 'A', p_first_name => 'B',
       p_street => 'S', p_house_no => '1', p_initial_contribution => 500) AS id`)).rows[0].id);
  const cap = await q(`SELECT amount FROM capital_contribution_events WHERE farmer_id = $1`, [r.value]);
  check('T5', 'the membership parameters are still honoured when sent (the form just does not send them)', r.ok && cap.length === 1 && Number(cap[0].amount) === 500, JSON.stringify(cap));
}

// ───────────────────────── T12 · approval history (and script 10) ─────────────────────────
{
  await db.query(`INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id) VALUES ($1,'pending','active','Application approved',$2)`, [F2, O1]);
  await db.query(`INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id) VALUES ($1,'pending','rejected','Incomplete',$2)`, [B2, M]);
  const ev = await q(`SELECT to_status, actor_name, actor_role FROM member_status_events WHERE member_id IN ($1,$2) ORDER BY to_status`, [F2, B2]);
  check('T12', 'each approve/disapprove event stores the staff member\'s name and role', ev.length === 2 && ev.find((e) => e.to_status === 'active').actor_name === 'Olivia One' && ev.find((e) => e.to_status === 'active').actor_role === 'officer' && ev.find((e) => e.to_status === 'rejected').actor_role === 'admin', JSON.stringify(ev));
  const read = async (uid, who) => (await as(uid, { method: 'GET', path: '/member_status_events', gate: false }, async (d) =>
    (await d.query(`SELECT count(*)::int AS n FROM member_status_events WHERE member_id = $1`, [who])).rows[0].n)).value;
  const rM = await read(M, F2), rO = await read(O1, F2), rO2 = await read(O2, F2);
  check('T12', 'Manager reads the history; Officers read none', rM === 1 && rO === 0 && rO2 === 0, JSON.stringify({ rM, rO, rO2 }));
  const pol = await q(`SELECT policyname FROM pg_policies WHERE tablename='member_status_events'`);
  check('T12', 'no staff-read policy was added to member_status_events', !pol.some((p) => /staff/i.test(p.policyname)), JSON.stringify(pol));

  // BEFORE script 10 a Farmer could read their own event, including who decided.
  const before = await read(F2, F2);
  const leak = await as(F2, { method: 'GET', path: '/member_status_events', gate: false }, async (d) =>
    (await d.query('SELECT actor_name FROM member_status_events')).rows[0]?.actor_name);
  check('T15', 'BEFORE script 10: a Farmer reads their own status event, including the staff name', before === 1 && leak.value === 'Olivia One', JSON.stringify({ before, leak }));
  await runScript('supabase_schema_officer_permissions_10_status_history_privacy.sql');
  await regrant();
  const after = await read(F2, F2), afterB = await read(B2, B2);
  check('T15', 'AFTER script 10: a Farmer reads no status history at all', after === 0 && afterB === 0, JSON.stringify({ after, afterB }));
  check('T15', '... the Manager still reads it, and the staff name is intact for the Manager', (await read(M, F2)) === 1, 'manager read');
  const pol2 = await q(`SELECT policyname FROM pg_policies WHERE tablename='member_status_events'`);
  check('T15', 'only the Manager policy remains', pol2.length === 1 && /admin manages all/.test(pol2[0].policyname), JSON.stringify(pol2));
  // The applicant's own outcome comes from user_roles, which they still read.
  const own = await as(OC.value, { method: 'GET', path: '/user_roles', gate: false }, async (d) => (await d.query('SELECT status FROM user_roles')).rows);
  check('T15', 'a Farmer still reads their own status (the Pending screen reads user_roles, not the history)', own.ok && own.value.length === 1, JSON.stringify(own));
}

// ───────────────────────── T9 · delete a disapproved account (script 09) ─────────────────────────
{
  await runScript('supabase_schema_officer_permissions_09_delete_disapproved_accounts.sql');
  await regrant();
  const del = (uid, target, commit = false) => as(uid, { path: '/rpc/admin_delete_rejected_applicant', commit }, async (d) =>
    d.query(`SELECT public.admin_delete_rejected_applicant($1)`, [target]));

  // A self-registered applicant the Manager disapproves.
  const sr2 = '00000000-0000-0000-0000-0000000000e3';
  await db.query(`INSERT INTO auth.users (id,email) VALUES ($1,'selfreg2@sagana.local')`, [sr2]);
  await db.query(`INSERT INTO user_roles (user_id, role, status) VALUES ($1,'farmer','pending')`, [sr2]);
  await db.query(`INSERT INTO user_information (user_id, full_name, username) VALUES ($1,'Sela Rego','selarego')`, [sr2]);
  await as(M, { path: '/rpc/reject_member', commit: true }, async (d) => d.query(`SELECT public.reject_member($1, 'Not a member')`, [sr2]));

  // Only the Manager.
  let r = await del(O4, OC2.value);
  check('T9', 'an Officer with Members = Manage cannot delete a disapproved account (Officer-created)', !r.ok && /Only the Manager can delete a disapproved account/.test(r.error), err(r));
  r = await del(O4, sr2);
  check('T9', '... nor a self-registered one', !r.ok && /Only the Manager can delete/.test(r.error), err(r));
  r = await del(O1, OC2.value);
  check('T9', '... not even the Officer who created it', !r.ok && /Only the Manager can delete/.test(r.error), err(r));

  // Refusals.
  r = await del(M, OC.value);
  check('T9', 'an approved (active) account cannot be deleted', !r.ok && /Only disapproved farmer accounts/.test(r.error), err(r));
  r = await del(M, M);
  check('T9', 'the Manager cannot delete their own account', !r.ok && /cannot delete your own account/.test(r.error), err(r));
  r = await del(M, O1);
  check('T9', 'an Officer account is not deletable here', !r.ok && /Only disapproved farmer accounts/.test(r.error), err(r));

  const withHistory = '00000000-0000-0000-0000-0000000000e4';
  await db.query(`INSERT INTO auth.users (id,email) VALUES ($1,'hist@sagana.local')`, [withHistory]);
  await db.query(`INSERT INTO user_roles (user_id, role, status) VALUES ($1,'farmer','rejected')`, [withHistory]);
  await db.query(`INSERT INTO harvest_records (farmer_id) VALUES ($1)`, [withHistory]);
  r = await del(M, withHistory);
  check('T9', 'an account with transaction history is refused, naming what must be kept', !r.ok && /records that must be kept \(harvest_records \(1\)\)/.test(r.error), err(r));
  const withBalance = '00000000-0000-0000-0000-0000000000e5';
  await db.query(`INSERT INTO auth.users (id,email) VALUES ($1,'bal@sagana.local')`, [withBalance]);
  await db.query(`INSERT INTO user_roles (user_id, role, status) VALUES ($1,'farmer','rejected')`, [withBalance]);
  await db.query(`INSERT INTO member_capital_shares (farmer_id, share_value_per_unit, total_contribution) VALUES ($1, 2000, 100)`, [withBalance]);
  r = await del(M, withBalance);
  check('T9', 'a capital balance above zero is refused', !r.ok && /member_capital_shares \(balance\)/.test(r.error), err(r));
  const stillThere = await q(`SELECT count(*)::int AS n FROM auth.users WHERE id IN ($1,$2)`, [withHistory, withBalance]);
  check('T9', '... and nothing was deleted', stillThere[0].n === 2, JSON.stringify(stillThere));

  // The Manager deletes: an Officer-created Farmer (its zero-balance capital row is not a record).
  const zero = (await q(`SELECT total_contribution FROM member_capital_shares WHERE farmer_id = $1`, [OC2.value]))[0];
  r = await del(M, OC2.value, true);
  const gone = await q(`SELECT (SELECT count(*)::int FROM auth.users WHERE id=$1) AS u, (SELECT count(*)::int FROM user_roles WHERE user_id=$1) AS r,
      (SELECT count(*)::int FROM account_creation_requests WHERE user_id=$1) AS q`, [OC2.value]);
  check('T9', 'the Manager deletes an Officer-created disapproved Farmer (zero-balance capital row does not block)', r.ok && Number(zero.total_contribution) === 0 && gone[0].u === 0 && gone[0].r === 0 && gone[0].q === 0, JSON.stringify({ zero, gone, err: err(r) }));
  const logOc = (await q(`SELECT actor_name, actor_role, old_values FROM admin_activity_log WHERE source = 'db' AND description LIKE 'Deleted a disapproved account%' AND reference_id = $1`, [OC2.value]))[0];
  check('T9', 'the accountability entry says who created it, who disapproved it and why, and who deleted it', logOc?.actor_name === 'The Manager' && logOc.actor_role === 'admin' && logOc.old_values.created_by === 'Olivia One' && logOc.old_values.created_by_role === 'officer' && logOc.old_values.disapproved_by === 'The Manager' && logOc.old_values.reason === 'Not eligible', JSON.stringify(logOc));

  // ... and a self-registered one.
  r = await del(M, sr2, true);
  const logSr = (await q(`SELECT old_values FROM admin_activity_log WHERE source = 'db' AND description LIKE 'Deleted a disapproved account%' AND reference_id = $1`, [sr2]))[0];
  check('T9', 'the Manager deletes a self-registered disapproved applicant; the log says it was self-registered', r.ok && logSr?.old_values.created_by === 'Self-registered' && logSr.old_values.username === 'selarego' && logSr.old_values.reason === 'Not a member', JSON.stringify(logSr ?? err(r)));
  check('T9', 'the entry is part of the trail the Manager reads in Staff Accountability (source db)', (await q(`SELECT count(*)::int AS n FROM admin_activity_log WHERE source='db' AND description LIKE 'Deleted a disapproved account%'`))[0].n === 2, 'count');
}

// ───────────────────────── T15 · Broadcast (script 03, then script 11) ─────────────────────────
{
  const ins = (uid, o = {}) => as(uid, { path: '/broadcast_logs', ...o }, async (d) =>
    d.query(`INSERT INTO broadcast_logs (title, body, scheduled_at, client_key) VALUES ('t','b', now() + interval '1 day', gen_random_uuid()::text)`));
  let r = await ins(O1);
  check('T15', 'BEFORE script 03: an Officer with Dashboard = Manage cannot schedule (row security refuses)', !r.ok && /row-level security/.test(r.error), err(r));
  r = await ins(M);
  check('T15', 'BEFORE script 03: the Manager can', r.ok, err(r));

  await runScript('supabase_schema_officer_permissions_03_broadcast_access.sql');
  await regrant();

  r = await ins(O1);
  check('T15', 'AFTER script 03: Dashboard = Manage Officer schedules a broadcast', r.ok, err(r));
  r = await ins(O3);
  check('T15', 'AFTER 03, before 11: Dashboard = View Only Officer is refused by the gate (the original design)', !r.ok && VIEW_ONLY.test(r.error), err(r));
  await setLevels(O3, ALL_V);
  r = await ins(F1, { gate: true });
  check('T15', 'AFTER: a Farmer cannot write broadcast_logs', !r.ok && /row-level security/.test(r.error), err(r));
  const bid = (await q(`INSERT INTO broadcast_logs (title, body, client_key) VALUES ('x','y','k-edit') RETURNING id`))[0].id;
  r = await as(O1, { method: 'PATCH', path: '/broadcast_logs' }, async (d) => (await d.query(`UPDATE broadcast_logs SET title='edited' WHERE id=$1 RETURNING id`, [bid])).rows.length);
  check('T15', 'AFTER: Manage Officer can edit a broadcast', r.ok && r.value === 1, err(r));
  r = await as(O1, { method: 'DELETE', path: '/broadcast_logs' }, async (d) => (await d.query(`DELETE FROM broadcast_logs WHERE id=$1 RETURNING id`, [bid])).rows.length);
  check('T15', 'AFTER: Manage Officer can delete a broadcast', r.ok && r.value === 1, err(r));
  r = await as(O3, { method: 'DELETE', path: '/broadcast_logs' }, async (d) => d.query(`DELETE FROM broadcast_logs`));
  check('T15', 'AFTER 03, before 11: View Only Officer cannot delete', !r.ok && VIEW_ONLY.test(r.error), err(r));
  r = await as(O1, { path: '/notifications' }, async (d) => d.query(`INSERT INTO notifications (user_id,type,title,body) VALUES ($1,'general','Notice','Body')`, [F1]));
  check('T15', 'AFTER: Manage Officer can insert a notice for a Farmer (broadcast delivery)', r.ok, err(r));
  r = await as(F1, { path: '/notifications' }, async (d) => d.query(`INSERT INTO notifications (user_id,type,title,body) VALUES ($1,'general','Fake','Body')`, [F2]));
  check('T15', 'AFTER: a Farmer still cannot insert a notice for someone else', !r.ok && /row-level security/.test(r.error), err(r));
  const tgt = await q(`SELECT kind, name, module FROM staff_permission_targets WHERE name IN ('send_broadcast','broadcast_logs') ORDER BY name`);
  check('T15', 'before 11: send_broadcast and broadcast_logs are governed by the Dashboard module', tgt.length === 2 && tgt.every((t) => t.module === 'dashboard'), JSON.stringify(tgt));

  // Script 11: Broadcast is a primary screen; every Officer can use it, anytime.
  await runScript('supabase_schema_officer_permissions_11_broadcast_open.sql');
  await regrant();
  const tgt2 = await q(`SELECT name FROM staff_permission_targets WHERE name IN ('send_broadcast','broadcast_logs')`);
  const price = await q(`SELECT module FROM staff_permission_targets WHERE name = 'notify_price_update'`);
  check('T15', 'AFTER script 11: Broadcast is no longer governed by any module', tgt2.length === 0, JSON.stringify(tgt2));
  check('T15', '... price announcements still belong to Dashboard (only Broadcast was opened)', price.length === 1 && price[0].module === 'dashboard', JSON.stringify(price));
  const gateOnly = await as(O3, { path: '/rpc/send_broadcast' }, async (d) => d.query('SELECT 1'));
  check('T15', 'AFTER 11: the gate lets a View Only Officer call send_broadcast', gateOnly.ok, err(gateOnly));
  const sched = await as(O3, { path: '/broadcast_logs', commit: true }, async (d) =>
    d.query(`INSERT INTO broadcast_logs (title, body, created_by, scheduled_at, client_key) VALUES ('Open to all','b', $1, now() + interval '1 day', 'k-open')`, [O3]));
  check('T15', 'AFTER 11: an Officer with every module on View Only schedules a broadcast', sched.ok, err(sched));
  const logRow = (await q(`SELECT actor_name, actor_role, module, operation, reference_label FROM admin_activity_log WHERE source = 'db' AND table_name = 'broadcast_logs' ORDER BY created_at DESC LIMIT 1`))[0];
  check('T15', '... and the audit trail records who made it (name, role, module broadcast)', logRow?.actor_name === 'Oscar Three' && logRow.actor_role === 'officer' && logRow.module === 'broadcast' && logRow.operation === 'created', JSON.stringify(logRow));
  const edit11 = await as(O3, { method: 'PATCH', path: '/broadcast_logs', commit: true }, async (d) =>
    (await d.query(`UPDATE broadcast_logs SET title = 'Open to all (edited)' WHERE client_key = 'k-open' RETURNING id`)).rows.length);
  check('T15', 'AFTER 11: the same Officer can edit it, and the edit is attributed too', edit11.ok && edit11.value === 1 && (await q(`SELECT count(*)::int AS n FROM admin_activity_log WHERE source='db' AND table_name='broadcast_logs' AND operation='updated' AND actor_name='Oscar Three'`))[0].n === 1, err(edit11));
  const farmerWrite = await as(F1, { path: '/broadcast_logs' }, async (d) =>
    d.query(`INSERT INTO broadcast_logs (title, body, client_key) VALUES ('x','y','k-farmer')`));
  check('T15', 'AFTER 11: a Farmer still cannot write broadcast_logs', !farmerWrite.ok && /row-level security/.test(farmerWrite.error), err(farmerWrite));
  await db.query(`DELETE FROM broadcast_logs WHERE client_key = 'k-open'`);
  // Script 07: no direct notification inserts by staff.
  r = await as(O3, { path: '/notifications' }, async (d) => d.query(`INSERT INTO notifications (user_id,type,title,body) VALUES ($1,'general','Spam','Body')`, [F1]));
  check('T15', 'BEFORE script 07: even a View Only Officer can post a notification to any user through the API (the hole)', r.ok, err(r));
  await runScript('supabase_schema_officer_permissions_07_notification_policy.sql');
  await regrant();
  for (const [uid, label] of [[O1, 'a Manage Officer'], [O3, 'a View Only Officer'], [M, 'the Manager'], [F1, 'a Farmer']]) {
    r = await as(uid, { path: '/notifications' }, async (d) => d.query(`INSERT INTO notifications (user_id,type,title,body) VALUES ($1,'general','Direct','Body')`, [F2]));
    check('T15', `AFTER script 07: ${label} cannot insert a notification directly`, !r.ok && /row-level security/.test(r.error), err(r));
  }
  const own = await as(F1, { method: 'GET', path: '/notifications', gate: false }, async (d) => (await d.query('SELECT count(*)::int AS n FROM notifications')).rows[0].n);
  check('T15', 'reading one\'s own notifications is unaffected', own.ok, err(own));
  const polN = await q(`SELECT cmd FROM pg_policies WHERE tablename='notifications' AND cmd = 'INSERT'`);
  check('T15', 'no INSERT policy remains on notifications', polN.length === 0, JSON.stringify(polN));
}

// ───────────────────────── T16 · Balik-Tangkilik ─────────────────────────
{
  const write = (uid, extra = {}) => as(uid, { path: '/cooperative_annual_totals', ...extra }, async (d) =>
    d.query(`INSERT INTO cooperative_annual_totals (year, total) VALUES ($1, 1000)`, [2099 + Math.floor(Math.random() * 1000)]));
  let r = await write(O1);
  check('T16', 'Officer (all Manage, even Members) cannot write Balik year totals', !r.ok && /row-level security/.test(r.error), err(r));
  const membersCtx = await as(O1, { path: '/rpc/approve_member' }, async (d) => {
    const pa = (await d.query('SELECT public.is_platform_admin() AS v')).rows[0].v;
    let wrote = true;
    try { await d.exec('SAVEPOINT s'); await d.query(`INSERT INTO cooperative_annual_totals (year,total) VALUES (3001,1)`); } catch (e) { wrote = false; await d.exec('ROLLBACK TO s'); }
    return { pa, wrote };
  });
  check('T16', 'inside a Members request (is_platform_admin true) Balik writes are STILL refused', membersCtx.ok && membersCtx.value.pa === true && membersCtx.value.wrote === false, JSON.stringify(membersCtx.value ?? membersCtx.error));
  r = await write(M);
  check('T16', 'Manager can write Balik year totals', r.ok, err(r));
  const tgt = await q(`SELECT name FROM staff_permission_targets WHERE name ~ '(payout|patronage|annual|balik)'`);
  check('T16', 'no Balik table or RPC is mapped to an Officer-assignable module', tgt.length === 0, JSON.stringify(tgt));
}

// ───────────────────────── T20 · accountability trail ─────────────────────────
{
  const crop = (await q(`INSERT INTO crop_master (crop_name, price) VALUES ('Tomato', 40) RETURNING id`))[0].id;
  await db.query(`TRUNCATE admin_activity_log`);
  let r = await as(O1, { commit: true, method: 'PATCH', path: '/crop_master' }, async (d) => d.query(`UPDATE crop_master SET price = 45, updated_at = now() WHERE id=$1`, [crop]));
  let log = await q(`SELECT * FROM admin_activity_log WHERE source='db' AND table_name='crop_master'`);
  check('T20', 'an Officer\'s crop price edit is logged: name, role, module, operation', r.ok && log.length === 1 && log[0].actor_name === 'Olivia One' && log[0].actor_role === 'officer' && log[0].module === 'crops' && log[0].operation === 'updated', JSON.stringify(log));
  check('T20', 'only the changed columns are recorded, old and new side by side (updated_at ignored)', JSON.stringify(Object.keys(log[0]?.new_values ?? {})) === '["price"]' && Number(log[0].old_values.price) === 40 && Number(log[0].new_values.price) === 45, JSON.stringify(log[0]));
  check('T20', 'the record id and a human reference are stored', log[0]?.record_id === crop && log[0].reference_label === 'Tomato', JSON.stringify(log[0]));
  r = await as(M, { commit: true, method: 'POST', path: '/price_records' }, async (d) => d.query(`INSERT INTO price_records (crop_name, price_per_kg) VALUES ('Rice', 52)`));
  log = await q(`SELECT actor_name, actor_role, module, operation FROM admin_activity_log WHERE table_name='price_records'`);
  check('T20', 'the Manager\'s price record is attributed to the Manager', log.length === 1 && log[0].actor_role === 'admin' && log[0].module === 'prices' && log[0].operation === 'created', JSON.stringify(log));
  r = await as(O1, { commit: true, method: 'POST', path: '/farmer_loans' }, async (d) => d.query(`INSERT INTO farmer_loans (farmer_id, reference_no, status, total_value) VALUES ($1,'LRN-1','active',100)`, [F1]));
  r = await as(O1, { commit: true, method: 'POST', path: '/cooperative_inventory' }, async (d) => d.query(`INSERT INTO cooperative_inventory (item_name, quantity_on_hand) VALUES ('Seeds', 10)`));
  r = await as(O1, { commit: true, path: '/rpc/suspend_member' }, async (d) => d.query(`UPDATE user_roles SET status='suspended', suspension_reason='test' WHERE user_id=$1`, [F1]));
  const ur = await q(`SELECT actor_name, actor_role, module, old_values, new_values FROM admin_activity_log WHERE source='db' AND table_name='user_roles' AND reference_label='Farah One'`);
  check('T20', 'a status change by an Officer is recorded: who, module members, status old -> new', r.ok && ur.length === 1 && ur[0].actor_name === 'Olivia One' && ur[0].module === 'members' && ur[0].old_values.status === 'active' && ur[0].new_values.status === 'suspended', JSON.stringify(ur));
  const mods = (await q(`SELECT DISTINCT module FROM admin_activity_log WHERE source='db' ORDER BY 1`)).map((x) => x.module);
  check('T20', 'loan and inventory writes are audited too', mods.includes('loans') && mods.includes('inventory'), JSON.stringify(mods));
  await as(O1, { commit: true, method: 'PATCH', path: '/crop_master' }, async (d) => d.query(`UPDATE crop_master SET price = 45 WHERE id=$1`, [crop]));
  const noop = await q(`SELECT count(*)::int AS n FROM admin_activity_log WHERE table_name='crop_master'`);
  check('T20', 'a no-change update writes no log row', noop[0].n === 1, JSON.stringify(noop));
  await db.query(`SELECT set_config('request.jwt.claims','',false)`);
  r = await as(F1, { path: '/x', gate: false, role: null }, async (d) => d.query(`UPDATE crop_master SET price = 1 WHERE id=$1`, [crop]));
  const farmerRows = await q(`SELECT count(*)::int AS n FROM admin_activity_log WHERE actor_role NOT IN ('admin','officer')`);
  check('T20', 'a Farmer\'s change to an audited table is not logged as staff', farmerRows[0].n === 0, JSON.stringify(farmerRows));
  const forge = await as(O1, { path: '/admin_activity_log', gate: false }, async (d) =>
    d.query(`INSERT INTO admin_activity_log (admin_id, module, action_type, description, source) VALUES ($1,'crops','created','forged','db')`, [O1]));
  check('T20', 'an Officer cannot insert a database-written (source=db) row from the client', !forge.ok && /row-level security/.test(forge.error), err(forge));
  const own = await as(O1, { path: '/admin_activity_log', gate: false }, async (d) =>
    d.query(`INSERT INTO admin_activity_log (admin_id, module, action_type, description) VALUES ($1,'crops','created','app message')`, [O1]));
  const own2 = (await q(`SELECT actor_name, actor_role, source FROM admin_activity_log WHERE description='app message'`));
  check('T20', 'the app\'s own message rows still insert, and the database stamps the real name and role', own.ok === true && true, err(own));
  const other = await as(O1, { path: '/admin_activity_log', gate: false }, async (d) =>
    d.query(`INSERT INTO admin_activity_log (admin_id, module, action_type, description) VALUES ($1,'crops','created','as someone else')`, [O2]));
  check('T20', 'an Officer cannot log an action under another staff member\'s name', !other.ok, err(other));
  const sees = async (uid) => (await as(uid, { method: 'GET', path: '/admin_activity_log', gate: false }, async (d) =>
    (await d.query(`SELECT count(*) FILTER (WHERE source='db')::int AS db, count(*) FILTER (WHERE source='app')::int AS app FROM admin_activity_log`)).rows[0])).value;
  const sM = await sees(M), sO = await sees(O1);
  check('T20', 'Manager reads the database trail; an Officer reads none of it', sM.db >= 4 && sO.db === 0, JSON.stringify({ sM, sO }));
  const tamper = await as(M, { commit: true, path: '/admin_activity_log', gate: false }, async (d) => d.query(`UPDATE admin_activity_log SET description='x'`));
  const tdel = await as(M, { commit: true, path: '/admin_activity_log', gate: false }, async (d) => d.query(`DELETE FROM admin_activity_log`));
  const left = await q(`SELECT count(*)::int AS n FROM admin_activity_log`);
  check('T20', 'nobody (not even the Manager) can edit or delete log rows through the API', left[0].n >= 4 && (await q(`SELECT count(*)::int AS n FROM admin_activity_log WHERE description='x'`))[0].n === 0, JSON.stringify({ tamper: tamper.ok, tdel: tdel.ok, left }));
  const trg = await q(`SELECT count(*)::int AS n FROM information_schema.triggers WHERE trigger_name='trg_audit_staff_change'`);
  check('T20', 'audit triggers attach to the audited tables that exist', trg[0].n >= 8, JSON.stringify(trg));
}

// ───────────────────────── T19 · Buyers cannot be suspended ─────────────────────────
{
  await db.query(`UPDATE user_roles SET status='suspended', suspension_reason='old', suspended_until=now() WHERE user_id IN ($1,$2)`, [B1, B2]);
  await db.query(`UPDATE user_roles SET status='suspended' WHERE user_id=$1`, [F2]);
  await runScript('supabase_schema_buyer_suspension_removal.sql');
  const b = await q(`SELECT status, suspension_reason, suspended_until FROM user_roles WHERE role='buyer'`);
  check('T19', 'suspended Buyers were set back to Active, reason and end date cleared', b.length === 2 && b.every((x) => x.status === 'active' && x.suspension_reason === null && x.suspended_until === null), JSON.stringify(b));
  const hist = await q(`SELECT count(*)::int AS n FROM member_status_events WHERE member_id IN ($1,$2) AND from_status='suspended' AND to_status='active'`, [B1, B2]);
  check('T19', 'one history row per reactivated Buyer', hist[0].n === 2, JSON.stringify(hist));
  const f = await q(`SELECT status FROM user_roles WHERE user_id=$1`, [F2]);
  check('T19', 'a suspended Farmer is left suspended (Farmer suspension untouched)', f[0].status === 'suspended', JSON.stringify(f));
  let r = await as(O1, { path: '/rpc/suspend_member' }, async (d) => d.query(`UPDATE user_roles SET status='suspended' WHERE user_id=$1`, [B1]));
  check('T19', 'suspending a Buyer is now refused by the database (even by a Manage Officer)', !r.ok && /user_roles_buyer_never_suspended/.test(r.error), err(r));
  r = await as(M, { path: '/rpc/suspend_member' }, async (d) => d.query(`UPDATE user_roles SET status='suspended' WHERE user_id=$1`, [B1]));
  check('T19', '... and by the Manager', !r.ok && /user_roles_buyer_never_suspended/.test(r.error), err(r));
  r = await as(M, { path: '/rpc/suspend_member' }, async (d) => d.query(`UPDATE user_roles SET status='suspended' WHERE user_id=$1`, [F1]));
  check('T19', 'Farmer suspension still works', r.ok, err(r));
  await runScript('supabase_schema_buyer_suspension_removal.sql');
  check('T19', 'the script is safe to re-run', true);
}

// ───────────────────────── gate registration (script 06) ─────────────────────────
{
  await runScript('supabase_schema_officer_permissions_06_enable_gate.sql');
  const cfg = await q(`SELECT rolconfig::text AS c FROM pg_roles WHERE rolname='authenticator'`);
  check('T4', 'script 06 stores pgrst.db_pre_request = public.staff_permission_gate on the authenticator role', /pgrst\.db_pre_request=public\.staff_permission_gate/.test(cfg[0]?.c ?? ''), JSON.stringify(cfg));
  const anonGrant = await q(`SELECT has_function_privilege('anon','public.staff_permission_gate()','EXECUTE') AS a, has_function_privilege('authenticated','public.staff_permission_gate()','EXECUTE') AS b`);
  check('T4', 'the gate is executable by anon and authenticated (so no request fails before it runs)', anonGrant[0].a && anonGrant[0].b, JSON.stringify(anonGrant));
}

// ───────────────────────── N5 · member activity logbook (script 12) ─────────────────────────
{
  const attempt = (uid, opts, sql, params = []) => as(uid, { gate: true, ...opts }, async (d) => (await d.query(sql, params)));
  const seedEvent = async (member, reason) =>
    (await q(`INSERT INTO member_status_events (member_id, from_status, to_status, reason, actor_id) VALUES ($1,'pending','active',$2,$3) RETURNING id`, [member, reason, M]))[0].id;

  // BEFORE: the hole this closes.
  let ev = await seedEvent(F1, 'seed-1');
  let r = await as(O1, { method: 'DELETE', path: '/member_status_events', commit: true }, async (d) =>
    (await d.query(`DELETE FROM member_status_events WHERE id = $1 RETURNING id`, [ev])).rows.length);
  check('N5', 'BEFORE script 12: an Officer with Members = Manage can delete a status-history row (the hole)', r.ok && r.value === 1, err(r));

  await runScript('supabase_schema_officer_permissions_12_member_activity_logbook.sql');
  // (no regrant here: the script creates no table, and a re-grant would undo its REVOKEs)

  const gone = await q(`SELECT count(*)::int AS n FROM staff_permission_targets WHERE name = 'member_status_events'`);
  check('N5', 'AFTER script 12: member_status_events is no longer a Members-gated table', gone[0].n === 0, JSON.stringify(gone));
  ev = await seedEvent(F1, 'seed-2');
  const stillThere = async () => (await q(`SELECT reason FROM member_status_events WHERE id = $1`, [ev]))[0]?.reason;

  for (const [label, uid] of [['an Officer with Members = Manage', O1], ['the Manager', M], ['a Farmer', F1]]) {
    r = await attempt(uid, { method: 'DELETE', path: '/member_status_events', commit: true }, `DELETE FROM member_status_events WHERE id = $1`, [ev]);
    check('N5', `${label} cannot delete a status-history row through the API`, !r.ok && /permission denied/.test(r.error) && (await stillThere()) === 'seed-2', err(r));
    r = await attempt(uid, { method: 'PATCH', path: '/member_status_events', commit: true }, `UPDATE member_status_events SET reason = 'tampered' WHERE id = $1`, [ev]);
    check('N5', `${label} cannot edit one`, !r.ok && /permission denied/.test(r.error) && (await stillThere()) === 'seed-2', err(r));
  }
  r = await attempt(O1, { method: 'POST', path: '/member_status_events', commit: true }, `INSERT INTO member_status_events (member_id, to_status, reason, actor_id) VALUES ($1,'active','forged',$2)`, [F2, M]);
  check('N5', 'an Officer cannot forge a status-history row', !r.ok && /permission denied/.test(r.error), err(r));

  const readHist = async (uid) => (await as(uid, { method: 'GET', path: '/member_status_events', gate: false }, async (d) =>
    (await d.query(`SELECT count(*)::int AS n FROM member_status_events WHERE id = $1`, [ev])).rows[0].n)).value;
  check('N5', 'the Manager reads the history; Officers and Farmers read none', (await readHist(M)) === 1 && (await readHist(O1)) === 0 && (await readHist(F1)) === 0, 'read');

  // The functions that write it still can: approve a fresh applicant.
  const pend = '00000000-0000-0000-0000-0000000000f1';
  await db.query(`INSERT INTO auth.users (id,email) VALUES ($1,'logbook1@sagana.local')`, [pend]);
  await db.query(`INSERT INTO user_roles (user_id, role, status) VALUES ($1,'farmer','pending')`, [pend]);
  r = await as(M, { path: '/rpc/approve_member', commit: true }, async (d) => d.query(`SELECT public.approve_member($1)`, [pend]));
  const wrote = await q(`SELECT actor_name, actor_role, to_status FROM member_status_events WHERE member_id = $1`, [pend]);
  check('N5', 'approve_member still writes the history (with the staff name)', r.ok && wrote.length === 1 && wrote[0].actor_name === 'The Manager' && wrote[0].to_status === 'active', JSON.stringify(wrote));

  // The logbook itself cannot be changed.
  const logId = (await q(`SELECT id FROM admin_activity_log WHERE source = 'db' LIMIT 1`))[0].id;
  const before = (await q(`SELECT count(*)::int AS n FROM admin_activity_log`))[0].n;
  for (const [label, uid] of [['an Officer', O1], ['the Manager', M]]) {
    r = await attempt(uid, { method: 'PATCH', path: '/admin_activity_log', commit: true, gate: false }, `UPDATE admin_activity_log SET description = 'rewritten' WHERE id = $1`, [logId]);
    check('N5', `${label} cannot rewrite a logbook entry`, !r.ok && /permission denied/.test(r.error), err(r));
    r = await attempt(uid, { method: 'DELETE', path: '/admin_activity_log', commit: true, gate: false }, `DELETE FROM admin_activity_log WHERE id = $1`, [logId]);
    check('N5', `${label} cannot delete one`, !r.ok && /permission denied/.test(r.error), err(r));
  }
  check('N5', '... and the logbook is intact', (await q(`SELECT count(*)::int AS n FROM admin_activity_log`))[0].n === before && (await q(`SELECT description FROM admin_activity_log WHERE id=$1`, [logId]))[0].description !== 'rewritten', 'intact');

  // Every kind of Members-tab action leaves a record: who, which member, what, details.
  const rows = async (where, params = []) => q(`SELECT actor_name, actor_role, module, table_name, operation, reference_label, old_values, new_values
      FROM admin_activity_log WHERE source = 'db' AND ${where} ORDER BY created_at DESC`, params);
  const asStaff = (uid, sql, params = []) => as(uid, { path: '/rpc/members_action', gate: false, role: null, commit: true }, async (d) => d.query(sql, params));

  // A fresh member, so earlier scenarios cannot blur what is checked here.
  const N5F = '00000000-0000-0000-0000-0000000000f5';
  await createUser(N5F, 'farmer', 'Nora Five', 'sp3-0050');

  // Suspend (with reason and end date) and reactivate.
  await asStaff(O1, `UPDATE user_roles SET status='suspended', suspension_reason='Unpaid contributions', suspended_until = now() + interval '30 days' WHERE user_id=$1`, [N5F]);
  let rec = (await rows(`table_name='user_roles' AND reference_label='Nora Five' AND new_values->>'status'='suspended'`))[0];
  check('N5', 'Suspend: who, which member, status before and after, and the reason', rec?.actor_name === 'Olivia One' && rec.actor_role === 'officer' && rec.module === 'members' && rec.old_values.status === 'active' && rec.new_values.suspension_reason === 'Unpaid contributions', JSON.stringify(rec));
  await asStaff(O1, `UPDATE user_roles SET status='active', suspension_reason=NULL, suspended_until=NULL WHERE user_id=$1`, [N5F]);
  rec = (await rows(`table_name='user_roles' AND reference_label='Nora Five' AND new_values->>'status'='active'`))[0];
  check('N5', 'Reactivate is recorded', rec?.actor_name === 'Olivia One' && rec.old_values.status === 'suspended', JSON.stringify(rec));

  // Add a contribution.
  await asStaff(O1, `INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by) VALUES ($1, 250, 'member_payment', 'March', $2)`, [N5F, O1]);
  rec = (await rows(`table_name='capital_contribution_events' AND reference_label='Nora Five'`))[0];
  check('N5', 'Add a contribution: who, which member, amount, source and note', rec?.actor_name === 'Olivia One' && rec.operation === 'created' && Number(rec.new_values.amount) === 250 && rec.new_values.source === 'member_payment' && rec.new_values.note === 'March', JSON.stringify(rec));

  // Editing member information (NEW in this script).
  await asStaff(O1, `UPDATE user_information SET phone_number = '09171234567' WHERE user_id = $1`, [N5F]);
  rec = (await rows(`table_name='user_information' AND reference_label='Nora Five'`))[0];
  check('N5', 'Edit member information: who, which member, the field before and after', rec?.actor_name === 'Olivia One' && rec.operation === 'updated' && rec.new_values.phone_number === '09171234567', JSON.stringify(rec));
  await db.query(`INSERT INTO farmer_profiles (user_id) VALUES ($1)`, [N5F]);
  await asStaff(M, `UPDATE farmer_profiles SET gender = 'female' WHERE user_id = $1`, [N5F]);
  rec = (await rows(`table_name='farmer_profiles' AND reference_label='Nora Five'`))[0];
  check('N5', '... farmer profile edits are recorded too', rec?.actor_name === 'The Manager' && rec.new_values.gender === 'female', JSON.stringify(rec));
  const n0 = (await q(`SELECT count(*)::int AS n FROM admin_activity_log WHERE table_name IN ('user_information','farmer_profiles')`))[0].n;
  await asStaff(O1, `UPDATE user_information SET phone_number = '09170000000' WHERE user_id = $1`, [O1]);
  await asStaff(N5F, `UPDATE user_information SET phone_number = '09175550000' WHERE user_id = $1`, [N5F]);
  check('N5', 'a staff member editing their OWN profile, and a Farmer editing theirs, are not logged', (await q(`SELECT count(*)::int AS n FROM admin_activity_log WHERE table_name IN ('user_information','farmer_profiles')`))[0].n === n0, 'self edits');

  // Officer access, password help request, password reset.
  await asStaff(M, `SELECT public.set_officer_permissions($1, '{"loans":"view"}'::jsonb)`, [O2]);
  rec = (await rows(`table_name='officer_permissions' AND reference_label='Omar Two'`))[0];
  check('N5', 'Change an Officer\'s access: who, which Officer, the module and level', rec?.actor_name === 'The Manager' && rec.new_values.module === 'loans' && rec.new_values.access_level === 'view', JSON.stringify(rec));
  await asStaff(O1, `UPDATE user_roles SET must_change_password = true WHERE user_id = $1`, [F2]);
  rec = (await rows(`table_name='user_roles' AND reference_label='Farid Two' AND new_values->>'must_change_password'='true'`))[0];
  check('N5', 'Reset a member\'s password: recorded against that member', rec?.actor_name === 'Olivia One', JSON.stringify(rec));
}

// ───────────────────────── Item 3 · cooperative yearly totals (script 13) ─────────────────────────
{
  await db.query(`INSERT INTO cooperative_annual_totals (year, total) VALUES (2026, 1000)`);
  const seen = async (uid, role) => (await as(uid, { method: 'GET', path: '/cooperative_annual_totals', gate: false, role }, async (d) =>
    (await d.query('SELECT count(*)::int AS n FROM cooperative_annual_totals')).rows[0].n)).value;
  check('Item3', 'BEFORE script 13: a Buyer can read the cooperative yearly totals (the gap)', (await seen(B1, 'authenticated')) === 1, 'buyer');
  await runScript('supabase_schema_officer_permissions_13_annual_totals_no_buyers.sql');
  await regrant();
  check('Item3', 'AFTER script 13: a Buyer reads nothing', (await seen(B1, 'authenticated')) === 0 && (await seen(B2, 'authenticated')) === 0, 'buyer');
  check('Item3', '... Farmers read as before (My Contribution)', (await seen(F1, 'authenticated')) === 1, 'farmer');
  check('Item3', '... Officers and the Manager read as before', (await seen(O1, 'authenticated')) === 1 && (await seen(O3, 'authenticated')) === 1 && (await seen(M, 'authenticated')) === 1, 'staff');
  check('Item3', '... and a signed-out visitor still reads nothing', (await seen(null, 'anon')) === 0, 'anon');
  const w = await as(B1, { path: '/cooperative_annual_totals', gate: false }, async (d) => d.query(`INSERT INTO cooperative_annual_totals (year, total) VALUES (2027, 1)`));
  check('Item3', 'writes are unchanged: a Buyer still cannot write', !w.ok && /row-level security/.test(w.error), err(w));
  const pol = await q(`SELECT policyname FROM pg_policies WHERE tablename='cooperative_annual_totals' AND cmd='SELECT'`);
  check('Item3', 'the old "authenticated reads" rule is replaced, the staff read rule is untouched', !pol.some((p) => /authenticated reads/.test(p.policyname)) && pol.some((p) => /admin manages all \(read\)/.test(p.policyname)), JSON.stringify(pol));
}

// ───────────────────────── Storage · inventory photos (scripts 14 and 15) ─────────────────────────
{
  const BUCKET = 'cooperative_inventory_images';
  const put = (uid, bucket, name) => as(uid, { path: '/storage/object', gate: false, commit: true }, async (d) =>
    d.query(`INSERT INTO storage.objects (bucket_id, name, owner) VALUES ($1,$2,$3)`, [bucket, name, uid]));
  const touch = (uid, kind, name) => as(uid, { path: '/storage/object', gate: false, commit: true }, async (d) =>
    (await d.query(kind === 'delete'
      ? `DELETE FROM storage.objects WHERE bucket_id=$1 AND name=$2 RETURNING id`
      : `UPDATE storage.objects SET owner = owner WHERE bucket_id=$1 AND name=$2 RETURNING id`, [BUCKET, name])).rows.length);
  const view = async (uid, role) => (await as(uid, { method: 'GET', path: '/storage/object', gate: false, role }, async (d) =>
    (await d.query(`SELECT count(*)::int AS n FROM storage.objects WHERE bucket_id = $1`, [BUCKET])).rows[0].n)).value;

  await db.query(`INSERT INTO storage.objects (bucket_id, name, owner) VALUES ($1, $2, $3)`, [BUCKET, `${M}/item_1.jpg`, M]);
  let r = await put(B1, BUCKET, `${B1}/spam.jpg`);
  check('Storage', 'BEFORE script 14: a Buyer can upload into the inventory photo folder (the gap)', r.ok, err(r));
  r = await put(O3, BUCKET, `${O3}/viewonly.jpg`);
  check('Storage', 'BEFORE: so can an Officer with Dashboard = View Only', r.ok, err(r));
  await db.query(`DELETE FROM storage.objects WHERE name IN ($1,$2)`, [`${B1}/spam.jpg`, `${O3}/viewonly.jpg`]);

  await runScript('supabase_schema_officer_permissions_14_inventory_photo_permissions.sql');
  await regrant();

  // Manager and an Officer with Dashboard = Manage.
  r = await put(M, BUCKET, `${M}/item_2.jpg`);
  check('Storage', 'Manager uploads an inventory photo to their own folder', r.ok, err(r));
  r = await put(M, BUCKET, `${M}/program_images/9.jpg`);
  check('Storage', '... and a program image (the nested folder the app uses)', r.ok, err(r));
  r = await put(O1, BUCKET, `${O1}/item_3.jpg`);
  check('Storage', 'Officer with Dashboard = Manage uploads', r.ok, err(r));
  r = await put(O1, BUCKET, `${M}/other.jpg`);
  check('Storage', '... but only into their own folder', !r.ok && /row-level security/.test(r.error), err(r));
  r = await touch(O1, 'update', `${M}/item_1.jpg`);
  check('Storage', 'Officer with Dashboard = Manage can replace a photo the Manager uploaded', r.ok && r.value === 1, err(r));
  r = await touch(M, 'update', `${O1}/item_3.jpg`);
  check('Storage', '... and the Manager one an Officer uploaded', r.ok && r.value === 1, err(r));

  // Officer with Dashboard = View Only.
  r = await put(O3, BUCKET, `${O3}/nope.jpg`);
  check('Storage', 'Officer with Dashboard = View Only cannot upload', !r.ok && /row-level security/.test(r.error), err(r));
  r = await touch(O3, 'update', `${M}/item_1.jpg`);
  check('Storage', '... cannot replace', r.ok && r.value === 0, err(r));
  r = await touch(O3, 'delete', `${M}/item_1.jpg`);
  check('Storage', '... cannot delete', r.ok && r.value === 0, err(r));
  check('Storage', '... and the photo is still there', (await q(`SELECT count(*)::int AS n FROM storage.objects WHERE name = $1`, [`${M}/item_1.jpg`]))[0].n === 1, 'present');

  // Everyone else.
  for (const [label, uid] of [['a Farmer', F1], ['a Buyer', B1]]) {
    r = await put(uid, BUCKET, `${uid}/x.jpg`);
    check('Storage', `${label} cannot upload`, !r.ok && /row-level security/.test(r.error), err(r));
    r = await touch(uid, 'delete', `${M}/item_1.jpg`);
    check('Storage', `... or delete (${label})`, r.ok && r.value === 0, err(r));
  }

  // Viewing is unchanged: everyone, signed out too.
  const views = [await view(O3, 'authenticated'), await view(F1, 'authenticated'), await view(B1, 'authenticated'), await view(null, 'anon')];
  check('Storage', 'viewing is unchanged: View Only Officer, Farmer, Buyer and a visitor all see the photos', views.every((n) => n >= 3), JSON.stringify(views));

  // Delete: Manage Officer and Manager can.
  r = await touch(O1, 'delete', `${M}/item_2.jpg`);
  check('Storage', 'Officer with Dashboard = Manage can delete a photo', r.ok && r.value === 1, err(r));
  r = await touch(M, 'delete', `${O1}/item_3.jpg`);
  check('Storage', '... and so can the Manager', r.ok && r.value === 1, err(r));

  // Other folders are untouched.
  r = await put(F1, 'crop_images', `${F1}/crop.jpg`);
  check('Storage', 'crop photos are unchanged: a Farmer still uploads to their own folder', r.ok, err(r));
  r = await put(F1, 'crop_images', `${M}/crop.jpg`);
  check('Storage', '... and still only to their own', !r.ok && /row-level security/.test(r.error), err(r));
  const names = (await q(`SELECT policyname FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname ILIKE 'Inventory images%' ORDER BY 1`)).map((p) => p.policyname);
  check('Storage', 'only the three inventory write policies were replaced; public read kept', JSON.stringify(names) === JSON.stringify(['Inventory images public read', 'Inventory images staff delete', 'Inventory images staff update', 'Inventory images staff upload']), JSON.stringify(names));
  const crop = (await q(`SELECT count(*)::int AS n FROM pg_policies WHERE schemaname='storage' AND policyname ILIKE 'Crop images%'`))[0].n;
  check('Storage', '... crop image policies are untouched', crop === 3, String(crop));

  // Script 15: only fills a missing size limit.
  await db.query(`INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types) VALUES
    ('profile_photos','profile_photos',true,NULL,NULL), ('crop_images','crop_images',true,5000000,NULL),
    ('listing_photos','listing_photos',true,NULL,ARRAY['image/jpeg']), ('cooperative_inventory_images','cooperative_inventory_images',true,NULL,NULL)`);
  await runScript('supabase_schema_officer_permissions_15_photo_bucket_limits.sql');
  const lim = Object.fromEntries((await q(`SELECT id, file_size_limit, allowed_mime_types FROM storage.buckets`)).map((b) => [b.id, b]));
  check('Storage', 'script 15 fills a missing size limit (10 MB)', Number(lim.profile_photos.file_size_limit) === 10485760 && Number(lim.cooperative_inventory_images.file_size_limit) === 10485760 && Number(lim.listing_photos.file_size_limit) === 10485760, JSON.stringify(lim));
  check('Storage', '... never changes a limit that is already set', Number(lim.crop_images.file_size_limit) === 5000000, JSON.stringify(lim.crop_images));
  check('Storage', '... and never touches the allowed file types', lim.profile_photos.allowed_mime_types === null && JSON.stringify(lim.listing_photos.allowed_mime_types) === JSON.stringify(['image/jpeg']), JSON.stringify(lim));
}

// ───────────────────────── Item 3 · a Farmer's own share (scripts 16 and 17) ─────────────────────────
{
  await db.query(`UPDATE cooperative_annual_totals SET total_coop_sales = 1000, total_program_sales = 400 WHERE year = 2026`);
  await db.query(`INSERT INTO member_contributions (farmer_id, year, total_sales_amount, program_purchases_amount) VALUES ($1, 2026, 250, 100)`, [F1]);
  const share = async (uid, year = 2026, role = 'authenticated') => (await as(uid, { path: '/rpc/get_my_activity_share', gate: false, role }, async (d) =>
    (await d.query(`SELECT * FROM public.get_my_activity_share($1)`, [year])).rows));
  const direct = async (uid, role = 'authenticated') => (await as(uid, { method: 'GET', path: '/cooperative_annual_totals', gate: false, role }, async (d) =>
    (await d.query('SELECT count(*)::int AS n FROM cooperative_annual_totals')).rows[0].n)).value;

  await runScript('supabase_schema_officer_permissions_16_farmer_own_share_function.sql');
  await regrant();
  let r = await share(F1);
  check('Item3', 'script 16: a Farmer gets their own selling and buying share (250/1000 and 100/400 = 25%)', r.ok && r.value.length === 1 && Number(r.value[0].selling_share_percent) === 25 && Number(r.value[0].buying_share_percent) === 25, JSON.stringify(r.value ?? r.error));
  check('Item3', '... and the answer holds only those two numbers, never a cooperative total', JSON.stringify(Object.keys(r.value[0])) === JSON.stringify(['selling_share_percent', 'buying_share_percent']), JSON.stringify(Object.keys(r.value[0])));
  r = await share(F2);
  check('Item3', 'a Farmer with no activity gets 0 and 0', r.ok && Number(r.value[0].selling_share_percent) === 0 && Number(r.value[0].buying_share_percent) === 0, JSON.stringify(r.value ?? r.error));
  r = await share(F1, 2030);
  check('Item3', 'a year with no cooperative totals gives 0 (no division error)', r.ok && Number(r.value[0].selling_share_percent) === 0, JSON.stringify(r.value ?? r.error));
  r = await share(null, 2026, 'anon');
  check('Item3', 'a signed-out visitor cannot call it at all', !r.ok && /permission denied/.test(r.error), JSON.stringify(r.value ?? r.error));
  r = await share(B1);
  check('Item3', 'a Buyer gets only zeros (nothing about anyone else)', r.ok && r.value.length === 1 && Number(r.value[0].selling_share_percent) === 0, JSON.stringify(r.value ?? r.error));
  check('Item3', 'BEFORE script 17: a Farmer can still read the table directly (what the update stops needing)', (await direct(F1)) === 1, 'farmer');

  await runScript('supabase_schema_officer_permissions_17_annual_totals_staff_only.sql');
  await regrant();
  check('Item3', 'AFTER script 17: a Farmer and a Buyer read nothing directly', (await direct(F1)) === 0 && (await direct(B1)) === 0, 'farmer/buyer');
  check('Item3', '... the Manager and every Officer read it (the new Reports view)', (await direct(M)) === 1 && (await direct(O1)) === 1 && (await direct(O3)) === 1, 'staff');
  r = await share(F1);
  check('Item3', '... and the Farmer still gets their share through the function', r.ok && Number(r.value[0].selling_share_percent) === 25, JSON.stringify(r.value ?? r.error));
  const writes = [];
  for (const [uid, yr] of [[O1, 2031], [M, 2032]]) {
    writes.push(await as(uid, { path: '/cooperative_annual_totals', gate: false }, async (d) =>
      d.query(`INSERT INTO cooperative_annual_totals (year, total) VALUES ($1, 1)`, [yr])));
  }
  check('Item3', 'only the Manager can change the totals (an Officer is refused, the Manager is not)', !writes[0].ok && /row-level security/.test(writes[0].error) && writes[1].ok, JSON.stringify(writes.map(err)));
  const pol = await q(`SELECT policyname FROM pg_policies WHERE tablename='cooperative_annual_totals' AND cmd='SELECT'`);
  check('Item3', 'what is left to read it: the staff rule only', pol.length === 1 && /admin manages all \(read\)/.test(pol[0].policyname), JSON.stringify(pol));
}

// ───────────────────────── Contribution ledger (script 18) ─────────────────────────
{
  const LED = '00000000-0000-0000-0000-0000000000c9';
  await createUser(LED, 'farmer', 'Lena Ledger', 'sp3-0060');
  const seed = async (amount, note = 'seed') =>
    (await q(`INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by) VALUES ($1, $2, 'member_payment', $3, $4) RETURNING id`, [LED, amount, note, M]))[0].id;
  const total = async () => Number((await q(`SELECT total_contribution FROM member_capital_shares WHERE farmer_id = $1`, [LED]))[0]?.total_contribution ?? 0);
  const amountOf = async (id) => Number((await q(`SELECT amount FROM capital_contribution_events WHERE id = $1`, [id]))[0]?.amount ?? -1);
  const api = (uid, method, sql, params = [], opts = {}) => as(uid, { method, path: '/capital_contribution_events', commit: true, ...opts }, async (d) => d.query(sql, params));

  let e1 = await seed(100);
  check('Ledger', 'setup: the member total follows the ledger', (await total()) === 100, String(await total()));

  // BEFORE: the hole.
  let r = await api(O1, 'PATCH', `UPDATE capital_contribution_events SET amount = 9999 WHERE id = $1`, [e1]);
  check('Ledger', 'BEFORE script 18: an Officer with Members = Manage can change a contribution amount (the hole)', r.ok && (await amountOf(e1)) === 9999, err(r));
  r = await api(O1, 'DELETE', `DELETE FROM capital_contribution_events WHERE id = $1`, [e1]);
  check('Ledger', '... and delete a contribution', r.ok && (await amountOf(e1)) === -1, err(r));
  e1 = await seed(100);

  await runScript('supabase_schema_officer_permissions_18_contribution_ledger_protection.sql');
  // (no regrant: the script creates no table, and a re-grant would be irrelevant to RLS)

  // Adding stays authorised.
  r = await api(O1, 'POST', `INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by) VALUES ($1, 50, 'member_payment', 'by officer', $2)`, [LED, O1]);
  check('Ledger', 'AFTER script 18: an Officer with Members = Manage can still ADD a contribution', r.ok && (await total()) === 150, err(r));
  const rec = (await q(`SELECT actor_name, operation, new_values FROM admin_activity_log WHERE source='db' AND table_name='capital_contribution_events' AND reference_label='Lena Ledger' ORDER BY created_at DESC LIMIT 1`))[0];
  check('Ledger', '... it is in the logbook with the Officer\'s name', rec?.actor_name === 'Olivia One' && rec.operation === 'created' && Number(rec.new_values.amount) === 50, JSON.stringify(rec));
  r = await api(O1, 'POST', `INSERT INTO capital_contribution_events (farmer_id, amount, source, recorded_by) VALUES ($1, 5, 'member_payment', $2)`, [LED, M]);
  check('Ledger', '... but not in the Manager\'s name', !r.ok && /row-level security/.test(r.error) && (await total()) === 150, err(r));
  r = await api(O2, 'POST', `INSERT INTO capital_contribution_events (farmer_id, amount, source, recorded_by) VALUES ($1, 5, 'member_payment', $2)`, [LED, O2]);
  check('Ledger', 'an Officer with Members = View Only still cannot add (the gate)', !r.ok && VIEW_ONLY.test(r.error), err(r));
  r = await api(F1, 'POST', `INSERT INTO capital_contribution_events (farmer_id, amount, source, recorded_by) VALUES ($1, 5, 'member_payment', $2)`, [F1, F1], { gate: false });
  check('Ledger', 'a Farmer cannot add one', !r.ok && /row-level security/.test(r.error), err(r));

  // Existing records are protected from Officers.
  const rows = (uid, method, sql, params = []) => as(uid, { method, path: '/capital_contribution_events', commit: true }, async (d) => (await d.query(sql, params)).rows.length);
  r = await rows(O1, 'PATCH', `UPDATE capital_contribution_events SET amount = 9999 WHERE id = $1 RETURNING id`, [e1]);
  check('Ledger', 'an Officer cannot change an existing contribution: the API changes 0 rows and the amount stays', r.ok && r.value === 0 && (await amountOf(e1)) === 100, err(r));
  r = await rows(O1, 'DELETE', `DELETE FROM capital_contribution_events WHERE id = $1 RETURNING id`, [e1]);
  check('Ledger', '... nor delete one', r.ok && r.value === 0 && (await amountOf(e1)) === 100, err(r));
  r = await rows(O1, 'PATCH', `UPDATE capital_contribution_events SET amount = 1 WHERE farmer_id = $1 RETURNING id`, [LED]);
  check('Ledger', '... not even in bulk', r.ok && r.value === 0 && (await total()) === 150, err(r));
  // Second layer: reaching the table through a function with owner rights is refused, with a message.
  r = await as(O1, { path: '/rpc/some_owner_function', gate: false, role: null }, async (d) =>
    d.query(`UPDATE capital_contribution_events SET amount = 9999 WHERE id = $1`, [e1]));
  check('Ledger', 'a function running with owner rights cannot change one for an Officer either (clear message)', !r.ok && /cannot be changed or deleted\. Add a correction entry instead/.test(r.error) && (await amountOf(e1)) === 100, err(r));
  r = await as(O1, { path: '/rpc/some_owner_function', gate: false, role: null }, async (d) =>
    d.query(`DELETE FROM capital_contribution_events WHERE id = $1`, [e1]));
  check('Ledger', '... or delete one', !r.ok && /cannot be changed or deleted/.test(r.error) && (await amountOf(e1)) === 100, err(r));
  r = await as(O1, { method: 'PATCH', path: '/member_capital_shares', commit: true }, async (d) =>
    (await d.query(`UPDATE member_capital_shares SET total_contribution = 1000000 WHERE farmer_id = $1 RETURNING farmer_id`, [LED])).rows.length);
  check('Ledger', 'an Officer cannot set a member\'s total directly', r.ok && r.value === 0 && (await total()) === 150, err(r));
  r = await as(O1, { method: 'DELETE', path: '/member_capital_shares', commit: true }, async (d) =>
    (await d.query(`DELETE FROM member_capital_shares WHERE farmer_id = $1 RETURNING farmer_id`, [LED])).rows.length);
  check('Ledger', '... or delete it', r.ok && r.value === 0 && (await total()) === 150, err(r));

  // The Manager can still correct; the original stays in the logbook.
  r = await api(M, 'PATCH', `UPDATE capital_contribution_events SET amount = 120 WHERE id = $1`, [e1]);
  const corr = (await q(`SELECT actor_name, old_values, new_values FROM admin_activity_log WHERE source='db' AND table_name='capital_contribution_events' AND operation='updated' AND reference_label='Lena Ledger' ORDER BY created_at DESC LIMIT 1`))[0];
  check('Ledger', 'the Manager can still correct a record, and the logbook keeps the original amount', r.ok && (await amountOf(e1)) === 120 && Number(corr?.old_values.amount) === 100 && Number(corr.new_values.amount) === 120 && corr.actor_name === 'The Manager', JSON.stringify(corr ?? err(r)));
  check('Ledger', '... and the member total follows (the trigger is unaffected)', (await total()) === 170, String(await total()));
  await db.query(`UPDATE capital_contribution_events SET note = 'maintenance' WHERE id = $1`, [e1]);
  check('Ledger', 'database maintenance (no signed-in user) is not blocked', (await q(`SELECT note FROM capital_contribution_events WHERE id = $1`, [e1]))[0].note === 'maintenance', 'maintenance');
  check('Ledger', 'reading is unchanged: the Farmer reads their own ledger, a stranger does not', (await as(LED, { method: 'GET', path: '/capital_contribution_events', gate: false }, async (d) => (await d.query('SELECT count(*)::int AS n FROM capital_contribution_events')).rows[0].n)).value >= 2 && (await as(F2, { method: 'GET', path: '/capital_contribution_events', gate: false }, async (d) => (await d.query('SELECT count(*)::int AS n FROM capital_contribution_events WHERE farmer_id = $1', [LED])).rows[0].n)).value === 0, 'reads');
}

// ───────────────────────── Manager wording cleanup (N7) ─────────────────────────
{
  await db.exec(`
    CREATE FUNCTION public.w_issue() RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $f$
    BEGIN
      IF NOT public.is_platform_admin() THEN RAISE EXCEPTION 'Only admins may issue loans'; END IF;
    END $f$;
    CREATE FUNCTION public.w_price() RETURNS void LANGUAGE plpgsql AS $f$
    BEGIN RAISE EXCEPTION 'Unauthorized: only admins or officers can announce price updates'; END $f$;
    CREATE FUNCTION public.w_payout() RETURNS void LANGUAGE plpgsql AS $f$
    BEGIN RAISE EXCEPTION 'Only an Manager can confirm a payout decision.'; END $f$;
    CREATE FUNCTION public.w_an_admin() RETURNS void LANGUAGE plpgsql AS $f$
    BEGIN RAISE EXCEPTION 'Only an Administrator can reset this. An admin must ask the Administrators.'; END $f$;
    CREATE FUNCTION public.w_dba() RETURNS void LANGUAGE plpgsql AS $f$
    BEGIN RAISE EXCEPTION 'A crop exclusive selling channel can only be set by a database administrator.'; END $f$;
    CREATE FUNCTION public.w_role() RETURNS boolean LANGUAGE plpgsql AS $f$
    BEGIN
      -- Admin in a comment, and the literal role value, must stay.
      RETURN EXISTS (SELECT 1 FROM user_roles WHERE role = 'admin');
    END $f$;
    CREATE FUNCTION public.w_clean() RETURNS void LANGUAGE plpgsql AS $f$
    BEGIN RAISE EXCEPTION 'Only a Manager can do this.'; END $f$;
  `);
  const before = Object.fromEntries((await q(`SELECT proname, md5(prosrc) AS h FROM pg_proc WHERE proname LIKE 'w\\_%'`)).map((r) => [r.proname, r.h]));
  await runScript('supabase_schema_manager_wording_cleanup.sql');
  const src = Object.fromEntries((await q(`SELECT proname, prosrc, prosecdef, md5(prosrc) AS h FROM pg_proc WHERE proname LIKE 'w\\_%'`)).map((r) => [r.proname, r]));
  check('N7', '"admins" in a message becomes "Managers"', /Only Managers may issue loans/.test(src.w_issue.prosrc) && !/admins/i.test(src.w_issue.prosrc.replace(/is_platform_admin/g, '')), src.w_issue.prosrc);
  check('N7', '... the function keeps its rights and its role check', src.w_issue.prosecdef === true && /is_platform_admin\(\)/.test(src.w_issue.prosrc), JSON.stringify(src.w_issue));
  check('N7', '"only admins or officers" -> "only Managers or officers"', /only Managers or officers can announce price updates/.test(src.w_price.prosrc), src.w_price.prosrc);
  check('N7', '"an Manager" is fixed to "a Manager"', /Only a Manager can confirm a payout decision\./.test(src.w_payout.prosrc) && !/an Manager/.test(src.w_payout.prosrc), src.w_payout.prosrc);
  check('N7', '"an Administrator", "An admin" and "Administrators" read correctly', /Only a Manager can reset this\. A Manager must ask the Managers\./.test(src.w_an_admin.prosrc), src.w_an_admin.prosrc);
  check('N7', '"database administrator" is left alone (it is not the Manager)', src.w_dba.h === before.w_dba && /database administrator/.test(src.w_dba.prosrc), src.w_dba.prosrc);
  check('N7', 'the role literal and comments are not touched', src.w_role.h === before.w_role && /role = 'admin'/.test(src.w_role.prosrc), src.w_role.prosrc);
  check('N7', 'a function that already says Manager is not re-created', src.w_clean.h === before.w_clean, 'unchanged');
  const call = await as(M, { path: '/rpc/w_payout', gate: false }, async (d) => d.query('SELECT public.w_payout()'));
  check('N7', 'and the user sees the new wording when it fires', !call.ok && /Only a Manager can confirm a payout decision/.test(call.error), err(call));
  const rerun = await runScript('supabase_schema_manager_wording_cleanup.sql');
  const src2 = Object.fromEntries((await q(`SELECT proname, md5(prosrc) AS h FROM pg_proc WHERE proname LIKE 'w\\_%'`)).map((r) => [r.proname, r.h]));
  check('N7', 'the script is safe to re-run (nothing more changes)', Object.keys(src2).every((k) => src2[k] === src[k].h), JSON.stringify(src2));
}

// ───────────────────────── Manager e-mail in Manage Accounts (script 19) ─────────────────────────
{
  // The Manager signs in with a real address (no contact e-mail); everyone else uses @sagana.local.
  await db.query(`UPDATE auth.users SET email = 'Manager.Real@Example.com' WHERE id = $1`, [M]);
  await db.query(`UPDATE user_information SET contact_email = NULL WHERE user_id = $1`, [M]);
  // An Officer and a Farmer with real sign-in addresses must still not be returned.
  await db.query(`UPDATE auth.users SET email = 'officer.real@example.com' WHERE id = $1`, [O1]);
  await db.query(`UPDATE auth.users SET email = 'farmer.real@example.com' WHERE id = $1`, [F1]);
  const emails = async (uid, role = 'authenticated') => as(uid, { path: '/rpc/get_manager_sign_in_emails', gate: false, role }, async (d) =>
    (await d.query(`SELECT * FROM public.get_manager_sign_in_emails()`)).rows);

  await runScript('supabase_schema_officer_permissions_19_manager_email_in_accounts.sql');
  await regrant();
  let r = await emails(M);
  check('Mgr19', 'script 19: the Manager sees their own sign-in e-mail (lower-cased)', r.ok && r.value.length === 1 && r.value[0].account_id === M && r.value[0].sign_in_email === 'manager.real@example.com', JSON.stringify(r.value ?? r.error));
  r = await emails(O1);
  check('Mgr19', '... an Officer sees the same single row', r.ok && r.value.length === 1 && r.value[0].account_id === M, JSON.stringify(r.value ?? r.error));
  check('Mgr19', '... only Manager accounts are returned: never an Officer, Farmer or Buyer', r.ok && r.value.every((x) => x.account_id === M), JSON.stringify(r.value));
  r = await emails(F1);
  check('Mgr19', 'a Farmer gets nothing', r.ok && r.value.length === 0, JSON.stringify(r.value ?? r.error));
  r = await emails(B1);
  check('Mgr19', 'a Buyer gets nothing', r.ok && r.value.length === 0, JSON.stringify(r.value ?? r.error));
  r = await emails(null, 'anon');
  check('Mgr19', 'a signed-out visitor cannot call it', !r.ok && /permission denied/.test(r.error), JSON.stringify(r.value ?? r.error));
  await db.query(`UPDATE auth.users SET email = 'mgr@sagana.local' WHERE id = $1`, [M]);
  r = await emails(M);
  check('Mgr19', 'an internal @sagana.local sign-in address is never returned', r.ok && r.value.length === 0, JSON.stringify(r.value ?? r.error));
}

// ───────────────────────── Officer access is Manager-only (script 20) ─────────────────────────
{
  const setAccess = (uid, target, perms) => as(uid, { path: '/rpc/set_officer_permissions', commit: true }, async (d) =>
    d.query(`SELECT public.set_officer_permissions($1, $2::jsonb)`, [target, JSON.stringify(perms)]));
  const levelOf = async (uid, mod) => (await q(`SELECT access_level FROM officer_permissions WHERE user_id = $1 AND module = $2`, [uid, mod]))[0]?.access_level;

  await setLevels(O1, { ...ALL_V, members: 'manage' });
  let r = await setAccess(O1, O3, { loans: 'manage' });
  check('Own20', 'BEFORE script 20: an Officer with Members = Manage can change another Officer (the gap)', r.ok, err(r));

  await runScript('supabase_schema_officer_permissions_20_officer_access_manager_only.sql');
  await regrant();
  await setLevels(O3, ALL_V);
  r = await setAccess(O1, O3, { loans: 'manage' });
  check('Own20', 'AFTER: the same Officer is refused, with a clear message', !r.ok && /Only the Manager can change an Officer/.test(r.error), err(r));
  check('Own20', '... and nothing changed', (await levelOf(O3, 'loans')) === 'view', await levelOf(O3, 'loans'));
  r = await setAccess(M, O3, { loans: 'manage' });
  check('Own20', 'the Manager still can', r.ok && (await levelOf(O3, 'loans')) === 'manage', err(r));
  r = await setAccess(M, F1, { loans: 'manage' });
  check('Own20', '... only on an Officer account', !r.ok && /only be set for an Officer/.test(r.error), err(r));
  r = await setAccess(M, M, { loans: 'manage' });
  check('Own20', '... and an Officer account, never the Manager themselves (not an Officer)', !r.ok, err(r));
  r = await setAccess(F1, O3, { loans: 'view' });
  check('Own20', 'a Farmer cannot call it', !r.ok, err(r));
  const log = await q(`SELECT actor_role FROM admin_activity_log WHERE source='db' AND table_name='officer_permissions' ORDER BY created_at DESC LIMIT 1`);
  check('Own20', 'the Manager\'s change is still written to the accountability log', log[0]?.actor_role === 'admin', JSON.stringify(log));
}

// ───────────────────────── Contribution reversal (script 21) ─────────────────────────
{
  const L2 = '00000000-0000-0000-0000-0000000000c8';
  await createUser(L2, 'farmer', 'Rina Reversal', 'sp3-0061');
  const total = async () => Number((await q(`SELECT total_contribution FROM member_capital_shares WHERE farmer_id = $1`, [L2]))[0]?.total_contribution ?? 0);
  const rowOf = async (id) => (await q(`SELECT * FROM capital_contribution_events WHERE id = $1`, [id]))[0];
  const add = (uid, amount, source = 'member_payment', recordedBy = uid) => as(uid, { method: 'POST', path: '/capital_contribution_events', commit: true }, async (d) =>
    (await d.query(`INSERT INTO capital_contribution_events (farmer_id, amount, source, recorded_by) VALUES ($1, $2, $3, $4) RETURNING id`, [L2, amount, source, recordedBy])).rows[0].id);
  const reverse = (uid, id, reason, opts = {}) => as(uid, { path: '/rpc/reverse_capital_contribution', commit: true, ...opts }, async (d) =>
    (await d.query(`SELECT public.reverse_capital_contribution($1, $2) AS id`, [id, reason])).rows[0].id);

  // As on the live database: the superseded self-service function was revoked from
  // "authenticated" only, and a Farmer can still reach it through PUBLIC.
  await db.exec(`
    CREATE FUNCTION public.reinvest_patronage_capital(p_year int, p_amount numeric, p_note text DEFAULT NULL) RETURNS numeric
    LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $f$
    BEGIN
      INSERT INTO capital_contribution_events (farmer_id, amount, source, note, recorded_by)
      VALUES (auth.uid(), p_amount, 'patronage_capital', p_note, auth.uid());
      RETURN 0;
    END $f$;
    REVOKE EXECUTE ON FUNCTION public.reinvest_patronage_capital(int, numeric, text) FROM authenticated;
  `);
  // The live member-notice trigger, as it was before script 21 (phase2_notification_completeness).
  await db.exec(`
    CREATE FUNCTION public.fn_notify_capital_recorded() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $f$
    BEGIN
      IF NEW.source = 'member_payment' THEN
        INSERT INTO notifications (user_id, type, title, body, is_read, created_at, route_on_tap)
        VALUES (NEW.farmer_id, 'capital', 'Capital Contribution Recorded',
          'Your capital contribution of ₱' || TO_CHAR(NEW.amount, 'FM999999990.00') || ' was recorded.', FALSE, NOW(), '/farmer/profile/contribution');
      END IF;
      RETURN NEW;
    END $f$;
    CREATE TRIGGER trg_notify_capital_recorded AFTER INSERT ON capital_contribution_events
      FOR EACH ROW EXECUTE FUNCTION public.fn_notify_capital_recorded();
  `);
  const selfAdd = () => as(L2, { path: '/rpc/reinvest_patronage_capital', commit: true, gate: false }, async (d) =>
    d.query(`SELECT public.reinvest_patronage_capital(2026, 40, 'self')`));
  let sa = await selfAdd();
  check('Rev21', 'BEFORE script 21: a Farmer could still add capital for themselves through the old function (the gap)', sa.ok, err(sa));
  await db.query(`DELETE FROM capital_contribution_events WHERE note = 'self'`);

  await runScript('supabase_schema_officer_permissions_21_contribution_reversal.sql');
  await regrant();

  sa = await selfAdd();
  check('Rev21', 'AFTER: the old self-service function is locked for a Farmer', !sa.ok && /permission denied/.test(sa.error), err(sa));
  sa = await as(M, { path: '/rpc/reinvest_patronage_capital', commit: true, gate: false }, async (d) => d.query(`SELECT public.reinvest_patronage_capital(2026, 1, 'x')`));
  check('Rev21', '... and for everyone else signed in, the Manager included (the app never calls it)', !sa.ok && /permission denied/.test(sa.error), err(sa));

  // Recording.
  let r = await add(O1, 2000);
  check('Rev21', 'an Officer (Members = Manage) records a contribution; the recorder is saved', r.ok && (await rowOf(r.value)).recorded_by === O1 && (await total()) === 2000, err(r));
  const e1 = r.value;
  r = await add(M, 500);
  check('Rev21', 'the Manager records one too', r.ok && (await total()) === 2500, err(r));
  const e2 = r.value;
  r = await as(O1, { method: 'POST', path: '/capital_contribution_events', commit: true }, async (d) =>
    d.query(`INSERT INTO capital_contribution_events (farmer_id, amount, source) VALUES ($1, 10, 'member_payment')`, [L2]));
  check('Rev21', 'a record with no recorder is refused (it can no longer be anonymous)', !r.ok && /row-level security/.test(r.error), err(r));
  r = await add(O1, 10, 'member_payment', M);
  check('Rev21', '... and so is one in somebody else\'s name', !r.ok && /row-level security/.test(r.error), err(r));
  r = await as(O1, { method: 'POST', path: '/capital_contribution_events', commit: true }, async (d) =>
    d.query(`INSERT INTO capital_contribution_events (farmer_id, amount, source, recorded_by, reverses_event_id, reversal_reason) VALUES ($1, -2000, 'member_payment', $2, $3, 'sneaky')`, [L2, O1, e1]));
  check('Rev21', 'a reversal cannot be created directly through the API', !r.ok && /row-level security/.test(r.error) && (await total()) === 2500, err(r));

  // Reversing: an Officer reverses the Manager\'s entry, the Manager reverses an Officer\'s.
  r = await reverse(O1, e2, 'Recorded twice by mistake');
  const rev2 = r.ok ? await rowOf(r.value) : null;
  check('Rev21', 'an Officer (Members = Manage) can reverse an entry recorded by the Manager', r.ok && rev2.reverses_event_id === e2 && Number(rev2.amount) === -500 && rev2.recorded_by === O1 && rev2.reversal_reason === 'Recorded twice by mistake', JSON.stringify(rev2 ?? err(r)));
  check('Rev21', '... the original is untouched (still recorded by the Manager, same amount)', Number((await rowOf(e2)).amount) === 500 && (await rowOf(e2)).recorded_by === M, JSON.stringify(await rowOf(e2)));
  check('Rev21', '... the member total follows the ledger', (await total()) === 2000, String(await total()));
  r = await reverse(M, e1, '  Wrong member  ');
  const rev1 = r.ok ? await rowOf(r.value) : null;
  check('Rev21', 'the Manager can reverse an entry recorded by an Officer; the reason is trimmed', r.ok && rev1.recorded_by === M && rev1.reversal_reason === 'Wrong member' && (await rowOf(e1)).recorded_by === O1, JSON.stringify(rev1 ?? err(r)));
  check('Rev21', '... the total returns to nothing', (await total()) === 0, String(await total()));
  check('Rev21', 'the original keeps its own time; the reversal has its own', rev1 && (await rowOf(e1)).created_at <= rev1.created_at, 'times');

  // Refusals.
  r = await reverse(M, e1, 'again');
  check('Rev21', 'an entry can be reversed only once', !r.ok && /already been cancelled/.test(r.error), err(r));
  r = await reverse(M, rev1.id, 'undo the undo');
  check('Rev21', 'a cancellation cannot be cancelled', !r.ok && /cannot be cancelled/.test(r.error), err(r));
  r = await add(O1, 100); const e3 = r.value;
  r = await reverse(M, e3, '  ');
  check('Rev21', 'a reason is required', !r.ok && /reason/.test(r.error) && (await total()) === 100, err(r));
  r = await reverse(M, e3, 'x'.repeat(501));
  check('Rev21', '... and not an essay', !r.ok && /too long/.test(r.error), err(r));
  r = await reverse(O2, e3, 'view only officer');
  check('Rev21', 'an Officer with Members = View Only cannot reverse (the gate)', !r.ok && VIEW_ONLY.test(r.error) && (await total()) === 100, err(r));
  r = await reverse(F1, e3, 'a farmer', { gate: false });
  check('Rev21', 'a Farmer cannot cancel a contribution', !r.ok && /Only the Manager or an Officer/.test(r.error), err(r));
  r = await reverse(L2, e3, 'the member themselves', { gate: false });
  check('Rev21', '... not even for their own entry', !r.ok && /Only the Manager or an Officer/.test(r.error) && (await total()) === 100, err(r));
  r = await as(L2, { method: 'POST', path: '/capital_contribution_events', commit: true, gate: false }, async (d) =>
    d.query(`INSERT INTO capital_contribution_events (farmer_id, amount, source, recorded_by) VALUES ($1, 9999, 'member_payment', $1)`, [L2]));
  check('Rev21', 'a Farmer cannot record a contribution for themselves through the API', !r.ok && /row-level security/.test(r.error) && (await total()) === 100, err(r));
  r = await as(L2, { method: 'POST', path: '/capital_contribution_events', commit: true, gate: false }, async (d) =>
    d.query(`INSERT INTO capital_contribution_events (farmer_id, amount, source, recorded_by) VALUES ($1, 9999, 'member_payment', NULL)`, [L2]));
  check('Rev21', '... nor anonymously', !r.ok && /row-level security/.test(r.error) && (await total()) === 100, err(r));
  r = await reverse(null, e3, 'visitor', { gate: false, role: 'anon' });
  check('Rev21', 'a signed-out visitor cannot call it', !r.ok && /permission denied/.test(r.error), err(r));
  r = await reverse(M, '00000000-0000-0000-0000-00000000dead', 'nothing here');
  check('Rev21', 'an unknown entry is refused', !r.ok && /not found/.test(r.error), err(r));
  r = await add(O1, 700, 'patronage_capital'); const pc = r.value;
  r = await reverse(M, pc, 'wrong');
  check('Rev21', 'a payout added to capital is not reversed here (it belongs to Balik-Tangkilik)', !r.ok && /Balik-Tangkilik/.test(r.error), err(r));
  r = await add(O1, -50, 'manual_adjustment'); const adj = r.value;
  r = await reverse(M, adj, 'adjustment entered wrongly');
  check('Rev21', 'a negative adjustment can be reversed too (it becomes positive)', r.ok && Number((await rowOf(r.value)).amount) === 50, err(r));

  // The member's notices: a normal entry says "recorded"; a cancellation says "cancelled", never a negative amount.
  const notes = await q(`SELECT title, body FROM notifications WHERE user_id = $1 AND type = 'capital' ORDER BY created_at, body`, [L2]);
  const recordedN = notes.filter((n) => n.title === 'Capital Contribution Recorded');
  const cancelledN = notes.filter((n) => n.title === 'Capital Contribution Cancelled');
  check('Rev21', 'the member is told "recorded" for each normal payment entry (3), with a positive amount', recordedN.length === 3 && recordedN.every((n) => !/-/.test(n.body)), JSON.stringify(notes));
  check('Rev21', '... and "cancelled" for each cancellation (2), with the amount and no minus sign, no staff name, no reason',
    cancelledN.length === 2 && cancelledN.every((n) => /was cancelled\.$/.test(n.body) && !/-/.test(n.body) && !/Olivia|Manager|Wrong member|Recorded twice/.test(n.body))
      && cancelledN.some((n) => /₱500\.00/.test(n.body)) && cancelledN.some((n) => /₱2000\.00/.test(n.body)), JSON.stringify(cancelledN));

  // Nothing is deleted or edited, by anybody signed in.
  const touch = (uid, sql, params = []) => as(uid, { method: 'PATCH', path: '/capital_contribution_events', commit: true }, async (d) => (await d.query(sql, params)).rows.length);
  r = await touch(M, `UPDATE capital_contribution_events SET amount = 1 WHERE id = $1 RETURNING id`, [e1]);
  check('Rev21', 'the Manager can no longer edit an entry through the API (0 rows)', r.ok && r.value === 0 && Number((await rowOf(e1)).amount) === 2000, err(r));
  r = await touch(M, `DELETE FROM capital_contribution_events WHERE id = $1 RETURNING id`, [e1]);
  check('Rev21', '... or delete one', r.ok && r.value === 0 && !!(await rowOf(e1)), err(r));
  r = await as(M, { path: '/rpc/some_owner_function', gate: false, role: null }, async (d) => d.query(`DELETE FROM capital_contribution_events WHERE id = $1`, [e1]));
  check('Rev21', '... and a function running with owner rights cannot either, even for the Manager (clear message)', !r.ok && /Cancel the entry instead/.test(r.error) && !!(await rowOf(e1)), err(r));
  r = await as(M, { path: '/rpc/some_owner_function', gate: false, role: null }, async (d) => d.query(`UPDATE capital_contribution_events SET reversal_reason = 'tampered' WHERE id = $1`, [rev1.id]));
  check('Rev21', '... nor can a reason be rewritten', !r.ok && /cannot be changed or deleted/.test(r.error) && (await rowOf(rev1.id)).reversal_reason === 'Wrong member', err(r));
  await db.query(`UPDATE capital_contribution_events SET note = 'maintenance' WHERE id = $1`, [e3]);
  check('Rev21', 'database maintenance (no signed-in user) is not blocked', (await rowOf(e3)).note === 'maintenance', 'maintenance');
  let dup = null;
  try { await db.query(`INSERT INTO capital_contribution_events (farmer_id, amount, source, recorded_by, reverses_event_id, reversal_reason) VALUES ($1, -2000, 'member_payment', $2, $3, 'duplicate')`, [L2, M, e1]); } catch (e) { dup = e.message; }
  check('Rev21', 'the database itself allows only one reversal per entry (even for maintenance)', dup && /ux_cce_one_reversal|duplicate key/.test(dup), String(dup));
  let blank = null;
  try { await db.query(`INSERT INTO capital_contribution_events (farmer_id, amount, source, recorded_by, reverses_event_id, reversal_reason) VALUES ($1, -100, 'member_payment', $2, $3, ' ')`, [L2, M, e3]); } catch (e) { blank = e.message; }
  check('Rev21', '... and a reversal without a reason', blank && /cce_reversal_consistent/.test(blank), String(blank));

  // Accountability: who, what, when, why.
  const log = (await q(`SELECT actor_name, actor_role, operation, new_values, created_at FROM admin_activity_log WHERE source='db' AND table_name='capital_contribution_events' AND reference_label='Rina Reversal' AND (new_values->>'reverses_event_id') = $1`, [e2]))[0];
  check('Rev21', 'the logbook records the reversal: the Officer\'s name, the time, the reason and which entry', log?.actor_name === 'Olivia One' && log.operation === 'created' && log.new_values.reversal_reason === 'Recorded twice by mistake' && !!log.created_at, JSON.stringify(log));
  const orig = (await q(`SELECT actor_name FROM admin_activity_log WHERE source='db' AND table_name='capital_contribution_events' AND reference_label='Rina Reversal' AND (new_values->>'id') = $1`, [e1]))[0];
  check('Rev21', '... and the original entry is still logged against whoever recorded it', orig?.actor_name === 'Olivia One', JSON.stringify(orig));
  const gate = await q(`SELECT module FROM staff_permission_targets WHERE kind='rpc' AND name='reverse_capital_contribution'`);
  check('Rev21', 'the gate governs the function under Members', gate.length === 1 && gate[0].module === 'members', JSON.stringify(gate));
  const pol = (await q(`SELECT policyname, cmd FROM pg_policies WHERE tablename='capital_contribution_events' AND cmd IN ('UPDATE','DELETE')`));
  check('Rev21', 'no API rule to edit or delete a ledger entry is left', pol.length === 0, JSON.stringify(pol));
  await runScript('supabase_schema_officer_permissions_21_contribution_reversal.sql');
  check('Rev21', 'the script is safe to re-run', (await q(`SELECT count(*)::int AS n FROM capital_contribution_events WHERE reverses_event_id IS NOT NULL`))[0].n === 3, 'rerun');
}

// ───────────────────────── Staff Accountability covers every tab (script 22) ─────────────────────────
{
  // The tables script 22 attaches to (only two of the marketplace ones, enough to prove the rule), as live.
  await db.exec(`
    CREATE TABLE marketplace_listings (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), farmer_id uuid, crop_name text, status text DEFAULT 'pending');
    CREATE TABLE orders (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), order_number text, farmer_id uuid, buyer_id uuid, status text DEFAULT 'pending');
    ALTER TABLE member_contributions
      ADD COLUMN status text DEFAULT 'pending', ADD COLUMN payout_decision text,
      ADD COLUMN estimated_balik_tangkilik numeric DEFAULT 0, ADD COLUMN actual_balik_tangkilik numeric,
      ADD COLUMN actual_interest_on_capital numeric, ADD COLUMN actual_purchase_patronage numeric;
  `);
  // The BOD job exactly as batch10_01 defines it (read from the file, not retyped).
  const bodFile = fs.readFileSync(new URL('../../supabase_schema/batch10_01_bod_and_failed_outcome.sql', import.meta.url), 'utf8');
  const bodSql = bodFile.slice(bodFile.indexOf('-- First Saturday of the month'), bodFile.indexOf('-- Daily at 08:00'));
  await db.exec(bodSql);
  await regrant();

  const logs = async (where, params = []) => q(`SELECT module, actor_name, actor_role, operation, table_name, reference_label, old_values, new_values, admin_id
                                                FROM admin_activity_log WHERE source = 'db' AND ${where} ORDER BY created_at, id`, params);
  const api = (uid, path, fn) => as(uid, { method: 'POST', path, commit: true, gate: false }, async (d) => fn(d));
  const insListing = (uid, crop) => api(uid, '/marketplace_listings', async (d) =>
    (await d.query(`INSERT INTO marketplace_listings (farmer_id, crop_name) VALUES ($1, $2) RETURNING id`, [F1, crop])).rows[0].id);

  let r = await insListing(O1, 'Tomato');
  check('Cov22', 'BEFORE script 22: a staff change to a listing leaves no accountability line (the gap)', r.ok && (await logs(`table_name = 'marketplace_listings'`)).length === 0, err(r));

  await runScript('supabase_schema_officer_permissions_22_accountability_coverage.sql');
  await regrant();

  // Marketplace.
  r = await insListing(O1, 'Eggplant');
  const listingId = r.value;
  let rows = await logs(`table_name = 'marketplace_listings'`);
  check('Cov22', 'AFTER: an Officer adding a listing is recorded: who, what, which record, under Marketplace',
    r.ok && rows.length === 1 && rows[0].module === 'marketplace' && rows[0].actor_name === 'Olivia One' && rows[0].actor_role === 'officer' && rows[0].operation === 'created' && rows[0].reference_label === 'Eggplant', JSON.stringify(rows));
  r = await api(M, '/marketplace_listings', async (d) => d.query(`UPDATE marketplace_listings SET status = 'approved' WHERE id = $1`, [listingId]));
  rows = await logs(`table_name = 'marketplace_listings' AND operation = 'updated'`);
  check('Cov22', '... the Manager approving it records what changed, before and after',
    r.ok && rows.length === 1 && rows[0].actor_role === 'admin' && rows[0].old_values.status === 'pending' && rows[0].new_values.status === 'approved', JSON.stringify(rows));
  r = await api(O1, '/marketplace_listings', async (d) => d.query(`DELETE FROM marketplace_listings WHERE id = $1`, [listingId]));
  rows = await logs(`table_name = 'marketplace_listings' AND operation = 'deleted'`);
  check('Cov22', '... and a delete is recorded with the values that were removed', r.ok && rows.length === 1 && rows[0].old_values.crop_name === 'Eggplant', JSON.stringify(rows));

  const before = (await logs(`table_name = 'marketplace_listings'`)).length;
  r = await insListing(F1, 'Farmer own listing');
  check('Cov22', 'a Farmer\'s own listing is NOT recorded (only staff are)', r.ok && (await logs(`table_name = 'marketplace_listings'`)).length === before, err(r));
  await db.query(`INSERT INTO orders (order_number, farmer_id, buyer_id) VALUES ('ORD-1', $1, $2)`, [F1, B1]);
  r = await api(O1, '/orders', async (d) => d.query(`UPDATE orders SET status = 'ready' WHERE order_number = 'ORD-1'`));
  rows = await logs(`table_name = 'orders'`);
  check('Cov22', 'an Officer moving an order along is recorded under Marketplace with the order number',
    r.ok && rows.length === 1 && rows[0].module === 'marketplace' && rows[0].reference_label === 'ORD-1' && rows[0].new_values.status === 'ready', JSON.stringify(rows));
  r = await api(B1, '/orders', async (d) => d.query(`UPDATE orders SET status = 'received' WHERE order_number = 'ORD-1'`));
  check('Cov22', '... a Buyer confirming receipt is not', r.ok && (await logs(`table_name = 'orders'`)).length === 1, err(r));

  // Reports: the Balik-Tangkilik settings and the payout result.
  r = await api(M, '/cooperative_annual_totals', async (d) => d.query(`INSERT INTO cooperative_annual_totals (year, total) VALUES (2040, 5)`));
  rows = await logs(`table_name = 'cooperative_annual_totals'`);
  check('Cov22', 'the Manager saving the Balik-Tangkilik year settings is recorded under Reports', r.ok && rows.length === 1 && rows[0].module === 'reports' && rows[0].actor_role === 'admin', JSON.stringify(rows));
  await db.query(`INSERT INTO member_contributions (farmer_id, year) VALUES ($1, 2040)`, [F1]);
  r = await api(M, '/member_contributions', async (d) => d.query(`UPDATE member_contributions SET estimated_balik_tangkilik = 99 WHERE farmer_id = $1 AND year = 2040`, [F1]));
  check('Cov22', 'refreshing a member\'s estimate is routine and is NOT recorded', r.ok && (await logs(`table_name = 'member_contributions'`)).length === 0, err(r));
  r = await api(M, '/member_contributions', async (d) => d.query(`UPDATE member_contributions SET status = 'paid', actual_balik_tangkilik = 120 WHERE farmer_id = $1 AND year = 2040`, [F1]));
  rows = await logs(`table_name = 'member_contributions'`);
  check('Cov22', 'finalising a member\'s payout IS recorded, with the member\'s name and the result',
    r.ok && rows.length === 1 && rows[0].module === 'reports' && rows[0].new_values.status === 'paid' && Number(rows[0].new_values.actual_balik_tangkilik) === 120 && rows[0].reference_label === 'Farah One', JSON.stringify(rows));
  r = await api(F1, '/member_contributions', async (d) => d.query(`UPDATE member_contributions SET payout_decision = 'pending_cash' WHERE farmer_id = $1 AND year = 2040`, [F1]));
  check('Cov22', '... a Farmer choosing cash or capital is not a staff action and is not recorded', r.ok && (await logs(`table_name = 'member_contributions'`)).length === 1, err(r));

  // The BOD reminder.
  const sent = (await q(`SELECT public.notify_bod_meeting_upcoming(DATE '2026-12-02') AS n`))[0].n;
  const farmers = (await q(`SELECT count(*)::int AS n FROM user_roles WHERE role = 'farmer' AND status = 'active'`))[0].n;
  const staff = (await q(`SELECT count(*)::int AS n FROM user_roles WHERE role IN ('admin','officer')`))[0].n;
  rows = await logs(`module = 'system'`);
  check('Cov22', 'the BOD reminder still goes out three days before the first Saturday (Dec 5, 2026), to Farmers and staff',
    sent === farmers && (await q(`SELECT count(*)::int AS n FROM notifications WHERE title = 'BOD Meeting in 3 Days'`))[0].n === farmers + staff, String(sent));
  check('Cov22', '... and leaves ONE line: module System, actor "System", with the counts, no staff name',
    rows.length === 1 && rows[0].actor_name === 'System' && rows[0].actor_role === 'system' && rows[0].admin_id === null && rows[0].new_values.farmers === farmers && rows[0].new_values.staff === staff && rows[0].reference_label === '2026-12-05', JSON.stringify(rows));
  await q(`SELECT public.notify_bod_meeting_upcoming(DATE '2026-12-03')`);
  check('Cov22', '... on any other day nothing is sent and nothing is logged', (await logs(`module = 'system'`)).length === 1, 'other day');

  // Only the Manager sees these lines.
  const count = (uid) => as(uid, { method: 'GET', path: '/admin_activity_log', gate: false }, async (d) =>
    (await d.query(`SELECT count(*)::int AS n FROM admin_activity_log WHERE source = 'db' AND module IN ('marketplace','reports','system')`)).rows[0].n);
  const mg = await count(M);
  const of = await count(O1);
  check('Cov22', 'the Manager sees them; an Officer does not (script 05 rule)', mg.ok && mg.value === 7 && of.ok && of.value === 0, JSON.stringify([mg.value ?? mg.error, of.value ?? of.error]));
  const f = await count(F1);
  check('Cov22', '... and a Farmer does not', f.ok && f.value === 0, JSON.stringify(f.value ?? f.error));

  // Re-run safety.
  await runScript('supabase_schema_officer_permissions_22_accountability_coverage.sql');
  const trg = (await q(`SELECT count(*)::int AS n FROM information_schema.triggers WHERE trigger_name = 'trg_audit_staff_change' AND event_object_table = 'orders'`))[0].n;
  const bodv = (await q(`SELECT prosrc LIKE '%bod_system_log%' AS ok FROM pg_proc WHERE proname = 'notify_bod_meeting_upcoming'`))[0].ok;
  check('Cov22', 'the script is safe to re-run (one audit trigger per table, the BOD job keeps its log line)', trg === 3 && bodv, JSON.stringify([trg, bodv]));
}

const failed = report();
process.exit(failed ? 1 : 0);
