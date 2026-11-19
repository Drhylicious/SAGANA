// Password rule checks in Chrome (local stack): Register (Farmer, Buyer), staff Create Farmer Member, Manager Create Officer,
// forced password change (shares its form with Forgot Password), in-app Change Password. Rule: 8+ chars, uppercase, number, special.
import { writeFileSync } from 'node:fs';
import { execSync } from 'node:child_process';
import { serve, launch, boot, loginAs, text, typeInto } from './lib.mjs';
const sql = q => execSync(`docker exec supabase_db_sagana-test psql -U postgres -tAc "${q}"`, { encoding: 'utf8' }).trim();
const results = [];
const note = (where, what, pass, detail = '') => { results.push({ where, what, pass, detail }); console.log(`${pass ? 'PASS' : 'FAIL'} [${where}] ${what}${detail ? ' -> ' + detail : ''}`); };
const MSG = /uppercase letter, a number and a special character/i;
const CASES = [
  ['Ab1!', 'too short', false], ['abcdefg1!', 'no uppercase', false], ['Abcdefgh!', 'no number', false],
  ['Abcdefg12', 'no special character', false], ['Abcd 123', 'space only (not special)', false], ['Abcdef1!', 'meets all four', true],
];
const stamp = Date.now().toString().slice(-7);
const srv = await serve();

// Runs the cases on one password input (index pwIdx), pressing `submitLabel` each time and reading the screen text.
async function runCases(page, where, pwIdx, submit, { before } = {}) {
  for (const [pw, label, ok] of CASES) {
    if (before) await before();
    await typeInto(page, pwIdx, pw);
    await submit(); await page.waitForTimeout(1200);
    const t = await text(page);
    note(where, `"${pw}" (${label}) ${ok ? 'is accepted by the password field' : 'is refused with the requirement message'}`, ok ? !MSG.test(t) : MSG.test(t), (ok ? 'message shown: ' + MSG.test(t) : t.match(/Password must[^.]*\./)?.[0] || t.slice(0, 80)));
  }
}

// ---- Register: Farmer and Buyer. The password sits on step 1; Next validates the whole step and shows inline errors.
for (const role of ['Farmer', 'Buyer']) {
  const { browser, page } = await launch(); await boot(page);
  await page.getByText(/^(Login|Mag-login)$/).last().click(); await page.waitForTimeout(1500);
  await page.getByText(/Create an Account/).last().click(); await page.waitForTimeout(2500);
  await page.getByText(role, { exact: true }).first().click(); await page.waitForTimeout(800);
  const n = await page.locator('flt-semantics-host input').count();
  const idxs = await page.locator('flt-semantics-host input').evaluateAll(els => els.map((e, i) => ({ i, type: e.type, label: e.getAttribute('aria-label') || '' })));
  const pwIdx = idxs.filter(x => x.type === 'password').map(x => x.i);
  note(`Register ${role}`, 'the form has a password and a confirm-password field', pwIdx.length === 2, JSON.stringify(idxs.map(x => x.type)));
  if (pwIdx.length === 2) {
    const cdp = await page.context().newCDPSession(page);
    await runCases(page, `Register ${role}`, pwIdx[0], async () => { for (let k = 0; k < 4 && !(await page.getByText(/^(Next|Create Account|Register|Sign Up|Submit|Continue)$/).count()); k++) { await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 500, yDistance: -500, speed: 1500, gestureSourceType: 'touch' }); await page.waitForTimeout(500); } const bx = await page.locator('flt-semantics-host [role=button]').evaluateAll(els => { const r = els.map(e => ({ t: (e.textContent || '').trim(), b: e.getBoundingClientRect() })).filter(o => /^(Next|Create Account|Register|Sign Up|Submit|Continue)$/.test(o.t) && o.b.width > 0); const o = r[r.length - 1]; return o && { x: o.b.x, y: o.b.y, width: o.b.width, height: o.b.height, t: o.t }; }); if (!bx) throw new Error('no submit button; buttons: ' + (await page.locator('flt-semantics-host [role=button]').allTextContents()).join('|').slice(0, 200)); await page.mouse.click(bx.x + bx.width / 2, Math.min(bx.y + bx.height / 2, 830)); });
    // the live hint under the field
    await typeInto(page, pwIdx[0], 'abc');
    note(`Register ${role}`, 'the amber hint under the field shows the full requirement while the password is weak', MSG.test(await text(page)));
  }
  await browser.close();
}

