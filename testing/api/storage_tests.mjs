// SAGANA storage security tests (buckets + policies). LOCAL STACK ONLY. Run: node testing/api/storage_tests.mjs
import { execSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const env = Object.fromEntries(
  execSync('supabase status -o env', { cwd: new URL('../stack', import.meta.url), encoding: 'utf8' })
    .split(/\r?\n/).filter(l => l.includes('=')).map(l => { const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1).replace(/^"|"$/g, '')]; }));
const API = env.API_URL, ANON = env.ANON_KEY;
if (!/^http:\/\/(127\.0\.0\.1|localhost):/.test(API)) throw new Error('Refusing to run: not a local stack');

async function login(u) {
  const r = await fetch(API + '/auth/v1/token?grant_type=password', { method: 'POST', headers: { apikey: ANON, 'Content-Type': 'application/json' }, body: JSON.stringify({ email: u + '@sagana.local', password: 'Test@12345' }) });
  const j = await r.json(); if (!j.access_token) throw new Error('login ' + u); return { token: j.access_token, id: j.user.id };
}
const U = {}; for (const u of ['t_manager', 't_officer_view', 't_officer_manage', 't_farmer1', 't_farmer2', 't_pending', 't_buyer1']) U[u] = await login(u);

// a tiny valid PNG
const PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==', 'base64');
async function up(token, bucket, path, body = PNG, type = 'image/png', method = 'POST') {
  const r = await fetch(`${API}/storage/v1/object/${bucket}/${path}`, { method, headers: { apikey: ANON, Authorization: 'Bearer ' + (token || ANON), 'Content-Type': type, 'x-upsert': 'false' }, body });
  const t = await r.text(); let j; try { j = JSON.parse(t); } catch { j = t; } return { status: r.status, body: j };
}
async function del(token, bucket, path) { const r = await fetch(`${API}/storage/v1/object/${bucket}/${path}`, { method: 'DELETE', headers: { apikey: ANON, Authorization: 'Bearer ' + (token || ANON) } }); return { status: r.status, body: await r.text() }; }
async function read(token, bucket, path, pub) { const r = await fetch(`${API}/storage/v1/object/${pub ? 'public/' : 'authenticated/'}${bucket}/${path}`, { headers: { apikey: ANON, Authorization: 'Bearer ' + (token || ANON) } }); await r.arrayBuffer(); return r.status; }
const ok = r => r.status >= 200 && r.status < 300;

const results = [];
async function t(area, name, fn) {
  try { const [pass, detail] = await fn(); results.push({ area, name, pass, detail: detail || '' }); } catch (e) { results.push({ area, name, pass: false, detail: 'EXCEPTION ' + e.message }); }
  const x = results.at(-1); console.log((x.pass ? 'PASS' : 'FAIL') + ` [${area}] ${name}` + (x.pass ? '' : ' -> ' + x.detail));
}
const f1 = U.t_farmer1, f2 = U.t_farmer2, P = U.t_pending, B = U.t_buyer1, OV = U.t_officer_view, OM = U.t_officer_manage, M = U.t_manager;
const stamp = Date.now();

