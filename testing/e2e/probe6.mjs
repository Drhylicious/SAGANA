import { serve, launch, boot, bodyText } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page);
await page.getByText('Login', { exact: true }).last().click(); await page.waitForTimeout(1500);
const i = page.locator('flt-semantics-host input');
for (const [n, v] of [[0, 't_farmer1'], [1, 'Test@12345']]) { await i.nth(n).click(); await page.keyboard.type(v, { delay: 15 }); }
await page.getByText('Sign In', { exact: true }).last().click(); await page.waitForTimeout(7000);
await page.goto('http://127.0.0.1:8099/farmer/settings'); await page.waitForSelector('flt-glass-pane', { state: 'attached' }); for (let k=0;k<6;k++){ await page.waitForTimeout(2500); console.log('t+', (k+1)*2.5, page.url()); }
if (await page.locator('flt-semantics-placeholder').count()) await page.locator('flt-semantics-placeholder').evaluate(e => e.click());
await page.waitForTimeout(1500);
console.log('URL', page.url()); console.log('TEXT:', (await bodyText(page)).replace(/\s+/g, ' ').slice(0, 700));
await page.screenshot({ path: '../results/shots/probe_settings.png' });
await browser.close(); srv.close();
