import { serve, launch, boot, text, typeInto } from './lib.mjs';
const [, , role = 'Farmer'] = process.argv;
const srv = await serve(); const { browser, page } = await launch(); await boot(page);
await page.getByText(/^(Login|Mag-login)$/).last().click(); await page.waitForTimeout(1500);
await page.getByText(/Create an Account/).last().click(); await page.waitForTimeout(2500);
await page.getByText(role, { exact: true }).first().click(); await page.waitForTimeout(800);
const inputs = page.locator('flt-semantics-host input'); console.log('inputs', await inputs.count());
await typeInto(page, 0, 'Testsur'); await typeInto(page, 1, 'Testfirst'); await typeInto(page, 3, 'pwtest' + Date.now().toString().slice(-7));
await page.getByText(/Select your date of birth/).first().click(); await page.waitForTimeout(1200);
await page.getByText('OK', { exact: true }).last().click().catch(() => console.log('no OK')); await page.waitForTimeout(800);
{ const bx = await page.locator('flt-semantics', { hasText: /^Gender/ }).last().boundingBox(); console.log('gender box', JSON.stringify(bx)); await page.mouse.click(bx.x + bx.width / 2, bx.y + bx.height / 2); await page.waitForTimeout(1000); console.log('G:', (await text(page)).slice(0, 120)); }
await page.getByText('Female').last().click().catch(() => console.log('no Female')); await page.waitForTimeout(800);
await page.getByText('Next', { exact: true }).last().click(); await page.waitForTimeout(2500);
console.log('STEP2:', (await text(page)).slice(0, 300)); await page.screenshot({ path: '../results/shots/pw_register2.png' });
console.log('inputs', await inputs.count());
await browser.close(); srv.close();
