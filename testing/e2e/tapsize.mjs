// Tap-target sizes (buttons and links) on every main tab of every role at phone width. Android guideline: at least 48 px; flagged under 40.
import { writeFileSync } from 'node:fs';
import { serve, launch, boot, loginAs } from './lib.mjs';
const srv = await serve(); const out = [];
for (const user of (process.env.ROLES || 't_farmer1,t_buyer1,t_manager,t_officer_view').split(',')) {
  const { browser, page } = await launch({ width: 390, height: 844 }); await boot(page); await loginAs(page, user); await page.waitForTimeout(3000);
  const tabs = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => { const r = e.getBoundingClientRect(); return { t: (e.textContent || '').trim(), y: r.y, h: r.height, x: r.x }; }).filter(o => o.t && o.t.length < 24 && !o.t.includes('\n') && o.y > 740 && o.h > 20).sort((a, b) => a.x - b.x));
  for (const n of ['(home)', ...[...new Set(tabs.map(x => x.t))]]) {
    if (n !== '(home)') { await page.getByText(n, { exact: true }).last().click({ timeout: 6000 }).catch(() => {}); await page.waitForTimeout(2500); }
    const small = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => { const r = e.getBoundingClientRect(); return { t: (e.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 28), w: Math.round(r.width), h: Math.round(r.height), onscreen: r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth }; }).filter(o => o.onscreen && o.w > 0 && (o.h < 40 || o.w < 40)));
    out.push({ user, screen: n, small });
    console.log(`${small.length ? 'SMALL' : 'ok   '} [${user}] ${n}${small.length ? ' -> ' + small.map(s => `"${s.t}" ${s.w}x${s.h}`).join(', ') : ''}`);
  }
  await browser.close();
}
srv.close(); writeFileSync('../results/e2e_tapsize.json', JSON.stringify(out, null, 1));
