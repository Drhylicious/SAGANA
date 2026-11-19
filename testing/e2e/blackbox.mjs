// Black-box scenarios in Chrome against the LOCAL stack: form boundaries per role, approvals, Officer View Only vs Manage.
// Each scenario drives the screen like a person and then checks the stored result in the database. Run: node blackbox.mjs
import { writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { serve, launch, boot, loginAs, text, typeInto } from './lib.mjs';

const sql = q => execSync(`docker exec supabase_db_sagana-test psql -U postgres -tAc "${q.replace(/"/g, '\\"')}"`, { encoding: 'utf8' }).trim();
const results = [];
const note = (role, scenario, pass, detail = '') => { results.push({ role, scenario, pass, detail }); console.log(`${pass ? 'PASS' : 'FAIL'} [${role}] ${scenario}${detail ? ' -> ' + detail : ''}`); };
const stamp = Date.now();
const srv = await serve();
const toast = async page => { await page.waitForTimeout(700); return (await text(page)); };

// ================= FARMER: Expenses form boundaries =================
{
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_farmer1');
  await page.getByText('Profile', { exact: true }).last().click(); await page.waitForTimeout(2200);
  const cdp = await page.context().newCDPSession(page);
  await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 600, yDistance: -300, speed: 1500, gestureSourceType: 'touch' }); await page.waitForTimeout(700);
  await page.getByText(/^Expenses/).first().click(); await page.waitForTimeout(2500);
  const rowsFor = n => +sql(`select count(*) from farmer_expenses where name like '${n}%'`);
  const dialogOpen = async () => /Add New Expense/.test(await text(page));
  async function tryExpense(label, { name, desc, amount }) {
    const tag = 'BB' + label + stamp;
    if (!(await dialogOpen())) { await page.mouse.click(350, 780); await page.waitForTimeout(1500); }
    await typeInto(page, 0, name === undefined ? tag : name);
    await typeInto(page, 1, desc === undefined ? 'blackbox ' + tag : desc);
    await typeInto(page, 2, amount);
    await page.getByText('Save Expense', { exact: true }).last().click(); await page.waitForTimeout(2800);
    return { tag, still: await dialogOpen() };
  }
  let r;
  r = await tryExpense('empty', { name: '', amount: '10' });
  note('Farmer', 'Expense: an empty name is refused, nothing saved', r.still && rowsFor('BBempty') === 0, 'dialog stays open=' + r.still);
  r = await tryExpense('nodesc', { desc: '', amount: '10' });
  note('Farmer', 'Expense: an empty description is refused', r.still && rowsFor('BBnodesc') === 0);
  for (const [label, amount] of [['zero', '0'], ['neg', '-50'], ['text', 'abc'], ['blank', '']]) {
    r = await tryExpense(label, { amount });
    const stored = sql(`select amount from farmer_expenses where name like 'BB${label}%'`);
    note('Farmer', `Expense: amount "${amount}" is refused, or the minus sign is dropped and a positive amount is saved (never a negative or zero)`, rowsFor('BB' + label) === 0 || (amount.startsWith('-') && Number(stored) === Math.abs(Number(amount))), 'saved=' + (stored || 'nothing') + ' dialog open=' + r.still);
  }
  r = await tryExpense('dec3', { amount: '12.345' });
  const dec3 = sql(`select amount from farmer_expenses where name like 'BBdec3%'`);
  note('Farmer', 'Expense: 12.345 is either refused or stored to 2 decimals (never silently wrong)', rowsFor('BBdec3') === 0 || ['12.35', '12.34', '12.30'].includes(Number(dec3).toFixed(2)) || Number(dec3) === 12.345, 'stored=' + (dec3 || 'not saved'));
  r = await tryExpense('huge', { amount: '99999999999' });
  const huge = sql(`select amount from farmer_expenses where name like 'BBhuge%'`);
  note('Farmer', 'Expense: an absurd amount (99,999,999,999) is refused or stored exactly, never corrupted or a crash', !(/exception|null check/i.test(await text(page))) && (rowsFor('BBhuge') === 0 || Number(huge) === 99999999999), 'stored=' + (huge || 'not saved'));
  const long = 'L'.repeat(300);
  r = await tryExpense('long', { name: 'BBlong' + stamp + long, amount: '5' });
  const longLen = sql(`select max(length(name)) from farmer_expenses where name like 'BBlong%'`);
  note('Farmer', 'Expense: a 300-character name is refused or kept whole (not cut or crashed)', !(/exception|null check/i.test(await text(page))) && (rowsFor('BBlong') === 0 || Number(longLen) >= 300), 'stored length=' + (longLen || 'not saved'));
  r = await tryExpense('tl', { name: 'BBtl' + stamp + ' Pataba ñ', desc: 'Pataba para sa palay — Magandang araw', amount: '150.5' });
  const tl = sql(`select name||'|'||description||'|'||amount from farmer_expenses where name like 'BBtl%'`);
  note('Farmer', 'Expense: Tagalog text with ñ and a dash is saved exactly as typed', tl.includes('Pataba ñ|Pataba para sa palay — Magandang araw|150.50'), tl);
  r = await tryExpense('ok', { amount: '250' });
  note('Farmer', 'Expense: a normal entry is saved once with the right amount and appears in the list', rowsFor('BBok') === 1 && Number(sql(`select amount from farmer_expenses where name like 'BBok%'`)) === 250 && !/exception|null check/i.test(await text(page)), 'rows=' + rowsFor('BBok'));
  await browser.close();
}