// ---- Staff-created accounts: Manager > Members > Add Member > Farmer / Officer
const SUBMIT = /^(Next|Create Account|Create Officer Account|Register|Sign Up|Submit|Continue|Save|Update Password|Change Password)$/;
async function submitBtn(page) {
  const cdp = await page.context().newCDPSession(page);
  for (let k = 0; k < 8 && !(await page.getByText(SUBMIT).count()); k++) { await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 500, yDistance: -500, speed: 1500, gestureSourceType: 'touch' }); await page.waitForTimeout(400); }
  const bx = await page.locator('flt-semantics-host [role=button]').evaluateAll((els, src) => { const re = new RegExp(src); const r = els.map(e => ({ t: (e.textContent || '').trim(), b: e.getBoundingClientRect() })).filter(o => re.test(o.t) && o.b.width > 0); const o = r[r.length - 1]; return o && { x: o.b.x, y: o.b.y, width: o.b.width, height: o.b.height }; }, SUBMIT.source);
  if (!bx) throw new Error('no submit button');
  await page.mouse.click(bx.x + bx.width / 2, Math.min(bx.y + bx.height / 2, 830));
}
for (const which of ['Add Farmer / Member', 'Add Officer Account']) {
  const label = which.startsWith('Add Farmer') ? 'Create Farmer Member (staff)' : 'Create Officer (Manager)';
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_manager');
  await page.getByText('Members', { exact: true }).last().click(); await page.waitForTimeout(3500);
  await page.getByText('Add Member', { exact: true }).last().click(); await page.waitForTimeout(2000);
  await page.getByText(which).first().click(); await page.waitForTimeout(3000);
  const pw = page.locator('flt-semantics-host input').nth(1);
  // AUTO button: the form's own check must accept every generated temporary password (5 tries). (The field's text is
  // drawn on the canvas, so the password is judged by the form's validation, not read back.)
  let accepted = 0;
  for (let i = 0; i < 5; i++) { const bx = await page.locator('flt-semantics', { hasText: /^AUTO$/ }).last().boundingBox(); await page.mouse.click(bx.x + bx.width / 2, bx.y + bx.height / 2); await page.waitForTimeout(500); await submitBtn(page); await page.waitForTimeout(1000); if (!MSG.test(await text(page))) accepted++; }
  note(label, "every temporary password from the AUTO button passes the form's password check (5 of 5)", accepted === 5, accepted + ' of 5');
  await runCases(page, label, 1, () => submitBtn(page));
  await browser.close();
}

// ---- In-app Change Password dialog: Farmer, Buyer, Manager, Officer (drawer > Account > Change Password)
for (const user of ['t_farmer1', 't_buyer1', 't_manager', 't_officer_manage']) {
  const role = { t_farmer1: 'Farmer', t_buyer1: 'Buyer', t_manager: 'Manager', t_officer_manage: 'Officer' }[user];
  const { browser, page } = await launch(); await boot(page); await loginAs(page, user);
  await page.mouse.click(29, 31); await page.waitForTimeout(1500);
  await page.getByText(/^Account$/).first().click(); await page.waitForTimeout(3000);
  const cdp = await page.context().newCDPSession(page);
  for (let k = 0; k < 6 && !(await page.getByText(/Change Password/).count()); k++) { await cdp.send('Input.synthesizeScrollGesture', { x: 195, y: 500, yDistance: -500, speed: 1500, gestureSourceType: 'touch' }); await page.waitForTimeout(400); }
  await page.getByText(/Change Password/).first().click(); await page.waitForTimeout(2000);
  const n = await page.locator('flt-semantics-host input').count();
  note('Change Password ' + role, 'the dialog opens with current, new and confirm fields', n === 3, 'inputs ' + n);
  const update = async () => { await page.getByText('Update Password', { exact: true }).last().click(); await page.waitForTimeout(1200); };
  for (const [pw, label, ok] of CASES) {
    await typeInto(page, 0, 'SomeCurrent1!'); await typeInto(page, 1, pw); await typeInto(page, 2, ok ? pw + 'x' : pw);
    await update(); const t = await text(page);
    // A weak new password is stopped by the requirement message. A strong one passes that check and is then stopped only by the
    // deliberately mismatched confirmation, so no password is ever really changed here.
    note('Change Password ' + role, `"${pw}" (${label}) ${ok ? 'passes the rule (stopped only by the mismatched confirm)' : 'is refused with the requirement message'}`, ok ? (!MSG.test(t) && /do not match|not match/i.test(t)) : MSG.test(t), (t.match(/(Password must[^.]*.|Passwords? [^.]*match[^.]*.?)/) || [''])[0]);
  }
  await browser.close();
}

// ---- Forced password change after a temporary password (this screen shares its form with Forgot Password > set new password)
{
  const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_farmer2');
  note('Forced change', 'a Farmer whose password a Manager reset is taken to "Set a New Password"', /Set a New Password/.test(await text(page)));
  for (const [pw, label, ok] of CASES) {
    await typeInto(page, 0, pw); await typeInto(page, 1, ok ? pw + 'x' : pw);
    await page.getByText('Continue', { exact: true }).last().click(); await page.waitForTimeout(1200);
    const t = await text(page);
    note('Forced change / Forgot Password form', `"${pw}" (${label}) ${ok ? 'passes the rule (stopped only by the mismatched confirm)' : 'is refused with the requirement message'}`, ok ? (!MSG.test(t) && /do not match|not match/i.test(t)) : MSG.test(t), (t.match(/(Password must[^.]*.|Passwords? [^.]*match[^.]*.?)/) || [''])[0]);
  }
  await browser.close();
}
sql("update user_roles set must_change_password=false where user_id=(select user_id from user_information where username='t_farmer2')");

srv.close();
writeFileSync('../results/e2e_password_rule.json', JSON.stringify(results, null, 1));
const p = results.filter(r => r.pass).length; console.log(`\n${p}/${results.length} passed`);
