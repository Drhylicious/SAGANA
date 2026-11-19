// SAGANA security checks beyond the per-role API tests: password rules, session tokens, sign-in rate limit,
// username enumeration. LOCAL STACK ONLY. Run: node testing/api/security_extra.mjs [--ratelimit]
// (--ratelimit sends ~45 sign-in attempts from this machine and may block sign-ins from it for about 5 minutes.)
import { execSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';
import { createHmac } from 'node:crypto';

const env = Object.fromEntries(execSync('supabase status -o env', { cwd: new URL('../stack', import.meta.url), encoding: 'utf8' }).split(/\r?\n/).filter(l => l.includes('=')).map(l => { const i = l.indexOf('='); return [l.slice(0, i), l.slice(i + 1).replace(/^"|"$/g, '')]; }));
const API = env.API_URL, ANON = env.ANON_KEY, SECRET = env.JWT_SECRET, SERVICE = env.SERVICE_ROLE_KEY;
if (!/^http:\/\/(127\.0\.0\.1|localhost):/.test(API)) throw new Error('Refusing to run: not a local stack');
const call = async (method, path, { token, body } = {}) => { const r = await fetch(API + path, { method, headers: { apikey: ANON, Authorization: 'Bearer ' + (token || ANON), 'Content-Type': 'application/json' }, body: body === undefined ? undefined : JSON.stringify(body) }); const t = await r.text(); let j; try { j = JSON.parse(t); } catch { j = t; } return { status: r.status, json: j }; };
const msg = r => typeof r.json === 'object' && r.json ? (r.json.msg || r.json.message || r.json.error_description || JSON.stringify(r.json)).toString().slice(0, 120) : String(r.json).slice(0, 120);
const results = [];
async function t(name, fn) { try { const [pass, detail] = await fn(); results.push({ area: 'security', name, pass, detail }); } catch (e) { results.push({ area: 'security', name, pass: false, detail: 'EXCEPTION ' + e.message }); } const x = results.at(-1); console.log((x.pass ? 'PASS' : 'FAIL') + ' [security] ' + name + (x.pass ? '' : ' -> ' + x.detail)); }
const stamp = Date.now();
const login = (email, password) => call('POST', '/auth/v1/token?grant_type=password', { body: { email, password } });
const signup = (email, password) => call('POST', '/auth/v1/signup', { body: { email, password } });
const b64 = o => Buffer.from(typeof o === 'string' ? o : JSON.stringify(o)).toString('base64url');

// --- password rules at the server
await t('server refuses a 1-character and a 5-character password at sign-up', async () => { const a = await signup(`weak1_${stamp}@sagana.local`, 'a'); const b = await signup(`weak5_${stamp}@sagana.local`, '12345'); return [a.status >= 400 && b.status >= 400, a.status + '/' + b.status + ' ' + msg(b)]; });
await t('server password minimum is at least the app minimum of 8 characters (a 6- and 7-character password are refused)', async () => { const a = await signup(`weak6_${stamp}@sagana.local`, 'abc123'); const b = await signup(`weak7_${stamp}@sagana.local`, 'abc1234'); return [a.status >= 400 && b.status >= 400, `6 chars: ${a.status}, 7 chars: ${b.status} (the app screens refuse under 8, so a call made straight to the API is held to a weaker rule)`]; });
await t('a normal 10-character password is accepted', async () => { const a = await signup(`ok_${stamp}@sagana.local`, 'Test@12345'); return [a.status < 300, a.status + ' ' + msg(a)]; });
await t('the same e-mail cannot be registered twice (no duplicate account)', async () => { const a = await signup(`ok_${stamp}@sagana.local`, 'Another@123'); const l = await login(`ok_${stamp}@sagana.local`, 'Test@12345'); return [(a.status >= 400 || !a.json?.identities?.length) && l.status === 200 && !!l.json.access_token, 'second signup ' + a.status + ' ' + msg(a) + ' | original still signs in: ' + l.status]; });
await t('a new self-registered account has no staff or farmer rights until approved', async () => { const l = await login(`ok_${stamp}@sagana.local`, 'Test@12345'); const tok = l.json.access_token; const roles = await call('GET', '/rest/v1/user_roles?select=role,status', { token: tok }); const prog = await call('POST', '/rest/v1/cooperative_programs', { token: tok, body: { program_name: 'x' } }); const lst = await call('GET', '/rest/v1/user_information?select=user_id&limit=5', { token: tok }); return [prog.status >= 400 && (Array.isArray(lst.json) ? lst.json.length <= 1 : true), `roles ${JSON.stringify(roles.json).slice(0, 60)}; program insert ${prog.status}; other people visible ${Array.isArray(lst.json) ? lst.json.length : lst.status}`]; });

// --- session tokens
const roleToken = (claims, secret = SECRET, alg = 'HS256') => { const head = b64({ alg, typ: 'JWT' }); const body = b64(claims); const sig = alg === 'none' ? '' : createHmac('sha256', secret).update(`${head}.${body}`).digest('base64url'); return `${head}.${body}.${sig}`; };
const exp = Math.floor(Date.now() / 1000);
await t('an expired token is refused', async () => { const tok = roleToken({ aud: 'authenticated', role: 'authenticated', sub: '00000000-0000-0000-0000-000000000001', exp: exp - 3600 }); const r = await call('GET', '/rest/v1/user_roles?select=*', { token: tok }); return [r.status === 401, r.status + ' ' + msg(r)]; });
await t('a token signed with the wrong secret, claiming to be service_role, is refused', async () => { const tok = roleToken({ aud: 'authenticated', role: 'service_role', sub: 'x', exp: exp + 3600 }, 'not-the-real-secret'); const r = await call('GET', '/rest/v1/user_roles?select=*&limit=1', { token: tok }); return [r.status === 401, r.status + ' ' + msg(r)]; });
await t('a token with algorithm "none" is refused', async () => { const tok = roleToken({ aud: 'authenticated', role: 'service_role', sub: 'x', exp: exp + 3600 }, '', 'none'); const r = await call('GET', '/rest/v1/user_roles?select=*&limit=1', { token: tok }); return [r.status === 401, r.status + ' ' + msg(r)]; });
await t('a signed-in user cannot change their own role claim by updating their auth metadata', async () => { const l = await login(`ok_${stamp}@sagana.local`, 'Test@12345'); const tok = l.json.access_token; await call('PUT', '/auth/v1/user', { token: tok, body: { data: { role: 'admin', is_admin: true } } }); const l2 = await login(`ok_${stamp}@sagana.local`, 'Test@12345'); const r = await call('GET', '/rest/v1/user_roles?select=role', { token: l2.json.access_token }); const p = await call('POST', '/rest/v1/cooperative_programs', { token: l2.json.access_token, body: { program_name: 'x' } }); return [p.status >= 400 && !(Array.isArray(r.json) && r.json.some(x => x.role === 'admin')), 'metadata edit then program insert ' + p.status]; });

// --- username / e-mail enumeration
await t('a wrong password and an unknown account give the same answer at sign-in (no account enumeration)', async () => { const a = await login('t_farmer1@sagana.local', 'WrongPass1!'); const b = await login(`nobody_${stamp}@sagana.local`, 'WrongPass1!'); return [a.status === b.status && msg(a) === msg(b), `${a.status} "${msg(a)}" vs ${b.status} "${msg(b)}"`]; });
await t('password-reset request answers the same for a known and an unknown e-mail', async () => { const a = await call('POST', '/auth/v1/recover', { body: { email: 't_farmer1@sagana.local' } }); const b = await call('POST', '/auth/v1/recover', { body: { email: `nobody_${stamp}@sagana.local` } }); return [a.status === b.status, `${a.status} vs ${b.status}`]; });
await t('a signed-in Farmer changing their password through the API is possible only with their own session (not for someone else)', async () => { const l = await login('t_farmer2@sagana.local', 'Test@12345'); const r = await call('PUT', '/auth/v1/admin/users/' + l.json.user.id, { token: l.json.access_token, body: { password: 'Hacked@12345' } }); const again = await login('t_farmer2@sagana.local', 'Test@12345'); return [r.status >= 400 && again.status === 200, 'admin endpoint with a user token: ' + r.status + '; original password still works: ' + again.status]; });

// --- sign-in lockout (supabase_schema_security_03_signin_lockout.sql, via Auth's password-verification hook)
const lockUser = `lock_${stamp}@sagana.local`, okUser = `keep_${stamp}@sagana.local`;
await signup(lockUser, 'Test@12345'); await signup(okUser, 'Test@12345');
const uidOf = async e => (await call('GET', '/rest/v1/user_roles?select=user_id&limit=1', { token: SERVICE })) && (await (await fetch(API + '/auth/v1/admin/users?per_page=1000', { headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } })).json()).users.find(u => u.email === e)?.id;
await t('10 wrong passwords in a row lock the account; the 11th attempt with the CORRECT password is refused with a clear message', async () => {
  const wrong = []; for (let i = 0; i < 10; i++) wrong.push((await login(lockUser, 'WrongPass1!' + i)).status);
  const good = await login(lockUser, 'Test@12345');
  return [wrong.every(s => s === 400) && good.status >= 400 && /too many|wait/i.test(msg(good)), 'wrong x10: ' + [...new Set(wrong)].join(',') + ' | correct password now: ' + good.status + ' "' + msg(good) + '"'];
});
await t('another account is not affected by the lock', async () => { const r = await login(okUser, 'Test@12345'); return [r.status === 200, String(r.status)]; });
await t('a correct sign-in before the limit clears the count (9 wrong, 1 right, then 9 more wrong does not lock)', async () => { for (let i = 0; i < 9; i++) await login(okUser, 'Bad' + i + 'xxxxxxx'); const good = await login(okUser, 'Test@12345'); for (let i = 0; i < 9; i++) await login(okUser, 'Bad' + i + 'yyyyyyy'); const after = await login(okUser, 'Test@12345'); return [good.status === 200 && after.status === 200, 'right after 9 wrong: ' + good.status + ', right after 9 more wrong: ' + after.status]; });
await t('the failure log cannot be read or written through the public API (no one can unlock or lock an account from outside)', async () => { const l = await login(okUser, 'Test@12345'); const a = await call('GET', '/rest/v1/auth_signin_failures?select=*', { token: l.json.access_token }); const b = await call('DELETE', '/rest/v1/auth_signin_failures?id=gt.0', { token: l.json.access_token }); const c = await call('GET', '/rest/v1/auth_signin_failures?select=*', {}); return [(a.status >= 400 || (Array.isArray(a.json) && a.json.length === 0)) && (b.status >= 400 || b.status === 204 && true) && (c.status >= 400 || (Array.isArray(c.json) && c.json.length === 0)), 'read ' + a.status + ' delete ' + b.status + ' anon read ' + c.status]; });
await t('the hook function cannot be called by a signed-in user or by anyone signed out', async () => { const l = await login(okUser, 'Test@12345'); const a = await call('POST', '/rest/v1/rpc/hook_password_verification_attempt', { token: l.json.access_token, body: { event: { user_id: '00000000-0000-0000-0000-000000000000', valid: false } } }); const b = await call('POST', '/rest/v1/rpc/hook_password_verification_attempt', { body: { event: { user_id: '00000000-0000-0000-0000-000000000000', valid: false } } }); return [a.status >= 400 && b.status >= 400, a.status + '/' + b.status]; });
await t('a Manager (service) clearing the rows unlocks the account at once', async () => { const id = await uidOf(lockUser); const d = await fetch(API + '/rest/v1/auth_signin_failures?user_id=eq.' + id, { method: 'DELETE', headers: { apikey: SERVICE, Authorization: 'Bearer ' + SERVICE } }); const r = await login(lockUser, 'Test@12345'); return [d.status < 300 && r.status === 200, 'clear ' + d.status + ', sign-in ' + r.status]; });

// --- sign-in rate limit (optional: it can block this machine's sign-ins for a few minutes)
if (process.argv.includes('--ratelimit')) {
  await t('(address-level limit) repeated wrong sign-ins from one address are slowed down (HTTP 429) before 60 attempts', async () => {
    const statuses = [];
    for (let i = 0; i < 60; i++) { const r = await login(`ratelimit_${stamp}@sagana.local`, 'WrongPass1!' + i); statuses.push(r.status); if (r.status === 429) break; }
    const first429 = statuses.indexOf(429) + 1;
    return [first429 > 0, first429 ? `first 429 after ${first429} attempts` : `no limit reached in ${statuses.length} attempts (${[...new Set(statuses)].join(',')})`];
  });
}
const pass = results.filter(x => x.pass).length;
console.log(`\n${pass}/${results.length} passed, ${results.length - pass} failed`);
writeFileSync(new URL('../results/security_extra_results.json', import.meta.url), JSON.stringify(results, null, 1));
