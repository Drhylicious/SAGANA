import { serve, launch, boot, text } from './lib.mjs';
const ERR = /something went wrong|exception|unhandled|null check|RangeError|PostgrestException/i;
const srv = await serve();
for (const which of ['Explore as Buyer', 'Explore as Farmer']) {
  const { browser, page, logs } = await launch(); await boot(page);
  await page.getByText(new RegExp('^' + which)).first().click(); await page.waitForTimeout(4000);
  const vh = page.viewportSize().height;
  const tabs = [...new Set((await page.locator('flt-semantics-host [role=button]').evaluateAll((els, vh) => els.map(e => { const r = e.getBoundingClientRect(); return { t: (e.textContent || '').trim(), y: r.y, h: r.height, x: r.x }; }).filter(o => o.t && o.t.length < 24 && !o.t.includes('\n') && o.y > vh - 110 && o.h > 20).sort((a, b) => a.x - b.x), vh)).map(x => x.t))];
  console.log(`[${which}] tabs: ${tabs.join(', ')}`);
  for (const tab of ['(home)', ...tabs]) {
    if (tab !== '(home)') { await page.getByText(tab, { exact: true }).last().click({ timeout: 5000 }).catch(() => {}); await page.waitForTimeout(2500); }
    const t = await text(page); const bad = t.match(ERR);
    console.log(`${bad || t.length < 25 ? 'FAIL' : 'ok  '} [${which}] ${tab}: ${t.slice(0, 70)}`);
    await page.screenshot({ path: `../results/shots/crawl/guest_${which.split(' ').pop()}_${tab.replace(/\W+/g, '')}.png` });
  }
  const c = logs.filter(l => !/favicon|manifest|CONNECTION_REFUSED|status of (400|401|404|406)|CanvasKit|fonts/i.test(l)); console.log('console errors:', c.length);
  await browser.close();
}
srv.close();
