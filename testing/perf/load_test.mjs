// SAGANA performance / load / stress test. LOCAL STACK ONLY.
// Run (after seed/05_perf_volume.sql):  node testing/perf/load_test.mjs
import { execSync } from 'node:child_process';
import { createHmac } from 'node:crypto';
import { writeFileSync } from 'node:fs';

const env = Object.fromEntries(
  execSync('supabase status -o env', { cwd: new URL('../stack', import.meta.url), encoding: 'utf8' })
    .split(/\r?\n/).filter(l => l.includes('=')).map(l => { const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1).replace(/^"|"$/g, '')]; }));
const API = env.API_URL, ANON = env.ANON_KEY, SERVICE = env.SERVICE_ROLE_KEY, SECRET = env.JWT_SECRET;
if (!/^http:\/\/(127\.0\.0\.1|localhost):/.test(API)) throw new Error('Refusing to run: not a local stack: ' + API);

const b64 = o => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');
function mint(sub) { // a sign-in token for the LOCAL stack only (its own JWT secret)
  const head = b64({ alg: 'HS256', typ: 'JWT' });
  const body = b64({ aud: 'authenticated', role: 'authenticated', sub, iss: 'supabase-demo', exp: Math.floor(Date.now() / 1000) + 3600 });
  return `${head}.${body}.${createHmac('sha256', SECRET).update(`${head}.${body}`).digest('base64url')}`;
}
async function q(path, token = SERVICE) {
  const r = await fetch(API + path, { headers: { apikey: ANON, Authorization: 'Bearer ' + token } }); return r.json();
}

// ---- who and what to hit
const byName = async n => (await q(`/rest/v1/user_information?select=user_id&username=eq.${n}`))[0].user_id;
const farmers = (await q('/rest/v1/user_information?select=user_id&username=like.perf_f*&limit=60')).map(x => x.user_id);
const buyers = (await q('/rest/v1/user_information?select=user_id&username=like.perf_b*')).map(x => x.user_id);
const manager = await byName('t_manager');
const listingIds = (await q('/rest/v1/marketplace_listings?select=id&status=eq.approved&limit=1000')).map(x => x.id);
if (farmers.length < 10 || buyers.length < 3 || listingIds.length < 100) throw new Error('Run seed/05_perf_volume.sql first');
const tok = {}; for (const u of [...farmers, ...buyers, manager]) tok[u] = mint(u);
const rnd = a => a[Math.floor(Math.random() * a.length)];
const uuid = () => crypto.randomUUID();

