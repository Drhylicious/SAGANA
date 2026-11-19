import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page);
await loginAs(page, 't_manager');
await page.getByText('Marketplace', { exact: true }).last().click(); await page.waitForTimeout(3500);
console.log('MKT:', (await text(page)).slice(0, 500));
await page.screenshot({ path: '../results/shots/probe_mgr_market.png' });
await browser.close(); srv.close();
