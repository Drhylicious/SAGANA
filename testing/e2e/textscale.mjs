// Text size 1.0 to 2.0 in Chrome: every tab of every role, looking for text pushed outside the screen.
import { writeFileSync } from 'node:fs';
import { serve, launch, boot, loginAs, text } from './lib.mjs';
const scales = (process.env.SCALES || '1,1.3,1.5,2').split(',').map(Number);
const roles = (process.env.ROLES || 't_farmer1,t_buyer1,t_manager,t_officer_view').split(',');
const width = 360;
const srv = await serve(); const results = [];
const note = (role, scale, tab, pass, detail = '') => { results.push({ role, scale, tab, pass, detail }); console.log(`${pass ? 'PASS' : 'FAIL'} [${role} x${scale}] ${tab}${detail ? ' -> ' + detail : ''}`); };
for (const scale of scales) for (const user of roles) {
  const { browser, ctx, page } = await launch({ width, height: 740 });
  try {
    await boot(page); await loginAs(page, user); await page.evaluate(px => { document.documentElement.style.fontSize = px + 'px'; }, 16 * scale); await page.waitForTimeout(2500);
    const vh = page.viewportSize().height;
    const tabs = await page.locator('flt-semantics-host [role=button]').evaluateAll((els, vh) => els.map(e => { const r = e.getBoundingClientRect(); return { t: (e.textContent || '').trim(), y: r.y, h: r.height, x: r.x }; }).filter(o => o.t && o.t.length < 26 && !o.t.includes('\n') && o.y > vh - 110 && o.h > 20).sort((a, b) => a.x - b.x), vh);
    const names = [...new Set(tabs.map(x => x.t))];
    if (names.length < 3) note(user, scale, 'bottom navigation visible', false, 'found ' + names.join(','));
    for (const n of ['(home)', ...names]) {
      if (n !== '(home)') { await page.getByText(n, { exact: true }).last().click({ timeout: 6000 }).catch(() => {}); await page.waitForTimeout(2200); }
      const over = await page.locator('flt-semantics-host flt-semantics').evaluateAll(els => els.map(e => { const r = e.getBoundingClientRect(); return { t: (e.textContent || '').trim().slice(0, 30), l: r.left, r: r.right, w: r.width }; }).filter(o => o.t && o.w > 0 && (o.r > innerWidth + 2 || o.l < -2) && o.w < innerWidth * 3).slice(0, 4));
      const bad = over.filter(o => !/^[\d\s]+$/.test(o.t));
      note(user, scale, n, bad.length === 0, bad.map(o => `"${o.t}" ${Math.round(o.l)}..${Math.round(o.r)}`).join(' | '));
      if (scale >= 1.5 && n !== '(home)') await page.screenshot({ path: `../results/shots/ts${scale}_${user}_${n.replace(/\W+/g, '')}.png` });
    }
    if (scale >= 1.5) await page.screenshot({ path: `../results/shots/ts${scale}_${user}_home.png` });
  } catch (e) { note(user, scale, 'walk', false, String(e).slice(0, 120)); }
  await browser.close();
}
srv.close();
const p = results.filter(r => r.pass).length;
console.log(`\n${p}/${results.length} passed`);
writeFileSync('../results/e2e_textscale.json', JSON.stringify(results, null, 1));
