// Black-box / exploratory / recovery flows in Chrome against the LOCAL stack.  Run: node flows.mjs
import { writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { serve, launch, boot, bodyText } from './lib.mjs';

const PORT = 8099;
const URL = `http://127.0.0.1:${PORT}/`;
const srv = await serve(8099);
const results = [];
const note = (area, step, pass, detail = '') => { results.push({ area, step, pass, detail }); console.log(`${pass ? 'PASS' : 'FAIL'} [${area}] ${step}${detail ? ' -> ' + detail : ''}`); };
const txt = async p => (await bodyText(p)).replace(/\s+/g, ' ');
const en = p => p.locator('flt-semantics-placeholder').count().then(c => c && p.locator('flt-semantics-placeholder').evaluate(e => e.click()));

async function typeInto(page, i, v) {
  const inputs = page.locator('flt-semantics-host input');
  for (let k = 0; k < 3; k++) { await inputs.nth(i).click(); await page.keyboard.press('Control+A'); await page.keyboard.type(v, { delay: 40 }); if ((await inputs.nth(i).inputValue().catch(() => v)) === v) break; }
}
async function toLogin(page) { await page.getByText(/^(Login|Mag-login)$/).last().click({ timeout: 8000 }).catch(() => {}); await page.waitForTimeout(1200); }
async function login(page, user, pw = 'Test@12345') {
  await toLogin(page); await typeInto(page, 0, user); await typeInto(page, 1, pw);
  await page.getByText(/^(Sign In|Mag-sign in)$/).last().click(); await page.waitForTimeout(6500);
}
const sql = q => execSync(`docker exec supabase_db_sagana-test psql -U postgres -tAc "${q}"`, { encoding: 'utf8' }).trim();

// ---------- 1. Sign-in black-box cases
{
  const { browser, page } = await launch(); await boot(page);
  await toLogin(page);
  await page.getByText(/^Sign In$/).last().click(); await page.waitForTimeout(1200);
  let t = await txt(page);
  note('black-box', 'empty sign-in shows field errors and does not sign in', /required|Enter/i.test(t) && /Forgot Password/.test(t), t.slice(0, 160));
  await typeInto(page, 0, 't_farmer1'); await typeInto(page, 1, 'WrongPassword9!');
  await page.getByText(/^Sign In$/).last().click(); await page.waitForTimeout(3500);
  t = await txt(page);
  note('black-box', 'wrong password is refused with a clear message', /Forgot Password/.test(t) && /invalid|incorrect|wrong|not match|try again/i.test(t), t.slice(0, 200));
  await typeInto(page, 0, 'no_such_user_xyz'); await typeInto(page, 1, 'Test@12345');
  await page.getByText(/^Sign In$/).last().click(); await page.waitForTimeout(3500);
  t = await txt(page);
  note('black-box', 'unknown username is refused (no account details leaked)', /Forgot Password/.test(t) && !/does not exist|not registered|no account/i.test(t), t.slice(0, 200));
  await typeInto(page, 0, "' OR 1=1 --"); await typeInto(page, 1, "' OR '1'='1");
  await page.getByText(/^Sign In$/).last().click(); await page.waitForTimeout(3500);
  t = await txt(page);
  note('black-box', 'SQL-injection style input is just a failed sign-in', /Forgot Password/.test(t));
  await browser.close();
}

// ---------- 2. Sign out and session handling
{
  const { browser, page } = await launch(); await boot(page);
  await login(page, 't_farmer1');
  await page.mouse.click(29, 31); await page.waitForTimeout(1500);
  await page.getByText('Sign Out', { exact: true }).last().click().catch(() => {}); await page.waitForTimeout(1500);
  await page.getByText(/^(Sign Out|Yes|Confirm|Mag-sign out|Oo)$/).last().click({ timeout: 3000 }).catch(() => {}); await page.waitForTimeout(3500);
  let t = await txt(page);
  note('session', 'Sign Out returns to the welcome/login screen', /Welcome|Login|Sign In/.test(t) && !/Monthly Yield/.test(t), t.slice(0, 100));
  await page.reload(); await page.waitForSelector('flt-glass-pane', { state: 'attached' }); await page.waitForTimeout(5000); await en(page);
  t = await txt(page);
  note('session', 'after Sign Out a browser refresh does not bring the account back', !/Monthly Yield/.test(t), t.slice(0, 100));
  await browser.close();
}
{ // expired / revoked session
  const { browser, page } = await launch(); await boot(page);
  await login(page, 't_farmer1');
  await page.evaluate(() => { for (const k of Object.keys(localStorage)) if (k.startsWith('sb-')) { const v = JSON.parse(localStorage.getItem(k)); v.access_token = 'x.y.z'; v.expires_at = 1; localStorage.setItem(k, JSON.stringify(v)); } });
  await page.reload(); await page.waitForSelector('flt-glass-pane', { state: 'attached' }); await page.waitForTimeout(7000); await en(page);
  const t = await txt(page); const logs = [];
  note('session', 'a corrupted/expired access token does not crash the app (signs out or refreshes it)', /Welcome|Login|Sign In|Monthly Yield/.test(t) && !/exception|null check/i.test(t), t.slice(0, 110));
  await browser.close();
}

// ---------- 3. Buyer: browse, search, open a listing, add to cart
{
  const { browser, page } = await launch(); await boot(page);
  await login(page, 't_buyer1');
  let t = await txt(page);
  note('buyer', 'marketplace lists approved crops with price and stock', /Tomato/.test(t) && /₱50\.00\/kg/.test(t) && /kg available/.test(t), t.slice(0, 90));
  const search = page.locator('flt-semantics-host input').first();
  await search.click(); await page.keyboard.type('zzzzzz', { delay: 30 }); await page.waitForTimeout(1500);
  t = await txt(page);
  note('buyer', 'searching for a crop that does not exist shows an empty result, not an error', !/Tomato ₱50/.test(t) && !/exception|error/i.test(t), t.slice(0, 120));
  await page.keyboard.press('Control+A'); await page.keyboard.type('Tom', { delay: 30 }); await page.waitForTimeout(1500);
  t = await txt(page);
  note('buyer', 'searching "Tom" finds Tomato', /Tomato/.test(t));
  // (the search box is cleared again before opening a listing)
  const ordersBefore = +sql("select count(*) from orders o join user_information u on u.user_id=o.buyer_id where u.username='t_buyer1'");
  await page.keyboard.press('Control+A'); await page.keyboard.press('Backspace'); await page.waitForTimeout(1500);
  await page.mouse.click(100, 320); await page.waitForTimeout(5000);
  t = await txt(page);
  note('buyer', 'tapping a listing opens its details with Buy Now (1,500 listings in the system)', /Buy Now/.test(t), t.slice(0, 120));
  await page.getByText('Buy Now', { exact: true }).last().click(); await page.waitForTimeout(2000);
  await page.locator('flt-semantics-host input').first().click(); await page.keyboard.press('Control+A'); await page.keyboard.type('999', { delay: 60 }); await page.waitForTimeout(600);
  const typed = +(await page.locator('flt-semantics-host input').first().inputValue());
  note('buyer', 'the quantity box will not accept more than the 60 kg in stock (typed 999)', typed > 0 && typed <= 60, 'field holds ' + typed);
  await typeInto(page, 0, '2.5'); await page.getByText('Buy Now', { exact: true }).last().click(); await page.waitForTimeout(4000);
  t = await txt(page);
  note('buyer', 'checkout shows the right total (2.50 kg x ₱50.00 = ₱125.00)', /2.50 kg/.test(t) && /₱125.00/.test(t), t.slice(0, 120));
  await page.getByText('Place Order', { exact: true }).last().click(); await page.waitForTimeout(6000);
  t = await txt(page);
  note('buyer', 'Place Order confirms the order', /Order Placed/.test(t), t.slice(0, 100));
  const row = sql("select status||'|'||quantity_kg||'|'||total_price from orders o join user_information u on u.user_id=o.buyer_id where u.username='t_buyer1' order by o.created_at desc limit 1");
  note('buyer', 'the order is saved as pending, 2.50 kg, ₱125.00', row === 'pending|2.50|125.00' && +sql("select count(*) from orders o join user_information u on u.user_id=o.buyer_id where u.username='t_buyer1'") === ordersBefore + 1, row);
  await browser.close();
}

// ---------- 4. Recovery: offline, then back online (Farmer)
{
  const { browser, ctx, page } = await launch(); await boot(page);
  await login(page, 't_farmer1');
  await ctx.setOffline(true); await page.waitForTimeout(4000);
  let t = await txt(page);
  note('recovery', 'going offline shows the Offline state on Home', /Offline/i.test(t), t.slice(0, 120));
  for (const tab of ['Harvest', 'Listings', 'Analytics', 'Profile']) {
    await page.getByText(tab, { exact: true }).last().click({ timeout: 5000 }).catch(() => {}); await page.waitForTimeout(2500);
    const x = await txt(page);
    note('recovery', `offline: "${tab}" still opens with saved data (no crash / blank)`, x.length > 60 && !/exception|null check|Something went wrong/i.test(x), x.slice(0, 80));
  }
  await page.screenshot({ path: '../results/shots/flow_offline_profile.png' });
  await ctx.setOffline(false); await page.waitForTimeout(6000);
  await page.getByText('Home', { exact: true }).last().click().catch(() => {}); await page.waitForTimeout(3000);
  t = await txt(page);
  note('recovery', 'coming back online shows Online again', /Online/.test(t) && !/Offline/.test(t), t.slice(0, 120));
  await browser.close();
}

// ---------- 5. Recovery: the database goes down and comes back
{
  const { browser, page } = await launch(); await boot(page);
  await login(page, 't_buyer1');
  await page.getByText('Orders', { exact: true }).last().click().catch(() => {}); await page.waitForTimeout(4000);
  const warm = await txt(page);
  await page.getByText('Browse', { exact: true }).last().click().catch(() => {}); await page.waitForTimeout(1500);
  execSync('docker stop supabase_db_sagana-test', { stdio: 'ignore' });
  await page.waitForTimeout(2000);
  await page.getByText('Orders', { exact: true }).last().click().catch(() => {}); await page.waitForTimeout(4500);
  let t = await txt(page);
  note('recovery', 'database down: the app stays up, no crash', t.length > 40 && !/exception|null check|Unhandled/i.test(t), t.slice(0, 140));
  note('recovery', 'database down: Orders already opened before still show the saved list (not an empty list)', !/All (0)/.test(t) && /ORD-/.test(t), 'warm: ' + warm.slice(0, 60) + ' | now: ' + t.slice(0, 120));
  await page.screenshot({ path: '../results/shots/flow_db_down.png' });
  execSync('docker start supabase_db_sagana-test', { stdio: 'ignore' });
  for (let i = 0; i < 24; i++) { try { if (sql('select 1') === '1') break; } catch { } await new Promise(r => setTimeout(r, 5000)); }
  await new Promise(r => setTimeout(r, 15000)); // let PostgREST / Auth reconnect
  await page.getByText('Browse', { exact: true }).last().click().catch(() => {}); await page.waitForTimeout(5000);
  t = await txt(page);
  note('recovery', 'database back: the Marketplace loads again without restarting the app', /Tomato/.test(t), t.slice(0, 100));
  await browser.close();
}

srv.close();
const p = results.filter(r => r.pass).length;
console.log(`\n${p}/${results.length} passed`);
writeFileSync('../results/e2e_flows.json', JSON.stringify(results, null, 1));
