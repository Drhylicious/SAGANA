import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_manager'); await page.waitForTimeout(4000);
await page.getByText('Marketplace', { exact: true }).last().click(); await page.waitForTimeout(3000);
const log = []; let t0 = 0;
page.on('requestfinished', r => { if (r.url().includes(':54321/rest')) log.push([Date.now() - t0, r.url().replace('http://127.0.0.1:54321/rest/v1/', '').split('?')[0], (r.url().match(/offset=(\d+)/) || [])[1]]); });
t0 = Date.now();
await page.getByText(/Order Management/).first().click();
let ready = 0; for (let i = 0; i < 120; i++) { await page.waitForTimeout(500); const x = await text(page); if (/All \((\d{3,})\)/.test(x)) { ready = Date.now() - t0; break; } }
console.log('ready at', ready, 'ms; requests:', log.length, 'last response at', Math.max(...log.map(l => l[0])), 'ms');
const byTable = {}; for (const [t, tb] of log) { byTable[tb] = byTable[tb] || { n: 0, last: 0 }; byTable[tb].n++; byTable[tb].last = Math.max(byTable[tb].last, t); }
console.log(JSON.stringify(byTable));
await browser.close(); srv.close();
