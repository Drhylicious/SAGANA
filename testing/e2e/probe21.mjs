import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page);
await loginAs(page, 't_manager'); await page.waitForTimeout(3000);
const cdp = await page.context().newCDPSession(page);
for (let k = 0; k < 3; k++) { await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 600, yDistance: -800, speed: 2000, gestureSourceType: 'touch' }); await page.waitForTimeout(800); }
await page.getByText(/Program Management/).first().click(); await page.waitForTimeout(3500);
console.log('PM:', (await text(page)).slice(0, 200));
await page.locator('flt-semantics-host [role=button]').filter({ hasText: /Add|New|Create/ }).first().click({ timeout: 4000 }).catch(async () => { await page.mouse.click(360, 780); });
await page.waitForTimeout(2500);
console.log('FORM:', (await text(page)).slice(0, 400)); await page.screenshot({ path: '../results/shots/probe_pform.png' });
const box = await page.locator('flt-semantics', { hasText: 'Select categories' }).last().boundingBox(); console.log('BOX', JSON.stringify(box));
await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2); await page.waitForTimeout(1500);
console.log('AFTER TAP:', (await text(page)).slice(0, 500)); await page.screenshot({ path: '../results/shots/probe_pform2.png' });
await browser.close(); srv.close();
