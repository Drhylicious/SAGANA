import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page);
await loginAs(page, 't_manager'); await page.waitForTimeout(3000);
const cdp = await page.context().newCDPSession(page);
for (let k = 0; k < 3; k++) { await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 600, yDistance: -800, speed: 2000, gestureSourceType: 'touch' }); await page.waitForTimeout(800); }
const btns = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => (e.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 50)).filter(Boolean));
console.log(btns.join(' | '));
await browser.close(); srv.close();
