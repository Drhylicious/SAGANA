import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); 
const pending = new Map();
page.on('request', r => { if (r.url().includes(':54321')) pending.set(r, r.url().replace('http://127.0.0.1:54321', '').slice(0, 100)); });
page.on('requestfinished', r => pending.delete(r)); page.on('requestfailed', r => pending.delete(r));
await boot(page); await loginAs(page, 't_manager'); await page.waitForTimeout(8000);
console.log('pending after 8s:', [...pending.values()]);
console.log((await text(page)).slice(0, 120));
await browser.close(); srv.close();
