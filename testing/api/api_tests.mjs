// SAGANA API / security tests. LOCAL STACK ONLY. Run: node testing/api/api_tests.mjs
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
const msg = r => typeof r.json === 'object' && r.json ? (r.json.message || r.json.error_description || r.json.msg || JSON.stringify(r.json)).toString().slice(0, 140) : String(r.json).slice(0, 140);
const rows = r => Array.isArray(r.json) ? r.json.length : -1;
const ok = r => r.status >= 200 && r.status < 300;

async function login(u) {
  const r = await call('POST', '/auth/v1/token?grant_type=password', { body: { email: u + '@sagana.local', password: 'Test@12345' } });
  if (!r.json.access_token) throw new Error('login failed ' + u + ' ' + JSON.stringify(r.json));
  return { token: r.json.access_token, id: r.json.user.id };
}
const results = [];
async function t(area, name, fn) {
  try { const [pass, detail] = await fn(); results.push({ area, name, pass, detail: detail || '' }); }
  catch (e) { results.push({ area, name, pass: false, detail: 'EXCEPTION ' + e.message }); }
  const x = results.at(-1); console.log((x.pass ? 'PASS' : 'FAIL') + ' [' + area + '] ' + name + (x.pass ? '' : ' -> ' + x.detail));
}
const U = {};
for (const u of ['t_manager', 't_officer_view', 't_officer_manage', 't_farmer1', 't_farmer2', 't_pending', 't_buyer1']) U[u] = await login(u);
const M = U.t_manager.token, OV = U.t_officer_view.token, OM = U.t_officer_manage.token, F1 = U.t_farmer1.token, F2 = U.t_farmer2.token, P = U.t_pending.token, B = U.t_buyer1.token;
const sr = (m, p, b) => call(m, p, { token: SERVICE, body: b });

// ---------- AUTH ----------
await t('auth', 'wrong password is refused', async () => { const r = await call('POST', '/auth/v1/token?grant_type=password', { body: { email: 't_farmer1@sagana.local', password: 'nope' } }); return [r.status === 400, r.status + ' ' + msg(r)]; });
await t('auth', 'garbage JWT is refused', async () => { const r = await get('user_roles?select=*', 'abc.def.ghi'); return [r.status === 401, r.status]; });

// ---------- ANON EXPOSURE ----------
for (const tb of ['user_information', 'user_roles', 'orders', 'farmer_loans', 'notifications', 'harvest_records', 'inventory_batches', 'farmer_expenses', 'member_capital_shares', 'buyer_addresses', 'admin_activity_log', 'cooperative_inventory'])
  await t('rls-anon', `anon cannot read ${tb}`, async () => { const r = await get(tb + '?select=*&limit=5'); return [rows(r) === 0 || r.status >= 400, r.status + ' rows=' + rows(r)]; });

// ---------- DATA ISOLATION BETWEEN ROLES ----------
// seed a harvest + batch for farmer1 and farmer2 through the real farmer path
async function makeBatch(F, id, crop, qty, unit = 'kg') {
  const fc = await get(`farmer_crops?select=id,crop_name&farmer_id=eq.${id}&crop_name=eq.${crop}`, F);
  const crop_id = fc.json[0].id;
  const h = await call('POST', '/rest/v1/harvest_records', { token: F, body: { farmer_id: id, crop_id, crop_name: crop, crop_category: 'Vegetables', quantity_kg: qty, harvest_date: new Date().toISOString().slice(0, 10), unit } });
  if (!ok(h)) return { error: msg(h), status: h.status };
  const b = await call('POST', '/rest/v1/inventory_batches', { token: F, body: { farmer_id: id, harvest_record_id: h.json[0].id, crop_id, crop_name: crop, batch_number: 'x', quantity_kg: qty, available_kg: qty, unit } });
  return { harvest: h.json[0], batch: ok(b) ? b.json[0] : null, error: ok(b) ? null : msg(b) };
}
let b1, b2;
await t('farmer', 'farmer records a harvest + batch (decimal qty 12.5)', async () => { b1 = await makeBatch(F1, U.t_farmer1.id, 'Tomato', 12.5); return [!!b1.batch, JSON.stringify(b1.batch ? { n: b1.batch.batch_number, a: b1.batch.available_kg, s: b1.batch.status } : b1)]; });
await t('farmer', 'batch number follows BATCH-CROP-YYMMDD-X0001', async () => [/^BATCH-TOMATO-\d{6}-[A-Z]+\d{4}$/.test(b1?.batch?.batch_number || ''), b1?.batch?.batch_number]);
b2 = await makeBatch(F2, U.t_farmer2.id, 'Tomato', 20);
await t('farmer', 'zero quantity harvest is refused', async () => { const x = await makeBatch(F1, U.t_farmer1.id, 'Tomato', 0); return [!!x.error, x.error]; });
await t('farmer', 'negative quantity harvest is refused', async () => { const x = await makeBatch(F1, U.t_farmer1.id, 'Tomato', -3); return [!!x.error, x.error]; });
await t('farmer', 'unknown unit is refused', async () => { const x = await makeBatch(F1, U.t_farmer1.id, 'Tomato', 2, 'parsec'); return [!!x.error, x.error]; });

