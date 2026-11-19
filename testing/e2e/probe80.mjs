import { serve, launch, boot, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page);
await page.getByText(/^(Login|Mag-login)$/).last().click(); await page.waitForTimeout(1500);
await page.getByText(/Create an Account/).last().click(); await page.waitForTimeout(2500);
console.log('REG1:', (await text(page)).slice(0, 400));
const btns = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => (e.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 30)).filter(Boolean));
console.log('BUTTONS:', btns.join(' | '), '| inputs', await page.locator('flt-semantics-host input').count());
await page.screenshot({ path: '../results/shots/pw_register1.png' });
await browser.close(); srv.close();
