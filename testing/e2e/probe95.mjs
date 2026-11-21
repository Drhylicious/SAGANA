import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_manager'); await page.waitForTimeout(3000);
await page.mouse.click(267, 31); await page.waitForTimeout(3000);
console.log('SCREEN:', (await text(page)).slice(0, 260));
console.log('inputs', await page.locator('flt-semantics-host input').count());
const b = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => (e.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 28)).filter(Boolean));
console.log('BUTTONS:', b.join(' | '));
await browser.close(); srv.close();
