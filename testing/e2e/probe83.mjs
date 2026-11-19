import { serve, launch, boot, loginAs, text } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page); await loginAs(page, 't_manager');
await page.getByText('Members', { exact: true }).last().click(); await page.waitForTimeout(3500);
await page.getByText('Add Member', { exact: true }).last().click(); await page.waitForTimeout(2000);
await page.getByText('Add Farmer / Member').first().click(); await page.waitForTimeout(3000);
for (let i = 0; i < 3; i++) {
  const bx = await page.locator('flt-semantics', { hasText: /^AUTO$/ }).last().boundingBox(); console.log('AUTO box', JSON.stringify(bx));
  await page.mouse.click(bx.x + bx.width / 2, bx.y + bx.height / 2); await page.waitForTimeout(700);
  console.log('value:', JSON.stringify(await page.locator('flt-semantics-host input').nth(1).inputValue()), 'type', await page.locator('flt-semantics-host input').nth(1).getAttribute('type'));
}
await page.screenshot({ path: '../results/shots/pw_auto.png' });
await browser.close(); srv.close();
