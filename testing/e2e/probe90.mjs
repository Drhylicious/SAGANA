import { serve, launch, boot, loginAs, text } from './lib.mjs';
const [, , user, label] = process.argv;
const srv = await serve(); const { browser, page, logs } = await launch(); await boot(page); await loginAs(page, user); await page.waitForTimeout(3000);
await page.mouse.click(29, 31); await page.waitForTimeout(1500);
const bx = await page.locator('flt-semantics', { hasText: new RegExp('^' + label) }).last().boundingBox(); console.log('box', JSON.stringify(bx));
await page.mouse.click(bx.x + bx.width / 2, bx.y + bx.height / 2);
for (const ms of [1500, 4000, 8000]) { await page.waitForTimeout(ms === 1500 ? 1500 : ms - (ms === 4000 ? 1500 : 4000)); console.log(ms, 'ms:', (await text(page)).slice(0, 140)); }
await page.screenshot({ path: `../results/shots/probe_${user}_${label.replace(/\W+/g, '')}.png` });
console.log('LOGS', logs.filter(l => !/favicon|manifest|CanvasKit|fonts/i.test(l)).slice(0, 4));
await browser.close(); srv.close();
