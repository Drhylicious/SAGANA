import { serve, launch, boot, bodyText } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page);
await page.getByText('Login', { exact: true }).last().click(); await page.waitForTimeout(1500);
const i = page.locator('flt-semantics-host input');
for (const [n, v] of [[0, 't_farmer1'], [1, 'Test@12345']]) { await i.nth(n).click(); await page.keyboard.type(v, { delay: 15 }); }
await page.getByText('Sign In', { exact: true }).last().click(); await page.waitForTimeout(7000);
await page.getByText('Profile', { exact: true }).last().click(); await page.waitForTimeout(2500);
const cdp = await page.context().newCDPSession(page);
for (let k = 0; k < 3; k++) { await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 600, yDistance: -700, speed: 1500, gestureSourceType: 'touch' }); await page.waitForTimeout(900); }
console.log('TEXT:', (await bodyText(page)).replace(/\s+/g, ' ').slice(0, 1100));
await page.screenshot({ path: '../results/shots/probe_profile_bottom.png' });
await browser.close(); srv.close();
