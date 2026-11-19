import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page);
await loginAs(page, 't_buyer1');
await page.mouse.click(100, 320); await page.waitForTimeout(15000); page.on('response', () => {});
console.log('DETAIL:', (await text(page)).slice(0, 700)); await page.screenshot({ path: '../results/shots/probe_detail.png' });
const btns = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => (e.textContent || '').trim().slice(0, 30)).filter(Boolean));
console.log('BUTTONS:', btns.join(' | '));
await browser.close(); srv.close();