for (const tb of ['harvest_records', 'inventory_batches', 'farmer_crops', 'farmer_expenses', 'member_capital_shares', 'buyer_addresses', 'notifications', 'farmer_loans'])
  await t('rls-farmer', `farmer1 cannot see farmer2 rows in ${tb}`, async () => { const col = ['member_capital_shares', 'farmer_crops', 'farmer_expenses', 'farmer_loans', 'harvest_records', 'inventory_batches'].includes(tb) ? 'farmer_id' : 'user_id'; const r = await get(`${tb}?select=*&${col}=eq.${U.t_farmer2.id}`, F1); return [rows(r) === 0, tb + ' rows=' + rows(r) + ' ' + (rows(r) < 0 ? msg(r) : '')]; });
await t('rls-buyer', 'buyer cannot read farmers\' harvest_records', async () => { const r = await get(`harvest_records?select=id&id=eq.${b1.harvest.id}`, B); return [rows(r) === 0, 'rows=' + rows(r) + ' (a harvest of a batch this buyer never ordered; a buyer may read harvests of batches they ordered, by design)']; });
await t('rls-buyer', 'buyer cannot read other users\' user_information', async () => { const r = await get('user_information?select=user_id', B); return [rows(r) <= 1, 'rows=' + rows(r)]; });
await t('rls-buyer', 'buyer cannot read a batch that is not on an approved listing (status=available policy)', async () => { const r = await get(`inventory_batches?select=id&id=eq.${b1.batch.id}`, B); return [rows(r) === 0, 'buyer sees ' + rows(r) + ' rows for an unlisted batch (batches of approved listings are readable, by design)']; });

// ---------- PRIVILEGE ESCALATION ----------
await t('escalation', 'pending farmer cannot approve themselves (user_roles.status)', async () => { const r = await call('PATCH', `/rest/v1/user_roles?user_id=eq.${U.t_pending.id}`, { token: P, body: { status: 'active' } }); const s = await sr('GET', `/rest/v1/user_roles?user_id=eq.${U.t_pending.id}&select=status`); return [s.json[0].status === 'pending', 'status now ' + s.json[0].status + ' http ' + r.status]; });
await t('escalation', 'farmer cannot make themselves admin', async () => { await call('PATCH', `/rest/v1/user_roles?user_id=eq.${U.t_farmer1.id}`, { token: F1, body: { role: 'admin' } }); const s = await sr('GET', `/rest/v1/user_roles?user_id=eq.${U.t_farmer1.id}&select=role`); return [s.json[0].role === 'farmer', 'role now ' + s.json[0].role]; });
await t('escalation', 'farmer cannot self-verify farmer_profiles.is_verified', async () => { await call('PATCH', `/rest/v1/farmer_profiles?user_id=eq.${U.t_pending.id}`, { token: P, body: { is_verified: true } }); const s = await sr('GET', `/rest/v1/farmer_profiles?user_id=eq.${U.t_pending.id}&select=is_verified`); return [s.json[0].is_verified === false, 'is_verified=' + s.json[0].is_verified]; });
await t('escalation', 'farmer cannot insert capital contribution for self', async () => { const r = await call('POST', '/rest/v1/capital_contribution_events', { token: F1, body: { farmer_id: U.t_farmer1.id, amount: 99999, source: 'member_payment' } }); return [!ok(r), r.status + ' ' + msg(r)]; });
await t('escalation', 'farmer cannot edit member_capital_shares total', async () => { const q = `/rest/v1/member_capital_shares?farmer_id=eq.${U.t_farmer1.id}&select=total_contribution`; const before = Number((await sr('GET', q)).json[0].total_contribution); await call('PATCH', `/rest/v1/member_capital_shares?farmer_id=eq.${U.t_farmer1.id}`, { token: F1, body: { total_contribution: 999999 } }); const after = Number((await sr('GET', q)).json[0].total_contribution); return [after === before && after !== 999999, `before=${before} after=${after}`]; });
await t('escalation', 'farmer cannot write price_records', async () => { const r = await call('POST', '/rest/v1/price_records', { token: F1, body: { crop_name: 'Tomato', price: 1, unit: 'kg', price_type: 'open_market' } }); return [!ok(r), r.status]; });
await t('escalation', 'farmer cannot write cooperative_inventory', async () => { const r = await call('POST', '/rest/v1/cooperative_inventory', { token: F1, body: { item_name: 'x', source: 'x', unit: 'kg' } }); return [!ok(r), r.status]; });
await t('escalation', 'farmer cannot change loan policy', async () => { await call('PATCH', '/rest/v1/loan_policy_settings?id=eq.1', { token: F1, body: { minimum_capital_contribution: 0 } }); const s = await sr('GET', '/rest/v1/loan_policy_settings?select=minimum_capital_contribution'); return [Number(s.json[0].minimum_capital_contribution) === 2000, 'min=' + s.json[0].minimum_capital_contribution]; });
await t('escalation', 'buyer cannot edit an order status directly', async () => { const r = await call('PATCH', '/rest/v1/orders?status=eq.pending', { token: B, body: { status: 'completed' } }); return [rows(r) <= 0, r.status + ' rows=' + rows(r)]; });
for (const [fn, args] of [['approve_listing', { p_listing_id: crypto.randomUUID() }], ['issue_loan', { p_farmer_id: U.t_farmer1.id, p_items: [], p_issued_date: '2026-01-01', p_monthly_payment: 1, p_next_payment_date: '2026-02-01' }], ['approve_member', { p_user_id: U.t_pending.id }], ['admin_reset_user_password', { p_user_id: U.t_manager.id }], ['create_officer_account', { p_username: 'evil', p_password: 'x', p_surname: 'Evil', p_first_name: 'Eve' }], ['suspend_member', { p_user_id: U.t_farmer2.id, p_reason: 'x' }], ['adjust_cooperative_stock', { p_inventory_id: crypto.randomUUID(), p_quantity: 1, p_transaction_type: 'restock', p_request_id: crypto.randomUUID() }], ['send_broadcast', { p_title: 'x', p_body: 'x', p_category: 'general', p_recipient_type: 'all_members', p_recipient_filter: null, p_client_key: crypto.randomUUID() }]])
  for (const [who, tok] of [['farmer', F1], ['buyer', B], ['anon', null]])
    await t('rpc-authz', `${who} cannot call staff RPC ${fn}`, async () => { const r = await rpc(fn, args, tok); const body = JSON.stringify(r.json); return [!ok(r), r.status + ' ' + msg(r)]; });

