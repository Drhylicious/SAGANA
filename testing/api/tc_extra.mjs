// Extra API checks used to execute test cases that the main API suite does not cover.
// LOCAL STACK ONLY. Run: node testing/api/tc_extra.mjs   (writes testing/results/tc_extra_results.json)
import { execSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const env = Object.fromEntries(
  execSync('supabase status -o env', { cwd: new URL('../stack', import.meta.url), encoding: 'utf8' })
    .split(/\r?\n/).filter(l => l.includes('=')).map(l => { const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1).replace(/^"|"$/g, '')]; }));
const URL_ = env.API_URL, ANON = env.ANON_KEY, SERVICE = env.SERVICE_ROLE_KEY;
if (!/^http:\/\/(127\.0\.0\.1|localhost):/.test(URL_)) throw new Error('Refusing to run: not a local stack: ' + URL_);

async function call(method, path, { token, body, headers } = {}) {
  const r = await fetch(URL_ + path, {
    method, headers: { apikey: ANON, Authorization: 'Bearer ' + (token || ANON), 'Content-Type': 'application/json', Prefer: 'return=representation', ...headers },
    body: body === undefined ? undefined : JSON.stringify(body) });
  const text = await r.text(); let json; try { json = JSON.parse(text); } catch { json = text; }
  return { status: r.status, json };
}
const rpc = (n, a, token) => call('POST', '/rest/v1/rpc/' + n, { token, body: a || {} });
const get = (p, token) => call('GET', '/rest/v1/' + p, { token });
const ok = r => r.status >= 200 && r.status < 300;
const msg = r => (typeof r.json === 'object' && r.json ? (r.json.message || r.json.error_description || r.json.msg || JSON.stringify(r.json)) : String(r.json)).toString().slice(0, 160);
async function login(u, pw = 'Test@12345', email) {
  const r = await call('POST', '/auth/v1/token?grant_type=password', { body: { email: email || (u + '@sagana.local'), password: pw } });
  return r.json.access_token ? { token: r.json.access_token, id: r.json.user.id } : null;
}
const refusedFor = (r, re) => !ok(r) && re.test(msg(r));
const out = [];
async function t(tc, name, fn) {
  let res;
  try { const [pass, detail] = await fn(); res = { tc, name, pass, detail: String(detail ?? '') }; }
  catch (e) { res = { tc, name, pass: false, detail: 'EXCEPTION ' + e.message }; }
  out.push(res); console.log((res.pass ? 'PASS' : 'FAIL') + ' [TC ' + tc + '] ' + name + ' -> ' + res.detail.slice(0, 150));
}
const U = {};
for (const u of ['t_manager', 't_officer_view', 't_officer_manage', 't_farmer1', 't_farmer2', 't_pending', 't_buyer1']) U[u] = await login(u);
const M = U.t_manager.token, OV = U.t_officer_view.token, OM = U.t_officer_manage.token, F1 = U.t_farmer1.token;
const run = Date.now().toString().slice(-6);
const dob = '1990-05-10';

