import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_manager');
await page.getByText('Members', { exact: true }).last().click(); await page.waitForTimeout(3500);
await page.getByText('Add Member', { exact: true }).last().click(); await page.waitForTimeout(2000);
console.log('SHEET:', (await text(page)).slice(0, 200));
await page.screenshot({ path: '../results/shots/pw_addmember_sheet.png' });
const btns = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => (e.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 30)).filter(Boolean));
console.log('BUTTONS:', btns.join(' | '));
const which = process.argv[2] || 'Add Farmer / Member';
await page.getByText(which).first().click(); await page.waitForTimeout(3000);
const info = await page.locator('flt-semantics-host input').evaluateAll(els => els.map((e, i) => ({ i, type: e.type, v: e.value.slice(0, 14) })));
console.log('INPUTS:', JSON.stringify(info));
const cdp = await page.context().newCDPSession(page);
for (let k = 0; k < 6; k++) { await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 500, yDistance: -500, speed: 1500, gestureSourceType: 'touch' }); await page.waitForTimeout(400); }
const b2 = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => (e.textContent || '').trim().replace(/s+/g, ' ').slice(0, 30)).filter(Boolean));
console.log('BUTTONS2:', b2.join(' | '));
await page.screenshot({ path: '../results/shots/pw_addmember_form.png' });
await browser.close(); srv.close();