// unauthenticated callers of SECURITY DEFINER helpers
await t('rpc-authz', 'anon cannot forge a notification (notify_user)', async () => { const r = await rpc('notify_user', { p_user_id: U.t_farmer1.id, p_type: 'system', p_title: 'FORGED', p_body: 'pay me' }, null); const n = await sr('GET', `/rest/v1/notifications?user_id=eq.${U.t_farmer1.id}&title=eq.FORGED&select=id`); return [n.json.length === 0, 'http ' + r.status + ' forged rows=' + n.json.length]; });
await t('rpc-authz', 'buyer cannot forge a notification to another user (notify_user)', async () => { const r = await rpc('notify_user', { p_user_id: U.t_farmer1.id, p_type: 'system', p_title: 'FORGED2', p_body: 'pay me' }, B); const n = await sr('GET', `/rest/v1/notifications?user_id=eq.${U.t_farmer1.id}&title=eq.FORGED2&select=id`); return [n.json.length === 0, 'http ' + r.status + ' forged rows=' + n.json.length]; });
await t('rpc-authz', 'anon cannot reduce another farmer\'s stock (_apply_batch_reservation)', async () => { const r = await rpc('_apply_batch_reservation', { p_batch_id: b2.batch.id, p_quantity: 5 }, null); const s = await sr('GET', `/rest/v1/inventory_batches?id=eq.${b2.batch.id}&select=available_kg`); return [Number(s.json[0].available_kg) === 20, 'available now ' + s.json[0].available_kg + ' http ' + r.status]; });
await t('rpc-authz', 'farmer cannot change another farmer\'s stock (_release_batch_reservation)', async () => { await sr('PATCH', `/rest/v1/inventory_batches?id=eq.${b2.batch.id}`, { available_kg: 10 }); const r = await rpc('_release_batch_reservation', { p_batch_id: b2.batch.id, p_quantity: 5 }, F1); const s = await sr('GET', `/rest/v1/inventory_batches?id=eq.${b2.batch.id}&select=available_kg`); const v = Number(s.json[0].available_kg); await sr('PATCH', `/rest/v1/inventory_batches?id=eq.${b2.batch.id}`, { available_kg: 20 }); return [v === 10, 'available now ' + v + ' (was 10) http ' + r.status]; });
await t('rpc-authz', 'anon cannot run loan maintenance (run_daily_loan_maintenance)', async () => { const r = await rpc('run_daily_loan_maintenance', {}, null); return [!ok(r), r.status + ' ' + msg(r)]; });
await t('rpc-authz', 'anon cannot run notify_overdue_farmers', async () => { const r = await rpc('notify_overdue_farmers', {}, null); return [!ok(r), r.status + ' ' + msg(r)]; });
await t('rpc-authz', 'anon cannot enumerate usernames (suggest_next_username)', async () => { const r = await rpc('suggest_next_username', { p_prefix: 't_farmer' }, null); return [!ok(r), r.status + ' ' + msg(r)]; });