// ---- TC 20, 20.1, 20.2, 20.3: create Farmer account
let mgrFarmer, offFarmer;
await t('20', 'Manager creates a Farmer account', async () => {
  const r = await rpc('create_farmer_account', { p_username: 'tcx_mgr' + run, p_password: 'Test@12345', p_surname: 'Cruz', p_first_name: 'Maria', p_date_of_birth: dob, p_gender: 'female', p_street: 'Rizal Street', p_house_no: '12' }, M);
  mgrFarmer = r.json; const id = (r.json && (r.json.user_id || r.json.id)) || (typeof r.json === 'string' ? r.json : null);
  const st = id ? (await get('user_roles?select=status&user_id=eq.' + id, SERVICE)).json?.[0]?.status : null;
  return [ok(r) && st === 'active', r.status + ' status after creation: ' + st];
});
await t('20.1', 'Officer (Members Manage) creates a Farmer account', async () => {
  const r = await rpc('create_farmer_account', { p_username: 'tcx_off' + run, p_password: 'Test@12345', p_surname: 'Reyes', p_first_name: 'Jose', p_date_of_birth: dob, p_gender: 'male', p_street: 'Rizal Street', p_house_no: '12' }, OM);
  offFarmer = r.json; const id = (r.json && (r.json.user_id || r.json.id)) || (typeof r.json === 'string' ? r.json : null);
  const st = id ? (await get('user_roles?select=status&user_id=eq.' + id, SERVICE)).json?.[0]?.status : null;
  return [ok(r) && st === 'pending', r.status + ' status after creation: ' + st];
});
await t('20.2', 'Officer with View Only cannot create a Farmer account', async () => {
  const r = await rpc('create_farmer_account', { p_username: 'tcx_ov' + run, p_password: 'Test@12345', p_surname: 'Lim', p_first_name: 'Ana', p_date_of_birth: dob, p_gender: 'female', p_street: 'Rizal Street', p_house_no: '12' }, OV);
  return [!ok(r), r.status + ' ' + msg(r)];
});
await t('20.3', 'Existing username, under-18 date of birth and invalid phone are each refused', async () => {
  const base = { p_password: 'Test@12345', p_surname: 'Check', p_first_name: 'Case', p_date_of_birth: dob, p_gender: 'male', p_street: 'Rizal Street', p_house_no: '12' };
  const dup = await rpc('create_farmer_account', { ...base, p_username: 'tcx_mgr' + run }, M);
  const young = await rpc('create_farmer_account', { ...base, p_username: 'tcx_u18' + run, p_date_of_birth: '2015-01-01' }, M);
  const phone = await rpc('create_farmer_account', { ...base, p_username: 'tcx_ph' + run, p_phone_number: '12345' }, M);
  return [refusedFor(dup, /username/i) && refusedFor(young, /18 years/i) && refusedFor(phone, /phone|mobile/i), 'existing username: ' + dup.status + ' ' + msg(dup) + ' | under 18: ' + young.status + ' ' + msg(young) + ' | phone 12345: ' + phone.status + ' ' + msg(phone)];
});
await t('OBS-20', 'Observation: server-side password length for a staff-created Farmer (3-character password)', async () => {
  const r = await rpc('create_farmer_account', { p_username: 'tcx_pw' + run, p_password: 'abc', p_surname: 'Short', p_first_name: 'Pass', p_date_of_birth: dob, p_gender: 'male', p_street: 'Rizal Street', p_house_no: '12' }, M);
  return [!ok(r), 'status ' + r.status + ' ' + msg(r) + ' (a pass here means the server refuses short passwords)'];
});
const idOf = (j) => (j && (j.user_id || j.id || (Array.isArray(j) && (j[0]?.user_id || j[0]?.id)))) || null;
const lookupId = async (uname) => { const r = await get(`user_information?select=user_id&username=eq.${uname}`, SERVICE); return r.json?.[0]?.user_id || null; };
const mgrFarmerId = idOf(mgrFarmer) || await lookupId('tcx_mgr' + run);
const offFarmerId = idOf(offFarmer) || await lookupId('tcx_off' + run);

// ---- TC 21, 21.3: approval
await t('21.3', 'Officer cannot decide an Officer-created Farmer account', async () => {
  if (!offFarmerId) return [false, 'no Officer-created Farmer id'];
  const r = await rpc('approve_member', { p_user_id: offFarmerId }, OM);
  return [!ok(r), r.status + ' ' + msg(r)];
});
await t('21', 'Manager approves a pending Farmer', async () => {
  if (!mgrFarmerId) return [false, 'no Manager-created Farmer id'];
  const r = await rpc('approve_member', { p_user_id: offFarmerId || mgrFarmerId }, M);
  return [ok(r), r.status + ' ' + msg(r)];
});

// ---- TC 24, 24.1, 24.2: suspension
const target = U.t_farmer2.id;
await t('24.1', 'Suspending without a reason is refused', async () => { const r = await rpc('suspend_member', { p_user_id: target, p_reason: '' }, M); return [!ok(r), r.status + ' ' + msg(r)]; });
await t('24', 'Manager suspends a member with a reason', async () => {
  const r = await rpc('suspend_member', { p_user_id: target, p_reason: 'Test suspension (TC 24)' }, M);
  const st = await get(`user_roles?select=status&user_id=eq.${target}`, SERVICE);
  return [ok(r), r.status + ' ' + msg(r) + ' | role status: ' + JSON.stringify(st.json)];
});
await t('24.2', 'Manager reactivates the suspended member', async () => {
  const r = await rpc('reactivate_member', { p_user_id: target }, M);
  const st = await get(`user_roles?select=status&user_id=eq.${target}`, SERVICE);
  return [ok(r) && JSON.stringify(st.json).includes('active'), r.status + ' ' + msg(r) + ' | role status: ' + JSON.stringify(st.json)];
});

