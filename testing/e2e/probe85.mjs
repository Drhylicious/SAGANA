import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_farmer2');
console.log('FORCED:', (await text(page)).slice(0, 300));
console.log('inputs', await page.locator('flt-semantics-host input').count());
const b2 = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => (e.textContent || '').trim().slice(0, 25)).filter(Boolean));
console.log('BUTTONS:', b2.join(' | '));
await browser.close(); srv.close();