// ---------- OFFICER VIEW-ONLY / MANAGE GATE ----------
await t('officer-gate', 'view-only officer can READ crop_master', async () => { const r = await get('crop_master?select=id&limit=1', OV); return [rows(r) === 1, 'rows=' + rows(r)]; });
await t('officer-gate', 'view-only officer is refused a write (units insert)', async () => { const r = await call('POST', '/rest/v1/units', { token: OV, body: { name: 'viewtest' + Date.now() } }); return [r.status === 403 || r.status === 400 || !ok(r), r.status + ' ' + msg(r)]; });
await t('officer-gate', 'manage officer may write (units insert)', async () => { const r = await call('POST', '/rest/v1/units', { token: OM, body: { name: 'mgrtest' + Date.now() } }); return [ok(r), r.status + ' ' + msg(r)]; });
await t('officer-gate', 'view-only officer is refused RPC approve_crop_request', async () => { const r = await rpc('approve_crop_request', { p_request_id: crypto.randomUUID() }, OV); return [/view-only/i.test(msg(r)), r.status + ' ' + msg(r)]; });
await t('officer-gate', 'manage officer passes the gate on RPC approve_crop_request', async () => { const r = await rpc('approve_crop_request', { p_request_id: crypto.randomUUID() }, OM); return [!/view-only/i.test(msg(r)), r.status + ' ' + msg(r)]; });

// Officer gate on writes added by later scripts (restrictions, monthly contributions, Capital Share rates)
await t('officer-gate', 'view-only officer cannot restrict a member (restrict_member)', async () => { const r = await rpc('restrict_member', { p_user_id: U.t_farmer1.id, p_features: ['checkout'], p_reason: 'x', p_ends_at: null }, OV); return [!ok(r) && /view-only/i.test(msg(r)), r.status + ' ' + msg(r)]; });
await t('officer-gate', 'manage officer may restrict and lift (restrict_member / lift_member_restriction)', async () => {
  const a = await rpc('restrict_member', { p_user_id: U.t_farmer2.id, p_features: ['checkout'], p_reason: 'Officer test', p_ends_at: null }, OM);
  if (!ok(a)) return [false, 'restrict: ' + msg(a)];
  const lst = await sr('GET', `/rest/v1/member_restrictions?member_id=eq.${U.t_farmer2.id}&status=eq.active&select=id`);
  const b = await rpc('lift_member_restriction', { p_restriction_id: lst.json[0].id }, OM); return [ok(b), 'lift: ' + msg(b)]; });
await t('officer-gate', 'view-only officer cannot record a monthly contribution payment', async () => { const r = await rpc('record_monthly_contribution_payment', { p_farmer_id: U.t_farmer1.id, p_month: '2026-11-01', p_amount: 100 }, OV); return [!ok(r) && /view-only|not|unauthorized|manager/i.test(msg(r)), r.status + ' ' + msg(r)]; });
await t('officer-gate', 'view-only officer cannot change Capital Share rates', async () => { await call('PATCH', '/rest/v1/capital_share_rates?id=eq.1', { token: OV, body: { purchase_percent: 99 } }); const s = await sr('GET', '/rest/v1/capital_share_rates?select=purchase_percent'); return [Number(s.json[0].purchase_percent) === 10, 'purchase_percent=' + s.json[0].purchase_percent]; });
await t('officer-gate', 'farmer cannot change Capital Share rates', async () => { await call('PATCH', '/rest/v1/capital_share_rates?id=eq.1', { token: F1, body: { purchase_percent: 99 } }); const s = await sr('GET', '/rest/v1/capital_share_rates?select=purchase_percent'); return [Number(s.json[0].purchase_percent) === 10, 'purchase_percent=' + s.json[0].purchase_percent]; });
await t('officer-gate', 'manager can change Capital Share rates (and it is versioned)', async () => { const r = await call('PATCH', '/rest/v1/capital_share_rates?id=eq.1', { token: M, body: { purchase_percent: 12 } }); const v = await sr('GET', '/rest/v1/capital_share_rate_versions?select=version,purchase_percent&order=version.desc&limit=1'); await call('PATCH', '/rest/v1/capital_share_rates?id=eq.1', { token: M, body: { purchase_percent: 10 } }); return [ok(r) && Number(v.json[0].purchase_percent) === 12, 'http ' + r.status + ' latest version=' + JSON.stringify(v.json[0])]; });

