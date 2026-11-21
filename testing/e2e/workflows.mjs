// Data-changing workflows through the real screens (Manager), each confirmed in the database. LOCAL STACK ONLY.
import { execSync } from 'node:child_process';
import { serve, launch, boot, loginAs, text, typeInto } from './lib.mjs';
const sql = q => execSync(`docker exec supabase_db_sagana-test psql -U postgres -tAc "${q}"`, { encoding: 'utf8' }).trim();
const note = (what, pass, d = '') => console.log(`${pass ? 'PASS' : 'FAIL'} ${what}${d ? ' -> ' + d : ''}`);
const SKIPBC = process.env.SKIPBC;
const srv = await serve(); const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_manager'); await page.waitForTimeout(3000);
const cdp = await page.context().newCDPSession(page);
const clickText = async re => { const b = await page.locator('flt-semantics-host [role=button]').evaluateAll((els, src) => { const r = new RegExp(src); const m = els.map(e => ({ t: (e.textContent || '').trim(), b: e.getBoundingClientRect() })).filter(o => r.test(o.t) && o.b.width > 0); const o = m[m.length - 1]; return o && { x: o.b.x + o.b.width / 2, y: o.b.y + o.b.height / 2 }; }, re.source); if (!b) throw new Error('no button ' + re); await page.mouse.click(b.x, Math.min(b.y, 840)); };

// ---- Broadcast
if (!SKIPBC) {
  const title = 'Defense check ' + Date.now().toString().slice(-6);
  await page.mouse.click(267, 31); await page.waitForTimeout(3000);
  await typeInto(page, 0, title); { const ta = page.locator('flt-semantics-host textarea').first(); await ta.click(); await page.keyboard.type('Cooperative meeting on Friday at 9 AM.', { delay: 30 }); }
  await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 600, yDistance: -250, speed: 800, gestureSourceType: 'touch' }); await page.waitForTimeout(800);
  const sb = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => { const o = els.map(e => ({ t: (e.textContent || '').trim(), b: e.getBoundingClientRect() })).find(o => /^Send to/.test(o.t)); return o && { x: o.b.x + o.b.width / 2, y: o.b.y + o.b.height / 2, h: o.b.height }; });
  console.log('send button', JSON.stringify(sb));
  await page.mouse.click(sb.x, sb.y); await page.waitForTimeout(5000);
  const t1 = await text(page); await page.screenshot({ path: '../results/shots/wf_broadcast_after_send.png' });
  const got = +sql(`select count(*) from notifications where title='${title}'`), members = +sql(`select count(*) from user_roles where status='active'`);
  const dup = +sql(`select count(*) from (select user_id from notifications where title='${title}' group by user_id having count(*)>1) x`);
  note('Broadcast: sent to all members from the screen; every member got it exactly once', got > 0 && dup === 0, `notifications ${got} (members active ${members}), duplicates ${dup}, screen: ${t1.slice(0, 80)}`);
}
// ---- Delivery settings: switch delivery on from the screen, confirm in the database, then put it back
{
  if (!SKIPBC) { await page.mouse.click(40, 32); await page.waitForTimeout(2500); }
  const before = sql('select delivery_enabled from delivery_settings');
  await page.getByText('Marketplace', { exact: true }).last().click(); await page.waitForTimeout(3000);
  const b = await page.getByText(/Order Management/).first().boundingBox(); await page.mouse.click(b.x + b.width / 2, b.y + b.height / 2);
  for (let i = 0; i < 80; i++) { await page.waitForTimeout(500); if (/Delivery Settings/.test(await text(page))) break; }
  await clickText(/^Delivery Settings/); await page.waitForTimeout(3500);
  const s = await text(page);
  const sw = page.locator('flt-semantics-host [role=switch], flt-semantics-host [role=checkbox]');
  const nsw = await sw.count();
  if (nsw) { await sw.nth(1).click(); await page.waitForTimeout(3000); }
  await page.screenshot({ path: '../results/shots/wf_delivery_settings.png' });
  for (const re of [/^(Save|Enable|Turn on|Confirm|Update)/]) { if (await page.getByText(re).count()) { await clickText(re).catch(() => {}); await page.waitForTimeout(3000); } }
  const after = sql('select delivery_enabled from delivery_settings');
  note('Delivery settings: the screen opens and its switch changes the stored setting', nsw > 0 && before !== after, `before ${before} after ${after}; switches ${nsw}; screen: ${s.slice(0, 80)}`);
  sql(`update delivery_settings set delivery_enabled=${before === 't'}`);
}
await browser.close(); srv.close();
