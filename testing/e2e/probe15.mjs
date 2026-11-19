import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page);
await loginAs(page, 't_manager');
page.on('response', r => { if (r.url().includes(':54321/rest')) console.log(r.status(), r.request().method(), r.url().replace('http://127.0.0.1:54321/rest/v1/', '').slice(0, 150)); });
page.on('requestfailed', r => console.log('FAILED', r.url().slice(0, 120), r.failure()?.errorText));
console.log('--- open marketplace');
await page.getByText('Marketplace', { exact: true }).last().click(); await page.waitForTimeout(6000);
console.log('MKT:', (await text(page)).slice(0, 300));
await browser.close(); srv.close();