// ---------- MARKETPLACE FLOW ----------
let listing, L2;
await t('marketplace', 'farmer lists 10 kg (pending approval)', async () => { const r = await rpc('create_listing_with_reservation', { p_batch_id: b1.batch.id, p_crop_name: 'Tomato', p_variety: null, p_quantity_kg: 10, p_price_per_kg: 50, p_photo_url: null, p_description: 'Fresh tomatoes' }, F1); listing = r.json; return [ok(r), msg(r) + ' ' + (ok(r) ? '' : '')]; });
await t('marketplace', 'batch available drops by reserved qty', async () => { const s = await sr('GET', `/rest/v1/inventory_batches?id=eq.${b1.batch.id}&select=available_kg,reserved_kg`); return [Number(s.json[0].available_kg) === 2.5 && Number(s.json[0].reserved_kg) === 10, JSON.stringify(s.json[0])]; });
await t('marketplace', 'cannot list more than available (5 kg > 2.5 left)', async () => { const r = await rpc('create_listing_with_reservation', { p_batch_id: b1.batch.id, p_crop_name: 'Tomato', p_variety: null, p_quantity_kg: 5, p_price_per_kg: 50, p_photo_url: null, p_description: 'x' }, F1); return [!ok(r), msg(r)]; });
await t('marketplace', 'cannot list another farmer\'s batch', async () => { const r = await rpc('create_listing_with_reservation', { p_batch_id: b2.batch.id, p_crop_name: 'Tomato', p_variety: null, p_quantity_kg: 1, p_price_per_kg: 50, p_photo_url: null, p_description: 'x' }, F1); return [!ok(r), msg(r)]; });
await t('marketplace', 'listing without description is refused', async () => { const r = await rpc('create_listing_with_reservation', { p_batch_id: b1.batch.id, p_crop_name: 'Tomato', p_variety: null, p_quantity_kg: 1, p_price_per_kg: 50, p_photo_url: null, p_description: '  ' }, F1); return [!ok(r), msg(r)]; });
await t('marketplace', 'listing with 3-decimal quantity is refused', async () => { const r = await rpc('create_listing_with_reservation', { p_batch_id: b1.batch.id, p_crop_name: 'Tomato', p_variety: null, p_quantity_kg: 1.234, p_price_per_kg: 50, p_photo_url: null, p_description: 'x' }, F1); return [!ok(r), msg(r)]; });
await t('marketplace', 'Ginger cannot be put on the marketplace (DA-AMAD only)', async () => { const g = await makeBatch(F1, U.t_farmer1.id, 'Ginger', 5); if (!g.batch) return [false, 'could not make ginger batch ' + JSON.stringify(g)]; const r = await rpc('create_listing_with_reservation', { p_batch_id: g.batch.id, p_crop_name: 'Ginger', p_variety: null, p_quantity_kg: 1, p_price_per_kg: 50, p_photo_url: null, p_description: 'x' }, F1); return [!ok(r), msg(r)]; });
await t('marketplace', 'buyer cannot see the listing before approval', async () => { const r = await get(`marketplace_listings?id=eq.${listing}&select=id`, B); return [rows(r) === 0, 'rows=' + rows(r)]; });
await t('marketplace', 'view-only officer cannot approve a listing', async () => { const r = await rpc('approve_listing', { p_listing_id: listing }, OV); return [!ok(r), r.status + ' ' + msg(r)]; });
await t('marketplace', 'farmer cannot approve own listing', async () => { const r = await rpc('approve_listing', { p_listing_id: listing }, F1); return [!ok(r), msg(r)]; });
await t('marketplace', 'manager approves the listing', async () => { const r = await rpc('approve_listing', { p_listing_id: listing }, M); return [ok(r), r.status + ' ' + msg(r)]; });
await t('marketplace', 'manager cannot approve twice', async () => { const r = await rpc('approve_listing', { p_listing_id: listing }, M); return [!ok(r), msg(r)]; });
await t('marketplace', 'buyer now sees the listing', async () => { const r = await get(`marketplace_listings?id=eq.${listing}&select=id,remaining_kg`, B); return [rows(r) === 1, 'rows=' + rows(r)]; });
let order, reqId = crypto.randomUUID();
await t('orders', 'buyer cannot order more than remaining (11 kg)', async () => { const r = await rpc('place_order', { p_listing_id: listing, p_quantity_kg: 11 }, B); return [!ok(r), msg(r)]; });
await t('orders', 'buyer cannot order 0 or negative', async () => { const a = await rpc('place_order', { p_listing_id: listing, p_quantity_kg: 0 }, B); const b = await rpc('place_order', { p_listing_id: listing, p_quantity_kg: -2 }, B); return [!ok(a) && !ok(b), msg(a) + ' | ' + msg(b)]; });
await t('orders', 'buyer cannot order 3 decimals', async () => { const r = await rpc('place_order', { p_listing_id: listing, p_quantity_kg: 1.005 }, B); return [!ok(r), msg(r)]; });
await t('orders', 'farmer cannot order own listing', async () => { const r = await rpc('place_order', { p_listing_id: listing, p_quantity_kg: 1 }, F1); return [!ok(r), msg(r)]; });
await t('orders', 'pending (unapproved) farmer cannot order', async () => { const r = await rpc('place_order', { p_listing_id: listing, p_quantity_kg: 1 }, P); return [!ok(r), msg(r)]; });
await t('orders', 'buyer places order of 2.5 kg', async () => { const r = await rpc('place_order', { p_listing_id: listing, p_quantity_kg: 2.5, p_request_id: reqId }, B); order = r.json; return [ok(r), msg(r)]; });
await t('orders', 'same request id returns the same order (idempotent)', async () => { const r = await rpc('place_order', { p_listing_id: listing, p_quantity_kg: 2.5, p_request_id: reqId }, B); const s = await sr('GET', `/rest/v1/marketplace_listings?id=eq.${listing}&select=remaining_kg`); return [r.json === order && Number(s.json[0].remaining_kg) === 7.5, 'same=' + (r.json === order) + ' remaining=' + s.json[0].remaining_kg]; });
await t('orders', 'order number format ORD-YYYYMMDD-A001', async () => { const r = await get(`orders?id=eq.${order}&select=order_number,status,total_price`, B); return [/^ORD-\d{8}-[A-Z]+\d{3}$/.test(r.json[0]?.order_number), JSON.stringify(r.json[0])]; });
await t('orders', 'other buyer/farmer cannot read the order', async () => { const r = await get(`orders?id=eq.${order}&select=id`, F2); return [rows(r) === 0, 'rows=' + rows(r)]; });
await t('orders', 'cannot skip: buyer cannot confirm receipt while pending', async () => { const r = await rpc('confirm_order_received', { p_order_id: order }, B); return [!ok(r), msg(r)]; });
await t('orders', 'cannot mark ready before approval', async () => { const r = await rpc('mark_order_ready_for_pickup', { p_order_id: order }, M); return [!ok(r), msg(r)]; });
await t('orders', 'view-only officer cannot approve order', async () => { const r = await rpc('approve_order', { p_order_id: order }, OV); return [!ok(r), r.status + ' ' + msg(r)]; });
await t('orders', 'manager approves order', async () => { const r = await rpc('approve_order', { p_order_id: order }, M); return [ok(r) && r.json === true, msg(r)]; });
await t('orders', 'approve again is a harmless no-op', async () => { const r = await rpc('approve_order', { p_order_id: order }, M); return [ok(r) && r.json === false, msg(r)]; });
await t('orders', 'buyer can no longer cancel an approved order', async () => { const r = await rpc('cancel_my_order', { p_order_id: order }, B); return [!ok(r), msg(r)]; });
await t('orders', 'manager marks ready for pickup', async () => { const r = await rpc('mark_order_ready_for_pickup', { p_order_id: order }, M); return [ok(r), msg(r)]; });
await t('orders', 'payment with wrong amount is refused', async () => { const r = await rpc('record_order_payment', { p_order_id: order, p_amount: 100 }, M); return [!ok(r), msg(r)]; });
await t('orders', 'buyer cannot confirm receipt before payment is recorded', async () => { const r = await rpc('confirm_order_received', { p_order_id: order }, B); return [!ok(r), msg(r)]; });
await t('orders', 'manager records correct payment (2.5 x 50 = 125)', async () => { const r = await rpc('record_order_payment', { p_order_id: order, p_amount: 125 }, M); return [ok(r), msg(r)]; });
await t('orders', 'payment cannot be recorded twice', async () => { const r = await rpc('record_order_payment', { p_order_id: order, p_amount: 125 }, M); return [!ok(r), msg(r)]; });
await t('orders', 'buyer confirms receipt -> completed', async () => { const r = await rpc('confirm_order_received', { p_order_id: order }, B); return [ok(r), msg(r)]; });
await t('orders', 'sold_kg of the batch is reconciled to 2.5', async () => { const s = await sr('GET', `/rest/v1/inventory_batches?id=eq.${b1.batch.id}&select=sold_kg,available_kg,reserved_kg`); return [Number(s.json[0].sold_kg) === 2.5, JSON.stringify(s.json[0])]; });
await t('orders', 'staff cannot completed-order directly through the table', async () => { const r = await call('PATCH', `/rest/v1/orders?id=eq.${order}`, { token: M, body: { status: 'pending' } }); return [!ok(r), r.status + ' ' + msg(r)]; });
await t('orders', 'recorded payment cannot be rewritten', async () => { const r = await call('PATCH', `/rest/v1/orders?id=eq.${order}`, { token: M, body: { amount_collected: 1 } }); return [!ok(r), r.status + ' ' + msg(r)]; });

