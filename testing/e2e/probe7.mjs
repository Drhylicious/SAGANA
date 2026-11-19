import { serve, launch, boot, bodyText } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page);
await page.getByText('Login', { exact: true }).last().click(); await page.waitForTimeout(1500);
const i = page.locator('flt-semantics-host input');
for (const [n, v] of [[0, 't_farmer1'], [1, 'Test@12345']]) { await i.nth(n).click(); await page.keyboard.type(v, { delay: 15 }); }
await page.getByText('Sign In', { exact: true }).last().click(); await page.waitForTimeout(7000);
console.log('before reload URL', page.url());
const ls = await page.evaluate(() => Object.keys(localStorage).join(',')); console.log('localStorage keys:', ls.slice(0, 300));
const dbs = await page.evaluate(async () => (await indexedDB.databases()).map(d => d.name).join(',')); console.log('IDB:', dbs);
await page.reload(); await page.waitForSelector('flt-glass-pane', { state: 'attached' }); await page.waitForTimeout(6000);
if (await page.locator('flt-semantics-placeholder').count()) await page.locator('flt-semantics-placeholder').evaluate(e => e.click());
await page.waitForTimeout(1500);
console.log('after reload URL', page.url()); console.log('TEXT:', (await bodyText(page)).replace(/\s+/g, ' ').slice(0, 200));
await browser.close(); srv.close();
