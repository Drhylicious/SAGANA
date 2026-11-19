// Ad-hoc / exploratory session (time-boxed, 2 charters): "odd taps, back button, resizing, rapid switching" in Chrome, LOCAL stack.
import { writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { serve, launch, boot, loginAs, text, typeInto } from './lib.mjs';
const sql = q => execSync(`docker exec supabase_db_sagana-test psql -U postgres -tAc "${q}"`, { encoding: 'utf8' }).trim();
const results = [];
const note = (charter, what, pass, detail = '') => { results.push({ charter, what, pass, detail }); console.log(`${pass ? 'PASS' : 'FAIL'} [${charter}] ${what}${detail ? ' -> ' + detail : ''}`); };
const bad = t => /exception|null check|unhandled|something went wrong/i.test(t);
const srv = await serve(); const stamp = Date.now();

// Charter 1: Buyer ordering with odd taps
{
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_buyer1'); await page.waitForTimeout(2500);
  const count = () => +sql("select count(*) from orders o join user_information u on u.user_id=o.buyer_id where u.username='t_buyer1'");
  const c0 = count();
  await page.mouse.click(100, 320); await page.waitForTimeout(4500);
  await page.getByText('Buy Now', { exact: true }).last().click(); await page.waitForTimeout(1800);
  await typeInto(page, 0, '1');
  await page.getByText('Buy Now', { exact: true }).last().click(); await page.waitForTimeout(3500);
  note('Buyer odd taps', 'checkout opens after Buy Now', /Checkout/.test(await text(page)));
  await page.goBack().catch(() => {}); await page.waitForTimeout(2500);
  let t = await text(page);
  note('Buyer odd taps', 'browser Back from checkout does not crash and does not place an order', !bad(t) && count() === c0, 'orders ' + c0 + '->' + count() + ' screen: ' + t.slice(0, 60));
  await page.getByText('Buy Now', { exact: true }).last().click({ timeout: 4000 }).catch(() => {}); await page.waitForTimeout(1500);
  await typeInto(page, 0, '1').catch(() => {});
  await page.getByText('Buy Now', { exact: true }).last().click({ timeout: 4000 }).catch(() => {}); await page.waitForTimeout(3000);
  const place = page.getByText('Place Order', { exact: true }).last();
  if (await place.count()) { await Promise.all([place.click({ clickCount: 1 }).catch(() => {}), place.click({ delay: 0 }).catch(() => {}), place.click().catch(() => {})]); await page.waitForTimeout(6000); }
  const c1 = count();
  note('Buyer odd taps', 'pressing Place Order three times in a row creates exactly one order', c1 - c0 === 1, 'orders ' + c0 + '->' + c1);
  await page.setViewportSize({ width: 320, height: 640 }); await page.waitForTimeout(1500);
  note('Buyer odd taps', 'shrinking the window to 320 px on the result screen: no crash', !bad(await text(page)));
  await page.setViewportSize({ width: 1024, height: 768 }); await page.waitForTimeout(1500);
  note('Buyer odd taps', 'widening to 1024 px: no crash', !bad(await text(page)));
  await browser.close();
}
// Charter 2: Farmer form with odd taps and rapid switching
{
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_farmer1'); await page.waitForTimeout(2500);
  for (let i = 0; i < 12; i++) for (const tab of ['Harvest', 'Listings', 'Analytics', 'Profile', 'Home']) await page.getByText(tab, { exact: true }).last().click({ timeout: 3000, noWaitAfter: true }).catch(() => {});
  await page.waitForTimeout(2500);
  note('Farmer odd taps', '60 rapid tab switches: still responsive, no error', !bad(await text(page)) && /Monthly Yield|Home/.test(await text(page)), (await text(page)).slice(0, 50));
  await page.getByText('Profile', { exact: true }).last().click(); await page.waitForTimeout(2200);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 600, yDistance: -300, speed: 1500, gestureSourceType: 'touch' }); await page.waitForTimeout(700);
  await page.getByText(/^Expenses/).first().click(); await page.waitForTimeout(2500);
  await page.mouse.click(350, 780); await page.waitForTimeout(1500);
  const name = 'AH' + stamp;
  await typeInto(page, 0, name); await typeInto(page, 1, 'adhoc'); await typeInto(page, 2, '12');
  await page.setViewportSize({ width: 320, height: 568 }); await page.waitForTimeout(1500);
  note('Farmer odd taps', 'resizing the window with a form open keeps what was typed', (await page.locator('flt-semantics-host input').first().inputValue().catch(() => '')) === name);
  await page.setViewportSize({ width: 390, height: 844 }); await page.waitForTimeout(1200);
  const save = page.getByText('Save Expense', { exact: true }).last();
  await Promise.all([save.click().catch(() => {}), save.click().catch(() => {}), save.click().catch(() => {})]); await page.waitForTimeout(4000);
  const n = +sql(`select count(*) from farmer_expenses where name='${name}'`);
  note('Farmer odd taps', 'pressing Save Expense three times in a row saves exactly one record', n === 1, 'rows=' + n);
  await page.goBack().catch(() => {}); await page.waitForTimeout(2000);
  note('Farmer odd taps', 'browser Back from Expenses: no crash', !bad(await text(page)), (await text(page)).slice(0, 50));
  await browser.close();
}
srv.close();
const p = results.filter(r => r.pass).length; console.log(`\n${p}/${results.length} passed`);
writeFileSync('../results/e2e_adhoc.json', JSON.stringify(results, null, 1));
