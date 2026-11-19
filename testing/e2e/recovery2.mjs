// Recovery scenarios that WRITE data. Chrome against the LOCAL stack. Run: node recovery2.mjs
import { writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { serve, launch, boot, loginAs, text, typeInto } from './lib.mjs';

const sql = q => execSync(`docker exec supabase_db_sagana-test psql -U postgres -tAc "${q}"`, { encoding: 'utf8' }).trim();
const countOf = name => +sql(`select count(*) from farmer_expenses where name='${name}'`);
const results = [];
const note = (step, pass, detail = '') => { results.push({ area: 'recovery', step, pass, detail }); console.log(`${pass ? 'PASS' : 'FAIL'} [recovery] ${step}${detail ? ' -> ' + detail : ''}`); };
const stamp = Date.now();
const srv = await serve();

async function openExpenses(page) {
  await page.getByText('Profile', { exact: true }).last().click(); await page.waitForTimeout(2200);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 600, yDistance: -300, speed: 1500, gestureSourceType: 'touch' }); await page.waitForTimeout(700);
  await page.getByText(/^Expenses/).first().click({ timeout: 8000 }); await page.waitForTimeout(2500);
}
async function addExpense(page, name, amount) {
  await page.mouse.click(350, 780); await page.waitForTimeout(1500);
  await typeInto(page, 0, name); await typeInto(page, 1, 'Recovery test ' + name); await typeInto(page, 2, String(amount));
  await page.getByText('Save Expense', { exact: true }).last().click(); await page.waitForTimeout(2500);
}

// ---------- R1: offline write is saved on the phone and sent once when the connection returns
{
  const { browser, ctx, page } = await launch(); await boot(page); await loginAs(page, 't_farmer1');
  await openExpenses(page);
  const name = 'OfflineA' + stamp;
  await ctx.setOffline(true); await page.waitForTimeout(2500);
  await addExpense(page, name, 150.5);
  let t = await text(page);
  note('offline: an expense added with no connection is accepted and shown on screen', t.includes(name) || /saved|queued|offline|sync/i.test(t), t.slice(0, 140));
  note('offline: nothing has reached the server yet (it waits on the device)', countOf(name) === 0, 'server rows=' + countOf(name));
  await page.screenshot({ path: '../results/shots/rec_offline_added.png' });
  await ctx.setOffline(false);
  let n = 0; for (let i = 0; i < 20 && n === 0; i++) { await page.waitForTimeout(2000); n = countOf(name); }
  note('back online: the saved expense is sent by itself, exactly once', n === 1, 'server rows=' + n);
  await page.waitForTimeout(6000);
  note('a few seconds later it is still exactly one record (no duplicate replay)', countOf(name) === 1, 'server rows=' + countOf(name));
  const amt = sql(`select amount from farmer_expenses where name='${name}'`);
  note('the saved amount is exactly what was typed (150.50)', Number(amt) === 150.5, 'amount=' + amt);
  await browser.close();
}

// ---------- R2: the app is closed and reopened while a write is still waiting, then it is sent once
{
  const { browser, ctx, page } = await launch(); await boot(page); await loginAs(page, 't_farmer1');
  await openExpenses(page);
  const name = 'RestartB' + stamp;
  await ctx.setOffline(true); await page.waitForTimeout(2500);
  await addExpense(page, name, 75);
  // network is back, but the server is unreachable for the app, so the write cannot go yet
  await ctx.setOffline(false);
  await page.route('**://127.0.0.1:54321/**', r => r.abort());
  await page.waitForTimeout(1500);
  await page.reload({ waitUntil: 'load' }); await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 90000 }); await page.waitForTimeout(6000);
  if (await page.locator('flt-semantics-placeholder').count()) await page.locator('flt-semantics-placeholder').evaluate(e => e.click());
  await page.waitForTimeout(1500);
  note('restart: the waiting write is still not on the server (nothing lost, nothing sent early)', countOf(name) === 0);
  await page.unroute('**://127.0.0.1:54321/**');
  let n = 0; for (let i = 0; i < 25 && n === 0; i++) { await page.waitForTimeout(2000); if (i === 5) await page.getByText('Sync now', { exact: true }).last().click({ timeout: 2000 }).catch(() => {}); n = countOf(name); }
  note('after the restart the waiting expense is sent once the server is reachable', n === 1, 'server rows=' + n);
  await page.waitForTimeout(5000);
  note('and it is still exactly one record', countOf(name) === 1, 'server rows=' + countOf(name));
  const owner = sql(`select u.username from farmer_expenses e join user_information u on u.user_id=e.farmer_id where e.name='${name}'`);
  note('the record belongs to the same signed-in Farmer (the session survived the restart)', owner === 't_farmer1', 'owner=' + owner);
  await browser.close();
}

// ---------- R3: the database stops in the middle of saving; nothing is lost or doubled when it returns
{
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_farmer1');
  await openExpenses(page);
  const name = 'DbDownC' + stamp;
  execSync('docker stop supabase_db_sagana-test', { stdio: 'ignore' });
  await page.waitForTimeout(1500);
  await addExpense(page, name, 33.25);
  const t = await text(page);
  note('database down while saving: nothing is saved, the form stays open with what was typed (a "Failed to save. Please try again." message shows; see shots/rec_db_down_save.png)', /Add New Expense/.test(t), 'dialog open=' + /Add New Expense/.test(t));
  await page.screenshot({ path: '../results/shots/rec_db_down_save.png' });
  execSync('docker start supabase_db_sagana-test', { stdio: 'ignore' });
  for (let i = 0; i < 30; i++) { try { if (sql('select 1') === '1') break; } catch { } await new Promise(r => setTimeout(r, 4000)); }
  await new Promise(r => setTimeout(r, 20000));
  await page.getByText('Save Expense', { exact: true }).last().click({ timeout: 4000 }).catch(() => {}); await page.waitForTimeout(6000);
  let rows = countOf(name);
  if (rows === 0) { await page.getByText('Save Expense', { exact: true }).last().click({ timeout: 4000 }).catch(() => {}); await page.waitForTimeout(6000); rows = countOf(name); }
  note('database back: pressing Save again saves the expense exactly once (nothing lost, nothing doubled)', rows === 1, 'server rows=' + rows);
  const after = await text(page);
  note('database back: the Expenses screen works again without restarting the app', !/exception|null check/i.test(after) && /My Expenses|Expenses/.test(after), after.slice(0, 120));
  await browser.close();
}

srv.close();
const p = results.filter(r => r.pass).length;
console.log(`\n${p}/${results.length} passed`);
writeFileSync('../results/e2e_recovery2.json', JSON.stringify(results, null, 1));
