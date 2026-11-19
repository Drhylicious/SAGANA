import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_manager'); await page.waitForTimeout(6000);
const reqs = []; const t0 = Date.now();
page.on('requestfinished', async r => { if (r.url().includes(':54321/rest')) { const t = r.timing(); let size = 0; try { size = (await r.sizes()).responseBodySize; } catch {} reqs.push({ start: Math.round(t.startTime - 0), end: Math.round(t.responseEnd), at: Date.now() - t0, url: r.url().replace('http://127.0.0.1:54321/rest/v1/', '').slice(0, 85), kb: Math.round(size / 1024) }); } });
await page.getByText('Reports', { exact: true }).last().click(); await page.waitForTimeout(12000);
reqs.sort((a, b) => a.at - b.at);
console.log('count', reqs.length, 'total KB', reqs.reduce((a, r) => a + r.kb, 0));
for (const r of reqs.sort((a, b) => b.end - a.end).slice(0, 12)) console.log(String(r.end).padStart(6), 'ms', String(r.kb).padStart(5), 'KB', r.url);
await browser.close(); srv.close();