// concurrency: 20 buyers race for 7.5 kg left, 1 kg each => exactly 7 succeed
await t('concurrency', '20 parallel 1 kg orders on 7.5 kg: exactly 7 succeed, never oversell', async () => {
  const rs = await Promise.all(Array.from({ length: 20 }, () => rpc('place_order', { p_listing_id: listing, p_quantity_kg: 1, p_request_id: crypto.randomUUID() }, B)));
  const n = rs.filter(ok).length; const s = await sr('GET', `/rest/v1/marketplace_listings?id=eq.${listing}&select=remaining_kg`);
  return [n === 7 && Number(s.json[0].remaining_kg) === 0.5, `succeeded=${n} remaining=${s.json[0].remaining_kg}`]; });

// feature restriction
await t('restrictions', 'manager restricts farmer2 checkout; place_order is refused with a reason', async () => {
  const r1 = await rpc('restrict_member', { p_user_id: U.t_farmer2.id, p_features: ['checkout'], p_reason: 'Test restriction', p_ends_at: null }, M);
  const r2 = await rpc('place_order', { p_listing_id: listing, p_quantity_kg: 0.5 }, F2); return [ok(r1) && !ok(r2) && /restricted/i.test(msg(r2)), msg(r1) + ' | ' + msg(r2)]; });
