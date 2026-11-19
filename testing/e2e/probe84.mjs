import { serve, launch, boot, loginAs, text } from './lib.mjs';
const [, , user = 't_farmer1'] = process.argv;
const srv = await serve(); const { browser, page } = await launch(); await boot(page); await loginAs(page, user);
await page.mouse.click(29, 31); await page.waitForTimeout(1500);
await page.getByText(/^Account$/).first().click(); await page.waitForTimeout(3000);
console.log('ACCOUNT:', (await text(page)).slice(0, 250));
const cdp = await page.context().newCDPSession(page);
for (let k = 0; k < 5 && !(await page.getByText(/Change Password/).count()); k++) { await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 500, yDistance: -500, speed: 1500, gestureSourceType: 'touch' }); await page.waitForTimeout(400); }
await page.getByText(/Change Password/).first().click(); await page.waitForTimeout(2000);
console.log('DIALOG:', (await text(page)).slice(0, 250));
console.log('inputs', await page.locator('flt-semantics-host input').count());
const b2 = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => (e.textContent || '').trim().slice(0, 25)).filter(Boolean));
console.log('BUTTONS:', b2.join(' | '));
await browser.close(); srv.close();
