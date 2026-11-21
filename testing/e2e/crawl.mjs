// Readiness crawl: for one role, opens every main tab, then every safe button on it, then every safe button on the screens that opened
// (depth 2). Records what opened, errors, blank screens, console errors and failed requests, and keeps a screenshot of each new screen.
// LOCAL STACK ONLY. Run: node crawl.mjs t_manager [dark]
import { writeFileSync, mkdirSync } from 'node:fs';
import { serve, launch, boot, loginAs, text } from './lib.mjs';

const user = process.argv[2] || 't_farmer1', dark = process.argv[3] === 'dark' || process.argv[3] === 'darktl';
const ERR = /something went wrong|exception|unhandled|null check|type '.*' is not|RangeError|PostgrestException|failed to load|error loading|no element/i;
// Never press anything that changes data or ends the session.
const UNSAFE = /sign out|mag-sign out|mag-log ?out|log ?out|appearance|language|wika|hitsura|delete|remove|archive|disapprove|reject|cancel|reset|suspend|ban\b|deactivate|clear|send|submit|save|place order|buy now|\bpay\b|record|approve|confirm|withdraw|mark|sync now|update password|upload|camera|take photo|dismiss|^close$|^ok$|^yes|^no$|create officer|create account|add to cart|checkout|download|export|share|generate|renew|restore|resolve|decline|accept|counter|deliver|distribute|finalize|verify|complete|start|stop/i;
const DEEP_UNSAFE = /create|add |new |issue|register|apply|request|join|enrol|offer|submit|next|continue|edit|change|toggle|switch/i;
const tag = process.argv[3] === 'darktl' ? '_darktl' : dark ? '_dark' : '';
const shotDir = '../results/shots/crawl'; mkdirSync(shotDir, { recursive: true });
const srv = await serve();
const { browser, page, logs } = await launch({ dark });
const failed = []; page.on('response', r => { if (r.status() >= 500 || (r.status() >= 400 && /127\.0\.0\.1:54321\/(rest|storage)/.test(r.url()) && ![400, 401, 404, 406].includes(r.status()))) failed.push(`${r.status()} ${r.url().replace('http://127.0.0.1:54321', '').slice(0, 90)}`); });
async function settle(parent, max = 22000) { const t0 = Date.now(); let last = '', since = Date.now(); while (Date.now() - t0 < max) { const t = (await text(page)); if (t !== last) { last = t; since = Date.now(); } if (t.slice(0, 110) !== parent && t.length > 60 && Date.now() - since > 1200) return; if (t.slice(0, 110) === parent && Date.now() - t0 > 2500) return; await page.waitForTimeout(150); } }
const sig = async () => (await text(page)).slice(0, 110);
const buttons = async () => page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => { const r = e.getBoundingClientRect(); return { t: (e.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 60), x: r.x + r.width / 2, y: r.y + r.height / 2, w: r.width, h: r.height }; }).filter(o => o.t && o.w > 4 && o.h > 4 && o.y > 40 && o.y < innerHeight - 4 && o.x > 0 && o.x < innerWidth));
const out = { user, dark, tabs: [], screens: [], problems: [], clicked: 0 };
const seen = new Set(); let n = 0;
const problem = (where, what) => { out.problems.push({ where, what }); console.log('PROBLEM', where, '->', what); };