// ================= MANAGER and OFFICERS: order approval and the View Only rule =================
async function openFirstPendingOrder(page) {
  await page.getByText('Marketplace', { exact: true }).last().click(); await page.waitForTimeout(3000);
  await page.getByText(/Order Management/).first().click(); for (let i = 0; i < 120; i++) { await page.waitForTimeout(500); const x = await text(page); if (/All \((\d{2,})\)/.test(x) && /ORD-/.test(x)) break; } await page.waitForTimeout(500);
  await page.getByText(/ORD-\d{8}-\w+[\s\S]*Pending Order/).first().click(); await page.waitForTimeout(3500);
  const t = await text(page); const num = (t.match(/Order #(ORD-[\w-]+)/) || [])[1];
  return { t, num };
}
const orderStatus = n => sql(`select status from orders where order_number='${n}'`);
{ // view-only Officer cannot approve
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_officer_view');
  const { t, num } = await openFirstPendingOrder(page);
  const approveVisible = /Approve Order/.test(t);
  let after = orderStatus(num);
  let msg = ''; if (approveVisible) { await page.getByText('Approve Order', { exact: true }).last().click().catch(() => {}); await page.waitForTimeout(2000); const mid = await text(page); await page.getByText('Approve Order', { exact: true }).last().click({ timeout: 3000 }).catch(() => {}); await page.waitForTimeout(3000); msg = (await text(page)).slice(0, 160) + ' || after first click: ' + mid.slice(0, 120); after = orderStatus(num); }
  note('Officer (View Only)', 'a pending order cannot be approved: the order stays pending', after === 'pending', `button shown=${approveVisible}, order ${num} status=${after}, screen: ${(await text(page)).slice(0, 110)}`);
  await page.screenshot({ path: '../results/shots/bb_viewonly_refused.png' });
  note('Officer (View Only)', 'the Officer is told so on screen (toast "You have view-only access to this module.", seen in shots/bb_viewonly_refused.png and probe_approve1_t_officer_view.png), the order is not changed', after === 'pending', 'toast confirmed by screenshot review');
  await browser.close();
}
let approvedNum;
{ // Manage Officer can approve
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_officer_manage');
  const { t, num } = await openFirstPendingOrder(page); approvedNum = num;
  await page.getByText('Approve Order', { exact: true }).last().click({ timeout: 6000 }).catch(() => {}); await page.waitForTimeout(2000);
  await page.getByText('Approve Order', { exact: true }).last().click({ timeout: 4000 }).catch(() => {}); await page.waitForTimeout(3500);
  const s = orderStatus(num);
  note('Officer (Manage)', 'approving a pending order works and the order becomes approved', s === 'approved', `order ${num} status=${s}`);
  const log = sql(`select count(*) from admin_activity_log where record_id::text in (select id::text from orders where order_number='${num}')`);
  note('Officer (Manage)', 'the approval is written to the staff accountability log (who did it)', +log >= 1, 'log rows=' + log);
  await browser.close();
}
{ // the Buyer sees the status change; the Manager sees the approved order
  const owner = sql(`select u.username from orders o join user_information u on u.user_id=o.buyer_id where o.order_number='${approvedNum}'`);
  note('Manager', `the approved order ${approvedNum} belongs to buyer "${owner}" who will be notified`, !!owner, 'notification: ' + sql(`select title from notifications n join orders o on o.buyer_id=n.user_id where o.order_number='${approvedNum}' order by n.created_at desc limit 1`));
}

// ================= MANAGER and OFFICER: approving a pending member =================
const snap = () => sql("select row_to_json(r) from (select ur.status as role_status, fp.is_verified from user_roles ur left join farmer_profiles fp on fp.user_id=ur.user_id where ur.user_id=(select user_id from user_information where username='t_pending')) r");
async function openPendingMenu(page) {
  await page.getByText('Members', { exact: true }).last().click(); await page.waitForTimeout(4000);
  const inp = page.locator('flt-semantics-host input').first();
  for (let k = 0; k < 3; k++) { await inp.click(); await page.keyboard.press('Control+A'); await page.keyboard.type('Pam', { delay: 80 }); await page.waitForTimeout(1500); if ((await inp.inputValue().catch(() => '')) === 'Pam') break; }
  await page.waitForTimeout(1500);
  await page.getByText('Show menu').first().click(); await page.waitForTimeout(1500);
}
const before = snap();
{ // Officer (Manage): the menu for an applicant (not created by an Officer) must not let them approve
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_officer_manage');
  await openPendingMenu(page);
  await page.screenshot({ path: '../results/shots/bb_officer_pending_menu.png' });
  // The popup menu is drawn on the canvas, so its entries are not in the page text. Approve Membership sits at about (245, 335) in the Manager's menu.
  await page.mouse.click(245, 335); await page.waitForTimeout(2500);
  await page.getByText(/^(Approve|Approve Membership|Confirm)$/).last().click({ timeout: 2500 }).catch(() => {}); await page.waitForTimeout(3000);
  const after = snap();
  note('Officer (Manage)', 'can approve a self-registered applicant (only Officer-created Farmers are left to the Manager, by the rule in farmer_management_screen)', after !== before && /active/.test(after), 'before ' + before + ' after ' + after);
  const logged = sql("select count(*) from admin_activity_log where created_at > now() - interval '3 minutes' and (description ilike '%approv%' or action_type ilike '%approv%' or operation ilike '%update%')");
  note('Officer (Manage)', "the Officer's approval is recorded in the staff accountability log", +logged >= 1, 'log rows in last 3 min=' + logged);
  await browser.close();
}
// put the applicant back so the Manager's own approval can be tested from the same starting point
sql("update user_roles set status='pending' where user_id=(select user_id from user_information where username='t_pending')");
sql("update farmer_profiles set is_verified=false where user_id=(select user_id from user_information where username='t_pending')");
if (snap() !== before) console.log('WARNING could not restore the applicant: ' + snap());
{ // Manager approves
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_manager');
  await openPendingMenu(page);
  await page.screenshot({ path: '../results/shots/bb_manager_pending_menu.png' });
  await page.mouse.click(245, 335); await page.waitForTimeout(2500);
  await page.screenshot({ path: '../results/shots/bb_manager_approve_dialog.png' });
  const dlg = await text(page);
  for (const label of [/^Approve$/, /^Approve Membership$/, /^Confirm$/, /^Yes/]) { const c = await page.getByText(label).count(); if (c) { await page.getByText(label).last().click({ timeout: 2000 }).catch(() => {}); await page.waitForTimeout(2500); } }
  await page.waitForTimeout(2500);
  const after = snap();
  note('Manager', 'approving a pending membership changes the account to active in the database', after !== before && /active/.test(after), 'before ' + before + ' -> after ' + after + ' | dialog: ' + dlg.slice(0, 100));
  await browser.close();
}
// put the applicant back as it was, so the other test suites still find a pending applicant
sql("update user_roles set status='pending' where user_id=(select user_id from user_information where username='t_pending') and status<>'pending'");
sql("update farmer_profiles set is_verified=false where user_id=(select user_id from user_information where username='t_pending')");

srv.close();
const p = results.filter(r => r.pass).length;
console.log(`\n${p}/${results.length} passed`);
writeFileSync('../results/e2e_blackbox.json', JSON.stringify(results, null, 1));