// ---- TC 6, 6.1, 6.2, 7, 7.1: Officer account and access
let newOfficerId;
await t('6', 'Manager creates an Officer with module access', async () => {
  const r = await rpc('create_officer_account', { p_username: 'tcx_officer' + run, p_password: 'Test@12345', p_surname: 'Dela Cruz', p_first_name: 'Pedro', p_date_of_birth: dob, p_gender: 'male', p_permissions: { members: 'manage', loans: 'view' } }, M);
  newOfficerId = idOf(r.json) || await lookupId('tcx_officer' + run);
  const g = newOfficerId ? await rpc('get_officer_permissions', { p_user_id: newOfficerId }, M) : { json: null };
  const pm = g.json || {}; const good = pm.members === 'manage' && pm.loans === 'view';
  return [ok(r) && good, r.status + ' stored access: ' + JSON.stringify(pm)];
});
await t('6.1', 'Officer with a duplicate username or under 18 is refused', async () => {
  const a = await rpc('create_officer_account', { p_username: 'tcx_officer' + run, p_password: 'Test@12345', p_surname: 'Copy', p_first_name: 'Cat', p_date_of_birth: dob, p_gender: 'male' }, M);
  const b = await rpc('create_officer_account', { p_username: 'tcx_officer2' + run, p_password: 'Test@12345', p_surname: 'Teen', p_first_name: 'Tim', p_date_of_birth: '2015-01-01', p_gender: 'male' }, M);
  return [refusedFor(a, /username|already|taken|exists/i) && refusedFor(b, /18 years/i), `duplicate: ${a.status} ${msg(a)} | under 18: ${b.status} ${msg(b)}`];
});
await t('6.2', 'An Officer cannot create Officer accounts', async () => {
  const r = await rpc('create_officer_account', { p_username: 'tcx_officer3' + run, p_password: 'Test@12345', p_surname: 'No', p_first_name: 'Way', p_date_of_birth: dob, p_gender: 'male' }, OM);
  return [refusedFor(r, /manager|permission|not allowed|only/i), r.status + ' ' + msg(r)];
});
await t('7', 'Manager changes an Officer\'s module access', async () => {
  if (!newOfficerId) return [false, 'no officer id'];
  const r = await rpc('set_officer_permissions', { p_user_id: newOfficerId, p_permissions: { members: 'view', loans: 'manage' } }, M);
  const g = await rpc('get_officer_permissions', { p_user_id: newOfficerId }, M);
  return [ok(r), r.status + ' ' + msg(r) + ' | now: ' + JSON.stringify(g.json).slice(0, 100)];
});
await t('7.1', 'An Officer cannot change Officer access', async () => {
  if (!newOfficerId) return [false, 'no officer id'];
  const r = await rpc('set_officer_permissions', { p_user_id: newOfficerId, p_permissions: { members: 'manage' } }, OM);
  return [!ok(r), r.status + ' ' + msg(r)];
});

// ---- TC 27, 27.1: monthly contribution
const month = new Date().toISOString().slice(0, 7) + '-01';
await rpc('sync_monthly_contributions', {}, SERVICE);
await t('27.1-zero', 'A zero contribution amount is refused', async () => {
  const r = await rpc('record_monthly_contribution_payment', { p_farmer_id: U.t_farmer1.id, p_month: month, p_amount: 0 }, M);
  return [refusedFor(r, /greater than zero/i), r.status + ' ' + msg(r)];
});

