import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_manager'); await page.waitForTimeout(3000);
let nreq = 0; const bad = [];
page.on('request', r => { if (r.url().includes(':54321/rest')) nreq++; });
page.on('requestfailed', r => bad.push(['FAILED', r.url().length, r.url().replace('http://127.0.0.1:54321/rest/v1/', '').split('?')[0], r.failure()?.errorText]));
page.on('response', r => { if (r.url().includes(':54321/rest') && r.status() >= 400) bad.push([r.status(), r.url().length, r.url().replace('http://127.0.0.1:54321/rest/v1/', '').split('?')[0]]); });
await page.getByText('Marketplace', { exact: true }).last().click(); await page.waitForTimeout(2500);
nreq = 0; const t0 = Date.now();
{ const b = await page.getByText(/All Listings/).first().boundingBox(); await page.mouse.click(b.x + b.width / 2, b.y + b.height / 2); }
for (let i = 0; i < 120; i++) { await page.waitForTimeout(500); const t = await text(page); if (t.length > 120) { console.log('content after', Date.now() - t0, 'ms:', t.slice(0, 120)); break; } }
await page.waitForTimeout(3000);
console.log('requests', nreq, 'bad', JSON.stringify(bad.slice(0, 6)));
console.log('final text:', (await text(page)).slice(0, 160));
await browser.close(); srv.close();