async function examine(path, depth) {
  const t = await text(page); const s = t.slice(0, 110);
  if (ERR.test(t)) problem(path, 'error text on screen: ' + (t.match(ERR) || [''])[0]);
  if (t.length < 25) problem(path, 'blank or nearly blank screen');
  if (!seen.has(s)) { seen.add(s); n++; await page.screenshot({ path: `${shotDir}/${user}${tag}_${String(n).padStart(2, '0')}.png` }); out.screens.push({ n, path, depth, head: s }); console.log(`screen ${n} [d${depth}] ${path} :: ${s.slice(0, 70)}`); return true; }
  return false;
}
async function restore(parentSig, tabName) {
  for (let k = 0; k < 3; k++) {
    if ((await sig()) === parentSig) return true;
    await page.keyboard.press('Escape').catch(() => {}); await page.waitForTimeout(500);
    if ((await sig()) === parentSig) return true;
    await page.goBack().catch(() => {}); await page.waitForTimeout(1200);
  }
  if (tabName) { await page.getByText(tabName, { exact: true }).last().click({ timeout: 4000 }).catch(() => {}); await page.waitForTimeout(1500); }
  return (await sig()) === parentSig;
}
async function explore(path, depth, navLabels, tabName) {
  const parent = await sig(); const bs = await buttons(); const done = new Set();
  for (const b of bs) {
    const key = b.t.slice(0, 30); if (done.has(key)) continue; done.add(key);
    if (navLabels.has(b.t) || UNSAFE.test(b.t) || (depth >= 1 && DEEP_UNSAFE.test(b.t))) continue;
    if (out.clicked > 140) return;
    out.clicked++;
    await page.mouse.click(b.x, b.y).catch(() => {}); await settle(parent);
    const now = await sig();
    if (now !== parent) {
      const isNew = await examine(`${path} > ${b.t.slice(0, 28)}`, depth + 1);
      if (isNew && depth < 1) await explore(`${path} > ${b.t.slice(0, 28)}`, depth + 1, navLabels, tabName);
      if (!(await restore(parent, tabName))) { problem(path, `could not return to the screen after opening "${b.t.slice(0, 30)}"`); return; }
    } else { await page.keyboard.press('Escape').catch(() => {}); await page.waitForTimeout(300); }
  }
}

try {
  await boot(page); await loginAs(page, user); await page.waitForTimeout(3500);
  if (process.argv[3] === 'darktl') { // the Appearance and Language switches are in the side menu (in-app settings, not the browser's)
    await page.mouse.click(29, 31); await page.waitForTimeout(1500);
    const sw = page.locator('flt-semantics-host [role=switch], flt-semantics-host [role=checkbox]');
    if ((await sw.count()) >= 2) { await sw.nth(0).click(); await page.waitForTimeout(700); await sw.nth(1).click(); await page.waitForTimeout(1500); } else problem('setup', 'dark/Tagalog switches not found');
    await page.getByText(/^(Dismiss|I-dismiss)$/).last().click({ timeout: 4000 }).catch(() => page.mouse.click(380, 700)); await page.waitForTimeout(1500);
  }
  const vh = page.viewportSize().height;
  let tabs = (await buttons()).filter(o => o.y > vh - 110 && o.t.length < 24 && !o.t.includes('\n'));
  const names = [...new Set(tabs.map(x => x.t))]; const navLabels = new Set(names);
  out.tabs = names; console.log('tabs:', names.join(', '));
  const sideMenu = async () => { await page.mouse.click(29, 31); await page.waitForTimeout(1200); };
  for (const tab of names) {
    await page.getByText(tab, { exact: true }).last().click({ timeout: 5000 }).catch(() => {}); await page.waitForTimeout(2500);
    await examine(`tab ${tab}`, 0);
    await explore(`tab ${tab}`, 0, navLabels, tab);
  }
  // Side menu entries (Account, Farm Details, About ... but never Sign Out)
  await page.getByText(names[0], { exact: true }).last().click({ timeout: 4000 }).catch(() => {}); await page.waitForTimeout(1500);
  await sideMenu(); const menu = await sig(); await examine('side menu', 0);
  const mbs = (await buttons()).filter(b => b.x < 300);
  for (const b of mbs) {
    if (UNSAFE.test(b.t) || /^Appearance|^Language/.test(b.t)) continue;
    await page.mouse.click(b.x, b.y).catch(() => {}); await page.waitForTimeout(1800);
    if ((await sig()) !== menu) { await examine(`side menu > ${b.t.slice(0, 26)}`, 1); await page.goBack().catch(() => {}); await page.waitForTimeout(1200); if ((await sig()) !== menu) { await page.mouse.click(29, 31).catch(() => {}); await page.waitForTimeout(1000); } }
  }
} catch (e) { problem('crawl', String(e).slice(0, 160)); }
const cErr = logs.filter(l => !/favicon|manifest|ERR_CONNECTION_REFUSED|status of (400|401|404|406)|CanvasKit|google_fonts|fonts\.g/i.test(l));
out.consoleErrors = [...new Set(cErr)].slice(0, 12); out.failedRequests = [...new Set(failed)].slice(0, 12);
console.log(`\n${user}${dark ? ' (dark)' : ''}: ${out.screens.length} screens, ${out.clicked} taps, ${out.problems.length} problems, ${out.consoleErrors.length} console errors, ${out.failedRequests.length} failed requests`);
writeFileSync(`../results/crawl_${user}${tag}.json`, JSON.stringify(out, null, 1));
await browser.close(); srv.close();
