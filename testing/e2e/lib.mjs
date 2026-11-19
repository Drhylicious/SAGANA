// Shared helpers for the Chrome end-to-end checks. LOCAL STACK ONLY (the web build points at 127.0.0.1:54321).
import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright-core';

export const ROOT = path.resolve(fileURLToPath(new URL('../web_build/', import.meta.url))) + path.sep;
const types = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json', '.png': 'image/png', '.wasm': 'application/wasm', '.ico': 'image/x-icon', '.otf': 'font/otf', '.ttf': 'font/ttf', '.css': 'text/css', '.svg': 'image/svg+xml' };

export function serve(port = 8099) {
  const srv = http.createServer((req, res) => {
    let p = decodeURIComponent(req.url.split('?')[0]); if (p === '/') p = '/index.html';
    const f = path.join(ROOT, p);
    if (!f.startsWith(ROOT) || !fs.existsSync(f) || fs.statSync(f).isDirectory()) { res.writeHead(200, { 'Content-Type': 'text/html' }); return res.end(fs.readFileSync(path.join(ROOT, 'index.html'))); }
    res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' }); fs.createReadStream(f).pipe(res);
  });
  return new Promise(r => srv.listen(port, () => r(srv)));
}

export async function launch({ width = 390, height = 844, dark = false, locale = 'en-US', scale = 2 } = {}) {
  const browser = await chromium.launch({ executablePath: 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe', headless: true, args: ['--disable-gpu', '--use-gl=swiftshader'] });
  const ctx = await browser.newContext({ viewport: { width, height }, deviceScaleFactor: scale, colorScheme: dark ? 'dark' : 'light', locale, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  const logs = [];
  page.on('console', m => { if (['error', 'warning'].includes(m.type())) logs.push(m.type() + ': ' + m.text().slice(0, 200)); });
  page.on('pageerror', e => logs.push('pageerror: ' + String(e).slice(0, 200)));
  return { browser, ctx, page, logs };
}

// Flutter web draws to a canvas; turning on its accessibility layer exposes real, queryable elements.
export async function boot(page, url = 'http://127.0.0.1:8099/') {
  await page.goto(url, { waitUntil: 'load' });
  await page.waitForSelector('flt-glass-pane', { state: 'attached', timeout: 60000 });
  await page.waitForTimeout(2500);
  const btn = page.locator('flt-semantics-placeholder');
  if (await btn.count()) { await btn.evaluate(e => e.click()); await page.waitForTimeout(800); }
}
export const sem = (page, text) => page.locator('flt-semantics', { hasText: text });
export async function bodyText(page) { return (await page.locator('flt-semantics-host').innerText().catch(() => '')) || ''; }

export async function typeInto(page, i, v) {
  const inputs = page.locator('flt-semantics-host input');
  for (let k = 0; k < 4; k++) { await inputs.nth(i).click(); await page.keyboard.press('Control+A'); if (v === '') await page.keyboard.press('Backspace'); else await page.keyboard.type(v, { delay: 40 }); if ((await inputs.nth(i).inputValue().catch(() => v)) === v) return; }
}
export async function loginAs(page, user, pw = 'Test@12345') {
  await page.getByText(/^(Login|Mag-login)$/).last().click({ timeout: 8000 }).catch(() => {}); await page.waitForTimeout(1200);
  await typeInto(page, 0, user); await typeInto(page, 1, pw);
  await page.getByText(/^(Sign In|Mag-sign in)$/).last().click(); await page.waitForTimeout(6500);
}
export const text = async p => (await bodyText(p)).replace(/\s+/g, ' ');
