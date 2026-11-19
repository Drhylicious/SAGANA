import { serve, launch, boot, loginAs } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page);
page.on('requestfailed', r => console.log('FAILED len=' + r.url().length, r.url().replace('http://127.0.0.1:54321', '').slice(0, 90), r.failure()?.errorText));
page.on('response', r => { if (r.url().includes(':54321/rest') && /in\.%28|in\.\(/.test(r.url())) console.log(r.status(), 'len=' + r.url().length, r.url().replace('http://127.0.0.1:54321', '').slice(0, 70)); });
await loginAs(page, 't_buyer1');
console.log('--- login done; waiting'); await page.waitForTimeout(5000);
await page.mouse.click(100, 320); await page.waitForTimeout(8000);
await browser.close(); srv.close();
