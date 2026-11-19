import { serve, launch, boot, bodyText } from './lib.mjs';
const srv = await serve();
const { browser, page, logs } = await launch();
await boot(page);
await page.screenshot({ path: '../results/shots/probe_first.png' });
console.log('TEXT:', (await bodyText(page)).replace(/\s+/g, ' ').slice(0, 400));
console.log('LOGS:', logs.slice(0, 5));
await browser.close(); srv.close();