await t('restrictions', 'view-only officer cannot restrict a member', async () => { const r = await rpc('restrict_member', { p_user_id: U.t_farmer1.id, p_features: ['checkout'], p_reason: 'x', p_ends_at: null }, OV); return [!ok(r), msg(r)]; });
await t('restrictions', 'manager lifts restriction', async () => { const lst = await sr('GET', `/rest/v1/member_restrictions?member_id=eq.${U.t_farmer2.id}&status=eq.active&select=id`); const r = await rpc('lift_member_restriction', { p_restriction_id: lst.json[0].id }, M); return [ok(r), msg(r)]; });

// ---------- LOANS ----------
await t('loans', 'pending farmer cannot request a loan', async () => { const r = await rpc('submit_loan_request', { p_items: [{ inventoryItemId: crypto.randomUUID(), quantity: 1 }] }, P); return [!ok(r), msg(r)]; });
await t('loans', 'loan request with empty items refused', async () => { const r = await rpc('submit_loan_request', { p_items: [] }, F1); return [!ok(r), msg(r)]; });
await t('loans', 'view-only officer cannot issue a loan', async () => { const r = await rpc('issue_loan', { p_farmer_id: U.t_farmer1.id, p_items: [{ itemName: 'x', quantity: 1, unit: 'bag', unitPrice: 10, lineTotal: 10 }], p_issued_date: '2026-11-01', p_monthly_payment: 5, p_next_payment_date: '2026-12-01' }, OV); return [!ok(r), msg(r)]; });
let loan;
await t('loans', 'manager issues loan of 1,500 (within 5,000 capital share)', async () => { const r = await rpc('issue_loan', { p_farmer_id: U.t_farmer1.id, p_items: [{ itemName: 'Fertilizer', quantity: 3, unit: 'bag', unitPrice: 500, lineTotal: 1500 }], p_issued_date: '2026-11-01', p_monthly_payment: 500, p_next_payment_date: '2026-12-01', p_idempotency_key: 'k-' + Date.now() }, M); loan = r.json?.[0]; return [ok(r) && /^LRN-\d{8}-[A-Z]+\d{3}$/.test(loan?.reference_no), msg(r) + ' ' + JSON.stringify(loan)]; });
await t('loans', 'loan item above capital share (6,000 > 5,000) is refused', async () => { const r = await rpc('issue_loan', { p_farmer_id: U.t_farmer1.id, p_items: [{ itemName: 'Tractor', quantity: 1, unit: 'pc', unitPrice: 6000, lineTotal: 6000 }], p_issued_date: '2026-11-01', p_monthly_payment: 500, p_next_payment_date: '2026-12-01' }, M); return [!ok(r), msg(r)]; });
await t('loans', 'cannot loan to a pending (non-active) farmer', async () => { const r = await rpc('issue_loan', { p_farmer_id: U.t_pending.id, p_items: [{ itemName: 'x', quantity: 1, unit: 'bag', unitPrice: 1, lineTotal: 1 }], p_issued_date: '2026-11-01', p_monthly_payment: 1, p_next_payment_date: '2026-12-01' }, M); return [!ok(r), msg(r)]; });
await t('loans', 'farmer sees own loan, farmer2 does not', async () => { const a = await get('farmer_loans?select=id', F1), b = await get('farmer_loans?select=id', F2); return [rows(a) >= 1 && rows(b) === 0, `f1=${rows(a)} f2=${rows(b)}`]; });
await t('loans', 'payment larger than balance is refused', async () => { const r = await rpc('record_loan_payment', { p_loan_id: loan.loan_id, p_amount: 1600, p_payment_date: '2026-11-10', p_next_payment_date_if_active: '2026-12-10' }, M); return [!ok(r), msg(r)]; });
await t('loans', 'zero/negative payment refused', async () => { const a = await rpc('record_loan_payment', { p_loan_id: loan.loan_id, p_amount: 0, p_payment_date: '2026-11-10', p_next_payment_date_if_active: '2026-12-10' }, M); const b = await rpc('record_loan_payment', { p_loan_id: loan.loan_id, p_amount: -5, p_payment_date: '2026-11-10', p_next_payment_date_if_active: '2026-12-10' }, M); return [!ok(a) && !ok(b), msg(a) + ' | ' + msg(b)]; });
await t('loans', 'payment 500 recorded; same idempotency key replays without double charge', async () => { const k = 'pay-' + Date.now(); const a = await rpc('record_loan_payment', { p_loan_id: loan.loan_id, p_amount: 500, p_payment_date: '2026-11-10', p_next_payment_date_if_active: '2026-12-10', p_idempotency_key: k }, M); const b = await rpc('record_loan_payment', { p_loan_id: loan.loan_id, p_amount: 500, p_payment_date: '2026-11-10', p_next_payment_date_if_active: '2026-12-10', p_idempotency_key: k }, M); const s = await sr('GET', `/rest/v1/farmer_loans?id=eq.${loan.loan_id}&select=amount_paid,status`); return [ok(a) && ok(b) && Number(s.json[0].amount_paid) === 500, JSON.stringify(s.json[0]) + ' ' + msg(a)]; });
await t('loans', 'farmer cannot write a loan payment directly', async () => { const r = await call('POST', '/rest/v1/farmer_loan_payments', { token: F1, body: { loan_id: loan.loan_id, payment_date: '2026-11-10', amount_paid: 1500, running_balance: 0 } }); return [!ok(r), r.status]; });
await t('loans', 'farmer cannot edit own loan balance', async () => { await call('PATCH', `/rest/v1/farmer_loans?id=eq.${loan.loan_id}`, { token: F1, body: { amount_paid: 1500, status: 'paid' } }); const s = await sr('GET', `/rest/v1/farmer_loans?id=eq.${loan.loan_id}&select=amount_paid,status`); return [Number(s.json[0].amount_paid) === 500, JSON.stringify(s.json[0])]; });
await t('loans', 'loan reference cannot be changed', async () => { const r = await sr('PATCH', `/rest/v1/farmer_loans?id=eq.${loan.loan_id}`, { reference_no: 'LRN-HACK' }); return [!ok(r), msg(r)]; });

