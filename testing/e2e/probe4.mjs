import { serve, launch, boot } from './lib.mjs';
const srv = await serve(); const { browser, page } = await launch(); await boot(page);
page.on('requestfailed', r => console.log('REQFAIL', r.url().slice(0, 150), r.failure()?.errorText));
await page.getByText('Login', { exact: true }).last().click(); await page.waitForTimeout(1500);
const i = page.locator('flt-semantics-host input'); await i.nth(0).fill('t_buyer1'); await i.nth(1).fill('Test@12345');
await page.getByText('Sign In', { exact: true }).last().click(); await page.waitForTimeout(8000);
await browser.close(); srv.close();