async function hit(token, method, path, body) {
  const t0 = performance.now();
  try {
    const r = await fetch(API + path, { method, headers: { apikey: ANON, Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' }, body: body ? JSON.stringify(body) : undefined });
    await r.arrayBuffer();
    return { ms: performance.now() - t0, ok: r.status < 400, status: r.status };
  } catch (e) { return { ms: performance.now() - t0, ok: false, status: 0 }; }
}
// weighted operations per role
const ops = [
  // Buyer (60%)
  { w: 20, name: 'buyer: browse listings', f: () => hit(tok[rnd(buyers)], 'GET', '/rest/v1/marketplace_listings?select=id,crop_name,price_per_kg,remaining_kg,photo_url&status=eq.approved&order=created_at.desc&limit=50') },
  { w: 12, name: 'buyer: public listings RPC', f: () => hit(tok[rnd(buyers)], 'POST', '/rest/v1/rpc/public_marketplace_listings', { p_limit: 50 }) },
  { w: 12, name: 'buyer: my orders', f: () => { const b = rnd(buyers); return hit(tok[b], 'GET', `/rest/v1/orders?select=*&buyer_id=eq.${b}&order=created_at.desc&limit=30`); } },
  { w: 16, name: 'buyer: place order (write)', f: () => hit(tok[rnd(buyers)], 'POST', '/rest/v1/rpc/place_order', { p_listing_id: rnd(listingIds), p_quantity_kg: 0.01, p_request_id: uuid() }) },
  // Farmer (25%)
  { w: 8, name: 'farmer: my batches', f: () => { const u = rnd(farmers); return hit(tok[u], 'GET', `/rest/v1/inventory_batches?select=*&farmer_id=eq.${u}&order=created_at.desc`); } },
  { w: 7, name: 'farmer: my harvests', f: () => { const u = rnd(farmers); return hit(tok[u], 'GET', `/rest/v1/harvest_records?select=*&farmer_id=eq.${u}&order=harvest_date.desc&limit=50`); } },
  { w: 5, name: 'farmer: notifications', f: () => { const u = rnd(farmers); return hit(tok[u], 'GET', `/rest/v1/notifications?select=*&user_id=eq.${u}&order=created_at.desc&limit=30`); } },
  { w: 5, name: 'farmer: orders on my listings', f: () => { const u = rnd(farmers); return hit(tok[u], 'GET', `/rest/v1/orders?select=*&farmer_id=eq.${u}&order=created_at.desc&limit=50`); } },
  // Manager (15%)
  { w: 5, name: 'manager: pending orders', f: () => hit(tok[manager], 'GET', '/rest/v1/orders?select=*&status=eq.pending&order=created_at.desc&limit=100') },
  { w: 4, name: 'manager: members list', f: () => hit(tok[manager], 'GET', '/rest/v1/user_information?select=user_id,full_name,username,phone_number&order=full_name&limit=200') },
  { w: 3, name: 'manager: overdue loans', f: () => hit(tok[manager], 'GET', '/rest/v1/farmer_loans?select=*&status=eq.overdue&limit=100') },
  { w: 3, name: 'manager: supply chain totals (RPC)', f: () => hit(tok[manager], 'POST', '/rest/v1/rpc/get_supply_chain_totals', {}) },
];
const total = ops.reduce((a, o) => a + o.w, 0);
const pick = () => { let r = Math.random() * total; for (const o of ops) { if ((r -= o.w) < 0) return o; } return ops[0]; };
const pct = (a, p) => a.length ? a[Math.min(a.length - 1, Math.floor(a.length * p))] : 0;

function dockerStats() {
  try {
    return execSync('docker stats --no-stream --format "{{.Name}} cpu={{.CPUPerc}} mem={{.MemUsage}}" supabase_db_sagana-test supabase_rest_sagana-test supabase_kong_sagana-test', { encoding: 'utf8' }).trim().split(/\r?\n/).join(' | ');
  } catch { return 'n/a'; }
}
async function phase(name, users, seconds, thinkMs = 0) {
  const lat = [], per = {}; let ok = 0, bad = 0; const status = {};
  const end = Date.now() + seconds * 1000, t0 = performance.now();
  await Promise.all(Array.from({ length: users }, async () => {
    while (Date.now() < end) {
      const o = pick(); const r = await o.f();
      (per[o.name] ||= []).push(r.ms); if (r.ok) { ok++; lat.push(r.ms); } else { bad++; status[r.status] = (status[r.status] || 0) + 1; }
      if (thinkMs) await new Promise(res => setTimeout(res, thinkMs * (0.5 + Math.random())));
    }
  }));
  const secs = (performance.now() - t0) / 1000; lat.sort((a, b) => a - b);
  const row = { phase: name, users, seconds: +secs.toFixed(1), requests: ok + bad, rps: +((ok + bad) / secs).toFixed(1), errorPct: +(100 * bad / (ok + bad)).toFixed(2),
    p50: Math.round(pct(lat, .5)), p95: Math.round(pct(lat, .95)), p99: Math.round(pct(lat, .99)), max: Math.round(lat.at(-1) || 0), errorStatuses: status, db: dockerStats(),
    byOp: Object.fromEntries(Object.entries(per).map(([k, v]) => { v.sort((a, b) => a - b); return [k, { n: v.length, p50: Math.round(pct(v, .5)), p95: Math.round(pct(v, .95)) }]; })) };
  console.log(`${name.padEnd(22)} users=${String(users).padStart(3)} rps=${String(row.rps).padStart(6)} err=${String(row.errorPct).padStart(5)}% p50=${row.p50}ms p95=${row.p95}ms p99=${row.p99}ms`);
  return row;
}

const results = [];
console.log('warm-up'); await phase('warm-up', 5, 5, 100);
results.push(await phase('baseline (1 user)', 1, 20));
results.push(await phase('normal load', 25, 30, 200));
results.push(await phase('heavy load', 50, 30, 100));
const stress = [];
for (const u of [100, 200, 400, 800]) {
  const r = await phase(`stress ${u} users`, u, 20); stress.push(r); results.push(r);
  if (r.errorPct > 25) { console.log('stopping the ramp: more than 25% errors'); break; }
}
await new Promise(r => setTimeout(r, 5000));
results.push(await phase('recovery (1 user)', 1, 15));
const orders = await q('/rest/v1/orders?select=id&limit=1', SERVICE);
writeFileSync(new URL('../results/perf_results.json', import.meta.url), JSON.stringify({ when: new Date().toISOString(), results }, null, 1));
console.log('saved testing/results/perf_results.json');