// ---- TC 21 (status + notification), 21.1, 21.2, 23, 23.1, 28, 28.1, 14, 14.1
const mk = async (suffix, tok = M) => {
  const r = await rpc('create_farmer_account', { p_username: 'tcx_' + suffix + run, p_password: 'Test@12345', p_surname: 'Case', p_first_name: suffix, p_date_of_birth: dob, p_gender: 'male', p_street: 'Rizal Street', p_house_no: '12' }, tok);
  return idOf(r.json) || await lookupId('tcx_' + suffix + run);
};
const statusOf = async (id) => (await get('user_roles?select=status&user_id=eq.' + id, SERVICE)).json?.[0]?.status;
await t('21-status', 'After approval the pending Farmer is Active and has been notified', async () => {
  const id = await mk('apr', OM); const before = await statusOf(id);
  const r = await rpc('approve_member', { p_user_id: id }, M);
  const after = await statusOf(id); const n = await get('notifications?select=id,type&user_id=eq.' + id, SERVICE);
  return [before === 'pending' && ok(r) && after === 'active' && Array.isArray(n.json) && n.json.length > 0, 'status ' + before + ' -> ' + after + ', notifications for the Farmer: ' + (Array.isArray(n.json) ? n.json.length : n.status)];
});
const rej = await mk('rej', OM);
await t('21.2', 'Disapproving without a reason is refused', async () => { const r = await rpc('reject_member', { p_user_id: rej, p_reason: '' }, M); return [refusedFor(r, /reason/i), r.status + ' ' + msg(r)]; });
await t('21.1', 'Disapproving with a reason records the decision', async () => {
  const r = await rpc('reject_member', { p_user_id: rej, p_reason: 'Incomplete details (TC 21.1)' }, M);
  const st = await statusOf(rej); const n = await get('notifications?select=id&user_id=eq.' + rej, SERVICE);
  return [ok(r) && /reject|disapprov/i.test(String(st)), 'status now ' + st + '; notifications: ' + (Array.isArray(n.json) ? n.json.length : n.status) + ' ' + msg(r)];
});
await t('23.1', 'An active member cannot be deleted as a disapproved applicant', async () => {
  const r = await rpc('admin_delete_rejected_applicant', { p_user_id: U.t_farmer1.id }, M);
  const still = await statusOf(U.t_farmer1.id); return [!ok(r) && still === 'active', r.status + ' ' + msg(r) + ' | member status still ' + still];
});
await t('23', 'A disapproved applicant\'s account can be deleted', async () => {
  const r = await rpc('admin_delete_rejected_applicant', { p_user_id: rej }, M);
  const gone = await get('user_roles?select=user_id&user_id=eq.' + rej, SERVICE);
  return [ok(r) && Array.isArray(gone.json) && gone.json.length === 0, r.status + ' ' + msg(r) + ' | rows left: ' + (Array.isArray(gone.json) ? gone.json.length : gone.status)];
});
await t('28', 'Manager issues a temporary password for a member', async () => {
  const id = await mk('pwd'); const r = await rpc('admin_reset_user_password', { p_user_id: id }, M);
  return [ok(r) && String(JSON.stringify(r.json)).length > 6, r.status + ' returned a value of length ' + JSON.stringify(r.json).length];
});
await t('28.1', 'An Officer with Members View Only cannot issue a temporary password', async () => {
  const r = await rpc('admin_reset_user_password', { p_user_id: U.t_farmer2.id }, OV); return [refusedFor(r, /view-only|manage|permission|not allowed|only/i), r.status + ' ' + msg(r)];
});
await t('14', 'The Manager can read the staff accountability records', async () => {
  const r = await get('admin_activity_log?select=id&limit=5', M); return [ok(r) && Array.isArray(r.json) && r.json.length > 0, 'status ' + r.status + ', rows returned: ' + (Array.isArray(r.json) ? r.json.length : msg(r))];
});
await t('14.1', 'An Officer cannot read the database accountability trail directly', async () => {
  const r = await get('admin_activity_log?select=id&source=eq.db&limit=5', OM); const r2 = await get('admin_activity_log?select=id&module=eq.reports&action_type=eq.exported&limit=5', OM);
  return [ok(r) && Array.isArray(r.json) && r.json.length === 0 && Array.isArray(r2.json) && r2.json.length === 0, 'database-trail rows visible to the Officer: ' + (Array.isArray(r.json) ? r.json.length : msg(r)) + '; export rows: ' + (Array.isArray(r2.json) ? r2.json.length : msg(r2))];
});

const pass = out.filter(x => x.pass).length;
console.log(`\n${pass}/${out.length} passed`);
writeFileSync(new URL('../results/tc_extra_results.json', import.meta.url), JSON.stringify({ ran: new Date().toISOString(), results: out }, null, 1));