for (const bucket of ['crop_images', 'listing_photos', 'profile_photos']) {
  await t('storage', `${bucket}: owner uploads into own folder`, async () => { const r = await up(f1.token, bucket, `${f1.id}/a${stamp}.png`); return [ok(r), r.status + ' ' + JSON.stringify(r.body).slice(0, 100)]; });
  await t('storage', `${bucket}: user cannot upload into another user's folder`, async () => { const r = await up(f1.token, bucket, `${f2.id}/evil${stamp}.png`); return [!ok(r), r.status]; });
  await t('storage', `${bucket}: signed-out cannot upload`, async () => { const r = await up(null, bucket, `${f1.id}/anon${stamp}.png`); return [!ok(r), r.status]; });
  await t('storage', `${bucket}: user cannot delete another user's file`, async () => { await up(f2.token, bucket, `${f2.id}/keep${stamp}.png`); const r = await del(f1.token, bucket, `${f2.id}/keep${stamp}.png`); const still = await read(null, bucket, `${f2.id}/keep${stamp}.png`, true); return [still === 200, 'delete http ' + r.status + ' then public read ' + still]; });
  await t('storage', `${bucket}: user cannot overwrite another user's file`, async () => { const r = await up(f1.token, bucket, `${f2.id}/keep${stamp}.png`, PNG, 'image/png', 'PUT'); return [!ok(r), r.status]; });
  await t('storage', `${bucket}: public read works without sign-in (photos are shown to buyers)`, async () => [await read(null, bucket, `${f1.id}/a${stamp}.png`, true) === 200, 'http']);
  await t('storage', `${bucket}: a pending (unapproved) farmer cannot upload photos`, async () => { if (bucket === 'profile_photos') return [true, 'profile photos are allowed for applicants (by design)']; const r = await up(P.token, bucket, `${P.id}/p${stamp}.png`); return [!ok(r), r.status]; });
  await t('storage-hygiene', `${bucket}: only image files are accepted (HTML upload is refused)`, async () => { const r = await up(f1.token, bucket, `${f1.id}/page${stamp}.html`, Buffer.from('<script>alert(1)</script>'), 'text/html'); return [!ok(r), 'html upload http ' + r.status]; });
  await t('storage-hygiene', `${bucket}: files over the size limit are refused`, async () => { const r = await up(f1.token, bucket, `${f1.id}/big${stamp}.png`, Buffer.alloc(11 * 1024 * 1024, 1)); return [!ok(r), 'http ' + r.status]; });
}
await t('storage', 'inventory images: Farmer cannot upload', async () => { const r = await up(f1.token, 'cooperative_inventory_images', `${f1.id}/x${stamp}.png`); return [!ok(r), r.status]; });
await t('storage', 'inventory images: view-only Officer cannot upload', async () => { const r = await up(OV.token, 'cooperative_inventory_images', `${OV.id}/x${stamp}.png`); return [!ok(r), r.status]; });
await t('storage', 'inventory images: Manage Officer / Manager can upload', async () => { const a = await up(OM.token, 'cooperative_inventory_images', `${OM.id}/x${stamp}.png`); const b = await up(M.token, 'cooperative_inventory_images', `${M.id}/x${stamp}.png`); return [ok(a) && ok(b), `officer ${a.status} manager ${b.status}`]; });
await t('storage', 'program evidence: private bucket is not publicly readable', async () => { await up(f1.token, 'program_evidence', `${f1.id}/ev${stamp}.png`); const pub = await read(null, 'program_evidence', `${f1.id}/ev${stamp}.png`, true); return [pub !== 200, 'public read http ' + pub]; });
await t('storage', 'program evidence: another Farmer cannot read it', async () => { const s = await read(f2.token, 'program_evidence', `${f1.id}/ev${stamp}.png`, false); return [s !== 200, 'http ' + s]; });
await t('storage', 'program evidence: owner and staff can read it', async () => { const a = await read(f1.token, 'program_evidence', `${f1.id}/ev${stamp}.png`, false); const b = await read(M.token, 'program_evidence', `${f1.id}/ev${stamp}.png`, false); return [a === 200 && b === 200, `owner ${a} manager ${b}`]; });
await t('storage', 'program evidence: Buyer cannot upload', async () => { const r = await up(B.token, 'program_evidence', `${B.id}/ev${stamp}.png`); return [!ok(r), r.status]; });
await t('storage', 'program evidence: only images are accepted (PDF refused)', async () => { const r = await up(f1.token, 'program_evidence', `${f1.id}/doc${stamp}.pdf`, Buffer.from('%PDF-1.4'), 'application/pdf'); return [!ok(r), r.status]; });
await t('storage', 'listing an object list is not open to everyone for private bucket', async () => { const r = await fetch(`${API}/storage/v1/object/list/program_evidence`, { method: 'POST', headers: { apikey: ANON, Authorization: 'Bearer ' + f2.token, 'Content-Type': 'application/json' }, body: JSON.stringify({ prefix: f1.id + '/' }) }); const j = await r.json(); return [Array.isArray(j) && j.length === 0, 'other farmer sees ' + (Array.isArray(j) ? j.length : JSON.stringify(j)) + ' files']; });

const pass = results.filter(x => x.pass).length;
console.log(`\n${pass}/${results.length} passed, ${results.length - pass} failed`);
writeFileSync(new URL('../results/storage_results.json', import.meta.url), JSON.stringify(results, null, 1));
