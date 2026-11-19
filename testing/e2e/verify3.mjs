import { execSync } from 'node:child_process';
import { serve, launch, boot, loginAs, text } from './lib.mjs';
const sql = q => execSync(`docker exec supabase_db_sagana-test psql -U postgres -tAc "${q}"`, { encoding: 'utf8' }).trim();
const srv = await serve();
{ // Buyer: server down -> notice
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_buyer1'); await page.waitForTimeout(2500);
  execSync('docker stop supabase_db_sagana-test', { stdio: 'ignore' });
  await page.getByText('Orders', { exact: true }).last().click(); await page.waitForTimeout(6000);
  const t = await text(page);
  console.log(/Couldn't load this screen/.test(t) ? 'PASS' : 'FAIL', '[buyer, database down] "Couldn\'t load this screen" notice ->', t.slice(0, 100));
  await page.screenshot({ path: '../results/shots/verify_load_failed.png' });
  execSync('docker start supabase_db_sagana-test', { stdio: 'ignore' });
  for (let i = 0; i < 30; i++) { try { if (sql('select 1') === '1') break; } catch { } await new Promise(r => setTimeout(r, 4000)); }
  await new Promise(r => setTimeout(r, 20000));
  await page.getByText('Prices', { exact: true }).last().click(); await page.waitForTimeout(3500);
  console.log(!/Couldn't load this screen/.test(await text(page)) ? 'PASS' : 'FAIL', '[buyer, database back] no notice on a healthy screen');
  await browser.close();
}
const hits = async (page, user, name, x, y, expectRe) => { await page.mouse.click(x, y); await page.waitForTimeout(2500); const t = await text(page); console.log(expectRe.test(t) ? 'PASS' : 'FAIL', `[${user}] ${name}: a tap 14 px off the icon still works ->`, t.slice(0, 60)); };
{ // Farmer bell: icon centre about (327,31); tap 14 px right/below
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_farmer1'); await page.waitForTimeout(3000);
  await hits(page, 'farmer', 'notification bell', 339, 44, /Notifications|notification/i);
  await browser.close();
}
{ // Manager avatar (circle centre about (351,31)); tap 11 px off its edge
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_manager'); await page.waitForTimeout(3000);
  await hits(page, 'manager', 'profile avatar', 351, 52, /Profile|Mara|Settings|Account/i);
  await browser.close();
}
srv.close();
