import { execSync } from 'node:child_process';
import { serve, launch, boot, loginAs, text } from './lib.mjs';
const sql = q => execSync(`docker exec supabase_db_sagana-test psql -U postgres -tAc "${q}"`, { encoding: 'utf8' }).trim();
const srv = await serve();
// 2. Manager: all orders (parallel pages), loan dashboard, tap sizes of header buttons
{
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_manager'); await page.waitForTimeout(3000);
  const total = sql('select count(*) from orders');
  await page.getByText('Marketplace', { exact: true }).last().click(); await page.waitForTimeout(2500);
  await page.getByText(/Order Management/).first().click();
  let t = ''; const t0 = Date.now(); for (let i = 0; i < 160; i++) { await page.waitForTimeout(500); t = await text(page); const m = t.match(/All \((\d+)\)/); if (m && +m[1] > 0) break; }
  const m = t.match(/All \((\d+)\)/); const coop = +sql('select count(*) from program_product_purchases');
  console.log(m && +m[1] === +total + coop ? 'PASS' : 'FAIL', `[manager] Order Management lists every order: shown ${m && m[1]} of ${+total + coop} in ${Math.round((Date.now() - t0) / 1000)} s`);
  await page.goBack().catch(() => {}); await page.waitForTimeout(1500);
  await page.getByText('Loans', { exact: true }).last().click(); await page.waitForTimeout(4000);
  const lt = await text(page); const act = sql("select count(*) from farmer_loans where status='active'");
  console.log(/Active Loans/.test(lt) ? 'PASS' : 'FAIL', '[manager] Loans dashboard loads ->', lt.slice(0, 90), '| active loans in DB', act);
  const small = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => { const r = e.getBoundingClientRect(); return { t: (e.textContent || '').trim().slice(0, 12), w: Math.round(r.width), h: Math.round(r.height), top: r.top < 120 }; }).filter(o => o.top && o.w > 0 && (o.w < 44 || o.h < 44)));
  console.log(small.length === 0 ? 'PASS' : 'FAIL', '[manager] header buttons are at least 44 px:', JSON.stringify(small));
  await browser.close();
}
{
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_farmer1'); await page.waitForTimeout(3000);
  const small = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => { const r = e.getBoundingClientRect(); return { t: (e.textContent || '').trim().slice(0, 14), w: Math.round(r.width), h: Math.round(r.height), top: r.top < 120 }; }).filter(o => o.top && o.w > 0 && (o.w < 44 || o.h < 44)));
  console.log(small.length === 0 ? 'PASS' : 'FAIL', '[farmer] header buttons at least 44 px:', JSON.stringify(small));
  const vm = await page.locator('flt-semantics', { hasText: 'View Market' }).last().boundingBox();
  console.log(vm && vm.height >= 44 ? 'PASS' : 'FAIL', '[farmer] "View Market" tap height', vm && Math.round(vm.height));
  await browser.close();
}
srv.close();
