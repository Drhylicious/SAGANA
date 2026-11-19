// Smoke + black-box walk in Chrome against the LOCAL stack: every role signs in, every bottom tab opens,
// no error text, no console errors, no failed requests. Run: node smoke.mjs [width] [dark] [locale]
import { writeFileSync } from 'node:fs';
import { serve, launch, boot, bodyText } from './lib.mjs';

const width = +(process.argv[2] || 390), dark = process.argv[3] === 'dark', locale = process.argv[4] || 'en-US';
const tag = `${width}${dark ? 'd' : 'l'}${locale.slice(0, 2)}`;
const ERR = /something went wrong|exception|unhandled|null check|type '.*' is not|RangeError|overflow|failed to load|PostgrestException/i;
const roles = (process.env.ROLES || 't_farmer1,t_manager,t_officer_view,t_officer_manage,t_buyer1,t_pending').split(',');
const srv = await serve();
const results = [];
const note = (role, step, pass, detail = '') => { results.push({ role, step, pass, detail }); console.log(`${pass ? 'PASS' : 'FAIL'} [${role}] ${step}${detail ? ' -> ' + detail : ''}`); };

for (const user of roles) {
  const { browser, page, logs } = await launch({ width, height: width < 500 ? 844 : width < 1000 ? 1024 : 800, dark, locale });
  const failed = [];
  page.on('response', r => { if (r.status() >= 500 || (r.status() >= 400 && /127\.0\.0\.1:54321\/(rest|auth|storage)/.test(r.url()) && r.status() !== 401 && r.status() !== 404 && r.status() !== 400)) failed.push(r.status() + ' ' + r.url().slice(0, 110)); });
  try {
    await boot(page);
    await page.getByText(/^(Login|Mag-login)$/).last().click({ timeout: 8000 }).catch(() => {});
    await page.waitForTimeout(1500);
    const inputs = page.locator('flt-semantics-host input');
    for (const [i, v] of [[0, user], [1, 'Test@12345']]) { for (let k = 0; k < 3; k++) { await inputs.nth(i).click(); await page.keyboard.press('Control+A'); await page.keyboard.type(v, { delay: 40 }); if ((await inputs.nth(i).inputValue().catch(() => v)) === v) break; } }
    await page.getByText(/^(Sign In|Mag-sign in)$/).last().click();
    await page.waitForTimeout(6500);
    if ((dark || locale.startsWith('tl')) && user !== 't_pending') {
      // The Appearance and Language switches live in the side menu (opened from the logo).
      await page.mouse.click(29, 31); await page.waitForTimeout(1500);
      const sw = page.locator('flt-semantics-host [role=switch], flt-semantics-host [role=checkbox]');
      const nsw = await sw.count();
      if (nsw < 2) note(user, 'side menu shows Appearance + Language switches', false, 'found ' + nsw);
      else {
        if (dark) await sw.nth(0).click();
        await page.waitForTimeout(700);
        if (locale.startsWith('tl')) await sw.nth(1).click();
        await page.waitForTimeout(1200);
      }
      await page.getByText(/^(Dismiss|I-dismiss)$/).last().click({ timeout: 4000 }).catch(() => page.mouse.click(380, 700));
      await page.waitForTimeout(1500);
    }
    const landing = (await bodyText(page)).replace(/\s+/g, ' ');
    note(user, 'signs in and lands on a home screen', landing.length > 40 && !/Sign In/.test(landing.slice(0, 120)), landing.slice(0, 80));
    await page.screenshot({ path: `../results/shots/${tag}_${user}_home.png` });
    // bottom navigation = buttons in the lowest 90px
    const vh = page.viewportSize().height;
    let nav = [];
    for (let k = 0; k < 8 && nav.length < 3; k++) {
      nav = await page.locator('flt-semantics-host [role=button]').evaluateAll((els, vh) => els.map(e => { const r = e.getBoundingClientRect(); return { t: (e.textContent || '').trim(), y: r.y, h: r.height, x: r.x, w: r.width }; }).filter(o => o.t && o.t.length < 24 && !o.t.includes('\n') && o.h > 20 && (o.y > vh - 100 || (o.x < 110 && o.w < 130 && o.y > 100))).sort((a, b) => a.x - b.x || a.y - b.y), vh);
      if (nav.length < 3) await page.waitForTimeout(1200);
    }
    for (const n of nav) {
      await page.getByText(n.t, { exact: true }).last().click({ timeout: 8000 }).catch(() => {});
      await page.waitForTimeout(2500);
      const txt = (await bodyText(page)).replace(/\s+/g, ' ');
      await page.screenshot({ path: `../results/shots/${tag}_${user}_${n.t.replace(/\W+/g, '')}.png` });
      const bad = txt.match(ERR);
      note(user, `tab "${n.t}" opens without an error`, !bad && txt.length > 20, bad ? bad[0] : '');
    }
    const cErr = logs.filter(l => !/favicon|manifest|ERR_CONNECTION_REFUSED|Failed to load resource: the server responded with a status of (400|401|404)|CanvasKit|google_fonts|fonts\.g/i.test(l));
    note(user, 'no unexpected console errors', cErr.length === 0, cErr.slice(0, 3).join(' | '));
    note(user, 'no failed (5xx / unexpected 4xx) network calls', failed.length === 0, failed.slice(0, 3).join(' | '));
  } catch (e) { note(user, 'walk completed', false, String(e).slice(0, 150)); }
  await browser.close();
}
srv.close();
const p = results.filter(r => r.pass).length;
console.log(`\n${p}/${results.length} passed`);
writeFileSync(`../results/e2e_smoke_${tag}.json`, JSON.stringify(results, null, 1));
