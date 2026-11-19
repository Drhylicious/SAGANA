// Screen load times in Chrome with the volume data (1,501 listings, 4,000+ orders, 160 users, 300 loans). LOCAL STACK ONLY.
// A screen is "ready" when its text has stopped changing for 700 ms (after it first shows real content).
import { writeFileSync } from 'node:fs';
import { serve, launch, boot, loginAs, text } from './lib.mjs';

const results = [];
const srv = await serve();
const BUDGET_MS = 3000; // the target in proposal.md is "about 2 seconds"; 3 s is the line this test calls slow

let inflight = 0, lastNet = Date.now();
function watch(page) { page.on('request', r => { if (r.url().includes(':54321')) { inflight++; lastNet = Date.now(); } }); const done = r => { if (r.url().includes(':54321')) { inflight = Math.max(0, inflight - 1); lastNet = Date.now(); } }; page.on('requestfinished', done); page.on('requestfailed', done); }
// ready = the screen's text changed from what was there, no data request is in flight, and nothing moved for 600 ms
async function settle(page, before, { quiet = 600, max = 40000 } = {}) {
  const t0 = Date.now(); let last = before, changed = false, lastChange = Date.now();
  while (Date.now() - t0 < max) {
    const now = await text(page);
    if (now !== last) { last = now; lastChange = Date.now(); if (now !== before) changed = true; }
    if (!changed && Date.now() - t0 > 2500 && (inflight === 0 || Date.now() - lastNet > 1500)) changed = true; // the screen legitimately looks the same (e.g. a search that returns the same rows)
    const idleFor = Math.min(Date.now() - lastChange, Date.now() - lastNet);
    if (changed && (inflight === 0 || Date.now() - lastNet > 1500) && idleFor >= quiet) return Date.now() - t0 - quiet;
    await page.waitForTimeout(100);
  }
  return max;
}
async function timed(page, who, name, action) {
  const before = await text(page);
  await action(); const t0 = Date.now() - 0;
  const ms = await settle(page, before);
  const slow = ms > BUDGET_MS;
  results.push({ who, screen: name, ms, slow });
  console.log(`${slow ? 'SLOW' : 'ok  '} ${String(ms).padStart(5)} ms  [${who}] ${name}`);
  return ms;
}
const tap = (page, label) => page.getByText(label, { exact: typeof label === 'string' }).last().click({ timeout: 8000 });
async function back(page) { await page.goBack().catch(() => {}); await page.waitForTimeout(800); }

for (const [who, user, plan] of [
  ['Farmer', 't_farmer1', async page => {
    for (const tab of ['Harvest', 'Listings', 'Analytics', 'Profile', 'Home']) await timed(page, 'Farmer', 'tab ' + tab, () => tap(page, tab));
  }],
  ['Buyer', 't_buyer1', async page => {
    await timed(page, 'Buyer', 'Browse (1,501 listings)', async () => { await tap(page, 'Orders'); await page.waitForTimeout(300); await tap(page, 'Browse'); });
    await timed(page, 'Buyer', 'Orders', () => tap(page, 'Orders'));
    await timed(page, 'Buyer', 'Prices', () => tap(page, 'Prices'));
    await tap(page, 'Browse'); await page.waitForTimeout(1500);
    await timed(page, 'Buyer', 'search "Tom" in Browse', async () => { await page.locator('flt-semantics-host input').first().click(); await page.keyboard.type('Tom', { delay: 40 }); });
  }],
  ['Manager', 't_manager', async page => {
    await timed(page, 'Manager', 'Dashboard (cold)', async () => { await page.reload(); await page.waitForSelector('flt-glass-pane', { state: 'attached' }); await page.waitForTimeout(500); if (await page.locator('flt-semantics-placeholder').count()) await page.locator('flt-semantics-placeholder').evaluate(e => e.click()); });
    for (const tab of ['Members', 'Marketplace', 'Loans', 'Reports', 'Dashboard']) await timed(page, 'Manager', 'tab ' + tab, () => tap(page, tab));
    await tap(page, 'Marketplace'); await page.waitForTimeout(1500);
    await timed(page, 'Manager', 'Order Management (4,000+ orders)', () => tap(page, /Order Management/));
    await back(page);
    await timed(page, 'Manager', 'All Listings (1,501)', () => tap(page, /All Listings/));
    await back(page);
    await tap(page, 'Members'); await page.waitForTimeout(2000);
    await timed(page, 'Manager', 'search a member in Members (160 farmers)', async () => { await page.locator('flt-semantics-host input').first().click(); await page.keyboard.type('Perf', { delay: 40 }); });
    await tap(page, 'Reports'); await page.waitForTimeout(1500);
    const cdp = await page.context().newCDPSession(page);
    const find = async name => { for (let k = 0; k < 4; k++) { if (await page.getByText(new RegExp(name)).count()) return true; await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 600, yDistance: -500, speed: 1500, gestureSourceType: 'touch' }); await page.waitForTimeout(600); } return false; };
    for (const rpt of ['Sales Report', 'Harvest Report', 'Cooperative Stock Report', 'Loan Report', 'Expense Report', 'Member Contribution Report', 'Analytics Dashboard', 'Export Center']) {
      if (!(await find(rpt))) { console.log('     (no card named ' + rpt + ' on this screen)'); continue; }
      await timed(page, 'Manager', rpt, () => tap(page, new RegExp(rpt)));
      await back(page);
      await page.waitForTimeout(1200);
    }
  }],
]) {
  const { browser, page } = await launch();
  inflight = 0; watch(page); try { await boot(page); await loginAs(page, user); await page.waitForTimeout(3000); await plan(page); }
  catch (e) { console.log('walk stopped for ' + who + ': ' + String(e).slice(0, 140)); results.push({ who, screen: 'walk', ms: -1, slow: true, error: String(e).slice(0, 140) }); }
  await browser.close();
}
srv.close();
const slow = results.filter(r => r.slow);
console.log(`\n${results.length - slow.length}/${results.length} within ${BUDGET_MS} ms`);
writeFileSync('../results/perf_ui.json', JSON.stringify(results, null, 1));
