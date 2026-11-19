import { serve, launch, boot, bodyText } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page);
await page.getByText('Login', { exact: true }).last().click(); await page.waitForTimeout(1500);
const i = page.locator('flt-semantics-host input');
for (const [n, v] of [[0, 't_farmer1'], [1, 'Test@12345']]) { await i.nth(n).click(); await page.keyboard.type(v, { delay: 15 }); }
await page.getByText('Sign In', { exact: true }).last().click(); await page.waitForTimeout(7000);
await page.getByText('Profile', { exact: true }).last().click(); await page.waitForTimeout(2500);
console.log('PROFILE:', (await bodyText(page)).replace(/\s+/g, ' ').slice(0, 900));
await page.mouse.wheel(0, 900); await page.waitForTimeout(800);
console.log('SCROLLED:', (await bodyText(page)).replace(/\s+/g, ' ').slice(0, 900));
await browser.close(); srv.close();
