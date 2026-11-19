import { serve, launch, boot, loginAs, text } from './lib.mjs';
const [, , user = 't_officer_manage'] = process.argv;
const srv = await serve(); const { browser, page } = await launch(); await boot(page); await loginAs(page, user);
await page.getByText('Marketplace', { exact: true }).last().click(); await page.waitForTimeout(3000);
await page.getByText(/Order Management/).first().click();
for (let i = 0; i < 120; i++) { await page.waitForTimeout(500); const x = await text(page); if (/All \((\d{2,})\)/.test(x) && /ORD-/.test(x)) break; }
await page.getByText(/ORD-\d{8}-\w+[\s\S]*Pending Order/).first().click(); await page.waitForTimeout(3500);
const num = ((await text(page)).match(/Order #(ORD-[\w-]+)/) || [])[1]; console.log('order', num);
await page.getByText('Approve Order', { exact: true }).last().click(); await page.waitForTimeout(2500); await page.screenshot({ path: '../results/shots/probe_approve1_' + user + '.png' }); console.log('FIRST:', (await text(page)).slice(0, 300)); await page.getByText('Approve Order', { exact: true }).last().click().catch(() => {}); await page.waitForTimeout(2500);
console.log('AFTER CLICK:', (await text(page)).slice(0, 500));
await page.screenshot({ path: '../results/shots/probe_approve_' + user + '.png' });
const btns = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => els.map(e => (e.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 40)).filter(Boolean));
console.log('BUTTONS:', btns.join(' | '));
await browser.close(); srv.close();
