import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch({ width: 360, height: 740 }); await boot(page); await loginAs(page, 't_farmer1');
await page.evaluate(() => { document.documentElement.style.fontSize = '32px'; });
await page.waitForTimeout(2500);
console.log('fs', await page.evaluate(() => getComputedStyle(document.documentElement).fontSize));
await page.screenshot({ path: '../results/shots/probe_ts.png' });
await browser.close(); srv.close();