// ---------- MISC ----------
await t('misc', 'public price/market RPCs work for anon (guest mode)', async () => { const a = await rpc('public_latest_prices', {}, null), b = await rpc('public_market_types', {}, null), c = await rpc('public_marketplace_listings', { p_limit: 5 }, null); return [ok(a) && ok(b) && ok(c), `${a.status}/${b.status}/${c.status}`]; });
await t('misc', 'anon public_marketplace_listings exposes no farmer identity', async () => { const c = await rpc('public_marketplace_listings', { p_limit: 5 }, null); const keys = Object.keys(c.json[0] || {}); return [!keys.includes('farmer_id'), keys.join(',')]; });
await t('misc', 'username check rejects bad format', async () => { const r = await rpc('check_username_available', { p_username: 'a b' }, null); return [r.json === 'invalid', JSON.stringify(r.json)]; });
await t('misc', 'phone normalisation 63917… equals 0917…', async () => { const r = await rpc('normalize_ph_mobile', { p_phone: '+639171234567' }, null); return [r.json === '09171234567', JSON.stringify(r.json)]; });
await t('misc', 'SQL-injection-style username is handled safely', async () => { const r = await rpc('check_username_available', { p_username: "x' OR '1'='1" }, null); return [r.json === 'invalid', JSON.stringify(r.json)]; });
await t('misc', 'PostgREST filter injection via text param returns no extra rows', async () => { const r = await get("user_information?username=eq.t_farmer1'%20or%20'1'='1&select=user_id", F1); return [rows(r) === 0, 'rows=' + rows(r)]; });

const pass = results.filter(x => x.pass).length;
console.log(`\n${pass}/${results.length} passed, ${results.length - pass} failed`);
writeFileSync(new URL('../results/api_results.json', import.meta.url), JSON.stringify(results, null, 1));
